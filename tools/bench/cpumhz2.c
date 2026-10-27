/* PMU-free core clock estimate: 1000 dependent adds per iteration = ~1000 cycles. */
#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
#define A4 "add %0, %0, #1\n\tadd %0, %0, #1\n\tadd %0, %0, #1\n\tadd %0, %0, #1\n\t"
#define A20 A4 A4 A4 A4 A4
#define A100 A20 A20 A20 A20 A20
#define A1000 A100 A100 A100 A100 A100 A100 A100 A100 A100 A100
int main(int argc, char **argv) {
	int cpu = argc > 1 ? atoi(argv[1]) : 0; double secs = argc > 2 ? atof(argv[2]) : 1.0;
	cpu_set_t s; CPU_ZERO(&s); CPU_SET(cpu, &s); sched_setaffinity(0, sizeof(s), &s);
	unsigned long x = 0, it = 0; double t0 = now(), t;
	while (now() - t0 < 0.3) __asm__ volatile(A1000 : "+r"(x));   /* warm-up/ramp */
	t0 = now();
	do { for (int k = 0; k < 200; k++) __asm__ volatile(A1000 : "+r"(x)); it += 200; t = now(); } while (t - t0 < secs);
	printf("cpu%d ~%.0f MHz\n", cpu, it * 1000.0 / (t - t0) / 1e6);
	return (int)(x & 0);
}
