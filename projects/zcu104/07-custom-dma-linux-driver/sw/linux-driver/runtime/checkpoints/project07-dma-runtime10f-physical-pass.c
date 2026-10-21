// SPDX-License-Identifier: GPL-2.0

#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/io.h>
#include <linux/interrupt.h>
#include <linux/dma-mapping.h>
#include <linux/delay.h>
#include <linux/bitops.h>
#include <linux/spinlock.h>
#include <linux/wait.h>
#include <linux/slab.h>
#include <linux/mutex.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/ioctl.h>
#include <linux/miscdevice.h>
#include <linux/uaccess.h>

/*
 * Project 07 — Runtime Linux DMA Driver
 *
 * Phase 10F:
 *   - production /dev/project07-dma userspace ABI
 *   - 64-byte TX through write()
 *   - 64-byte RX through read()
 *   - persistent coherent TX/RX descriptor and payload rings
 *   - asynchronous threaded IRQ TX/RX reclaim
 *   - GET_INFO / GET_STATS ioctls
 *   - controlled RESET ioctl
 *   - automatic hardware-error recovery
 *   - TX/RX recovery-loss accounting
 *   - runtime performance-counter reporting
 *   - no temporary recovery sysfs trigger
 *   - no arbitrary MMIO or userspace DMA addresses
 *
 * No DMA traffic is generated during probe.
 */

/* -------------------------------------------------------------------------- */
/* Global CSR                                                                 */
/* -------------------------------------------------------------------------- */

#define P07_ID                  0x000
#define P07_VERSION             0x004
#define P07_GLOBAL_CONTROL      0x008
#define P07_GLOBAL_STATUS       0x00C

#define P07_IRQ_STATUS          0x010
#define P07_IRQ_ENABLE          0x014
#define P07_ERROR_STATUS        0x018
#define P07_ERROR_INFO          0x01C
#define P07_ERROR_ADDR_LO       0x020
#define P07_ERROR_ADDR_HI       0x024

/* -------------------------------------------------------------------------- */
/* TX CSR                                                                     */
/* -------------------------------------------------------------------------- */

#define P07_TX_CONTROL          0x100
#define P07_TX_STATUS           0x104
#define P07_TX_BASE_LO          0x108
#define P07_TX_BASE_HI          0x10C
#define P07_TX_RING_SIZE        0x110
#define P07_TX_TAIL             0x114
#define P07_TX_HEAD             0x118

#define P07_TX_BYTES_LO         0x11C
#define P07_TX_BYTES_HI         0x120
#define P07_TX_DESC_COUNT       0x124
#define P07_TX_ACTIVE_LO        0x128
#define P07_TX_ACTIVE_HI        0x12C
#define P07_TX_AXI_STALL_LO     0x130
#define P07_TX_AXI_STALL_HI     0x134
#define P07_TX_AXIS_STALL_LO    0x138
#define P07_TX_AXIS_STALL_HI    0x13C

/* -------------------------------------------------------------------------- */
/* RX CSR                                                                     */
/* -------------------------------------------------------------------------- */

#define P07_RX_CONTROL          0x200
#define P07_RX_STATUS           0x204
#define P07_RX_BASE_LO          0x208
#define P07_RX_BASE_HI          0x20C
#define P07_RX_RING_SIZE        0x210
#define P07_RX_TAIL             0x214
#define P07_RX_HEAD             0x218

#define P07_RX_BYTES_LO         0x21C
#define P07_RX_BYTES_HI         0x220
#define P07_RX_DESC_COUNT       0x224
#define P07_RX_ACTIVE_LO        0x228
#define P07_RX_ACTIVE_HI        0x22C
#define P07_RX_AXI_STALL_LO     0x230
#define P07_RX_AXI_STALL_HI     0x234
#define P07_RX_AXIS_STALL_LO    0x238
#define P07_RX_AXIS_STALL_HI    0x23C

/* -------------------------------------------------------------------------- */
/* Control bits                                                               */
/* -------------------------------------------------------------------------- */

#define P07_GLOBAL_ENABLE       BIT(0)
#define P07_SOFT_RESET          BIT(1)
#define P07_COUNTER_CLEAR       BIT(2)

#define P07_CHANNEL_ENABLE      BIT(0)
#define P07_CHANNEL_HALT        BIT(1)

/* -------------------------------------------------------------------------- */
/* IRQ bits                                                                   */
/* -------------------------------------------------------------------------- */

#define P07_IRQ_TX_COMPLETE     BIT(0)
#define P07_IRQ_RX_COMPLETE     BIT(1)
#define P07_IRQ_TX_ERROR        BIT(2)
#define P07_IRQ_RX_ERROR        BIT(3)

#define P07_IRQ_COMPLETIONS \
	(P07_IRQ_TX_COMPLETE | P07_IRQ_RX_COMPLETE)

#define P07_IRQ_ERRORS \
	(P07_IRQ_TX_ERROR | P07_IRQ_RX_ERROR)

#define P07_IRQ_ALL \
	(P07_IRQ_COMPLETIONS | P07_IRQ_ERRORS)

/* -------------------------------------------------------------------------- */
/* Hardware contract                                                          */
/* -------------------------------------------------------------------------- */

#define P07_EXPECTED_ID         0x43444D41
#define P07_EXPECTED_VERSION    0x00010000

#define P07_DMA_BITS            40

#define P07_RING_ENTRIES        16
#define P07_RING_MASK           (P07_RING_ENTRIES - 1)
#define P07_DESC_BYTES          64

#define P07_PAYLOAD_BYTES       64
#define P07_TX_POOL_BYTES       (P07_RING_ENTRIES * P07_PAYLOAD_BYTES)
#define P07_RX_POOL_BYTES       (P07_RING_ENTRIES * P07_PAYLOAD_BYTES)

#define P07_ABI_VERSION         0x00010000

#define P07_CAP_TX_WRITE        BIT(0)
#define P07_CAP_RX_READ         BIT(1)
#define P07_CAP_GET_INFO        BIT(2)
#define P07_CAP_GET_STATS       BIT(3)
#define P07_CAP_RESET           BIT(4)
#define P07_CAP_HW_RECOVERY     BIT(5)

struct project07_user_info {
	__u32 abi_version;
	__u32 hw_id;
	__u32 hw_version;
	__u32 ring_entries;
	__u32 descriptor_bytes;
	__u32 payload_bytes;
	__u32 dma_bits;
	__u32 capabilities;
};

struct project07_user_stats {
	__u64 tx_bytes;
	__u64 rx_bytes;

	__u64 tx_active_cycles;
	__u64 rx_active_cycles;

	__u64 tx_axi_stall;
	__u64 rx_axi_stall;

	__u64 tx_axis_stall;
	__u64 rx_axis_stall;

	__u32 tx_desc;
	__u32 rx_desc;

	__u32 tx_prod;
	__u32 tx_clean;
	__u32 tx_head;

	__u32 rx_prod;
	__u32 rx_clean;
	__u32 rx_head;

	__u32 irq_count;
	__u32 irq_seen;

	__u32 error_status;
	__u32 faulted;

	__u32 recovery_count;
	__u32 recovery_failures;

	__u32 recovery_dropped_tx;
	__u32 recovery_dropped_rx;

	__u32 last_error_status;
	__u32 last_error_info;
	__u64 last_error_addr;
};

#define P07_IOCTL_MAGIC          'P'
#define P07_IOCTL_RESET          _IO(P07_IOCTL_MAGIC, 0x01)
#define P07_IOCTL_GET_INFO       _IOR(P07_IOCTL_MAGIC, 0x02, struct project07_user_info)
#define P07_IOCTL_GET_STATS      _IOR(P07_IOCTL_MAGIC, 0x03, struct project07_user_stats)


struct project07_desc {
	__le64 buffer_addr;
	__le32 length;
	__le32 control;
	__le64 cookie;
	__le32 status;
	__le32 actual_length;
	u8 reserved[32];
};

struct project07_ring {
	struct project07_desc *desc;
	dma_addr_t dma;

	/*
	 * Monotonic logical indices.
	 *
	 * Never truncate these to ring size.
	 *
	 * Physical slot:
	 *
	 *     logical_index & P07_RING_MASK
	 */
	u32 prod;
	u32 clean;
};

struct project07_dma {
	struct device *dev;
	void __iomem *regs;
	int irq;

	struct miscdevice miscdev;

	struct project07_ring tx;
	struct project07_ring rx;

	void *tx_payload_cpu;
	dma_addr_t tx_payload_dma;

	void *rx_payload_cpu;
	dma_addr_t rx_payload_dma;

	struct mutex tx_mutex;
	struct mutex rx_mutex;
	struct mutex rx_user_mutex;

	spinlock_t state_lock;

	wait_queue_head_t tx_wait;
	wait_queue_head_t rx_wait;

	atomic_t irq_count;
	atomic_t irq_seen;
	atomic_t irq_thread_pending;

	bool runtime_faulted;

	u32 recovery_count;
	u32 recovery_failures;

	u32 recovery_dropped_tx;
	u32 last_recovery_dropped_tx;

	u32 recovery_dropped_rx;
	u32 last_recovery_dropped_rx;

	bool rx_user_pending;
	u32 rx_user_logical;
	u32 rx_user_generation;

	u32 last_error_status;
	u32 last_error_info;
	u64 last_error_addr;
};

/* -------------------------------------------------------------------------- */
/* Interrupt handler                                                          */
/* -------------------------------------------------------------------------- */

static int project07_tx_reclaim(struct project07_dma *dma);
static int project07_rx_reclaim(struct project07_dma *dma);

static int project07_runtime_recover(
	struct project07_dma *dma,
	const char *reason,
	bool from_irq);

static irqreturn_t project07_dma_irq(int irq, void *data)
{
	struct project07_dma *dma = data;
	u32 pending;

	pending =
		readl(dma->regs + P07_IRQ_STATUS) &
		P07_IRQ_ALL;

	if (!pending)
		return IRQ_NONE;

	atomic_inc(&dma->irq_count);
	atomic_or(pending, &dma->irq_seen);
	atomic_or(pending, &dma->irq_thread_pending);

	/*
	 * IRQ_STATUS is RW1C.
	 *
	 * Acknowledge the level-sensitive hardware interrupt in
	 * hard-IRQ context. Completion processing is deferred.
	 */
	writel(pending,
	       dma->regs + P07_IRQ_STATUS);

	(void)readl(
		dma->regs + P07_IRQ_STATUS);

	return IRQ_WAKE_THREAD;
}

static irqreturn_t project07_dma_irq_thread(int irq, void *data)
{
	struct project07_dma *dma = data;

	u32 causes;

	u32 tx_head = 0;
	u32 rx_head = 0;

	int tx_reclaimed = 0;
	int rx_reclaimed = 0;

	int ret;

	causes =
		(u32)atomic_xchg(
			&dma->irq_thread_pending,
			0);

	/*
	 * Hardware errors have priority over ordinary completion.
	 */
	if (causes & P07_IRQ_ERRORS) {

		ret =
			project07_runtime_recover(
				dma,
				"hardware-error-irq",
				true);

		if (ret) {

			dev_err(dma->dev,
				"Project07 Runtime10F IRQ recovery FAIL: causes=0x%08x ret=%d\n",
				causes,
				ret);
		}

		wake_up_all(
			&dma->tx_wait);

		wake_up_all(
			&dma->rx_wait);

		return IRQ_HANDLED;
	}

	if (causes & P07_IRQ_TX_COMPLETE) {

		mutex_lock(
			&dma->tx_mutex);

		tx_reclaimed =
			project07_tx_reclaim(
				dma);

		tx_head =
			readl(
				dma->regs +
				P07_TX_HEAD);

		mutex_unlock(
			&dma->tx_mutex);

		if (tx_reclaimed < 0) {

			dev_err(dma->dev,
				"Project07 Runtime10F TX reclaim validation FAIL: causes=0x%08x ret=%d\n",
				causes,
				tx_reclaimed);

			ret =
				project07_runtime_recover(
					dma,
					"tx-reclaim-error",
					true);

			if (ret) {

				dev_err(dma->dev,
					"Project07 Runtime10F TX reclaim recovery FAIL: ret=%d\n",
					ret);
			}

			wake_up_all(
				&dma->tx_wait);

			wake_up_all(
				&dma->rx_wait);

			return IRQ_HANDLED;
		}

		dev_info(dma->dev,
			 "Project07 Runtime10F TX IRQ reclaim: causes=0x%08x reclaimed=%d tx_clean=%u tx_head=%u\n",
			 causes,
			 tx_reclaimed,
			 dma->tx.clean,
			 tx_head);

		wake_up_all(
			&dma->tx_wait);
	}

	if (causes & P07_IRQ_RX_COMPLETE) {

		mutex_lock(
			&dma->rx_mutex);

		rx_reclaimed =
			project07_rx_reclaim(
				dma);

		rx_head =
			readl(
				dma->regs +
				P07_RX_HEAD);

		mutex_unlock(
			&dma->rx_mutex);

		if (rx_reclaimed < 0) {

			dev_err(dma->dev,
				"Project07 Runtime10F RX reclaim validation FAIL: causes=0x%08x ret=%d\n",
				causes,
				rx_reclaimed);

			ret =
				project07_runtime_recover(
					dma,
					"rx-reclaim-error",
					true);

			if (ret) {

				dev_err(dma->dev,
					"Project07 Runtime10F RX reclaim recovery FAIL: ret=%d\n",
					ret);
			}

			wake_up_all(
				&dma->tx_wait);

			wake_up_all(
				&dma->rx_wait);

			return IRQ_HANDLED;
		}

		dev_info(dma->dev,
			 "Project07 Runtime10F RX IRQ reclaim: causes=0x%08x reclaimed=%d rx_clean=%u rx_head=%u\n",
			 causes,
			 rx_reclaimed,
			 dma->rx.clean,
			 rx_head);

		wake_up_all(
			&dma->rx_wait);
	}

	return IRQ_HANDLED;
}


/* -------------------------------------------------------------------------- */
/* Runtime TX reclaim                                                         */
/* -------------------------------------------------------------------------- */

static u64 project07_read_counter64(
	struct project07_dma *dma,
	u32 lo_reg,
	u32 hi_reg)
{
	u32 hi_before;
	u32 lo;
	u32 hi_after;

	do {

		hi_before =
			readl(
				dma->regs +
					hi_reg);

		lo =
			readl(
				dma->regs +
					lo_reg);

		hi_after =
			readl(
				dma->regs +
					hi_reg);

	} while (hi_before != hi_after);

	return
		((u64)hi_after << 32) |
		(u64)lo;
}


static u64 project07_read_tx_bytes(struct project07_dma *dma)
{
	return
		project07_read_counter64(
			dma,
			P07_TX_BYTES_LO,
			P07_TX_BYTES_HI);
}


static u64 project07_read_rx_bytes(struct project07_dma *dma)
{
	return
		project07_read_counter64(
			dma,
			P07_RX_BYTES_LO,
			P07_RX_BYTES_HI);
}

static int project07_tx_reclaim(struct project07_dma *dma)
{
	u32 hw_head;
	int reclaimed = 0;

	/*
	 * HW_HEAD is the authoritative hardware completion point.
	 */
	hw_head =
		readl(dma->regs + P07_TX_HEAD);

	/*
	 * Descriptor writeback must be observed after HEAD.
	 */
	dma_rmb();

	while (dma->tx.clean != hw_head) {
		struct project07_desc *desc;
		u32 logical;
		u32 slot;
		u32 control;
		u32 status;
		u32 actual;

		logical =
			dma->tx.clean;

		slot =
			logical & P07_RING_MASK;

		desc =
			&dma->tx.desc[slot];

		control =
			le32_to_cpu(desc->control);

		status =
			le32_to_cpu(desc->status);

		actual =
			le32_to_cpu(desc->actual_length);

		if (control != 0x6 ||
		    status != 0x1 ||
		    actual != P07_PAYLOAD_BYTES) {

			dev_err(dma->dev,
				"Project07 Runtime10F reclaim FAIL: logical=%u slot=%u control=0x%08x status=0x%08x actual=%u\n",
				logical,
				slot,
				control,
				status,
				actual);

			return -EIO;
		}

		dev_info(dma->dev,
			 "Project07 Runtime10F reclaim: logical=%u slot=%u control=0x%08x status=0x%08x actual=%u cookie=0x%016llx\n",
			 logical,
			 slot,
			 control,
			 status,
			 actual,
			 (unsigned long long)
			 le64_to_cpu(desc->cookie));

		dma->tx.clean++;
		reclaimed++;
	}

	return reclaimed;
}

/* -------------------------------------------------------------------------- */
/* Runtime RX reclaim / publication                                           */
/* -------------------------------------------------------------------------- */

static int project07_rx_reclaim(struct project07_dma *dma)
{
	u32 hw_head;

	int reclaimed = 0;

	hw_head =
		readl(
			dma->regs +
				P07_RX_HEAD);

	/*
	 * Descriptor writeback must be observed after authoritative
	 * RX_HEAD publication.
	 */
	dma_rmb();

	while (dma->rx.clean != hw_head) {

		struct project07_desc *desc;

		u32 logical;
		u32 slot;
		u32 control;
		u32 status;
		u32 actual;

		logical =
			dma->rx.clean;

		slot =
			logical &
			P07_RING_MASK;

		desc =
			&dma->rx.desc[slot];

		control =
			le32_to_cpu(
				desc->control);

		status =
			le32_to_cpu(
				desc->status);

		actual =
			le32_to_cpu(
				desc->actual_length);

		if (control != 0x6 ||
		    status != 0x1 ||
		    actual != P07_PAYLOAD_BYTES) {

			dev_err(dma->dev,
				"Project07 Runtime10F RX reclaim FAIL: logical=%u slot=%u control=0x%08x status=0x%08x actual=%u\n",
				logical,
				slot,
				control,
				status,
				actual);

			return -EIO;
		}

		dev_info(dma->dev,
			 "Project07 Runtime10F RX reclaim: logical=%u slot=%u control=0x%08x status=0x%08x actual=%u cookie=0x%016llx\n",
			 logical,
			 slot,
			 control,
			 status,
			 actual,
			 (unsigned long long)
			 le64_to_cpu(
				 desc->cookie));

		dma->rx.clean++;
		reclaimed++;
	}

	return reclaimed;
}


static int project07_rx_submit_locked(
	struct project07_dma *dma,
	u32 *logical_out,
	u32 *slot_out)
{
	struct project07_desc *desc;

	u8 *payload;

	dma_addr_t payload_dma;

	u32 logical;
	u32 slot;
	u32 error_status;

	if (READ_ONCE(
		    dma->runtime_faulted))
		return -EIO;

	if ((u32)(dma->rx.prod - dma->rx.clean) >=
	    P07_RING_ENTRIES)
		return -EAGAIN;

	error_status =
		readl(
			dma->regs +
				P07_ERROR_STATUS);

	if (error_status != 0)
		return -EIO;

	logical =
		dma->rx.prod;

	slot =
		logical &
		P07_RING_MASK;

	desc =
		&dma->rx.desc[slot];

	payload =
		(u8 *)dma->rx_payload_cpu +
		(slot * P07_PAYLOAD_BYTES);

	payload_dma =
		dma->rx_payload_dma +
		(slot * P07_PAYLOAD_BYTES);

	memset(
		payload,
		0,
		P07_PAYLOAD_BYTES);

	memset(
		desc,
		0,
		sizeof(*desc));

	desc->buffer_addr =
		cpu_to_le64(
			(u64)payload_dma);

	desc->length =
		cpu_to_le32(
			P07_PAYLOAD_BYTES);

	/*
	 * OWN | IRQ | EOP
	 */
	desc->control =
		cpu_to_le32(
			0x7);

	desc->cookie =
		cpu_to_le64(
			0x3130460000000000ULL |
			(u64)logical);

	/*
	 * Publish buffer + descriptor before logical TAIL.
	 */
	dma_wmb();

	dma->rx.prod =
		logical + 1;

	/*
	 * RX becomes operational only after software has prepared
	 * a descriptor.
	 *
	 * On the current validation FPGA wrapper this also permits the
	 * physically proven deterministic AXI4-Stream source to begin.
	 */
	writel(
		P07_CHANNEL_ENABLE,
		dma->regs +
			P07_RX_CONTROL);

	writel(
		dma->rx.prod,
		dma->regs +
			P07_RX_TAIL);

	(void)readl(
		dma->regs +
			P07_RX_TAIL);

	dev_info(dma->dev,
		 "Project07 Runtime10F RX posted: logical=%u slot=%u rx_prod=%u rx_clean=%u tail=%u bytes=%u payload_dma=%pad\n",
		 logical,
		 slot,
		 dma->rx.prod,
		 dma->rx.clean,
		 dma->rx.prod,
		 P07_PAYLOAD_BYTES,
		 &payload_dma);

	*logical_out =
		logical;

	*slot_out =
		slot;

	return 0;
}

/* -------------------------------------------------------------------------- */
/* Runtime TX submission                                                      */
/* -------------------------------------------------------------------------- */

static int project07_tx_submit_user(
	struct project07_dma *dma,
	const u8 *data,
	size_t len)
{
	struct project07_desc *desc;
	u8 *payload;
	dma_addr_t payload_dma;

	u32 logical;
	u32 slot;
	u32 error_status;

	int ret = 0;

	if (len != P07_PAYLOAD_BYTES)
		return -EMSGSIZE;

	mutex_lock(&dma->tx_mutex);

	if (READ_ONCE(dma->runtime_faulted)) {

		dev_err(dma->dev,
			"Project07 Runtime10F write FAIL: runtime is faulted; recovery required\n");

		ret = -EIO;
		goto out_unlock;
	}

	/*
	 * tx_clean is advanced asynchronously by threaded IRQ reclaim.
	 */
	if ((u32)(dma->tx.prod - dma->tx.clean) >=
	    P07_RING_ENTRIES) {

		dev_err(dma->dev,
			"Project07 Runtime10F write FAIL: TX ring full prod=%u clean=%u\n",
			dma->tx.prod,
			dma->tx.clean);

		ret = -EAGAIN;
		goto out_unlock;
	}

	error_status =
		readl(
			dma->regs +
			P07_ERROR_STATUS);

	if (error_status != 0) {

		dev_err(dma->dev,
			"Project07 Runtime10F write FAIL: error_status=0x%08x\n",
			error_status);

		ret = -EIO;
		goto out_unlock;
	}

	logical =
		dma->tx.prod;

	slot =
		logical & P07_RING_MASK;

	desc =
		&dma->tx.desc[slot];

	payload =
		(u8 *)dma->tx_payload_cpu +
		(slot * P07_PAYLOAD_BYTES);

	payload_dma =
		dma->tx_payload_dma +
		(slot * P07_PAYLOAD_BYTES);

	/*
	 * Userspace never supplies a DMA address.
	 *
	 * Data is copied into the driver's own coherent TX pool.
	 */
	memcpy(
		payload,
		data,
		P07_PAYLOAD_BYTES);

	memset(
		desc,
		0,
		sizeof(*desc));

	desc->buffer_addr =
		cpu_to_le64(
			(u64)payload_dma);

	desc->length =
		cpu_to_le32(
			P07_PAYLOAD_BYTES);

	/*
	 * OWN | IRQ | EOP
	 */
	desc->control =
		cpu_to_le32(0x7);

	desc->cookie =
		cpu_to_le64(
			0x3130440000000000ULL |
			(u64)logical);

	/*
	 * Publish userspace payload + descriptor before logical TAIL.
	 */
	dma_wmb();

	dma->tx.prod =
		logical + 1;

	writel(
		P07_CHANNEL_ENABLE,
		dma->regs +
		P07_TX_CONTROL);

	writel(
		dma->tx.prod,
		dma->regs +
		P07_TX_TAIL);

	(void)readl(
		dma->regs +
		P07_TX_TAIL);

	dev_info(dma->dev,
		 "Project07 Runtime10F write queued: logical=%u slot=%u tx_prod=%u tx_clean=%u tail=%u bytes=%zu payload_dma=%pad\n",
		 logical,
		 slot,
		 dma->tx.prod,
		 dma->tx.clean,
		 dma->tx.prod,
		 len,
		 &payload_dma);

	/*
	 * Return without waiting for completion.
	 *
	 * Completion path:
	 *
	 *     hardware IRQ
	 *       -> hard IRQ acknowledgement
	 *       -> threaded IRQ
	 *       -> HW_HEAD reclaim
	 */

out_unlock:
	mutex_unlock(&dma->tx_mutex);

	return ret;
}

/* -------------------------------------------------------------------------- */
/* Temporary Phase 10F validation controls                                    */
/* -------------------------------------------------------------------------- */






/* -------------------------------------------------------------------------- */
/* Real Linux userspace device interface                                      */
/* -------------------------------------------------------------------------- */

static int project07_dma_open(
	struct inode *inode,
	struct file *file)
{
	struct miscdevice *misc =
		file->private_data;

	struct project07_dma *dma =
		container_of(
			misc,
			struct project07_dma,
			miscdev);

	file->private_data =
		dma;

	return 0;
}

static ssize_t project07_dma_write(
	struct file *file,
	const char __user *buf,
	size_t count,
	loff_t *ppos)
{
	struct project07_dma *dma =
		file->private_data;

	u8 payload[P07_PAYLOAD_BYTES];

	int ret;

	if (!dma)
		return -ENODEV;

	/*
	 * Phase 10F deliberately exposes only the already physically
	 * qualified 64-byte transfer size.
	 *
	 * Variable-size TX can be generalized later without changing
	 * descriptor ownership or reclaim semantics.
	 */
	if (count != P07_PAYLOAD_BYTES)
		return -EMSGSIZE;

	if (copy_from_user(
		    payload,
		    buf,
		    P07_PAYLOAD_BYTES))
		return -EFAULT;

	ret =
		project07_tx_submit_user(
			dma,
			payload,
			P07_PAYLOAD_BYTES);

	if (ret)
		return ret;

	return count;
}

static ssize_t project07_dma_read(
	struct file *file,
	char __user *buf,
	size_t count,
	loff_t *ppos)
{
	struct project07_dma *dma =
		file->private_data;

	u32 logical;
	u32 slot;
	u32 generation;

	u8 *payload;

	int ret;

	if (!dma)
		return -ENODEV;

	if (count != P07_PAYLOAD_BYTES)
		return -EMSGSIZE;

	ret =
		mutex_lock_interruptible(
			&dma->rx_user_mutex);

	if (ret)
		return ret;

	mutex_lock(
		&dma->rx_mutex);

	if (dma->rx_user_pending) {

		logical =
			dma->rx_user_logical;

		slot =
			logical &
			P07_RING_MASK;

		generation =
			dma->rx_user_generation;

	} else {

		generation =
			READ_ONCE(
				dma->recovery_count);

		ret =
			project07_rx_submit_locked(
				dma,
				&logical,
				&slot);

		if (ret) {

			mutex_unlock(
				&dma->rx_mutex);

			mutex_unlock(
				&dma->rx_user_mutex);

			return ret;
		}

		dma->rx_user_pending =
			true;

		dma->rx_user_logical =
			logical;

		dma->rx_user_generation =
			generation;
	}

	mutex_unlock(
		&dma->rx_mutex);

	/*
	 * One read() owns one posted RX request.
	 *
	 * The wait terminates on:
	 *
	 *   normal HW_HEAD reclaim
	 *   recovery establishing a new DMA epoch
	 *   unrecovered runtime fault
	 */
	ret =
		wait_event_interruptible(
			dma->rx_wait,
			READ_ONCE(dma->rx.clean) ==
				(logical + 1) ||
			READ_ONCE(dma->recovery_count) !=
				generation ||
			READ_ONCE(dma->runtime_faulted));

	if (ret) {

		/*
		 * Interrupted userspace may retry the same pending packet.
		 */
		mutex_unlock(
			&dma->rx_user_mutex);

		return ret;
	}

	if (READ_ONCE(dma->recovery_count) !=
	    generation ||
	    READ_ONCE(dma->runtime_faulted)) {

		mutex_unlock(
			&dma->rx_user_mutex);

		return -EIO;
	}

	/*
	 * Payload write must be observed after descriptor completion.
	 */
	dma_rmb();

	payload =
		(u8 *)dma->rx_payload_cpu +
		(slot * P07_PAYLOAD_BYTES);

	if (copy_to_user(
		    buf,
		    payload,
		    P07_PAYLOAD_BYTES)) {

		/*
		 * Keep the completed packet pending so userspace may retry.
		 */
		mutex_unlock(
			&dma->rx_user_mutex);

		return -EFAULT;
	}

	mutex_lock(
		&dma->rx_mutex);

	dma->rx_user_pending =
		false;

	mutex_unlock(
		&dma->rx_mutex);

	dev_info(dma->dev,
		 "Project07 Runtime10F RX delivered to userspace: logical=%u slot=%u bytes=%u\n",
		 logical,
		 slot,
		 P07_PAYLOAD_BYTES);

	mutex_unlock(
		&dma->rx_user_mutex);

	return P07_PAYLOAD_BYTES;
}


static void project07_fill_info(
	struct project07_dma *dma,
	struct project07_user_info *info)
{
	memset(
		info,
		0,
		sizeof(*info));

	info->abi_version =
		P07_ABI_VERSION;

	info->hw_id =
		readl(
			dma->regs +
				P07_ID);

	info->hw_version =
		readl(
			dma->regs +
				P07_VERSION);

	info->ring_entries =
		P07_RING_ENTRIES;

	info->descriptor_bytes =
		P07_DESC_BYTES;

	info->payload_bytes =
		P07_PAYLOAD_BYTES;

	info->dma_bits =
		P07_DMA_BITS;

	info->capabilities =
		P07_CAP_TX_WRITE |
		P07_CAP_RX_READ |
		P07_CAP_GET_INFO |
		P07_CAP_GET_STATS |
		P07_CAP_RESET |
		P07_CAP_HW_RECOVERY;
}


static void project07_fill_stats(
	struct project07_dma *dma,
	struct project07_user_stats *stats)
{
	unsigned long flags;

	memset(
		stats,
		0,
		sizeof(*stats));

	/*
	 * Same lock order as recovery:
	 *
	 *     TX -> RX
	 */
	mutex_lock(
		&dma->tx_mutex);

	mutex_lock(
		&dma->rx_mutex);

	stats->tx_bytes =
		project07_read_tx_bytes(
			dma);

	stats->rx_bytes =
		project07_read_rx_bytes(
			dma);

	stats->tx_active_cycles =
		project07_read_counter64(
			dma,
			P07_TX_ACTIVE_LO,
			P07_TX_ACTIVE_HI);

	stats->rx_active_cycles =
		project07_read_counter64(
			dma,
			P07_RX_ACTIVE_LO,
			P07_RX_ACTIVE_HI);

	stats->tx_axi_stall =
		project07_read_counter64(
			dma,
			P07_TX_AXI_STALL_LO,
			P07_TX_AXI_STALL_HI);

	stats->rx_axi_stall =
		project07_read_counter64(
			dma,
			P07_RX_AXI_STALL_LO,
			P07_RX_AXI_STALL_HI);

	stats->tx_axis_stall =
		project07_read_counter64(
			dma,
			P07_TX_AXIS_STALL_LO,
			P07_TX_AXIS_STALL_HI);

	stats->rx_axis_stall =
		project07_read_counter64(
			dma,
			P07_RX_AXIS_STALL_LO,
			P07_RX_AXIS_STALL_HI);

	stats->tx_desc =
		readl(
			dma->regs +
				P07_TX_DESC_COUNT);

	stats->rx_desc =
		readl(
			dma->regs +
				P07_RX_DESC_COUNT);

	stats->tx_prod =
		dma->tx.prod;

	stats->tx_clean =
		dma->tx.clean;

	stats->tx_head =
		readl(
			dma->regs +
				P07_TX_HEAD);

	stats->rx_prod =
		dma->rx.prod;

	stats->rx_clean =
		dma->rx.clean;

	stats->rx_head =
		readl(
			dma->regs +
				P07_RX_HEAD);

	mutex_unlock(
		&dma->rx_mutex);

	mutex_unlock(
		&dma->tx_mutex);

	stats->irq_count =
		(u32)atomic_read(
			&dma->irq_count);

	stats->irq_seen =
		(u32)atomic_read(
			&dma->irq_seen);

	stats->error_status =
		readl(
			dma->regs +
				P07_ERROR_STATUS);

	spin_lock_irqsave(
		&dma->state_lock,
		flags);

	stats->faulted =
		dma->runtime_faulted ?
			1 : 0;

	stats->recovery_count =
		dma->recovery_count;

	stats->recovery_failures =
		dma->recovery_failures;

	stats->recovery_dropped_tx =
		dma->recovery_dropped_tx;

	stats->recovery_dropped_rx =
		dma->recovery_dropped_rx;

	stats->last_error_status =
		dma->last_error_status;

	stats->last_error_info =
		dma->last_error_info;

	stats->last_error_addr =
		dma->last_error_addr;

	spin_unlock_irqrestore(
		&dma->state_lock,
		flags);
}


static long project07_dma_ioctl(
	struct file *file,
	unsigned int cmd,
	unsigned long arg)
{
	struct project07_dma *dma =
		file->private_data;

	void __user *argp =
		(void __user *)arg;

	struct project07_user_info info;
	struct project07_user_stats stats;

	if (!dma)
		return -ENODEV;

	switch (cmd) {

	case P07_IOCTL_RESET:

		return
			project07_runtime_recover(
				dma,
				"userspace-ioctl",
				false);

	case P07_IOCTL_GET_INFO:

		project07_fill_info(
			dma,
			&info);

		if (copy_to_user(
			    argp,
			    &info,
			    sizeof(info)))
			return -EFAULT;

		return 0;

	case P07_IOCTL_GET_STATS:

		project07_fill_stats(
			dma,
			&stats);

		if (copy_to_user(
			    argp,
			    &stats,
			    sizeof(stats)))
			return -EFAULT;

		return 0;

	default:

		return -ENOTTY;
	}
}

/*
 * Temporary physical-validation trigger.
 *
 * Final userspace recovery ABI is ioctl RESET.
 */


static const struct file_operations project07_fops = {
	.owner =
		THIS_MODULE,

	.open =
		project07_dma_open,

	.read =
		project07_dma_read,

	.write =
		project07_dma_write,

	.unlocked_ioctl =
		project07_dma_ioctl,

	.llseek =
		no_llseek,
};

static ssize_t runtime_status_show(
	struct device *dev,
	struct device_attribute *attr,
	char *buf)
{
	struct project07_dma *dma =
		dev_get_drvdata(dev);

	unsigned long flags;

	u32 tx_head;
	u32 tx_desc;

	u32 rx_head;
	u32 rx_desc;

	u32 error_status;

	u32 recovery_count;
	u32 recovery_failures;

	u32 recovery_dropped_tx;
	u32 recovery_dropped_rx;

	u32 last_recovery_dropped_tx;
	u32 last_recovery_dropped_rx;

	u32 last_error_status;
	u32 last_error_info;

	u64 last_error_addr;

	bool runtime_faulted;
	bool rx_user_pending;

	u64 tx_bytes;
	u64 rx_bytes;

	if (!dma)
		return -ENODEV;

	tx_head =
		readl(
			dma->regs +
				P07_TX_HEAD);

	tx_desc =
		readl(
			dma->regs +
				P07_TX_DESC_COUNT);

	rx_head =
		readl(
			dma->regs +
				P07_RX_HEAD);

	rx_desc =
		readl(
			dma->regs +
				P07_RX_DESC_COUNT);

	error_status =
		readl(
			dma->regs +
				P07_ERROR_STATUS);

	tx_bytes =
		project07_read_tx_bytes(
			dma);

	rx_bytes =
		project07_read_rx_bytes(
			dma);

	spin_lock_irqsave(
		&dma->state_lock,
		flags);

	runtime_faulted =
		dma->runtime_faulted;

	recovery_count =
		dma->recovery_count;

	recovery_failures =
		dma->recovery_failures;

	recovery_dropped_tx =
		dma->recovery_dropped_tx;

	recovery_dropped_rx =
		dma->recovery_dropped_rx;

	last_recovery_dropped_tx =
		dma->last_recovery_dropped_tx;

	last_recovery_dropped_rx =
		dma->last_recovery_dropped_rx;

	last_error_status =
		dma->last_error_status;

	last_error_info =
		dma->last_error_info;

	last_error_addr =
		dma->last_error_addr;

	spin_unlock_irqrestore(
		&dma->state_lock,
		flags);

	rx_user_pending =
		READ_ONCE(
			dma->rx_user_pending);

	return sysfs_emit(
		buf,
		"tx_prod=%u tx_clean=%u tx_head=%u tx_bytes=%llu tx_desc=%u "
		"rx_prod=%u rx_clean=%u rx_head=%u rx_bytes=%llu rx_desc=%u "
		"rx_pending=%u "
		"irq_count=%d irq_seen=0x%08x "
		"error_status=0x%08x faulted=%u "
		"recovery_count=%u recovery_failures=%u "
		"recovery_dropped_tx=%u recovery_dropped_rx=%u "
		"last_recovery_dropped_tx=%u last_recovery_dropped_rx=%u "
		"last_error_status=0x%08x last_error_info=0x%08x "
		"last_error_addr=0x%016llx\n",
		dma->tx.prod,
		dma->tx.clean,
		tx_head,
		(unsigned long long)tx_bytes,
		tx_desc,
		dma->rx.prod,
		dma->rx.clean,
		rx_head,
		(unsigned long long)rx_bytes,
		rx_desc,
		rx_user_pending ? 1 : 0,
		atomic_read(
			&dma->irq_count),
		atomic_read(
			&dma->irq_seen),
		error_status,
		runtime_faulted ? 1 : 0,
		recovery_count,
		recovery_failures,
		recovery_dropped_tx,
		recovery_dropped_rx,
		last_recovery_dropped_tx,
		last_recovery_dropped_rx,
		last_error_status,
		last_error_info,
		(unsigned long long)
			last_error_addr);
}

static DEVICE_ATTR_RO(runtime_status);

/* -------------------------------------------------------------------------- */
/* Hardware shutdown                                                          */
/* -------------------------------------------------------------------------- */

static void project07_hw_quiesce(struct project07_dma *dma)
{
	writel(0,
	       dma->regs + P07_IRQ_ENABLE);

	writel(0,
	       dma->regs + P07_TX_CONTROL);

	writel(0,
	       dma->regs + P07_RX_CONTROL);

	writel(0,
	       dma->regs + P07_GLOBAL_CONTROL);

	writel(P07_IRQ_ALL,
	       dma->regs + P07_IRQ_STATUS);

	(void)readl(
		dma->regs + P07_IRQ_STATUS);
}

/* -------------------------------------------------------------------------- */
/* Runtime hardware initialization                                            */
/* -------------------------------------------------------------------------- */

static int project07_hw_init(struct project07_dma *dma)
{
	u32 tx_head;
	u32 rx_head;
	u32 error_status;

	/*
	 * Establish a known stopped state.
	 */
	project07_hw_quiesce(dma);

	/*
	 * Reset the custom DMA core.
	 */
	writel(P07_SOFT_RESET,
	       dma->regs + P07_GLOBAL_CONTROL);

	(void)readl(
		dma->regs + P07_GLOBAL_CONTROL);

	udelay(10);

	/*
	 * Clear runtime counters and stale status.
	 */
	writel(P07_COUNTER_CLEAR,
	       dma->regs + P07_GLOBAL_CONTROL);

	writel(P07_IRQ_ALL,
	       dma->regs + P07_IRQ_STATUS);

	writel(0xffffffff,
	       dma->regs + P07_ERROR_STATUS);

	(void)readl(
		dma->regs + P07_IRQ_STATUS);

	/*
	 * Persistent TX ring.
	 *
	 * BASE first.
	 * SIZE last commits the configuration.
	 */
	writel(lower_32_bits(dma->tx.dma),
	       dma->regs + P07_TX_BASE_LO);

	writel(upper_32_bits(dma->tx.dma),
	       dma->regs + P07_TX_BASE_HI);

	writel(P07_RING_ENTRIES,
	       dma->regs + P07_TX_RING_SIZE);

	/*
	 * Persistent RX ring.
	 */
	writel(lower_32_bits(dma->rx.dma),
	       dma->regs + P07_RX_BASE_LO);

	writel(upper_32_bits(dma->rx.dma),
	       dma->regs + P07_RX_BASE_HI);

	writel(P07_RING_ENTRIES,
	       dma->regs + P07_RX_RING_SIZE);

	/*
	 * No descriptors have been published.
	 */
	dma->tx.prod = 0;
	dma->tx.clean = 0;

	dma->rx.prod = 0;
	dma->rx.clean = 0;

	dma->rx_user_pending = false;
	dma->rx_user_logical = 0;
	dma->rx_user_generation = 0;

	dma_wmb();

	writel(0,
	       dma->regs + P07_TX_TAIL);

	writel(0,
	       dma->regs + P07_RX_TAIL);

	/*
	 * Completion/error IRQs are armed, but channels remain disabled.
	 *
	 * This is important on the current validation FPGA image:
	 * enabling RX would also arm the deterministic built-in AXIS
	 * source. Runtime RX will therefore enable the channel only when
	 * software has actually posted receive descriptors.
	 */
	atomic_set(&dma->irq_count, 0);
	atomic_set(&dma->irq_seen, 0);
	atomic_set(&dma->irq_thread_pending, 0);

	writel(P07_IRQ_ALL,
	       dma->regs + P07_IRQ_ENABLE);

	/*
	 * Global DMA infrastructure is enabled.
	 * Individual TX/RX channels remain idle.
	 */
	writel(P07_GLOBAL_ENABLE,
	       dma->regs + P07_GLOBAL_CONTROL);

	(void)readl(
		dma->regs + P07_GLOBAL_CONTROL);

	tx_head =
		readl(dma->regs + P07_TX_HEAD);

	rx_head =
		readl(dma->regs + P07_RX_HEAD);

	error_status =
		readl(dma->regs + P07_ERROR_STATUS);

	dev_info(dma->dev,
		 "Project07 Runtime10F state: tx_prod=%u tx_clean=%u tx_head=%u rx_prod=%u rx_clean=%u rx_head=%u error_status=0x%08x\n",
		 dma->tx.prod,
		 dma->tx.clean,
		 tx_head,
		 dma->rx.prod,
		 dma->rx.clean,
		 rx_head,
		 error_status);

	if (tx_head != 0 ||
	    rx_head != 0 ||
	    error_status != 0) {

		dev_err(dma->dev,
			"Project07 Runtime10F FAIL: initial runtime state is not clean\n");

		return -EIO;
	}

	return 0;
}

/* -------------------------------------------------------------------------- */
/* Runtime fault/reset recovery                                               */
/* -------------------------------------------------------------------------- */

static int project07_runtime_recover(
	struct project07_dma *dma,
	const char *reason,
	bool from_irq)
{
	unsigned long flags;

	u32 error_status;
	u32 error_info;
	u32 error_addr_lo;
	u32 error_addr_hi;

	u32 before_tx_prod;
	u32 before_tx_clean;
	u32 before_tx_head;

	u32 before_rx_prod;
	u32 before_rx_clean;
	u32 before_rx_head;

	u32 dropped_tx;
	u32 dropped_rx;

	u32 after_tx_head;
	u32 after_rx_head;
	u32 after_error;

	u64 error_addr;

	int saved_irq_count;
	int saved_irq_seen;

	int ret;

	if (!from_irq)
		disable_irq(
			dma->irq);

	/*
	 * Global recovery lock order:
	 *
	 *     tx_mutex -> rx_mutex
	 */
	mutex_lock(
		&dma->tx_mutex);

	mutex_lock(
		&dma->rx_mutex);

	error_status =
		readl(
			dma->regs +
				P07_ERROR_STATUS);

	error_info =
		readl(
			dma->regs +
				P07_ERROR_INFO);

	error_addr_lo =
		readl(
			dma->regs +
				P07_ERROR_ADDR_LO);

	error_addr_hi =
		readl(
			dma->regs +
				P07_ERROR_ADDR_HI);

	error_addr =
		((u64)error_addr_hi << 32) |
		(u64)error_addr_lo;

	before_tx_prod =
		dma->tx.prod;

	before_tx_clean =
		dma->tx.clean;

	before_tx_head =
		readl(
			dma->regs +
				P07_TX_HEAD);

	before_rx_prod =
		dma->rx.prod;

	before_rx_clean =
		dma->rx.clean;

	before_rx_head =
		readl(
			dma->regs +
				P07_RX_HEAD);

	dropped_tx =
		(u32)(
			before_tx_prod -
			before_tx_clean);

	/*
	 * The current userspace RX ABI permits only one outstanding
	 * read request.
	 */
	dropped_rx =
		dma->rx_user_pending ?
			1 : 0;

	saved_irq_count =
		atomic_read(
			&dma->irq_count);

	saved_irq_seen =
		atomic_read(
			&dma->irq_seen);

	spin_lock_irqsave(
		&dma->state_lock,
		flags);

	dma->runtime_faulted =
		true;

	dma->last_error_status =
		error_status;

	dma->last_error_info =
		error_info;

	dma->last_error_addr =
		error_addr;

	dma->last_recovery_dropped_tx =
		dropped_tx;

	dma->last_recovery_dropped_rx =
		dropped_rx;

	dma->recovery_dropped_tx +=
		dropped_tx;

	dma->recovery_dropped_rx +=
		dropped_rx;

	spin_unlock_irqrestore(
		&dma->state_lock,
		flags);

	dev_warn(dma->dev,
		 "Project07 Runtime10F recovery start: reason=%s error_status=0x%08x error_info=0x%08x error_addr=0x%016llx tx_prod=%u tx_clean=%u tx_head=%u rx_prod=%u rx_clean=%u rx_head=%u dropped_tx=%u dropped_rx=%u\n",
		 reason,
		 error_status,
		 error_info,
		 (unsigned long long)
			error_addr,
		 before_tx_prod,
		 before_tx_clean,
		 before_tx_head,
		 before_rx_prod,
		 before_rx_clean,
		 before_rx_head,
		 dropped_tx,
		 dropped_rx);

	ret =
		project07_hw_init(
			dma);

	/*
	 * hw_init establishes a new DMA hardware epoch.
	 * Preserve lifetime Linux interrupt history.
	 */
	atomic_set(
		&dma->irq_count,
		saved_irq_count);

	atomic_set(
		&dma->irq_seen,
		saved_irq_seen);

	atomic_set(
		&dma->irq_thread_pending,
		0);

	if (ret) {

		project07_hw_quiesce(
			dma);

		spin_lock_irqsave(
			&dma->state_lock,
			flags);

		dma->recovery_failures++;

		spin_unlock_irqrestore(
			&dma->state_lock,
			flags);

		dev_err(dma->dev,
			"Project07 Runtime10F recovery FAIL: reason=%s ret=%d\n",
			reason,
			ret);

		mutex_unlock(
			&dma->rx_mutex);

		mutex_unlock(
			&dma->tx_mutex);

		if (!from_irq)
			enable_irq(
				dma->irq);

		wake_up_all(
			&dma->tx_wait);

		wake_up_all(
			&dma->rx_wait);

		return ret;
	}

	after_tx_head =
		readl(
			dma->regs +
				P07_TX_HEAD);

	after_rx_head =
		readl(
			dma->regs +
				P07_RX_HEAD);

	after_error =
		readl(
			dma->regs +
				P07_ERROR_STATUS);

	spin_lock_irqsave(
		&dma->state_lock,
		flags);

	dma->runtime_faulted =
		false;

	dma->recovery_count++;

	spin_unlock_irqrestore(
		&dma->state_lock,
		flags);

	dev_info(dma->dev,
		 "Project07 Runtime10F recovery complete: reason=%s recovery_count=%u tx_prod=%u tx_clean=%u tx_head=%u rx_prod=%u rx_clean=%u rx_head=%u error_status=0x%08x\n",
		 reason,
		 dma->recovery_count,
		 dma->tx.prod,
		 dma->tx.clean,
		 after_tx_head,
		 dma->rx.prod,
		 dma->rx.clean,
		 after_rx_head,
		 after_error);

	mutex_unlock(
		&dma->rx_mutex);

	mutex_unlock(
		&dma->tx_mutex);

	if (!from_irq)
		enable_irq(
			dma->irq);

	wake_up_all(
		&dma->tx_wait);

	wake_up_all(
		&dma->rx_wait);

	return 0;
}


/* -------------------------------------------------------------------------- */
/* Probe                                                                      */
/* -------------------------------------------------------------------------- */

static int project07_dma_probe(struct platform_device *pdev)
{
	struct project07_dma *dma;
	size_t ring_bytes;
	u32 id;
	u32 version;
	int ret;

	BUILD_BUG_ON(sizeof(struct project07_desc) !=
		     P07_DESC_BYTES);

	BUILD_BUG_ON(
		(P07_RING_ENTRIES &
		 (P07_RING_ENTRIES - 1)) != 0);

	dma =
		devm_kzalloc(
			&pdev->dev,
			sizeof(*dma),
			GFP_KERNEL);

	if (!dma)
		return -ENOMEM;

	dma->dev = &pdev->dev;

	dma->regs =
		devm_platform_ioremap_resource(
			pdev, 0);

	if (IS_ERR(dma->regs))
		return PTR_ERR(dma->regs);

	id =
		readl(dma->regs + P07_ID);

	version =
		readl(dma->regs + P07_VERSION);

	dev_info(&pdev->dev,
		 "Project07 DMA probe: ID=0x%08x VERSION=0x%08x\n",
		 id,
		 version);

	if (id != P07_EXPECTED_ID ||
	    version != P07_EXPECTED_VERSION) {

		dev_err(&pdev->dev,
			"Project07 runtime hardware identity mismatch\n");

		return -ENODEV;
	}

	ret =
		dma_set_mask_and_coherent(
			&pdev->dev,
			DMA_BIT_MASK(P07_DMA_BITS));

	if (ret) {
		dev_err(&pdev->dev,
			"Project07 failed to establish %u-bit DMA mask\n",
			P07_DMA_BITS);

		return ret;
	}

	ring_bytes =
		P07_RING_ENTRIES *
		sizeof(struct project07_desc);

	dma->tx.desc =
		dmam_alloc_coherent(
			&pdev->dev,
			ring_bytes,
			&dma->tx.dma,
			GFP_KERNEL);

	if (!dma->tx.desc)
		return -ENOMEM;

	dma->rx.desc =
		dmam_alloc_coherent(
			&pdev->dev,
			ring_bytes,
			&dma->rx.dma,
			GFP_KERNEL);

	if (!dma->rx.desc)
		return -ENOMEM;

	dma->tx_payload_cpu =
		dmam_alloc_coherent(
			&pdev->dev,
			P07_TX_POOL_BYTES,
			&dma->tx_payload_dma,
			GFP_KERNEL);

	if (!dma->tx_payload_cpu)
		return -ENOMEM;

	dma->rx_payload_cpu =
		dmam_alloc_coherent(
			&pdev->dev,
			P07_RX_POOL_BYTES,
			&dma->rx_payload_dma,
			GFP_KERNEL);

	if (!dma->rx_payload_cpu)
		return -ENOMEM;

	memset(
		dma->tx_payload_cpu,
		0,
		P07_TX_POOL_BYTES);

	memset(
		dma->rx_payload_cpu,
		0,
		P07_RX_POOL_BYTES);

	/*
	 * DMA ring base must satisfy descriptor alignment.
	 */
	if ((dma->tx.dma & (P07_DESC_BYTES - 1)) ||
	    (dma->rx.dma & (P07_DESC_BYTES - 1))) {

		dev_err(&pdev->dev,
			"Project07 coherent ring base alignment failure\n");

		return -EINVAL;
	}

	if ((dma->tx_payload_dma & 0x7) ||
	    (dma->rx_payload_dma & 0x7)) {

		dev_err(&pdev->dev,
			"Project07 coherent payload alignment failure\n");

		return -EINVAL;
	}

	memset(dma->tx.desc,
	       0,
	       ring_bytes);

	memset(dma->rx.desc,
	       0,
	       ring_bytes);

	mutex_init(&dma->tx_mutex);
	mutex_init(&dma->rx_mutex);
	mutex_init(&dma->rx_user_mutex);

	spin_lock_init(&dma->state_lock);

	init_waitqueue_head(&dma->tx_wait);
	init_waitqueue_head(&dma->rx_wait);

	atomic_set(&dma->irq_count, 0);
	atomic_set(&dma->irq_seen, 0);
	atomic_set(&dma->irq_thread_pending, 0);

	dma->runtime_faulted = false;

	dma->recovery_count = 0;
	dma->recovery_failures = 0;

	dma->recovery_dropped_tx = 0;
	dma->last_recovery_dropped_tx = 0;

	dma->recovery_dropped_rx = 0;
	dma->last_recovery_dropped_rx = 0;

	dma->rx_user_pending = false;
	dma->rx_user_logical = 0;
	dma->rx_user_generation = 0;

	dma->last_error_status = 0;
	dma->last_error_info = 0;
	dma->last_error_addr = 0;

	dma->irq =
		platform_get_irq(pdev, 0);

	if (dma->irq < 0)
		return dma->irq;

	/*
	 * Prevent stale causes from asserting the level IRQ before
	 * Linux owns the handler.
	 */
	writel(0,
	       dma->regs + P07_IRQ_ENABLE);

	writel(P07_IRQ_ALL,
	       dma->regs + P07_IRQ_STATUS);

	(void)readl(
		dma->regs + P07_IRQ_STATUS);

	ret =
		devm_request_threaded_irq(
			&pdev->dev,
			dma->irq,
			project07_dma_irq,
			project07_dma_irq_thread,
			IRQF_ONESHOT,
			"project07-dma",
			dma);

	if (ret)
		return ret;

	platform_set_drvdata(
		pdev, dma);

	dev_info(&pdev->dev,
		 "Project07 IRQ registered: Linux IRQ %d\n",
		 dma->irq);

	dev_info(&pdev->dev,
		 "Project07 Runtime10F rings: tx_dma=%pad rx_dma=%pad tx_payload_dma=%pad rx_payload_dma=%pad entries=%u descriptor_bytes=%u\n",
		 &dma->tx.dma,
		 &dma->rx.dma,
		 &dma->tx_payload_dma,
		 &dma->rx_payload_dma,
		 P07_RING_ENTRIES,
		 P07_DESC_BYTES);

	ret =
		project07_hw_init(dma);

	if (ret) {
		project07_hw_quiesce(dma);
		return ret;
	}

	ret =
		device_create_file(
			&pdev->dev,
			&dev_attr_runtime_status);

	if (ret) {
		project07_hw_quiesce(dma);
		return ret;
	}

	dma->miscdev.minor =
		MISC_DYNAMIC_MINOR;

	dma->miscdev.name =
		"project07-dma";

	dma->miscdev.fops =
		&project07_fops;

	dma->miscdev.parent =
		&pdev->dev;

	dma->miscdev.mode =
		0600;

	ret =
		misc_register(
			&dma->miscdev);

	if (ret) {

		device_remove_file(
			&pdev->dev,
			&dev_attr_runtime_status);

		project07_hw_quiesce(
			dma);

		return ret;
	}

	dev_info(&pdev->dev,
		 "Project07 Runtime10F READY: /dev/project07-dma TX/RX runtime interface registered\n");

	dev_info(&pdev->dev,
		 "Project07 Runtime10F ABI v1: write=64-byte TX read=64-byte RX ioctls=GET_INFO,GET_STATS,RESET\n");

	dev_info(&pdev->dev,
		 "Project07 Runtime10F policy: driver-owned coherent DMA buffers; no userspace DMA addresses; no temporary recovery sysfs trigger\n");

	dev_info(&pdev->dev,
		 "Project07 runtime DMA hardware initialized successfully\n");

	return 0;
}

/* -------------------------------------------------------------------------- */
/* Remove                                                                     */
/* -------------------------------------------------------------------------- */

static int project07_dma_remove(struct platform_device *pdev)
{
	struct project07_dma *dma =
		platform_get_drvdata(pdev);

	if (dma)
		misc_deregister(
			&dma->miscdev);

	device_remove_file(
		&pdev->dev,
		&dev_attr_runtime_status);

	if (dma)
		project07_hw_quiesce(dma);

	dev_info(&pdev->dev,
		 "Project07 runtime DMA stopped\n");

	return 0;
}

/* -------------------------------------------------------------------------- */
/* Device Tree                                                                */
/* -------------------------------------------------------------------------- */

static const struct of_device_id project07_dma_of_match[] = {
	{
		.compatible =
			"xlnx,dma-ddr-gate-top-1.2"
	},
	{ }
};

MODULE_DEVICE_TABLE(
	of,
	project07_dma_of_match);

/* -------------------------------------------------------------------------- */
/* Platform driver                                                            */
/* -------------------------------------------------------------------------- */

static struct platform_driver project07_dma_driver = {
	.probe =
		project07_dma_probe,

	.remove =
		project07_dma_remove,

	.driver = {
		.name =
			"project07-dma",

		.of_match_table =
			project07_dma_of_match,
	},
};

module_platform_driver(
	project07_dma_driver);

MODULE_AUTHOR("Coltium Industries");
MODULE_DESCRIPTION("Project 07 Custom Descriptor-Ring DMA Runtime Linux Driver");
MODULE_LICENSE("GPL");
