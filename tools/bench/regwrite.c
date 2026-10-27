/* Single 32-bit MMIO write via /dev/mem, printing old and new: regwrite <phys-hex> <val> */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
int main(int argc, char **argv) {
	if (argc != 3) { fprintf(stderr, "usage: %s phys val\n", argv[0]); return 1; }
	unsigned long a = strtoul(argv[1], 0, 16), page = a & ~0xfffUL;
	uint32_t v = strtoul(argv[2], 0, 0);
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("open /dev/mem"); return 1; }
	volatile uint8_t *m = mmap(0, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, page);
	if (m == MAP_FAILED) { perror("mmap"); return 1; }
	volatile uint32_t *r = (volatile uint32_t *)(m + (a - page));
	uint32_t old = *r;
	*r = v;
	printf("%#010lx: %#010x -> %#010x (readback %#010x)\n", a, old, v, *r);
	return 0;
}
