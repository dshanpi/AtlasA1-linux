// SPDX-License-Identifier: GPL-2.0-only
/* Temporary PG/PM withstand-mode trial. T736 manual v0.92, printed
 * pp.1589/1935: 01=auto, 10=3.3V, 11=1.8V. Does not change PMIC voltage.
 * Use only with SDIO1 unbound and the v47 pinctrl drivers, which leave these
 * fields untouched. Remove after SDIO1 is unbound to restore saved fields.
 */
#include <linux/module.h>
#include <linux/io.h>
#include <linux/delay.h>

static unsigned int mode = 1;
module_param(mode, uint, 0444);
MODULE_PARM_DESC(mode, "1=automatic; 3=manual 1.8V; no other modes permitted");
static void __iomem *pg, *pm;
static u32 old_pg, old_pm;
#define PG_MASK (3U << 12)
#define PM_MASK (3U << 2)

static void restore(void)
{
	writel((readl(pm) & ~PM_MASK) | (old_pm & PM_MASK), pm);
	writel((readl(pg) & ~PG_MASK) | (old_pg & PG_MASK), pg);
	pr_info("atlas-wireless-pad restored PG=%08x PM=%08x\n",
		readl(pg), readl(pm));
}

static int __init trial(void)
{
	if (mode != 1 && mode != 3)
		return -EINVAL;
	pg = ioremap(0x02000040, 12);
	pm = ioremap(0x07025340, 12);
	if (!pg || !pm) {
		if (pg) iounmap(pg);
		if (pm) iounmap(pm);
		return -ENOMEM;
	}
	old_pg = readl(pg);
	old_pm = readl(pm);
	pr_info("atlas-wireless-pad before PG=%08x val=%08x PM=%08x val=%08x\n",
		old_pg, readl(pg + 8), old_pm, readl(pm + 8));
	writel((old_pg & ~PG_MASK) | (mode << 12), pg);
	writel((old_pm & ~PM_MASK) | (mode << 2), pm);
	if ((readl(pg) & PG_MASK) != mode << 12 ||
	    (readl(pm) & PM_MASK) != mode << 2) {
		restore();
		iounmap(pm);
		iounmap(pg);
		return -EIO;
	}
	msleep(20);
	pr_info("atlas-wireless-pad mode=%u PG=%08x val=%08x PM=%08x val=%08x\n",
		mode, readl(pg), readl(pg + 8), readl(pm), readl(pm + 8));
	return 0;
}

static void __exit done(void)
{
	restore();
	iounmap(pm);
	iounmap(pg);
}
module_init(trial);
module_exit(done);
MODULE_LICENSE("GPL");
