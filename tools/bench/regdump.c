/* Read-only MMIO dump via /dev/mem: regdump <phys-base-hex> <count-words> [stride] */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>
int main(int argc, char **argv) {
	if (argc < 3) { fprintf(stderr, "usage: %s base count [stride]\n", argv[0]); return 1; }
	unsigned long base = strtoul(argv[1], 0, 16), n = strtoul(argv[2], 0, 0);
	unsigned long stride = argc > 3 ? strtoul(argv[3], 0, 0) : 4;
	unsigned long page = base & ~0xfffUL, off = base - page, len = off + n * stride + 4;
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("open /dev/mem"); return 1; }
	volatile uint8_t *m = mmap(0, len, PROT_READ, MAP_SHARED, fd, page);
	if (m == MAP_FAILED) { perror("mmap"); return 1; }
	for (unsigned long i = 0; i < n; i++)
		printf("%#010lx: %#010x\n", base + i * stride, *(volatile uint32_t *)(m + off + i * stride));
	return 0;
}
