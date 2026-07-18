/*
 * seccomp-probe.c — Verify the seccomp filter is working correctly.
 *
 * Runs INSIDE the bwrap sandbox and tests:
 *   — Session inheritance (SIGWINCH propagation proxy)
 *   — Blocked syscalls return EPERM/ENOSYS/EAFNOSUPPORT
 *   — Allowed syscalls (TIOCGWINSZ, socket(AF_INET)) work normally
 *
 * Exit 0 = all tests pass, 1 = any test fails.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <unistd.h>

static int tests = 0;
static int passed = 0;
static int failed = 0;
static char line[256];

#define TEST(cond, fmt, ...)                                                   \
  do {                                                                         \
    tests++;                                                                   \
    snprintf(line, sizeof(line), fmt, ##__VA_ARGS__);                          \
    if ((cond)) {                                                              \
      passed++;                                                                \
      printf("  PASS: %s\n", line);                                            \
    } else {                                                                   \
      failed++;                                                                \
      printf("  FAIL: %s\n", line);                                            \
    }                                                                          \
  } while (0)

#define TRY_SYSCALL(nr, ...) syscall((long)(nr), ##__VA_ARGS__)
#define CHK_EPERM(nr, name) CHK_ERRNO(nr, EPERM, name)
#define CHK_ENOSYS(nr, name) CHK_ERRNO(nr, ENOSYS, name)
#define CHK_EAFNOSUPPORT(nr, name) CHK_ERRNO(nr, EAFNOSUPPORT, name)

#define CHK_ERRNO(nr, expected, name)                                          \
  do {                                                                         \
    errno = 0;                                                                 \
    TRY_SYSCALL(nr);                                                           \
    TEST(errno == (expected), "%s -> errno=%d (%s)", name, errno,              \
         strerror(errno));                                                     \
  } while (0)

/* Synchronous kill — test that SIGWINCH can be sent within the sandbox.
 * We send to our own pid, not the group, so it's delivered directly. */
static volatile int sigwinch_caught = 0;
static void sigwinch_handler(int sig) {
  (void)sig;
  sigwinch_caught = 1;
}

int main(void) {
  /* ── SIGWINCH propagation blinker ── */
  /* Without --new-session the sandbox inherits the parent session, so
     sid != pid.  With --new-session (the old broken behaviour) setsid()
     makes the process a session leader, sid == pid. */
  int sid = getsid(0);
  int pgid = getpgrp();
  int pid = getpid();
  printf("SIGWINCH_BLINKER: sid=%d pgid=%d pid=%d\n", sid, pgid, pid);

  /* Also test that we can actually send WINCH and have a handler fire.
     This proves signal delivery within the sandbox isn't blocked. */
  signal(SIGWINCH, sigwinch_handler);
  sigwinch_caught = 0;
  kill(pid, SIGWINCH);
  TEST(sigwinch_caught, "SIGWINCH handler fired after kill(getpid(), WINCH)");

  /* ── Core CVE fixes ── */

  /* CVE-2017-5226 TIOCSTI keystroke injection */
  errno = 0;
  ioctl(STDIN_FILENO, TIOCSTI, (char[]){'X'});
  TEST(errno == EPERM, "CVE-2017-5226: ioctl(TIOCSTI) -> errno=%d (%s)", errno,
       strerror(errno));

  /* CVE-2023-28100 TIOCLINUX virtual-console copy/paste */
  errno = 0;
  ioctl(STDIN_FILENO, 0x541C, NULL);
  TEST(errno == EPERM, "CVE-2023-28100: ioctl(TIOCLINUX) -> errno=%d (%s)",
       errno, strerror(errno));

  /* TIOCGWINSZ must NOT be blocked (terminal-size query for resize). */
  errno = 0;
  ioctl(STDOUT_FILENO, TIOCGWINSZ, NULL);
  TEST(errno != EPERM, "TIOCGWINSZ not blocked (errno=%d != EPERM)", errno);

  /* ── Blocked syscalls ── */
  /* (all should return EPERM unless noted) */
  CHK_EPERM(SYS_ptrace, "ptrace");
  CHK_EPERM(SYS_mount, "mount");
  CHK_EPERM(SYS_unshare, "unshare");
  CHK_EPERM(SYS_setns, "setns");
  CHK_EPERM(SYS_pivot_root, "pivot_root");
  CHK_EPERM(SYS_chroot, "chroot");
  CHK_EPERM(SYS_syslog, "syslog (dmesg)");
  CHK_EPERM(SYS_perf_event_open, "perf_event_open");
  CHK_EPERM(SYS_keyctl, "keyctl");
  CHK_EPERM(SYS_add_key, "add_key");
  CHK_EPERM(SYS_request_key, "request_key");

  /* personality(anything but 0) → EPERM */
  errno = 0;
  TRY_SYSCALL(SYS_personality, 0x1);
  TEST(errno == EPERM, "personality(0x1) -> errno=%d (%s)", errno,
       strerror(errno));

  /* modify_ldt — only filtered on non-multiarch; test it anyway */
  errno = 0;
  TRY_SYSCALL(SYS_modify_ldt, 0, NULL, 0);
  TEST(errno == EPERM, "modify_ldt -> errno=%d (%s)", errno, strerror(errno));

#ifdef SYS_clone3
  CHK_ENOSYS(SYS_clone3, "clone3 -> ENOSYS (CVE-2021-41133)");
#endif

  /* ── Socket family filtering ── */
  /* AF_PACKET (17) should be blocked with EAFNOSUPPORT */
  errno = 0;
  int sock = (int)TRY_SYSCALL(SYS_socket, 17, SOCK_STREAM, 0);
  int sock_err = errno;
  if (sock >= 0)
    close(sock);
  TEST(sock_err == EAFNOSUPPORT, "socket(AF_PACKET) -> errno=%d (%s)", sock_err,
       strerror(sock_err));

  /* AF_INET (2) should be allowed — don't use SOCK_STREAM since that would
   * try to connect to something; just create a raw/seqpacket placeholder. */
  errno = 0;
  int inet_sock = (int)TRY_SYSCALL(SYS_socket, AF_INET, SOCK_DGRAM, 0);
  int inet_err = errno;
  if (inet_sock >= 0)
    close(inet_sock);
  TEST(inet_sock >= 0, "socket(AF_INET) -> created fd=%d (allowed)", inet_sock);

  /* ── Summary ── */
  printf("\n=== RESULTS: %d tests, %d passed, %d failed ===\n", tests, passed,
         failed);
  if (failed > 0) {
    printf("SOME TEST FAILED\n");
    return 1;
  }
  printf("ALL TESTS PASSED\n");
  return 0;
}
