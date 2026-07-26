#include <stdarg.h>
/*
 * K125: localise the joan render wedge at the DRM ioctl boundary.
 *
 * The SoC resets silently the moment Mesa initialises the msm driver, with no
 * kernel log line and without triggering a second hw_init.  This walks the
 * ioctls Mesa issues during screen creation one at a time, announcing each
 * BEFORE issuing it and pausing long enough for the line to leave the device,
 * so the last line printed names the call that killed the SoC.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <stdint.h>

#define DRM_COMMAND_BASE 0x40
#define DRM_MSM_GET_PARAM 0x00
#define DRM_MSM_GEM_NEW 0x02
#define DRM_MSM_GEM_INFO 0x03
#define DRM_MSM_SUBMITQUEUE_NEW 0x0A

struct drm_msm_param { uint32_t pipe, param; uint64_t value; uint32_t len, pad; };
struct drm_msm_gem_new { uint64_t size; uint32_t flags, handle; };
struct drm_msm_gem_info { uint32_t handle, info; uint64_t value; uint32_t len, pad; };
struct drm_msm_submitqueue { uint32_t flags, prio, id; };

#define IOWR_PARAM  _IOWR('d', DRM_COMMAND_BASE + DRM_MSM_GET_PARAM, struct drm_msm_param)
#define IOWR_GEMNEW _IOWR('d', DRM_COMMAND_BASE + DRM_MSM_GEM_NEW, struct drm_msm_gem_new)
#define IOWR_GEMINF _IOWR('d', DRM_COMMAND_BASE + DRM_MSM_GEM_INFO, struct drm_msm_gem_info)
#define IOWR_SQNEW  _IOWR('d', DRM_COMMAND_BASE + DRM_MSM_SUBMITQUEUE_NEW, struct drm_msm_submitqueue)

/* Announce, then give the line ~120ms to clear the USB link before we risk dying. */
static void say(const char *fmt, ...) {
	va_list ap; va_start(ap, fmt);
	vfprintf(stderr, fmt, ap); va_end(ap);
	fputc('\n', stderr); fflush(stderr);
	usleep(120000);
}

static int fd;
static void getparam(uint32_t id, const char *name) {
	struct drm_msm_param p; memset(&p, 0, sizeof p);
	p.pipe = 0x10;		/* MSM_PIPE_3D0 */ p.param = id;
	say("ABOUT TO: GET_PARAM 0x%02x %s", id, name);
	int r = ioctl(fd, IOWR_PARAM, &p);
	say("   ok: %s = 0x%llx (rc=%d errno=%d)", name,
	    (unsigned long long)p.value, r, r ? errno : 0);
}

int main(void) {
	say("=== K125 probe start ===");
	say("ABOUT TO: open /dev/dri/renderD128");
	fd = open("/dev/dri/renderD128", O_RDWR);
	say("   ok: fd=%d errno=%d", fd, fd < 0 ? errno : 0);
	if (fd < 0) return 1;

	getparam(0x01, "GPU_ID");
	getparam(0x02, "GMEM_SIZE");
	getparam(0x03, "CHIP_ID");
	getparam(0x04, "MAX_FREQ");
	getparam(0x06, "GMEM_BASE");
	getparam(0x07, "PRIORITIES");
	getparam(0x09, "FAULTS");
	getparam(0x0a, "SUSPENDS");
	getparam(0x0e, "VA_START");
	getparam(0x0f, "VA_SIZE");
	getparam(0x10, "HIGHEST_BANK_BIT");
	getparam(0x12, "UBWC_SWIZZLE");
	getparam(0x13, "MACROTILE_MODE");
	/* Touches GPU registers via pm_runtime_get + ALWAYSON counter read. */
	getparam(0x05, "TIMESTAMP  <-- reads GPU regs");

	struct drm_msm_submitqueue sq; memset(&sq, 0, sizeof sq);
	say("ABOUT TO: SUBMITQUEUE_NEW");
	int r = ioctl(fd, IOWR_SQNEW, &sq);
	say("   ok: id=%u rc=%d errno=%d", sq.id, r, r ? errno : 0);

	struct drm_msm_gem_new gn; memset(&gn, 0, sizeof gn);
	gn.size = 4096; gn.flags = 0x00010000; /* MSM_BO_CACHED */;
	say("ABOUT TO: GEM_NEW 4096");
	r = ioctl(fd, IOWR_GEMNEW, &gn);
	say("   ok: handle=%u rc=%d errno=%d", gn.handle, r, r ? errno : 0);

	if (!r) {
		struct drm_msm_gem_info gi; memset(&gi, 0, sizeof gi);
		gi.handle = gn.handle; gi.info = 1 /* GET_IOVA */;
		say("ABOUT TO: GEM_INFO GET_IOVA  <-- maps into GPU pagetable");
		r = ioctl(fd, IOWR_GEMINF, &gi);
		say("   ok: iova=0x%llx rc=%d errno=%d",
		    (unsigned long long)gi.value, r, r ? errno : 0);
	}

	say("=== K125 probe SURVIVED all steps ===");
	return 0;
}
