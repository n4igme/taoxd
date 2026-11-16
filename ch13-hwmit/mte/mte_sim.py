#!/usr/bin/env python3
"""mte_sim.py — simulate ARMv8.5 MTE tag mismatch on a 1-byte overflow.

MTE gives every 16-byte heap granule a 4-bit tag, stored in the top byte
of the pointer. On every load/store the CPU compares pointer tag vs memory
tag. Mismatch -> SIGSEGV si_code=9 (SEGV_MTESERR).

This script prints the pointer layout and the mismatch story that the
real hardware enforces. Run alongside mte_overflow.c.
"""
import sys

GRANULE = 16          # bytes per MTE granule
TAG_SHIFT = 56        # 4-bit tag lives in top byte

def tagged(tag: int, addr: int) -> int:
    return ((tag & 0xF) << TAG_SHIFT) | addr

def main():
    # two adjacent 16-byte allocations, different tags (what the allocator does)
    base = 0x0000aaaaaaab0000
    a_addr = base + 0x2a0
    b_addr = base + 0x2b0
    a_tag, b_tag = 0x3, 0x7

    a_ptr = tagged(a_tag, a_addr)
    b_ptr = tagged(b_tag, b_addr)
    print(f'a = {a_ptr:#018x}  (tag=0x{a_tag:x}, 16-byte granule)')
    print(f'b = {b_ptr:#018x}  (tag=0x{b_tag:x}, 16-byte granule)')
    print()
    print("a[16] = 'X';  // write 1 byte PAST end of a")
    print("  -> crosses into b's granule")
    print(f'  -> hardware check: pointer tag 0x{a_tag:x} vs memory tag 0x{b_tag:x}')
    print('  -> MISMATCH -> SIGSEGV si_code=9 (SEGV_MTESERR)')
    print('  -> One byte. Caught. At load/store time.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
