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

/*
 * Project 07 — Runtime Linux DMA Driver
 *
 * Phase 10A:
 *   - persistent coherent TX/RX descriptor rings
 *   - monotonic software producer/reclaim indices
 *   - physical slot = logical_index & (ring_size - 1)
 *   - Linux IRQ infrastructure
 *   - hardware ring configuration
 *   - clean idle runtime state
 *
 * No synthetic descriptor traffic is submitted in this phase.
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
		 "Project07 Runtime10A state: tx_prod=%u tx_clean=%u tx_head=%u rx_prod=%u rx_clean=%u rx_head=%u error_status=0x%08x\n",
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
			"Project07 Runtime10A FAIL: initial runtime state is not clean\n");

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

	/*
	 * DMA ring base must satisfy descriptor alignment.
	 */
	if ((dma->tx.dma & (P07_DESC_BYTES - 1)) ||
	    (dma->rx.dma & (P07_DESC_BYTES - 1))) {

		dev_err(&pdev->dev,
			"Project07 coherent ring base alignment failure\n");

		return -EINVAL;
	}

	memset(dma->tx.desc,
	       0,
	       ring_bytes);

	memset(dma->rx.desc,
	       0,
	       ring_bytes);

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
		 "Project07 Runtime10A rings: tx_dma=%pad rx_dma=%pad entries=%u descriptor_bytes=%u\n",
		 &dma->tx.dma,
		 &dma->rx.dma,
		 P07_RING_ENTRIES,
		 P07_DESC_BYTES);

	ret =
		project07_hw_init(dma);

	if (ret) {
		project07_hw_quiesce(dma);
		return ret;
	}

	dev_info(&pdev->dev,
		 "Project07 Runtime10A READY: persistent coherent TX/RX rings configured; channels idle\n");

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
