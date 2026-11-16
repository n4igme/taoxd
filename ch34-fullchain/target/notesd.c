/* notesd.c — deliberately vulnerable note service matching V06 narration.
 * parse_header() has an unbounded memcpy overflow.
 * No PIE — binary at fixed address (0x400000).
 * Adjacent function pointer — overwrite → libc leak → one-gadget.
 * Build: gcc -O0 -g -no-pie -fno-stack-protector notesd.c -o notesd */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

#define PORT   9931
#define HDRSZ  32

/* Adjacent to header buf — function pointer overwrite target */
struct request {
    char   header[HDRSZ];        /* 32-byte buffer                */
    size_t hdrlen;               /* filled by parse_header        */
    void (*log_fn)(const char*); /* function pointer — our target */
};

static void default_log(const char *msg) {
    /* deliberately uses puts — leaks libc via GOT */
    puts(msg);
}

/* Deliberate vulnerability: unbounded memcpy — matches narration:
 * "Root cause: unbounded memcpy in parse_header" */
static void parse_header(struct request *req, const char *input, size_t len) {
    memcpy(req->header, input, len);   /* BUG: len can exceed HDRSZ */
    req->hdrlen = len;
}

static void handle(int fd) {
    /* Read 1-byte command + payload */
    char cmd;
    if (read(fd, &cmd, 1) != 1) return;

    if (cmd == 'L') {
        /* LEAK: return libc base from /proc/self/maps */
        FILE *maps = fopen("/proc/self/maps", "r");
        char line[256];
        unsigned long libc_base = 0;
        while (fgets(line, sizeof(line), maps)) {
            if (strstr(line, "libc") && strstr(line, "r-xp")) {
                libc_base = strtoul(line, NULL, 16);
                break;
            }
        }
        fclose(maps);
        write(fd, &libc_base, 8);
        write(fd, "OK\n", 3);

    } else if (cmd == 'N') {
        /* NOTE: read length-prefixed note — overflow possible */
        uint16_t msglen;
        if (read(fd, &msglen, 2) != 2) return;

        struct request req;
        memset(&req, 0, sizeof(req));
        req.log_fn = default_log;

        char *buf = malloc(msglen + 1);
        if (!buf) return;
        if (read(fd, buf, msglen) > 0) {
            buf[msglen] = '\0';
            /* parse_header — overflow when msglen > 32 */
            parse_header(&req, buf, msglen);
            /* call function pointer — target for overwrite */
            req.log_fn(req.header);
            write(fd, "OK\n", 3);
        }
        free(buf);
    }
}

int main(void) {
    int srv = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {
        .sin_family      = AF_INET,
        .sin_port        = htons(PORT),
        .sin_addr.s_addr = INADDR_ANY,
    };
    bind(srv, (struct sockaddr*)&addr, sizeof(addr));
    listen(srv, 8);
    fprintf(stderr, "[*] notesd listening on :%d  (no PIE — base=0x400000)\n", PORT);
    fprintf(stderr, "[*] parse_header@%p  log_fn offset=+%zu  HDRSZ=%d\n",
            (void*)parse_header,
            offsetof(struct request, log_fn),
            HDRSZ);
    fflush(stderr);

    int cli;
    while ((cli = accept(srv, NULL, NULL)) >= 0) {
        handle(cli);
        close(cli);
    }
}
