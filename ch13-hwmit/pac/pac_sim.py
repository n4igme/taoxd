#!/usr/bin/env python3
"""pac_sim.py — simulate ARMv8.3 PAC sign/strip/forge cycle.

Shows what pacia/autia/xpaci do to a pointer, without needing real
ARMv8.3 hardware. Run alongside `objdump -d pac_demo` to connect the
machine instructions to the pointer transformation.

Real hardware note: the PAC value is computed by the CPU from the IA key
(readable only at EL1+) and the modifier. Software can never read the key —
this simulation hardcodes a plausible PAC value to illustrate the layout.
"""
import sys

def sign(ptr: int, pac: int) -> int:
    """Simulate pacia: embed PAC bits in the top byte."""
    return (ptr & 0x0000FFFFFFFFFFFF) | ((pac & 0xFF) << 56)

def strip(signed: int) -> int:
    """Simulate xpaci: strip the PAC, recover the original pointer."""
    return signed & 0x0000FFFFFFFFFFFF

def forge(signed: int, bit: int) -> int:
    """Simulate an attacker flipping one bit of the signed pointer."""
    return signed ^ (1 << bit)

def main():
    ptr = 0x0000aaaaaaaa1234
    pac = 0x3C  # what the CPU would compute from key+modifier

    signed = sign(ptr, pac)
    print(f'raw    = {ptr:#018x}')
    print(f'signed = {signed:#018x}  (PAC bits in top byte)')

    stripped = strip(signed)
    print(f'xpaci  = {stripped:#018x}  (strip PAC, recover original)')

    forged = forge(signed, 40)
    print(f'forged = {forged:#018x}  (1 bit flipped)')

    print()
    print('autia(forged) -> SIGSEGV at deref (key mismatch)')
    print('Key never leaves the system register - unreadable from EL0.')

    # Exit code lets scripts assert on the story
    return 0 if stripped == ptr else 1

if __name__ == '__main__':
    sys.exit(main())
