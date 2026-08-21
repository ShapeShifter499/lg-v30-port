/* gpiohold - request PMIC GPIO lines as outputs, hold them, exit.
 * Written-by: Ember Nymbrand (agent-ember) / Claude-Code:claude-opus-5
 * usage: gpiohold <chip-label-substring> <seconds> <off>=<val> [<off>=<val>...]
 * Offsets are 0-based cdev offsets (PMIC GPIO_n == offset n-1).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <linux/gpio.h>

int main(int argc, char **argv)
{
	if (argc < 4) { fprintf(stderr, "usage: %s <label-substr> <secs> off=val ...\n", argv[0]); return 2; }
	const char *want = argv[1];
	int secs = atoi(argv[2]);

	char path[64]; int fd = -1;
	for (int i = 0; i < 32; i++) {
		struct gpiochip_info ci;
		snprintf(path, sizeof path, "/dev/gpiochip%d", i);
		int f = open(path, O_RDWR);
		if (f < 0) continue;
		if (ioctl(f, GPIO_GET_CHIPINFO_IOCTL, &ci) == 0 && strstr(ci.label, want)) {
			printf("chip %s label='%s' lines=%u\n", path, ci.label, ci.lines);
			fd = f; break;
		}
		close(f);
	}
	if (fd < 0) { fprintf(stderr, "no gpiochip matching '%s'\n", want); return 1; }

	struct gpio_v2_line_request req;
	memset(&req, 0, sizeof req);
	strncpy(req.consumer, "gpiohold", sizeof req.consumer - 1);
	req.config.flags = GPIO_V2_LINE_FLAG_OUTPUT;
	struct gpio_v2_line_values vals; memset(&vals, 0, sizeof vals);

	for (int a = 3; a < argc; a++) {
		int off, val;
		if (sscanf(argv[a], "%d=%d", &off, &val) != 2) { fprintf(stderr, "bad arg %s\n", argv[a]); return 2; }
		req.offsets[req.num_lines] = off;
		if (val) vals.bits |= (1ULL << req.num_lines);
		vals.mask |= (1ULL << req.num_lines);
		printf("  line offset %d (PMIC GPIO_%d) = %d\n", off, off + 1, val);
		req.num_lines++;
	}
	req.config.num_attrs = 1;
	req.config.attrs[0].mask = vals.mask;
	req.config.attrs[0].attr.id = GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES;
	req.config.attrs[0].attr.values = vals.bits;

	if (ioctl(fd, GPIO_V2_GET_LINE_IOCTL, &req) < 0) { perror("GPIO_V2_GET_LINE_IOCTL"); return 1; }
	printf("held for %d s\n", secs); fflush(stdout);
	sleep(secs);
	close(req.fd);
	return 0;
}
