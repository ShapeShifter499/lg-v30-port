# Boots 22a / 23a — root cause found and fixed: q6asmdai had no `iommus`

Written-by: Ember Nymbrand (agent-ember)
Agent-harness: Claude-Code:claude-opus-5
Date: 2026-08-21

22a kernel: 7.2.0-rc2-gf92fccb9c454-dirty (f92fccb9c + APR/heartbeat instrumentation)
23a kernel: same, plus the DT fix
Images: boot-joan-qmidbg22a.img (527c65ad...), boot-joan-qmidbg23a.img (14191725...)
Captures: /tmp/joanrun/boot22a/netconsole.txt, /tmp/joanrun/boot23a/netconsole.txt

## Boot 22a — the heartbeat moved the death 320 ms later

Every boot from 19y to 21b appeared to end at the seventh `apr_audio_svc`
response. It did not. **Nothing was printing for 320 ms** while aplay filled
its 24960-frame buffer; 18 heartbeats (seq 1409-1426, 10 ms apart) run
cleanly through that gap on cpu 0. The apps CPU was never wedged.

With APR headers logged, the stream start decodes completely:

```
55.677  tx 0x100EF  AFE_PORT_CMD_SET_PARAM_V2         -> 0x110E8 ack
55.677  tx 0x100E5  AFE_PORT_CMD_DEVICE_START         -> ack (16 ms later)
55.694  tx 0x10D92  ASM_CMD_SHARED_MEM_MAP_REGIONS    -> 0x10D93, map ACCEPTED
55.694  tx 0x10DB3  ASM_STREAM_CMD_OPEN_WRITE_V3      -> ack
55.697  tx 0x10326  ADM_CMD_DEVICE_OPEN_V5            -> 0x10329
55.701  tx 0x10325  ADM_CMD_MATRIX_MAP_ROUTINGS_V5    -> ack
55.704  tx 0x10D98  ASM_DATA_CMD_MEDIA_FMT_UPDATE_V2  -> ack
        --- 320 ms, heartbeats only ---
56.0245 tx 0x10DAB x4  ASM_DATA_CMD_WRITE_V2, tokens 0x61800000..03
        --- dead within 6 ms; the next 10 ms heartbeat never fires ---
```

The kill is the **first PCM data handed to the DSP**. Not the port config,
not the trigger. `ASM_SESSION_CMD_RUN_V2` never even got sent.

## Root cause

`msm8998.dtsi` carried this on the APR block:

> Two deliberate omissions: `qcom,protection-domain` ... and the `q6asmdai`
> iommus property (msm8998 has no apps_smmu; its ADSP sits behind
> lpass_q6_smmu instead).

That omission is the bug. `q6asm_dai_probe()` reads `iommus` to recover the
audio stream ID:

```c
rc = of_parse_phandle_with_fixed_args(node, "iommus", 1, 0, &args);
if (rc < 0) pdata->sid = -1;
else        pdata->sid = args.args[0] & SID_MASK_DEFAULT;   /* 0xF */
```

and puts it in the top half of the address it gives the DSP
(`q6asm-dai.c:452` and `:656`):

```c
prtd->phys = substream->dma_buffer.addr | (pdata->sid << 32);
```

With no `iommus`: `sid == -1`, the buffer comes from
`snd_dma_alloc_pages(SNDRV_DMA_TYPE_DEV, dev, ...)` on a device attached to
no IOMMU, and the DSP is handed a **bare physical address with no SID in
bits [63:32]**. `ASM_CMD_SHARED_MEM_MAP_REGIONS` succeeds because the ADSP
only records the address; it does not validate until it DMAs. The first
`ASM_DATA_CMD_WRITE_V2` makes it read, the Q6 master faults through
`lpass_q6_smmu` (which was `status = "disabled"` and referenced by nothing),
and on this SoC that is a silent reset — no panic, no RCU stall, no
"crash detected in adsp", because the fault is handled below the kernel.

**The SID is 1**, confirmed from two independent directions:
- sdm845 puts `iommus = <&apps_smmu 0x1821 0x0>` on `q6asmdai`; `0x1821 & 0xF` = 1.
- downstream msm8998 `msm-audio.dtsi:448`: `qcom,msm-audio-ion` has
  `iommus = <&lpass_q6_smmu 1>`.

## The fix

```dts
/* msm8998.dtsi */
q6asmdai: dais {
        compatible = "qcom,q6asm-dais";
        ...
        iommus = <&lpass_q6_smmu 1>;
};

/* msm8998-lge-joan.dts */
&lpass_q6_smmu {
        status = "okay";
};
```

## Boot 23a — it works

```
== aplay1 start 59 ==     aplay1 rc=0 at 65
== aplay2 start 71 ==     aplay2 rc=0 at 77
== seq end 77 ==
REACHABLE_CHECK_1..4 all pass, uptime climbs to 2 min
```

Both 5 s playbacks completed, in 6 s of wall clock each — real time, so the
port really is clocking at 48 kHz rather than draining instantly.

From the netconsole capture (22147 lines, no faults of any kind):

```
[36.136352] platform 17300000.remoteproc:glink-edge:apr:service@7:dais:
            Adding to iommu group 4
```

APR opcode histogram over the two playbacks:

| count | opcode | meaning |
|---|---|---|
| 156 | 0x10D99 | ASM_DATA_EVENT_WRITE_DONE_V2 |
|  78 | 0x10DAB | ASM_DATA_CMD_WRITE_V2 |
|  58 | 0x110E8 | APRV2_IBASIC_RSP_RESULT |
|   6 | 0x10D93 | ASM_CMDRSP_SHARED_MEM_MAP_REGIONS |
|   6 | 0x10329 | ADM_CMDRSP_DEVICE_OPEN_V5 |
|   3 | 0x10D94 | ASM_CMD_SHARED_MEM_UNMAP_REGIONS |
|   2 | 0x10DAA | ASM_SESSION_CMD_RUN_V2 |
|   3 | 0x10327 | ADM_CMD_DEVICE_CLOSE_V5 |

156 write-dones is the DSP reading the IOVA and acking, 156 times. The
teardown path (`SHARED_MEM_UNMAP` then `ADM_CMD_DEVICE_CLOSE_V5`, both
acked at 77.13) also completes cleanly — which retires the separate
"teardown-crash" suspect open since 2026-08-17.

## What this does NOT prove

**Audible sound.** aplay played `/dev/zero`, which is silence by
construction, and the analog path is still incomplete:

- the AFE port is configured for ONE channel (`ch 1 map 144/0/0/0`) because
  only `SLIM RX0 MUX` is routed; stereo needs RX1 as well;
- joan's DT still has no `audio-routing`, and the codec logs a long list of
  `ASoC: mux ... has no paths` (RX INT0-7 MIX2 INP, CDC_IF TX9/10/11/13);
- the codec-side chain (RX INT0_1 MIX1 INP0 = RX0, RX INT0 DEM MUX =
  CLSH_DSM_OUT, SPK PA) has never been set up.

So: the DSP playback pipeline now runs end-to-end without killing the SoC.
Making it audible is the next lane, and it is a codec/DAPM problem, not a
SLIMbus or ADSP one.

## Retroactive note

This explains why every apps-side lane came up empty. App-side PGD register
writes, the ADSP QMI indication, the app-PGD pipe connects and the whole of
runtime PM were never in the data path; the fault was the DSP reading DDR
through an IOMMU nobody had turned on.
