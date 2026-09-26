// SPDX-License-Identifier: GPL-2.0
/*
 * Bench probe: replay the msm-4.4 LMh bring-up on MSM8998, one step per bit.
 *  bit0: enable the LMh DCVS thermal algorithm (msm_lmh_dcvs.c probe)
 *  bit1: arm/high/low thermal thresholds 65/85/84.5 C (CONFIG_LGE_PM values)
 *  bit2: switch to limits profile 1 (lmh_lite.c, qcom,lmh_v1)
 *  bit3: enable reliability and current algorithms (msm_thermal.c, msm8998)
 *  bit4: enable the BCL algorithm (mainline sdm845 only)
 *  bit5/bit6: disable reliability / current;  bit7/bit8: enable reliability / current alone
 */
#include <linux/module.h>
#include <linux/firmware/qcom/qcom_scm.h>

#define NODE_DCVS	0x44435653
#define FN_THERMAL	0x54484D4C
#define FN_CRNT		0x43524E54
#define FN_REL		0x52454C00
#define FN_BCL		0x42434C00
#define ALGO_ENABLE	0x454E424C
#define TH_HI		0x48494748
#define TH_LOW		0x4C4F5700
#define TH_ARM		0x41524D00

static int steps = 1;
module_param(steps, int, 0444);

static void dcvsh(const char *what, u32 fn, u32 reg, u32 val)
{
	static const u32 nodes[] = { 0x6370302D, 0x6370312D };
	int i;

	for (i = 0; i < 2; i++)
		pr_info("lmhprof: cluster%d %s: %d\n", i, what,
			qcom_scm_lmh_dcvsh(fn, reg, val, NODE_DCVS, nodes[i], 0));
}

static int __init lmhprof_init(void)
{
	pr_info("lmhprof: steps=%#x dcvsh_available=%d\n", steps,
		qcom_scm_lmh_dcvsh_available());
	if (steps & BIT(3)) {
		dcvsh("rel enable", FN_REL, ALGO_ENABLE, 1);
		dcvsh("crnt enable", FN_CRNT, ALGO_ENABLE, 1);
	}
	if (steps & BIT(5))
		dcvsh("rel disable", FN_REL, ALGO_ENABLE, 0);
	if (steps & BIT(6))
		dcvsh("crnt disable", FN_CRNT, ALGO_ENABLE, 0);
	if (steps & BIT(7))
		dcvsh("rel enable", FN_REL, ALGO_ENABLE, 1);
	if (steps & BIT(8))
		dcvsh("crnt enable", FN_CRNT, ALGO_ENABLE, 1);
	if (steps & BIT(4))
		dcvsh("bcl enable", FN_BCL, ALGO_ENABLE, 1);
	if (steps & BIT(0))
		dcvsh("thermal enable", FN_THERMAL, ALGO_ENABLE, 1);
	if (steps & BIT(1)) {
		dcvsh("thermal hi", FN_THERMAL, TH_HI, 85000);
		dcvsh("thermal low", FN_THERMAL, TH_LOW, 84500);
		dcvsh("thermal arm", FN_THERMAL, TH_ARM, 65000);
	}
	if (steps & BIT(2))
		pr_info("lmhprof: profile 1: %d\n", qcom_scm_lmh_profile_change(1));
	return 0;
}

static void __exit lmhprof_exit(void) { }

module_init(lmhprof_init);
module_exit(lmhprof_exit);
MODULE_DESCRIPTION("MSM8998 LMh bring-up bench probe");
MODULE_LICENSE("GPL");
