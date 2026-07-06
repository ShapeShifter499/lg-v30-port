/* LG V30 bringup: kill/pet the APSS watchdog (0x17817000) via /dev/mem.
 * Prints initial register state so the diag dump shows whether the
 * boot chain armed it. Offsets: 0x04 RST, 0x08 EN, 0x10 BARK, 0x14 BITE. */
#include <stdint.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void)
{
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("open /dev/mem"); return 1; }
	volatile uint32_t *w = mmap(0, 4096, PROT_READ | PROT_WRITE,
				    MAP_SHARED, fd, 0x17817000);
	if (w == MAP_FAILED) { perror("mmap"); return 1; }
	printf("WDT initial: EN=%u BARK=%u BITE=%u\n", w[2], w[4], w[5]);
	fflush(stdout);
	w[1] = 1;	/* pet only: writing EN=0 provoked an instant reset (round 18) */
	printf("WDT pet-only mode, EN untouched=%u\n", w[2]);
	fflush(stdout);
	for (;;) { w[1] = 1; sleep(2); }	/* re-pet forever */
}
