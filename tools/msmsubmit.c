/*
 * K141: submit-path prober for the joan (LG V30 / msm8998, Adreno 540) bring-up.
 *
 * Kernel-written IBs execute on this GPU with register-readback proof (K139),
 * but the identical cmdstream submitted through the DRM submit path has never
 * signalled a fence.  This walks that path one ioctl at a time so the failure
 * can be pinned without Mesa in the picture:
 *
 *   1. an EMPTY submit (no cmds) -- POSITIVE CONTROL.  K131 showed these do
 *      signal; if this one does not, the run is void and nothing below it
 *      means anything.
 *   2. one IB submit whose cmdstream writes a marker to CP_SCRATCH_REG(3),
 *      which the kernel-side K141 probe reads back.
 *
 * The cmdstream BO's cache mode is selectable because every kernel-side test
 * that executed used MSM_BO_WC, while the earlier userspace probe used
 * MSM_BO_CACHED and never issued CPU_FINI -- on this non-coherent walker that
 * alone could leave the CP fetching stale memory, which would make "the submit
 * path is broken" the wrong conclusion.  Default here is WC; -c cached adds a
 * proper CPU_PREP/CPU_FINI pair so cached mode is tested honestly too.
 *
 * Every step announces itself BEFORE it runs and prints its own rc and errno
 * after: the SoC can die mid-call, and a probe that silently does nothing
 * looks exactly like a probe that passed.
 *
 * Build: aarch64-linux-gnu-gcc -static -O1 -o msmsubmit msmsubmit.c
 */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <time.h>

#define DRM_COMMAND_BASE 0x40
#define DRM_MSM_GEM_NEW 0x02
#define DRM_MSM_GEM_INFO 0x03
#define DRM_MSM_GEM_CPU_PREP 0x04
#define DRM_MSM_GEM_CPU_FINI 0x05
#define DRM_MSM_GEM_SUBMIT 0x06
#define DRM_MSM_WAIT_FENCE 0x07
#define DRM_MSM_SUBMITQUEUE_NEW 0x0A

#define MSM_PIPE_3D0 0x10

#define MSM_BO_CACHED 0x00010000
#define MSM_BO_WC     0x00020000

#define MSM_INFO_GET_OFFSET 0x00
#define MSM_INFO_GET_IOVA   0x01

#define MSM_PREP_READ  0x01
#define MSM_PREP_WRITE 0x02

#define MSM_SUBMIT_CMD_BUF 0x0001
#define MSM_SUBMIT_BO_READ 0x0001

struct drm_msm_timespec { int64_t tv_sec, tv_nsec; };
struct drm_msm_gem_new { uint64_t size; uint32_t flags, handle; };
struct drm_msm_gem_info { uint32_t handle, info; uint64_t value; uint32_t len, pad; };
struct drm_msm_gem_cpu_prep { uint32_t handle, op; struct drm_msm_timespec timeout; };
struct drm_msm_gem_cpu_fini { uint32_t handle; };
struct drm_msm_submitqueue { uint32_t flags, prio, id; };
struct drm_msm_gem_submit_cmd {
	uint32_t type, submit_idx, submit_offset, size, pad, nr_relocs;
	uint64_t relocs;
};
struct drm_msm_gem_submit_bo { uint32_t flags, handle; uint64_t presumed; };
struct drm_msm_gem_submit {
	uint32_t flags, fence, nr_bos, nr_cmds;
	uint64_t bos, cmds;
	int32_t fence_fd;
	uint32_t queueid;
	uint64_t in_syncobjs, out_syncobjs;
	uint32_t nr_in_syncobjs, nr_out_syncobjs, syncobj_stride, pad;
};
struct drm_msm_wait_fence {
	uint32_t fence, flags;
	struct drm_msm_timespec timeout;
	uint32_t queueid;
};

#define IOWR_GEMNEW  _IOWR('d', DRM_COMMAND_BASE + DRM_MSM_GEM_NEW, struct drm_msm_gem_new)
#define IOWR_GEMINF  _IOWR('d', DRM_COMMAND_BASE + DRM_MSM_GEM_INFO, struct drm_msm_gem_info)
#define IOW_CPUPREP  _IOW ('d', DRM_COMMAND_BASE + DRM_MSM_GEM_CPU_PREP, struct drm_msm_gem_cpu_prep)
#define IOW_CPUFINI  _IOW ('d', DRM_COMMAND_BASE + DRM_MSM_GEM_CPU_FINI, struct drm_msm_gem_cpu_fini)
#define IOWR_SUBMIT  _IOWR('d', DRM_COMMAND_BASE + DRM_MSM_GEM_SUBMIT, struct drm_msm_gem_submit)
#define IOW_WAITFEN  _IOW ('d', DRM_COMMAND_BASE + DRM_MSM_WAIT_FENCE, struct drm_msm_wait_fence)
#define IOWR_SQNEW   _IOWR('d', DRM_COMMAND_BASE + DRM_MSM_SUBMITQUEUE_NEW, struct drm_msm_submitqueue)

/* Announce, then give the line ~120ms to clear the USB link before we risk dying. */
static void say(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fputc('\n', stderr);
	fflush(stderr);
	usleep(120000);
}

static int fd;
static uint32_t queueid;

/* a5xx type-4 packet: register write, with the parity bits the CP checks. */
#define CP_TYPE4_PKT 0x40000000
#define REG_CP_SCRATCH_REG3 0x0b7b

/*
 * PM4_PARITY, verbatim from adreno_gpu.h. This is NOT plain bit parity: the
 * nibbles are folded together and the result indexes the constant 0x9669.
 * Getting it wrong produces a packet the CP rejects with "opcode error" --
 * measured, and the reason the value 0x480B7B81 recorded in the ledger for
 * PKT4(CP_SCRATCH_REG(3), 1) is wrong; the correct encoding is 0x400B7B01.
 */
static uint32_t parity(uint32_t val)
{
	return (0x9669 >> (0xF & (val ^ (val >> 4) ^ (val >> 8) ^ (val >> 12) ^
				  (val >> 16) ^ (val >> 20) ^ (val >> 24) ^
				  (val >> 28)))) & 1;
}

static uint32_t pkt4(uint32_t reg, uint32_t cnt)
{
	return CP_TYPE4_PKT | cnt | (parity(cnt) << 7) |
	       ((reg & 0x3ffff) << 8) | (parity(reg) << 27);
}

/*
 * a5xx type-7 packet: an opcode with a payload.
 *
 * CP_NOP is the only content that is unambiguously legal from an unprivileged
 * IB. The PKT4 scratch-register marker below is NOT: measured on joan, the CP
 * fetches such an IB and rejects it with "CP | opcode error | possible
 * opcode=0x480B7B81" because CP_SCRATCH is protected from userspace
 * cmdstreams. That is a property of the test, not of the driver -- Mesa never
 * writes those registers -- so NOP is the default and the marker is opt-in.
 */
#define CP_TYPE7_PKT 0x70000000
#define CP_NOP 0x10

static uint32_t pkt7(uint32_t opcode, uint32_t cnt)
{
	return CP_TYPE7_PKT | (cnt & 0x3fff) | (parity(cnt) << 15) |
	       ((opcode & 0x7f) << 16) | (parity(opcode) << 23);
}

/* Returns the fence, or 0 on failure. */
static uint32_t do_submit(const char *what, struct drm_msm_gem_submit_bo *bos,
			  uint32_t nr_bos, struct drm_msm_gem_submit_cmd *cmds,
			  uint32_t nr_cmds)
{
	struct drm_msm_gem_submit req;
	int r;

	memset(&req, 0, sizeof req);
	req.flags = MSM_PIPE_3D0;
	req.queueid = queueid;
	req.nr_bos = nr_bos;
	req.bos = (uint64_t)(uintptr_t)bos;
	req.nr_cmds = nr_cmds;
	req.cmds = (uint64_t)(uintptr_t)cmds;

	say("ABOUT TO: GEM_SUBMIT %s (nr_bos=%u nr_cmds=%u)", what, nr_bos, nr_cmds);
	r = ioctl(fd, IOWR_SUBMIT, &req);
	say("   done: %s fence=%u rc=%d errno=%d", what, req.fence, r, r ? errno : 0);
	return r ? 0 : req.fence;
}

/* 0 = signalled, non-zero = did not (errno printed). */
static int do_wait(const char *what, uint32_t fence, int seconds)
{
	struct drm_msm_wait_fence wf;
	struct timespec now;
	int r;

	if (!fence) {
		say("   SKIP wait %s: no fence (submit failed)", what);
		return -1;
	}

	memset(&wf, 0, sizeof wf);
	wf.fence = fence;
	wf.queueid = queueid;
	clock_gettime(CLOCK_MONOTONIC, &now);
	wf.timeout.tv_sec = now.tv_sec + seconds;
	wf.timeout.tv_nsec = now.tv_nsec;

	say("ABOUT TO: WAIT_FENCE %s fence=%u timeout=%ds", what, fence, seconds);
	r = ioctl(fd, IOW_WAITFEN, &wf);
	say("   RESULT: %s fence=%u %s (rc=%d errno=%d)", what, fence,
	    r ? "NOT SIGNALLED" : "SIGNALLED", r, r ? errno : 0);
	return r;
}

int main(int argc, char **argv)
{
	uint32_t cache = MSM_BO_WC;
	const char *cachename = "wc";
	int markers = 4, i, r, opt, scratch_content = 0;
	struct drm_msm_gem_new gn;
	struct drm_msm_gem_info gi;
	struct drm_msm_gem_submit_bo bos[1];
	struct drm_msm_gem_submit_cmd cmds[1];
	uint64_t iova, mmap_offset;
	uint32_t *ib;
	uint32_t fence;

	while ((opt = getopt(argc, argv, "c:n:s")) != -1) {
		switch (opt) {
		case 'c':
			if (!strcmp(optarg, "cached")) {
				cache = MSM_BO_CACHED;
				cachename = "cached";
			} else if (!strcmp(optarg, "wc")) {
				cache = MSM_BO_WC;
				cachename = "wc";
			} else {
				fprintf(stderr, "cache must be wc or cached\n");
				return 2;
			}
			break;
		case 'n':
			markers = atoi(optarg);
			break;
		case 's':
			scratch_content = 1;	/* opt in to the protected write */
			break;
		default:
			fprintf(stderr, "usage: %s [-c wc|cached] [-n count] [-s]\n", argv[0]);
			return 2;
		}
	}

	say("=== K141 submit probe start (cache=%s packets=%d content=%s) ===",
	    cachename, markers, scratch_content ? "PKT4-scratch" : "PKT7-NOP");

	say("ABOUT TO: open /dev/dri/renderD128");
	fd = open("/dev/dri/renderD128", O_RDWR);
	say("   ok: fd=%d errno=%d", fd, fd < 0 ? errno : 0);
	if (fd < 0)
		return 1;

	{
		struct drm_msm_submitqueue sq;

		memset(&sq, 0, sizeof sq);
		say("ABOUT TO: SUBMITQUEUE_NEW");
		r = ioctl(fd, IOWR_SQNEW, &sq);
		say("   ok: id=%u rc=%d errno=%d", sq.id, r, r ? errno : 0);
		if (r)
			return 1;
		queueid = sq.id;
	}

	/*
	 * The BO comes first, and not only for the IB: GEM_INFO GET_IOVA is
	 * what lazily creates the context's VM.  A GEM_SUBMIT issued before it
	 * NULL-derefs the kernel (msm_gem_submit.c reads
	 * to_msm_vm(ctx->vm)->unusable without going through msm_context_vm()),
	 * measured here as an oops in msm_ioctl_gem_submit+0x60.  Mesa never
	 * hits it because it always allocates first; keep that order.
	 */
	memset(&gn, 0, sizeof gn);
	gn.size = 4096;
	gn.flags = cache;
	say("ABOUT TO: GEM_NEW 4096 flags=%08x (%s)", gn.flags, cachename);
	r = ioctl(fd, IOWR_GEMNEW, &gn);
	say("   ok: handle=%u rc=%d errno=%d", gn.handle, r, r ? errno : 0);
	if (r)
		return 1;

	memset(&gi, 0, sizeof gi);
	gi.handle = gn.handle;
	gi.info = MSM_INFO_GET_OFFSET;
	say("ABOUT TO: GEM_INFO GET_OFFSET");
	r = ioctl(fd, IOWR_GEMINF, &gi);
	say("   ok: offset=0x%llx rc=%d errno=%d",
	    (unsigned long long)gi.value, r, r ? errno : 0);
	if (r)
		return 1;
	mmap_offset = gi.value;

	say("ABOUT TO: mmap the cmdstream BO");
	ib = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmap_offset);
	say("   ok: ib=%p errno=%d", (void *)ib, ib == MAP_FAILED ? errno : 0);
	if (ib == MAP_FAILED)
		return 1;

	/*
	 * For a cached BO the CPU write must be bracketed by CPU_PREP/CPU_FINI
	 * so the kernel performs cache maintenance; without it the CP can fetch
	 * stale memory and the hang says nothing about the submit path.
	 */
	if (cache == MSM_BO_CACHED) {
		struct drm_msm_gem_cpu_prep prep;
		struct timespec now;

		memset(&prep, 0, sizeof prep);
		prep.handle = gn.handle;
		prep.op = MSM_PREP_WRITE | MSM_PREP_READ;
		clock_gettime(CLOCK_MONOTONIC, &now);
		prep.timeout.tv_sec = now.tv_sec + 2;
		prep.timeout.tv_nsec = now.tv_nsec;
		say("ABOUT TO: GEM_CPU_PREP (cached mode)");
		r = ioctl(fd, IOW_CPUPREP, &prep);
		say("   ok: rc=%d errno=%d", r, r ? errno : 0);
	}

	for (i = 0; i < markers; i++) {
		ib[i * 2] = scratch_content ? pkt4(REG_CP_SCRATCH_REG3, 1)
					    : pkt7(CP_NOP, 1);
		ib[i * 2 + 1] = 0x01410000 + i;
	}
	say("   wrote %d %s packets: head=%08x %08x", markers,
	    scratch_content ? "PKT4 scratch-marker" : "PKT7 NOP", ib[0], ib[1]);

	if (cache == MSM_BO_CACHED) {
		struct drm_msm_gem_cpu_fini fini;

		memset(&fini, 0, sizeof fini);
		fini.handle = gn.handle;
		say("ABOUT TO: GEM_CPU_FINI (cache maintenance)");
		r = ioctl(fd, IOW_CPUFINI, &fini);
		say("   ok: rc=%d errno=%d", r, r ? errno : 0);
	}

	memset(&gi, 0, sizeof gi);
	gi.handle = gn.handle;
	gi.info = MSM_INFO_GET_IOVA;
	say("ABOUT TO: GEM_INFO GET_IOVA  <-- maps into the GPU pagetable");
	r = ioctl(fd, IOWR_GEMINF, &gi);
	say("   ok: iova=0x%llx rc=%d errno=%d",
	    (unsigned long long)gi.value, r, r ? errno : 0);
	if (r)
		return 1;
	iova = gi.value;

	/*
	 * POSITIVE CONTROL.  An IB-less submit still emits the seqno write and
	 * CACHE_FLUSH_TS tail, so it exercises kick, fence and retire without
	 * fetching anything.  If this does not signal, the GPU is already sick
	 * and the IB result below is meaningless -- say so and stop.
	 */
	fence = do_submit("EMPTY (positive control)", NULL, 0, NULL, 0);
	if (do_wait("EMPTY (positive control)", fence, 3)) {
		say("=== VOID RUN: the positive control did not signal; ===");
		say("=== nothing about the IB path can be concluded.    ===");
		return 1;
	}

	memset(bos, 0, sizeof bos);
	bos[0].flags = MSM_SUBMIT_BO_READ;
	bos[0].handle = gn.handle;
	bos[0].presumed = iova;

	memset(cmds, 0, sizeof cmds);
	cmds[0].type = MSM_SUBMIT_CMD_BUF;
	cmds[0].submit_idx = 0;
	cmds[0].submit_offset = 0;
	cmds[0].size = markers * 2 * 4;	/* bytes */
	cmds[0].nr_relocs = 0;

	fence = do_submit("IB (the test)", bos, 1, cmds, 1);
	r = do_wait("IB (the test)", fence, 3);

	say("=== K141 submit probe SURVIVED: control=SIGNALLED ib=%s (cache=%s) ===",
	    r ? "NOT SIGNALLED" : "SIGNALLED", cachename);
	return 0;
}
