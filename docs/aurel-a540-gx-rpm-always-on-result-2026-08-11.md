# A540 GPU GX runtime-always-on discriminator — 2026-08-11

Written-by: Aurel Nymvale (agent-aurel)
Agent-harness: Hermes-Agent:moa/deep-flash
Acting model: openai-codex:gpt-5.6-sol (`reasoning=high`)
Reference models: zai:glm-5.2, minimax:MiniMax-M3, deepseek:deepseek-v4-flash (`reasoning=high`)
Date: 2026-08-11
State: DEVICE-TESTED REJECTED DIAGNOSTIC; intended transition not exercised; not promoted

## Purpose

The device-proven Phase 7 result at
`f8fe4956e5aa471e96483e3b9b899aaadb0bc43a` showed that the driver-local
runtime-suspend callback remains safe through regulator-vote removal when the
PM core is prevented from advancing to physical genpd collapse. The remaining
untested boundary was the GPU GX/CX genpd transition after the callback returns
success.

Phase 8 placed one diagnostic change on top of the clean SPTP-gated unpin
candidate `9f3d891201060dba13e0a28e641914365e9cf6cd`:

```c
static struct gdsc gpu_gx_gdsc = {
        ...
        .pd = {
                .name = "gpu_gx",
                .flags = GENPD_FLAG_RPM_ALWAYS_ON,
        },
        ...
};
```

The intent was to let the complete Adreno runtime-suspend callback return
success while preventing only runtime-PM power-off of `gpu_gx`. The change was
diagnostic only and was never a promotion candidate.

## Source and build seal

- source host: `nym-skyforge`
- branch: `joan/a540-gx-rpm-always-on-test`
- commit: `a856f868ec30893be16409b69aa010f9f9d74c54`
- parent: `9f3d891201060dba13e0a28e641914365e9cf6cd`
- tree: `c0aac2f55e671fbfd8c460e9f7ab06d5fde9f8d3`
- source status: clean
- build directory: `/data/buildcache/kbuild/build-a540-gx-rpm-on-a856f868e`
- config SHA-256: `2ff4ee606a346b77c2d833c979eb08d18a52dde85c56f072153fff50c6561c36`
- build command: `make -j12 O=<build-dir> ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="/usr/bin/ccache aarch64-linux-gnu-gcc" Image.gz dtbs modules`
- ccache executable: `/usr/bin/ccache`
- ccache storage: `/data/buildcache/ccache`
- build result: exit 0
- kernel release: `7.2.0-rc2-ga856f868ec30`
- modules: 1,596
- Image: 49,687,040 bytes; SHA-256 `7757c5d0fd5cfcc1099e95f672e12863bd2ea1f18853d3877d14e786f38a18e7`
- Image.gz: 17,275,633 bytes; SHA-256 `eac83f2c0ee8adadd0b888eb5496f27eef8f31dcfda3b0c8a84507d3745039dc`
- joan DTB: 69,066 bytes; SHA-256 `650913e7865f6dad78ba1cc48907c42d6de44695ab487325ff42cbb2db044e6a`

The saved kbuild `.cmd` files contain `/usr/bin/ccache
aarch64-linux-gnu-gcc`, proving the compiler was actually routed through
ccache rather than merely finding an installed cache.

## Packaged image

The image reused the device-proven Phase 7 ramdisk and command line
byte-for-byte.

- path: `out/boot-joan-a540-gx-rpm-on-a856f868e.img`
- size: 27,815,936 bytes (passes the established working-family gate)
- SHA-256: `8ff54bfa1ba1475cbb354c5b0d49b0012b2f03c148591ac0b9d2b809f6b54982`
- appended Image.gz+DTB SHA-256: `8abf15de57a0a537320bad7e5a2688fa098ee311ee2527149eecf0c361260bcd`
- ramdisk SHA-256: `43d1a861a694c40d5a51e9cfdf1db228d9e627b568f0d55a2f8404eda52d5b28`

## Single RAM-only device attempt

The phone was gracefully returned from the healthy Phase 7 pmOS RAM boot to
its untouched LineageOS installation. LineageOS was verified fully booted and
authorized as serial `LGUS9986e606d55`. The sealed image was copied to
`nym-nest`, then rechecked for exact size and SHA-256.

Exactly one device attempt was made:

- transport: `adb reboot bootloader` followed by `fastboot boot`
- no `fastboot getvar`
- no flash
- no timeout around the fastboot transfer
- no retry
- fastboot transfer: `OKAY`
- fastboot boot: `OKAY`
- pmOS USB gadget `18d1:d001`: present 13 seconds after transfer
- exact running release: `7.2.0-rc2-ga856f868ec30`

## Result

The kernel reached pmOS and remained reachable beyond four minutes. Battery
reporting remained present at 99%. There were zero occurrences of:

- `qcom_icc_rpm_smd_send`
- `Failed to remove bandwidth`
- `Kernel panic`
- `watchdog`
- `Internal error`

However, the intended runtime-suspend discriminator was **not exercised**.
At provider initialization the kernel logged:

```text
[    1.065575] PM: always-on PM domain gpu_gx is not on
[    1.065652] gpucc-msm8998 5065000.clock-controller: probe with driver gpucc-msm8998 failed with error -22
```

The failure propagated to the GPU consumers:

```text
[   18.406576] platform 5040000.iommu: deferred probe pending: platform: supplier 5065000.clock-controller not ready
[   18.406649] platform 5000000.gpu: deferred probe pending: platform: supplier 5065000.clock-controller not ready
```

Live state confirmed:

```text
gpucc=unbound
gpu=unbound
runtime_status=unsupported
runtime_usage=0
runtime_active_time=0
runtime_suspended_time=0
```

The result follows directly from the generic genpd initialization gate in
`drivers/pmdomain/core.c`: a domain carrying either the system-always-on or
runtime-always-on flag must already report ON at initialization. If not, genpd
prints the observed message and returns `-EINVAL` before registering the
domain.

Joan's `gpu_gx` was OFF when GPUCC registered it. Therefore adding
`GENPD_FLAG_RPM_ALWAYS_ON` statically is not a valid way to isolate the later
runtime transition on this platform: it rejects the provider before GPUCC,
the GPU, or the Adreno runtime-suspend callback can bind.

The `gcc_rx1_usb2_clkref_clk status stuck at 'on'` warning at 4.18 seconds was
non-fatal and the kernel continued through switch-root; it is not the Phase 8
failure.

## Classification

**DEVICE-TESTED REJECTED DIAGNOSTIC / PRECONDITION FAILURE.**

- Stable pmOS boot: yes.
- Intended GPU runtime-suspend callback exercised: no.
- Intended GX genpd-collapse suppression tested: no.
- Evidence that suppressing GX collapse fixes the prior reset: none.
- Evidence that the physical collapse is safe or unsafe: none from this boot.
- Promotion status: prohibited; do not promote `a856f868e...`.

A successor discriminator must keep GPUCC and the GPU bound, permit normal
initial power-on, and suppress or instrument only the later runtime-PM
genpd-off transition. It must not statically mark an initially-off GDSC as
RPM-always-on.

## Evidence

- `out/a540-gx-rpm-on-a856f868e-package.log`
- `out/a540-gx-rpm-a856f868e-ramboot-20260811T083904Z.log`
- `out/a540-gx-rpm-a856f868e-runtime-immediate.txt`
- `out/a540-gx-rpm-a856f868e-runtime-2min.txt`
- `out/a540-gx-rpm-a856f868e-full-dmesg.txt`

Evidence SHA-256:

```text
452c9195444c98a4c214aa599bb28e107bf58cd6e88cb31c257158591f3948a4  a540-gx-rpm-on-a856f868e-package.log
82599fed26966e9055b3529f6fe3ef48da209429d2b5137ccb778fbd62b8fca2  a540-gx-rpm-a856f868e-ramboot-20260811T083904Z.log
3aa9e6d42df7e0ee19d1284fa1a7da53b9d1f7c7e43ced2259d0e40cf9e8a857  a540-gx-rpm-a856f868e-runtime-immediate.txt
ef2d2f48840f4dd25d97bb31062fe26ddcf8cccc7c7380c1c7429d86f8af2ea8  a540-gx-rpm-a856f868e-runtime-2min.txt
1d00b2bb2be02f43b8d94cbf84a37a08621d9ac3051070bac1f35a521c44e462  a540-gx-rpm-a856f868e-full-dmesg.txt
```
