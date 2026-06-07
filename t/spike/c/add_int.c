/* ABOUTME: Toolchain proof: type-specialized C for `return 1+2` with no libperl. */
/* ABOUTME: Spike probe for Phase 3e cost-reconnaissance — t/spike/c/add_int.c */
#include <stdio.h>

int main(void) {
    long result = 1 + 2;
    printf("%ld\n", result);
    return 0;
}
