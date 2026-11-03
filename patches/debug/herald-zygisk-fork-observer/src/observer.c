// rootless Zygisk 阶段 2:在真机上验证"ptrace 住 init、追它 fork+exec 出的 zygote64、
// 在它执行第一条指令之前读到 PC==ELF 入口"这条链路——跟本机 x86_64 的 PoC(monitor.c)
// 是同一套算法,只是寄存器结构换成 ARM64 的 user_pt_regs.pc。
//
// 只做观察,不注入任何代码、不改 zygote 的任何行为:抓到 zygote64 的 EXEC 事件,记一行日志立刻
// PTRACE_CONT 放行,然后 detach 退出。10 秒拿不到就放弃退出,绝不无限期攥着 init。
// 不设 PTRACE_O_EXITKILL:万一这个程序自己崩了,内核会自动放行所有被跟踪的进程,不会把 init
// 或 zygote 卡死——这是特意选的,ptrace(2) 文档里写的"跟踪器死了不带 EXITKILL 就自动放行"语义。
#define _GNU_SOURCE
#include <elf.h>
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ptrace.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define LOGDIR "/metadata/herald_log"
#define LOGPATH LOGDIR "/zygisk-fork-observer.log"
static FILE *logf;

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_BOOTTIME, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void logline(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(logf, fmt, ap);
    va_end(ap);
    fflush(logf);
}

static void get_cmdline(pid_t pid, char *buf, size_t buflen) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
    buf[0] = 0;
    FILE *f = fopen(path, "rb");
    if (!f) return;
    size_t n = fread(buf, 1, buflen - 1, f);
    fclose(f);
    buf[n] = 0;
    for (size_t i = 0; i < n; i++) if (buf[i] == 0) buf[i] = ' ';
}

static int read_elf_entry(const char *path, unsigned long long *entry_out) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    Elf64_Ehdr eh;
    size_t n = fread(&eh, 1, sizeof(eh), f);
    fclose(f);
    if (n != sizeof(eh)) return -1;
    if (memcmp(eh.e_ident, ELFMAG, SELFMAG) != 0) return -1;
    *entry_out = eh.e_entry;
    return 0;
}

static volatile sig_atomic_t timed_out = 0;
static void on_alarm(int sig) { (void)sig; timed_out = 1; }

static pid_t attached[256];
static int attached_n = 0;
static void remember(pid_t p) { if (attached_n < 256) attached[attached_n++] = p; }
static void detach_all(void) {
    for (int i = 0; i < attached_n; i++) ptrace(PTRACE_DETACH, attached[i], NULL, NULL);
}

int main(void) {
    mkdir(LOGDIR, 0755);   // 可能是本次开机第一个写 herald_log 的,herald-start.sh 要等到 boot_completed 才会建
    logf = fopen(LOGPATH, "a");
    if (!logf) logf = stderr;

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_alarm;
    sigaction(SIGALRM, &sa, NULL);
    alarm(10);   // 10 秒拿不到目标就放弃,绝不无限期攥着 init

    logline("[%lld] start, attaching to init(1)\n", now_ms());

    if (ptrace(PTRACE_SEIZE, 1, NULL,
               (void *)(long)(PTRACE_O_TRACEFORK | PTRACE_O_TRACEEXEC)) != 0) {
        logline("[%lld] PTRACE_SEIZE(1) failed: %s\n", now_ms(), strerror(errno));
        fclose(logf);
        return 1;
    }
    remember(1);
    logline("[%lld] seized init\n", now_ms());

    int done = 0;
    while (!done && !timed_out) {
        int status;
        pid_t w = waitpid(-1, &status, __WALL);
        if (w < 0) {
            if (errno == EINTR) continue;
            logline("[%lld] waitpid error: %s\n", now_ms(), strerror(errno));
            break;
        }
        if (WIFEXITED(status) || WIFSIGNALED(status)) continue;
        if (!WIFSTOPPED(status)) continue;

        int sig = WSTOPSIG(status);
        if (sig != SIGTRAP) {
            ptrace(PTRACE_CONT, w, NULL, (void *)(long)(sig == SIGSTOP ? 0 : sig));
            continue;
        }

        int event = status >> 16;
        if (event == PTRACE_EVENT_FORK) {
            unsigned long newpid = 0;
            ptrace(PTRACE_GETEVENTMSG, w, NULL, &newpid);
            remember((pid_t)newpid);
            logline("[%lld] FORK from %d -> %lu\n", now_ms(), w, newpid);
            ptrace(PTRACE_CONT, w, NULL, NULL);
        } else if (event == PTRACE_EVENT_EXEC) {
            char cmdline[256];
            get_cmdline(w, cmdline, sizeof(cmdline));
            logline("[%lld] EXEC pid=%d cmdline=\"%s\"\n", now_ms(), w, cmdline);

            // 这一刻 argv 还是 exec 时的原样("app_process64 ... --zygote ..."),
            // 还没跑到 Zygote 把自己改名成"zygote64"——按 --zygote 这个固定参数认,不按名字猜。
            if (strstr(cmdline, "--zygote")) {
                char exe[64];
                snprintf(exe, sizeof(exe), "/proc/%d/exe", w);
                unsigned long long entry = 0;
                int have_entry = (read_elf_entry(exe, &entry) == 0);

                struct user_pt_regs regs;
                struct iovec iov = { &regs, sizeof(regs) };
                if (ptrace(PTRACE_GETREGSET, w, (void *)NT_PRSTATUS, &iov) == 0) {
                    logline("[%lld] ZYGOTE pid=%d pc=0x%llx elf_entry=%s%llx %s\n",
                            now_ms(), w, (unsigned long long)regs.pc,
                            have_entry ? "0x" : "(读不到)", have_entry ? entry : 0ULL,
                            (have_entry && (unsigned long long)regs.pc == entry) ? "MATCH" : "MISMATCH/未知");
                } else {
                    logline("[%lld] PTRACE_GETREGSET 失败: %s\n", now_ms(), strerror(errno));
                }
                done = 1;
            }
            ptrace(PTRACE_CONT, w, NULL, NULL);
        } else {
            ptrace(PTRACE_CONT, w, NULL, NULL);
        }
    }

    if (timed_out) logline("[%lld] 超时(10s),放弃\n", now_ms());
    logline("[%lld] detach 全部 %d 个跟踪对象,退出\n", now_ms(), attached_n);
    detach_all();
    fclose(logf);
    return 0;
}
