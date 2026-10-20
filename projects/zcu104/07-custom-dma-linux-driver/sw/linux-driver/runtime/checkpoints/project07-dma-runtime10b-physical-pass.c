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
#include <linux/jiffies.h>
#include <linux/device.h>

/*
 * Project 07 — Runtime Linux DMA Driver
 *
 * Phase 10B:
 *   - persistent coherent TX/RX descriptor rings
 *   - persistent coherent TX payload pool
 *   - monotonic software producer/reclaim indices
 *   - runtime TX descriptor publication
 *   - IRQ-driven completion
 *   - HW_HEAD-authoritative reclaim
 *   - temporary controlled sysfs validation trigger
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
#define P07_TX_TIMEOUT_MS       1000

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

	struct project07_ring tx;
	struct project07_ring rx;

	void *tx_payload_cpu;
	dma_addr_t tx_payload_dma;

	struct mutex tx_mutex;
	spinlock_t state_lock;

	wait_queue_head_t tx_wait;
	wait_queue_head_t rx_wait;

	atomic_t irq_count;
	atomic_t irq_seen;
};

/* -------------------------------------------------------------------------- */
/* Interrupt handler                                                          */
/* -------------------------------------------------------------------------- */

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

	/*
	 * IRQ_STATUS is RW1C.
	 */
	writel(pending,
	       dma->regs + P07_IRQ_STATUS);

	/*
	 * Flush write before returning from a level-sensitive ISR.
	 */
	(void)readl(
		dma->regs + P07_IRQ_STATUS);

	if (pending &
	    (P07_IRQ_TX_COMPLETE |
	     P07_IRQ_TX_ERROR))
		wake_up_all(&dma->tx_wait);

	if (pending &
	    (P07_IRQ_RX_COMPLETE |
	     P07_IRQ_RX_ERROR))
		wake_up_all(&dma->rx_wait);

	return IRQ_HANDLED;
}


/* -------------------------------------------------------------------------- */
/* Runtime TX reclaim                                                         */
/* -------------------------------------------------------------------------- */

static u64 project07_read_tx_bytes(struct project07_dma *dma)
{
	return
		(u64)readl(dma->regs + P07_TX_BYTES_LO) |
		((u64)readl(dma->regs + P07_TX_BYTES_HI) << 32);
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
				"Project07 Runtime10B reclaim FAIL: logical=%u slot=%u control=0x%08x status=0x%08x actual=%u\n",
				logical,
				slot,
				control,
				status,
				actual);

			return -EIO;
		}

		dev_info(dma->dev,
			 "Project07 Runtime10B reclaim: logical=%u slot=%u control=0x%08x status=0x%08x actual=%u cookie=0x%016llx\n",
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
/* Runtime TX submission                                                      */
/* -------------------------------------------------------------------------- */

static int project07_tx_submit_test(struct project07_dma *dma)
{
	struct project07_desc *desc;
	__le64 *payload;
	dma_addr_t payload_dma;

	unsigned long timeout;

	u32 logical;
	u32 slot;
	u32 irq_before;
	u32 irq_after;
	u32 hw_head;
	u32 error_status;
	u32 tx_desc_count;
	u64 tx_bytes;

	int reclaimed;
	int i;
	int ret = 0;

	mutex_lock(&dma->tx_mutex);

	/*
	 * Reclaim anything hardware may already have completed before
	 * checking ring occupancy.
	 */
	reclaimed =
		project07_tx_reclaim(dma);

	if (reclaimed < 0) {
		ret = reclaimed;
		goto out_unlock;
	}

	if ((u32)(dma->tx.prod - dma->tx.clean) >=
	    P07_RING_ENTRIES) {

		dev_err(dma->dev,
			"Project07 Runtime10B submit FAIL: TX ring full prod=%u clean=%u\n",
			dma->tx.prod,
			dma->tx.clean);

		ret = -EBUSY;
		goto out_unlock;
	}

	logical =
		dma->tx.prod;

	slot =
		logical & P07_RING_MASK;

	desc =
		&dma->tx.desc[slot];

	payload =
		(__le64 *)dma->tx_payload_cpu +
		(slot * (P07_PAYLOAD_BYTES / sizeof(__le64)));

	payload_dma =
		dma->tx_payload_dma +
		(slot * P07_PAYLOAD_BYTES);

	/*
	 * Distinct deterministic payload for each logical submission.
	 */
	for (i = 0; i < 8; i++)
		payload[i] =
			cpu_to_le64(
				0x10B0000000000000ULL |
				((u64)logical << 16) |
				(u64)i);

	memset(desc, 0, sizeof(*desc));

	desc->buffer_addr =
		cpu_to_le64((u64)payload_dma);

	desc->length =
		cpu_to_le32(P07_PAYLOAD_BYTES);

	/*
	 * OWN | IRQ | EOP
	 */
	desc->control =
		cpu_to_le32(0x7);

	desc->cookie =
		cpu_to_le64(
			0x3130420000000000ULL |
			(u64)logical);

	/*
	 * Clear stale latched TX causes before this submission.
	 */
	writel(P07_IRQ_TX_COMPLETE |
	       P07_IRQ_TX_ERROR,
	       dma->regs + P07_IRQ_STATUS);

	(void)readl(
		dma->regs + P07_IRQ_STATUS);

	irq_before =
		atomic_read(&dma->irq_count);

	/*
	 * Publish payload + descriptor before advertising the new tail.
	 */
	dma_wmb();

	dma->tx.prod =
		logical + 1;

	/*
	 * Keep TX enabled as a persistent runtime channel.
	 * With HEAD == TAIL it remains idle.
	 */
	writel(P07_CHANNEL_ENABLE,
	       dma->regs + P07_TX_CONTROL);

	writel(dma->tx.prod,
	       dma->regs + P07_TX_TAIL);

	(void)readl(
		dma->regs + P07_TX_TAIL);

	dev_info(dma->dev,
		 "Project07 Runtime10B submit: logical=%u slot=%u tx_prod=%u tx_clean=%u tail=%u payload_dma=%pad\n",
		 logical,
		 slot,
		 dma->tx.prod,
		 dma->tx.clean,
		 dma->tx.prod,
		 &payload_dma);

	/*
	 * Completion is IRQ-driven.
	 *
	 * Reclaim itself remains HW_HEAD-authoritative.
	 */
	timeout =
		wait_event_timeout(
			dma->tx_wait,
			atomic_read(&dma->irq_count) != irq_before,
			msecs_to_jiffies(P07_TX_TIMEOUT_MS));

	if (!timeout) {

		hw_head =
			readl(dma->regs + P07_TX_HEAD);

		dev_err(dma->dev,
			"Project07 Runtime10B submit FAIL: TX completion timeout prod=%u clean=%u head=%u\n",
			dma->tx.prod,
			dma->tx.clean,
			hw_head);

		ret = -ETIMEDOUT;
		goto out_unlock;
	}

	irq_after =
		atomic_read(&dma->irq_count);

	error_status =
		readl(dma->regs + P07_ERROR_STATUS);

	if ((atomic_read(&dma->irq_seen) &
	     P07_IRQ_TX_ERROR) ||
	    error_status != 0) {

		dev_err(dma->dev,
			"Project07 Runtime10B submit FAIL: TX error irq_seen=0x%08x error_status=0x%08x\n",
			atomic_read(&dma->irq_seen),
			error_status);

		ret = -EIO;
		goto out_unlock;
	}

	reclaimed =
		project07_tx_reclaim(dma);

	if (reclaimed < 0) {
		ret = reclaimed;
		goto out_unlock;
	}

	hw_head =
		readl(dma->regs + P07_TX_HEAD);

	tx_desc_count =
		readl(dma->regs + P07_TX_DESC_COUNT);

	tx_bytes =
		project07_read_tx_bytes(dma);

	dev_info(dma->dev,
		 "Project07 Runtime10B state: irq_before=%u irq_after=%u tx_prod=%u tx_clean=%u tx_head=%u bytes=%llu desc=%u error_status=0x%08x\n",
		 irq_before,
		 irq_after,
		 dma->tx.prod,
		 dma->tx.clean,
		 hw_head,
		 (unsigned long long)tx_bytes,
		 tx_desc_count,
		 error_status);

	if (dma->tx.clean != dma->tx.prod ||
	    hw_head != dma->tx.prod ||
	    tx_desc_count != dma->tx.prod ||
	    tx_bytes !=
		((u64)dma->tx.prod *
		 P07_PAYLOAD_BYTES)) {

		dev_err(dma->dev,
			"Project07 Runtime10B submit FAIL: runtime TX accounting mismatch\n");

		ret = -EIO;
		goto out_unlock;
	}

	dev_info(dma->dev,
		 "Project07 Runtime10B PASS: persistent TX descriptor submitted and reclaimed through HW_HEAD\n");

out_unlock:
	mutex_unlock(&dma->tx_mutex);

	return ret;
}

/* -------------------------------------------------------------------------- */
/* Temporary Phase 10B validation controls                                    */
/* -------------------------------------------------------------------------- */

static ssize_t runtime_tx_test_store(
	struct device *dev,
	struct device_attribute *attr,
	const char *buf,
	size_t count)
{
	struct project07_dma *dma =
		dev_get_drvdata(dev);

	bool run;
	int ret;

	if (!dma)
		return -ENODEV;

	ret =
		kstrtobool(buf, &run);

	if (ret)
		return ret;

	if (!run)
		return -EINVAL;

	ret =
		project07_tx_submit_test(dma);

	if (ret)
		return ret;

	return count;
}

static DEVICE_ATTR_WO(runtime_tx_test);

static ssize_t runtime_status_show(
	struct device *dev,
	struct device_attribute *attr,
	char *buf)
{
	struct project07_dma *dma =
		dev_get_drvdata(dev);

	u32 tx_head;
	u32 tx_desc;
	u32 rx_head;
	u32 error_status;
	u64 tx_bytes;

	if (!dma)
		return -ENODEV;

	tx_head =
		readl(dma->regs + P07_TX_HEAD);

	tx_desc =
		readl(dma->regs + P07_TX_DESC_COUNT);

	rx_head =
		readl(dma->regs + P07_RX_HEAD);

	error_status =
		readl(dma->regs + P07_ERROR_STATUS);

	tx_bytes =
		project07_read_tx_bytes(dma);

	return sysfs_emit(
		buf,
		"tx_prod=%u tx_clean=%u tx_head=%u tx_bytes=%llu tx_desc=%u rx_prod=%u rx_clean=%u rx_head=%u irq_count=%d irq_seen=0x%08x error_status=0x%08x\n",
		dma->tx.prod,
		dma->tx.clean,
		tx_head,
		(unsigned long long)tx_bytes,
		tx_desc,
		dma->rx.prod,
		dma->rx.clean,
		rx_head,
		atomic_read(&dma->irq_count),
		atomic_read(&dma->irq_seen),
		error_status);
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
		 "Project07 Runtime10B state: tx_prod=%u tx_clean=%u tx_head=%u rx_prod=%u rx_clean=%u rx_head=%u error_status=0x%08x\n",
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
			"Project07 Runtime10B FAIL: initial runtime state is not clean\n");

		return -EIO;
	}

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

	memset(dma->tx_payload_cpu,
	       0,
	       P07_TX_POOL_BYTES);

	/*
	 * DMA ring base must satisfy descriptor alignment.
	 */
	if ((dma->tx.dma & (P07_DESC_BYTES - 1)) ||
	    (dma->rx.dma & (P07_DESC_BYTES - 1))) {

		dev_err(&pdev->dev,
			"Project07 coherent ring base alignment failure\n");

		return -EINVAL;
	}

	if (dma->tx_payload_dma & 0x7) {

		dev_err(&pdev->dev,
			"Project07 coherent TX payload alignment failure\n");

		return -EINVAL;
	}

	memset(dma->tx.desc,
	       0,
	       ring_bytes);

	memset(dma->rx.desc,
	       0,
	       ring_bytes);

	mutex_init(&dma->tx_mutex);
	spin_lock_init(&dma->state_lock);

	init_waitqueue_head(&dma->tx_wait);
	init_waitqueue_head(&dma->rx_wait);

	atomic_set(&dma->irq_count, 0);
	atomic_set(&dma->irq_seen, 0);

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
		devm_request_irq(
			&pdev->dev,
			dma->irq,
			project07_dma_irq,
			0,
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
		 "Project07 Runtime10B rings: tx_dma=%pad rx_dma=%pad tx_payload_dma=%pad entries=%u descriptor_bytes=%u\n",
		 &dma->tx.dma,
		 &dma->rx.dma,
		 &dma->tx_payload_dma,
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

	ret =
		device_create_file(
			&pdev->dev,
			&dev_attr_runtime_tx_test);

	if (ret) {
		device_remove_file(
			&pdev->dev,
			&dev_attr_runtime_status);

		project07_hw_quiesce(dma);
		return ret;
	}

	dev_info(&pdev->dev,
		 "Project07 Runtime10B READY: persistent rings configured; runtime TX submission ready\n");

	dev_info(&pdev->dev,
		 "Project07 Runtime10B control: runtime_status=RO runtime_tx_test=WO\n");

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

	device_remove_file(
		&pdev->dev,
		&dev_attr_runtime_tx_test);

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
