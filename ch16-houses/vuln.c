/* vuln.c — deliberately vulnerable heap target for ch16-houses demo
 * Interface matches ch16-houses/botcake/solve.py and apple2/solve.py
 * Build: gcc -O0 -g -no-pie vuln.c -o vuln */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_CHUNKS 16

typedef struct {
    size_t  sz;
    char   *data;
    void  (*fn)(void);   /* function pointer — House of Apple 2 target */
} Chunk;

static Chunk heap[MAX_CHUNKS];

static void win(void) {
    puts("[+] win() called — code execution achieved!");
    system("/bin/sh");
}

static void menu(void) {
    puts("\n1) alloc  2) free  3) edit  4) show  5) call  0) quit");
    printf("> ");
    fflush(stdout);
}

int main(void) {
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);
    int choice, idx;
    size_t sz;

    printf("heap demo — win() @ %p\n", win);   /* leak for demo clarity */

    while (1) {
        menu();
        if (scanf("%d", &choice) != 1) break;
        if (choice == 0) break;

        switch (choice) {
        case 1: /* alloc */
            printf("idx: "); scanf("%d", &idx);
            printf("sz: ");  scanf("%zu", &sz);
            if (idx < 0 || idx >= MAX_CHUNKS) { puts("bad idx"); break; }
            heap[idx].data = malloc(sz);
            heap[idx].sz   = sz;
            heap[idx].fn   = win;
            printf("alloc[%d] size=0x%zx user=%p\n", idx, sz, heap[idx].data);
            break;

        case 2: /* free */
            printf("idx: "); scanf("%d", &idx);
            if (idx < 0 || idx >= MAX_CHUNKS || !heap[idx].data) { puts("bad idx"); break; }
            free(heap[idx].data);
            printf("free[%d]\n", idx);
            break;

        case 3: /* edit — deliberately no bounds check */
            printf("idx: "); scanf("%d", &idx);
            if (idx < 0 || idx >= MAX_CHUNKS || !heap[idx].data) { puts("bad idx"); break; }
            printf("data: ");
            read(0, heap[idx].data, heap[idx].sz + 64);  /* overflow! */
            break;

        case 4: /* show — first 8 bytes (fd pointer), matches solve.py u64(recvline()) */
            printf("idx: "); scanf("%d", &idx);
            if (idx < 0 || idx >= MAX_CHUNKS || !heap[idx].data) { puts("bad idx"); break; }
            write(1, heap[idx].data, 8);
            putchar('\n');
            break;

        case 5: /* call function pointer */
            printf("idx: "); scanf("%d", &idx);
            if (idx < 0 || idx >= MAX_CHUNKS) { puts("bad idx"); break; }
            printf("calling fn @ %p\n", heap[idx].fn);
            heap[idx].fn();
            break;

        default:
            puts("unknown");
        }
    }
    return 0;
}
