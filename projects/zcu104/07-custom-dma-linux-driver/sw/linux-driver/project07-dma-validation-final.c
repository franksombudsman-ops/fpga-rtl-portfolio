// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/io.h>
#include <linux/interrupt.h>
#include <linux/dma-mapping.h>
#include <linux/delay.h>
#include <linux/bitops.h>
#include <linux/iopoll.h>

#define P07_ID                  0x000
#define P07_VERSION             0x004
#define P07_GLOBAL_CONTROL      0x008

#define P07_IRQ_STATUS          0x010
#define P07_IRQ_ENABLE          0x014
#define P07_ERROR_STATUS        0x018

#define P07_TX_CONTROL          0x100
#define P07_TX_BASE_LO          0x108
#define P07_TX_BASE_HI          0x10C
#define P07_TX_RING_SIZE        0x110
#define P07_TX_TAIL             0x114
#define P07_TX_HEAD             0x118
#define P07_TX_BYTES_LO         0x11C
#define P07_TX_BYTES_HI         0x120
#define P07_TX_DESC_COUNT       0x124

#define P07_GLOBAL_ENABLE       BIT(0)
#define P07_SOFT_RESET          BIT(1)
#define P07_COUNTER_CLEAR       BIT(2)

#define P07_TX_ENABLE           BIT(0)

#define P07_IRQ_TX_COMPLETE     BIT(0)
#define P07_IRQ_RX_COMPLETE     BIT(1)
#define P07_IRQ_TX_ERROR        BIT(2)
#define P07_IRQ_RX_ERROR        BIT(3)
#define P07_IRQ_ALL             0x0f

#define P07_EXPECTED_ID         0x43444D41
#define P07_EXPECTED_VERSION    0x00010000

#define P07_DMA_BITS            40
#define P07_RING_ENTRIES        16
#define P07_DESC_BYTES          64
#define P07_PAYLOAD_BYTES       64
#define P07_PHYS_BYTES          (P07_RING_ENTRIES * P07_PAYLOAD_BYTES)

#define P07_STAGE1_DESC         15
#define P07_STAGE1_BYTES        (P07_STAGE1_DESC * P07_PAYLOAD_BYTES)

#define P07_FINAL_TAIL          18
#define P07_FINAL_BYTES         (P07_FINAL_TAIL * P07_PAYLOAD_BYTES)

#define P07_POLL_DELAY_US       10
#define P07_TIMEOUT_US          1000000

struct project07_desc {
	__le64 buffer_addr;
	__le32 length;
	__le32 control;
	__le64 cookie;
	__le32 status;
	__le32 actual_length;
	u8 reserved[32];
};

struct project07_dma {
	void __iomem *regs;
	int irq;

	void *ring_cpu;
	dma_addr_t ring_dma;

	void *payload_cpu;
	dma_addr_t payload_dma;

	atomic_t irq_count;
	atomic_t seen_irq;
};

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
	atomic_or(pending, &dma->seen_irq);

	/* IRQ_STATUS is RW1C. */
	writel(pending,
	       dma->regs + P07_IRQ_STATUS);

	/* Flush acknowledgement for level-sensitive IRQ. */
	(void)readl(dma->regs + P07_IRQ_STATUS);

	return IRQ_HANDLED;
}

static u64 p07_read_tx_bytes(struct project07_dma *dma)
{
	return
		(u64)readl(dma->regs + P07_TX_BYTES_LO) |
		((u64)readl(dma->regs + P07_TX_BYTES_HI) << 32);
}

static int project07_gate9n(struct platform_device *pdev,
			    struct project07_dma *dma)
{
	struct device *dev = &pdev->dev;
	struct project07_desc *desc;
	__le64 *payload;

	u32 poll_value;
	u32 stage1_head;
	u32 stage1_desc;
	u64 stage1_bytes;

	u32 final_head;
	u32 final_desc;
	u64 final_bytes;

	u32 seen;
	u32 irq_after;
	u32 error_status;
	int irq_count;
	int ret;
	int i;
	int j;

	BUILD_BUG_ON(sizeof(struct project07_desc) !=
		     P07_DESC_BYTES);

	dma->ring_cpu =
		dmam_alloc_coherent(
			dev,
			P07_RING_ENTRIES * P07_DESC_BYTES,
			&dma->ring_dma,
			GFP_KERNEL);

	dma->payload_cpu =
		dmam_alloc_coherent(
			dev,
			P07_PHYS_BYTES,
			&dma->payload_dma,
			GFP_KERNEL);

	if (!dma->ring_cpu ||
	    !dma->payload_cpu)
		return -ENOMEM;

	memset(dma->ring_cpu,
	       0,
	       P07_RING_ENTRIES * P07_DESC_BYTES);

	memset(dma->payload_cpu,
	       0,
	       P07_PHYS_BYTES);

	desc = dma->ring_cpu;
	payload = dma->payload_cpu;

	/*
	 * Populate all 16 descriptors before launch.
	 * Stage 1 advertises only descriptors 0..14.
	 * Stage 2 changes TAIL 15 -> 0, advertising descriptor 15
	 * and forcing HEAD to wrap 15 -> 0.
	 */
	for (i = 0; i < P07_RING_ENTRIES; i++) {

		for (j = 0; j < 8; j++)
			payload[(i * 8) + j] =
				cpu_to_le64(
					0x9000000000000000ULL |
					((u64)i << 32) |
					(u64)j);

		desc[i].buffer_addr =
			cpu_to_le64(
				(u64)dma->payload_dma +
				(i * P07_PAYLOAD_BYTES));

		desc[i].length =
			cpu_to_le32(P07_PAYLOAD_BYTES);

		/* OWN | IRQ | EOP */
		desc[i].control =
			cpu_to_le32(0x7);

		desc[i].cookie =
			cpu_to_le64(
				0x394E000000000000ULL |
				(u64)i);

		desc[i].status =
			cpu_to_le32(0);

		desc[i].actual_length =
			cpu_to_le32(0);
	}

	dev_info(dev,
		 "Project07 Gate9N ring=%pad payload=%pad entries=%u total_bytes=%u\n",
		 &dma->ring_dma,
		 &dma->payload_dma,
		 P07_RING_ENTRIES,
		 P07_PHYS_BYTES);

	/*
	 * Known stopped/reset state.
	 */
	writel(0,
	       dma->regs + P07_IRQ_ENABLE);

	writel(0,
	       dma->regs + P07_TX_CONTROL);

	writel(P07_SOFT_RESET,
	       dma->regs + P07_GLOBAL_CONTROL);

	(void)readl(
		dma->regs + P07_GLOBAL_CONTROL);

	udelay(10);

	writel(P07_COUNTER_CLEAR,
	       dma->regs + P07_GLOBAL_CONTROL);

	writel(P07_IRQ_ALL,
	       dma->regs + P07_IRQ_STATUS);

	writel(0xffffffff,
	       dma->regs + P07_ERROR_STATUS);

	(void)readl(
		dma->regs + P07_IRQ_STATUS);

	atomic_set(&dma->irq_count, 0);
	atomic_set(&dma->seen_irq, 0);

	/*
	 * BASE first, SIZE last = configuration commit.
	 */
	writel(lower_32_bits(dma->ring_dma),
	       dma->regs + P07_TX_BASE_LO);

	writel(upper_32_bits(dma->ring_dma),
	       dma->regs + P07_TX_BASE_HI);

	writel(P07_RING_ENTRIES,
	       dma->regs + P07_TX_RING_SIZE);

	/*
	 * Publish all descriptor/payload writes before advertising tail.
	 */
	dma_wmb();

	/*
	 * Stage 1:
	 * HW_HEAD starts at 0.
	 * TAIL=15 advertises descriptors 0..14.
	 */
	writel(P07_STAGE1_DESC,
	       dma->regs + P07_TX_TAIL);

	writel(P07_IRQ_TX_COMPLETE |
	       P07_IRQ_TX_ERROR,
	       dma->regs + P07_IRQ_ENABLE);

	writel(P07_GLOBAL_ENABLE,
	       dma->regs + P07_GLOBAL_CONTROL);

	writel(P07_TX_ENABLE,
	       dma->regs + P07_TX_CONTROL);

	(void)readl(
		dma->regs + P07_TX_CONTROL);

	dev_info(dev,
		 "Project07 Gate9N stage1 launched: tail=15, expecting head=15\n");

	/*
	 * Use descriptor count as the authoritative stage-completion
	 * condition. This avoids interrupt-coalescing assumptions.
	 */
	ret =
		readl_poll_timeout(
			dma->regs + P07_TX_DESC_COUNT,
			poll_value,
			poll_value == P07_STAGE1_DESC,
			P07_POLL_DELAY_US,
			P07_TIMEOUT_US);

	if (ret) {
		dev_err(dev,
			"Project07 Gate9N FAIL: stage1 descriptor-count timeout, count=%u head=%u\n",
			poll_value,
			readl(dma->regs + P07_TX_HEAD));
		return ret;
	}

	dma_rmb();

	stage1_head =
		readl(dma->regs + P07_TX_HEAD);

	stage1_desc =
		readl(dma->regs + P07_TX_DESC_COUNT);

	stage1_bytes =
		p07_read_tx_bytes(dma);

	dev_info(dev,
		 "Project07 Gate9N pre-wrap: head=%u bytes=%llu desc=%u\n",
		 stage1_head,
		 (unsigned long long)stage1_bytes,
		 stage1_desc);

	if (stage1_head != 15 ||
	    stage1_desc != 15 ||
	    stage1_bytes != P07_STAGE1_BYTES) {
		dev_err(dev,
			"Project07 Gate9N FAIL: pre-wrap state mismatch\n");
		return -EIO;
	}

	/*
	 * Stage 2 — real wrap:
	 *
	 * HEAD/TAIL are monotonically increasing logical indices.
	 * Physical descriptor selection is logical_index & ring_mask.
	 *
	 * HEAD=15, then publish TAIL=18:
	 *
	 * logical 15 -> physical slot 15
	 * logical 16 -> physical slot 0
	 * logical 17 -> physical slot 1
	 *
	 * Slots 0 and 1 were consumed during stage 1, so re-arm them
	 * before publishing logical tail 18.
	 */
	for (i = 0; i < 2; i++) {
		desc[i].control =
			cpu_to_le32(0x7);

		desc[i].status =
			cpu_to_le32(0);

		desc[i].actual_length =
			cpu_to_le32(0);

		desc[i].cookie =
			cpu_to_le64(
				0x394E000000000000ULL |
				(u64)(16 + i));
	}

	dma_wmb();

	writel(P07_FINAL_TAIL,
	       dma->regs + P07_TX_TAIL);

	(void)readl(
		dma->regs + P07_TX_TAIL);

	dev_info(dev,
		 "Project07 Gate9N wrap submitted: logical tail 15->18; physical slots 15->0->1; expecting head=18\n");

	/*
	 * Poll total completed descriptors rather than HEAD=0 because
	 * HEAD was also 0 before the original launch.
	 */
	ret =
		readl_poll_timeout(
			dma->regs + P07_TX_DESC_COUNT,
			poll_value,
			poll_value == P07_FINAL_TAIL,
			P07_POLL_DELAY_US,
			P07_TIMEOUT_US);

	if (ret) {
		dev_err(dev,
			"Project07 Gate9N FAIL: wrap completion timeout, count=%u head=%u\n",
			poll_value,
			readl(dma->regs + P07_TX_HEAD));
		return ret;
	}

	/*
	 * Give the Linux IRQ handler time to service the final
	 * completion if descriptor completion won the poll race.
	 */
	usleep_range(1000, 2000);

	dma_rmb();

	final_head =
		readl(dma->regs + P07_TX_HEAD);

	final_desc =
		readl(dma->regs + P07_TX_DESC_COUNT);

	final_bytes =
		p07_read_tx_bytes(dma);

	seen =
		atomic_read(&dma->seen_irq);

	irq_count =
		atomic_read(&dma->irq_count);

	irq_after =
		readl(dma->regs + P07_IRQ_STATUS);

	error_status =
		readl(dma->regs + P07_ERROR_STATUS);

	dev_info(dev,
		 "Project07 Gate9N final: irq_count=%d seen_irq=0x%08x irq_after=0x%08x error_status=0x%08x head=%u bytes=%llu desc=%u\n",
		 irq_count,
		 seen,
		 irq_after,
		 error_status,
		 final_head,
		 (unsigned long long)final_bytes,
		 final_desc);

	for (i = 0; i < P07_RING_ENTRIES; i++) {

		u32 control =
			le32_to_cpu(desc[i].control);

		u32 status =
			le32_to_cpu(desc[i].status);

		u32 actual =
			le32_to_cpu(desc[i].actual_length);

		dev_info(dev,
			 "Project07 Gate9N desc[%d]: control=0x%08x status=0x%08x actual=%u cookie=0x%016llx\n",
			 i,
			 control,
			 status,
			 actual,
			 (unsigned long long)
			 le64_to_cpu(desc[i].cookie));
	}

	/*
	 * Quiet hardware after evidence collection.
	 */
	writel(0,
	       dma->regs + P07_IRQ_ENABLE);

	writel(0,
	       dma->regs + P07_TX_CONTROL);

	writel(0,
	       dma->regs + P07_GLOBAL_CONTROL);

	if (seen & P07_IRQ_TX_ERROR) {
		dev_err(dev,
			"Project07 Gate9N FAIL: TX error IRQ seen=0x%08x\n",
			seen);
		return -EIO;
	}

	if (!(seen & P07_IRQ_TX_COMPLETE)) {
		dev_err(dev,
			"Project07 Gate9N FAIL: no TX completion IRQ observed\n");
		return -EIO;
	}

	if (irq_count < 1) {
		dev_err(dev,
			"Project07 Gate9N FAIL: Linux observed no IRQ\n");
		return -EIO;
	}

	if (irq_after != 0 ||
	    error_status != 0) {
		dev_err(dev,
			"Project07 Gate9N FAIL: irq_after=0x%08x error_status=0x%08x\n",
			irq_after,
			error_status);
		return -EIO;
	}

	if (final_head != P07_FINAL_TAIL) {
		dev_err(dev,
			"Project07 Gate9N FAIL: TX_HEAD=%u expected logical head %u\n",
			final_head,
			P07_FINAL_TAIL);
		return -EIO;
	}

	if (final_desc != P07_FINAL_TAIL) {
		dev_err(dev,
			"Project07 Gate9N FAIL: TX_DESC_COUNT=%u expected %u\n",
			final_desc,
			P07_FINAL_TAIL);
		return -EIO;
	}

	if (final_bytes != P07_FINAL_BYTES) {
		dev_err(dev,
			"Project07 Gate9N FAIL: TX_BYTES=%llu expected %u\n",
			(unsigned long long)final_bytes,
			P07_FINAL_BYTES);
		return -EIO;
	}

	for (i = 0; i < P07_RING_ENTRIES; i++) {

		if (le32_to_cpu(desc[i].control) != 0x6 ||
		    le32_to_cpu(desc[i].status) != 0x1 ||
		    le32_to_cpu(desc[i].actual_length) !=
		    P07_PAYLOAD_BYTES) {

			dev_err(dev,
				"Project07 Gate9N FAIL: descriptor %d retirement mismatch\n",
				i);

			return -EIO;
		}
	}

	dev_info(dev,
		 "Project07 Gate9N PASS: Linux logical HEAD crossed 15->18 while physical descriptor slots wrapped 15->0->1\n");

	return 0;
}

static int project07_dma_probe(struct platform_device *pdev)
{
	struct project07_dma *dma;
	u32 id;
	u32 version;
	int ret;

	dma =
		devm_kzalloc(
			&pdev->dev,
			sizeof(*dma),
			GFP_KERNEL);

	if (!dma)
		return -ENOMEM;

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
	    version != P07_EXPECTED_VERSION)
		return -ENODEV;

	ret =
		dma_set_mask_and_coherent(
			&pdev->dev,
			DMA_BIT_MASK(P07_DMA_BITS));

	if (ret)
		return ret;

	atomic_set(&dma->irq_count, 0);
	atomic_set(&dma->seen_irq, 0);

	dma->irq =
		platform_get_irq(pdev, 0);

	if (dma->irq < 0)
		return dma->irq;

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

	platform_set_drvdata(pdev, dma);

	dev_info(&pdev->dev,
		 "Project07 IRQ registered: Linux IRQ %d\n",
		 dma->irq);

	ret =
		project07_gate9n(
			pdev, dma);

	if (ret)
		return ret;

	dev_info(&pdev->dev,
		 "Project07 custom DMA hardware identified successfully\n");

	return 0;
}

static const struct of_device_id project07_dma_of_match[] = {
	{ .compatible = "xlnx,dma-ddr-gate-top-1.2" },
	{ }
};
MODULE_DEVICE_TABLE(of, project07_dma_of_match);

static struct platform_driver project07_dma_driver = {
	.probe = project07_dma_probe,
	.driver = {
		.name = "project07-dma",
		.of_match_table = project07_dma_of_match,
	},
};

module_platform_driver(project07_dma_driver);

MODULE_AUTHOR("Coltium Industries");
MODULE_DESCRIPTION("Project 07 Custom Descriptor-Ring DMA Linux driver");
MODULE_LICENSE("GPL");
