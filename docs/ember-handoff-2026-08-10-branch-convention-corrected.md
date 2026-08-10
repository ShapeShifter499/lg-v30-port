# Handoff to Aurel — 2026-08-10: your integration verified, branch convention corrected

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-10

Short version: your integration work is correct and I verified it
independently rather than taking it on trust. One thing in your handoff
needs amending — the branch convention is recorded backwards from what
Lance actually wants — and I have implemented his version, so the doc
should be updated before the next session follows the stale one.

## Your work: verified

I re-derived each load-bearing claim instead of reading it:

- `master` and `joan/latest-clean-test` were both `47041183b`; the GitHub
  compare API returned `status: identical, 0 ahead, 0 behind`.
- Merge `47041183b` has exactly the parents you documented:
  `72c736ae7` (old master, PR #5) + `7ba1c0f1f` (latest-clean-test tip),
  authored by Lance.
- **The tree invariant holds.** All seven joan files on master are
  byte-identical to my device-tested `ember/joan-fixes-v2`:
  `msm8998-lge-joan.dts`, `hci_qca.c`, `stmfts.c`, `panel-lg-sw43402.c`,
  `interconnect/qcom/msm8998.c`, `a5xx_catalog.c`, `drm_atomic.c`.
  That last pair matters: it confirms the GDSC revert landed (back to
  upstream 250 ms) and the TEMP-DIAG drm prints are gone.
- PRs: none open. #1-#4 merged to latest-clean-test, #5 merged to master
  on 2026-08-08, #6 and #7 closed as superseded. Closing #7 was the right
  call — it still carried the ungated quirk.

Your correction to me was right, too: I wrote "PRs #5 and #7 parked,
untouched" when Lance had already merged #5. Noted and fixed.

## The open decision, quantified

You flagged that master's combined tree (newer upstream base + our joan
files) had never been booted as a unit. I measured what the drift
actually touches, comparing the tested base `9bfc50add` against master:

    drivers/gpu/drm/msm            0 files
    drivers/interconnect/qcom      0 files
    drivers/clk/qcom               0 files
    drivers/soc/qcom               0 files
    drivers/power/supply           0 files
    drivers/remoteproc             0 files
    drivers/input/touchscreen      1  (ours)
    arch/arm64/boot/dts/qcom       1  (ours)
    drivers/gpu/drm/panel          1  (ours)
    net/bluetooth                 12  (upstream drift)
    drivers/bluetooth              5  (4 upstream + ours)

So GPU, interconnect, clocks, modem, battery and touch all sit on an
identical base to what booted. Bluetooth is the only real exposure, and
the three things our BT fix depends on are untouched:

- `hci_sync.c`: `invalid_bdaddr`, `HCI_QUIRK_USE_BDADDR_PROPERTY`,
  `HCI_UNCONFIGURED`, `hci_dev_get_bd_addr_from_property` — unchanged
- `mgmt.c`: `set_public_address`, `is_configured`, unconf index — unchanged
- `hci_qca.c`: the only delta is our own gated block, no drift underneath

Remaining untested surface is a 14-line `hci_ldisc.c` change plus BT core
churn that misses our mechanism. Low risk, and BT is the one thing we can
test objectively in seconds (mgmt index lists + `bluetoothctl`). A
from-scratch build of master's tree is running as I write this; boot
verification follows.

## Branch convention — please amend your doc

Your handoff records:

> joan/latest-clean-test = WORKING/staging branch. Confirmed fixes
> accumulate there, in a sensible order. master = STABLE. Receives PRs
> from latest-clean-test containing ONLY the commits that worked.

Lance's actual intent, stated today:

> "master should be verified fixes while joan/latest-clean-test should be
> 'booting but ugly commit history'. Full of try this, revert that, etc.
> The raw working history of what we tried and what stuck"

The difference is the staging branch. Yours has it holding a curated
series; his has it holding the messy record. Both of us had squashed the
flailing *out* of it, so after your merge the two branches held the same
cleaned history and the record of how the fixes were reached existed only
in local branches on nym-skyforge — which your handoff also proposed
pruning.

### What I did about it

Rather than force-push (which would have dropped `latest-clean-test` back
onto the older base and lost your upstream alignment), I used your own
`commit-tree` technique:

    tree    = master's tree, verbatim
    parent1 = 47041183b   (master tip)  -> makes it a fast-forward
    parent2 = f4a7d951f   (raw history tip)

Pushed to `joan/latest-clean-test` as `345eb2ddc`, a clean fast-forward
(`47041183b..345eb2ddc`, no force). Result:

    master ................. 47041183b   verified fixes, clean history
    joan/latest-clean-test . 345eb2ddc   ahead 21, behind 0, files differing 0

The staging branch now carries 21 commits more *history* than master
while being byte-for-byte identical in *content*. Nothing was rewritten,
master is untouched, and the upstream base came along automatically.

The history it preserves is the real sequence:

    531e7b10e  A540 GDSC held alive across short locks -- an experiment
    a3b28b8d5  drm atomic failure-code prints -- a diagnostic
    8974ea3de  full power_on at runtime resume
    0d0456153  panel drives the touch controller's power
    14955ba2e  gate the QCA BD-address quirk on the property existing
    9314f9acd  all-zero local-bd-address placeholder
    b3ea8a9cd  stmfts power-state guard
    f967f8834  release held contacts at power-down -- a partial fix
    ea743e8d6  TEMP-DIAG raw packet dump -- the probe that found it
    1ecb07bb4  Revert of that probe, once it had answered
    6773b3627  INPUT_MT_DROP_UNUSED -- the fix the probe pointed to
    f4a7d951f  Revert of the GDSC experiment, once its premise was gone

Two reverts of commits in the same series, which is the point.
`a3b28b8d5`'s prints have no revert of their own; the merge resolves them
away by taking master's tree, which is more honest than a fabricated
revert — they were dropped during cleanup, not backed out on the device.

### Consequence for pruning

Do **not** prune the local branches yet without checking with Lance.
`joan/bt-uart-clock-fix` is now published as ancestry of
`latest-clean-test`, so that record is safe. But
`ember/joan-integration-v2`, `ember/joan-integration-v3` and
`ember/joan-touch-fixes` are still local-only. Deletion needs Lance's
per-item OK regardless.

## Environment note to add to yours

Your handoff recommends the single-dtb form:

    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom/msm8998-lge-joan.dtb

That is the right target form, but run without `O=` it is an **in-tree**
build and it leaves `.config`, `include/config/`, `include/generated/` and
`scripts/basic/fixdep` in the source tree. Every subsequent `O=` build
from that tree then fails with:

    *** The source tree is not clean, please run 'make ARCH=arm64 mrproper'

`/tmp/joan-bt-fix` is in that state now. I did not run `mrproper` on files
I did not create; I built master from a fresh worktree instead
(`/tmp/joan-master-verify` + `build-master-verify`). Either always pass
`O=`, or clean it with Lance's OK.

## Lanes

Cards 88 (ghost touch), 89 (rainbow on wake), 90 (wlanmdsp.mbn / WLFW
service 69), 91 (pwrkey IRQ) and 94 (GPU runtime PM never suspends) are
still mine and untouched. 94 is the strongest lead: the GPU power domain
never releases its runtime PM reference at *either* inactive_period value,
so it is a genuine standby drain independent of anything we changed.
Next step there is `CONFIG_PM_ADVANCED_DEBUG` to expose
`power/runtime_usage`, then find the unbalanced `pm_runtime_get` in
drm/msm.

Your integration was clean work and the tree invariant you established is
the right oracle — I used it three times today.
