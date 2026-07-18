/*
 * setup-seccomp.c — Generate a seccomp BPF filter for bwrap --seccomp
 *
 * This replaces `bwrap --new-session` (setsid) as the CVE-2017-5226
 * mitigation. The sandbox keeps its controlling terminal (receiving SIGWINCH
 * on resize) while TIOCSTI keystroke injection and other dangerous syscalls
 * are blocked.
 *
 * The blocklist is ported from Flatpak's setup_seccomp() in
 * common/flatpak-run.c:
 * https://github.com/flatpak/flatpak/blob/main/common/flatpak-run.c
 *
 * Usage: setup-seccomp [--multiarch] [--allow-can] [--allow-bluetooth]
 * Outputs a compiled cBPF program to stdout (for bwrap --seccomp FD).
 */
// NOLINTBEGIN(clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling)
// Suppressed: fprintf to stderr with a format string is sound;
// the suggested replacement (fprintf_s) is not implemented in glibc.

#include <errno.h>
#include <linux/sched.h> /* CLONE_NEWUSER */
#include <seccomp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>  /* TIOCSTI */
#include <sys/socket.h> /* AF_* */
#include <unistd.h>

/* TIOCLINUX may not be defined on all architectures. */
#ifndef TIOCLINUX
#define TIOCLINUX 0x541c
#endif

/* PER_LINUX — the default Linux personality, allowed by the personality filter.
 */
#define ALLOWED_PERSONALITY 0

/*
 * Add a rule that blocks a syscall (no arg condition).
 * EFAULT (syscall not known for a non-native arch) is a warning, not fatal.
 * Returns 0 on success, -1 on fatal error.
 */
static int block_syscall(scmp_filter_ctx ctx, int nr, int errnum) {
  int r = seccomp_rule_add(ctx, SCMP_ACT_ERRNO(errnum), nr, 0);
  if (r == -EFAULT) {
    fprintf(stderr,
            "setup-seccomp: warning: syscall %d not known for all arches, "
            "skipping\n",
            nr);
    return 0;
  }
  if (r < 0) {
    fprintf(stderr, "setup-seccomp: error: failed to block syscall %d: %d\n",
            nr, r);
    return -1;
  }
  return 0;
}

/*
 * Add a rule that blocks a syscall with an argument condition.
 * EFAULT is a warning, not fatal (same as block_syscall).
 */
static int block_syscall_arg(scmp_filter_ctx ctx, int nr, int errnum,
                             struct scmp_arg_cmp arg) {
  int r = seccomp_rule_add(ctx, SCMP_ACT_ERRNO(errnum), nr, 1, arg);
  if (r == -EFAULT) {
    fprintf(stderr,
            "setup-seccomp: warning: syscall %d not known for all arches, "
            "skipping\n",
            nr);
    return 0;
  }
  if (r < 0) {
    fprintf(stderr,
            "setup-seccomp: error: failed to block syscall %d with arg: %d\n",
            nr, r);
    return -1;
  }
  return 0;
}

/*
 * Block a socket family using seccomp_rule_add_exact.
 * seccomp_rule_add_exact is needed for socket filtering:
 * https://github.com/seccomp/libseccomp/issues/8
 */
static int block_socket_family_eq(scmp_filter_ctx ctx, int family) {
  int r =
      seccomp_rule_add_exact(ctx, SCMP_ACT_ERRNO(EAFNOSUPPORT),
                             SCMP_SYS(socket), 1, SCMP_A0(SCMP_CMP_EQ, family));
  if (r == -EFAULT) {
    fprintf(stderr, "setup-seccomp: warning: socket syscall not known for all "
                    "arches, skipping\n");
    return 0;
  }
  if (r < 0) {
    fprintf(stderr,
            "setup-seccomp: error: failed to block socket family %d: %d\n",
            family, r);
    return -1;
  }
  return 0;
}

static int block_socket_family_ge(scmp_filter_ctx ctx, int family) {
  int r =
      seccomp_rule_add_exact(ctx, SCMP_ACT_ERRNO(EAFNOSUPPORT),
                             SCMP_SYS(socket), 1, SCMP_A0(SCMP_CMP_GE, family));
  if (r == -EFAULT) {
    fprintf(stderr, "setup-seccomp: warning: socket syscall not known for all "
                    "arches, skipping\n");
    return 0;
  }
  if (r < 0) {
    fprintf(stderr,
            "setup-seccomp: error: failed to block socket family >= %d: %d\n",
            family, r);
    return -1;
  }
  return 0;
}

int main(int argc, char *argv[]) {
  int multiarch = 0;
  int allow_can = 0;
  int allow_bluetooth = 0;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--multiarch") == 0)
      multiarch = 1;
    else if (strcmp(argv[i], "--allow-can") == 0)
      allow_can = 1;
    else if (strcmp(argv[i], "--allow-bluetooth") == 0)
      allow_bluetooth = 1;
    else {
      fprintf(stderr, "setup-seccomp: unknown option: %s\n", argv[i]);
      return 1;
    }
  }

  scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ALLOW);
  if (!ctx) {
    fprintf(stderr, "setup-seccomp: failed to initialize seccomp filter\n");
    return 1;
  }

  /* On multiarch x86_64, also filter the 32-bit x86 syscall table. */
  if (multiarch) {
#ifdef __x86_64__
    int r = seccomp_arch_add(ctx, SCMP_ARCH_X86);
    if (r < 0 && r != -EEXIST) {
      fprintf(stderr, "setup-seccomp: failed to add x86 arch: %d\n", r);
      seccomp_release(ctx);
      return 1;
    }
#endif
  }

  int ret = 0;

  /* ---- Syscall blocklist (ported from Flatpak's setup_seccomp) ---- */

  /* Block dmesg */
  ret |= block_syscall(ctx, SCMP_SYS(syslog), EPERM);
  /* Useless old syscall */
  ret |= block_syscall(ctx, SCMP_SYS(uselib), EPERM);
  /* Don't allow disabling accounting */
  ret |= block_syscall(ctx, SCMP_SYS(acct), EPERM);
  /* Don't allow reading current quota use */
  ret |= block_syscall(ctx, SCMP_SYS(quotactl), EPERM);

  /* Don't allow access to the kernel keyring */
  ret |= block_syscall(ctx, SCMP_SYS(add_key), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(keyctl), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(request_key), EPERM);

  /* Scary VM/NUMA ops */
  ret |= block_syscall(ctx, SCMP_SYS(move_pages), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(mbind), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(get_mempolicy), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(set_mempolicy), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(migrate_pages), EPERM);

  /* Don't allow subnamespace setups */
  ret |= block_syscall(ctx, SCMP_SYS(unshare), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(setns), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(mount), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(umount), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(umount2), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(pivot_root), EPERM);
  ret |= block_syscall(ctx, SCMP_SYS(chroot), EPERM);

  /* Block clone() with CLONE_NEWUSER flag */
#if defined(__s390__) || defined(__s390x__) || defined(__CRIS__)
  /* CONFIG_CLONE_BACKWARDS2: flags are the second arg */
  ret |= block_syscall_arg(
      ctx, SCMP_SYS(clone), EPERM,
      SCMP_A1(SCMP_CMP_MASKED_EQ, CLONE_NEWUSER, CLONE_NEWUSER));
#else
  /* Normally flags are the first arg */
  ret |= block_syscall_arg(
      ctx, SCMP_SYS(clone), EPERM,
      SCMP_A0(SCMP_CMP_MASKED_EQ, CLONE_NEWUSER, CLONE_NEWUSER));
#endif

  /* Don't allow faking input to the controlling tty (CVE-2017-5226) */
  ret |= block_syscall_arg(ctx, SCMP_SYS(ioctl), EPERM,
                           SCMP_A1(SCMP_CMP_MASKED_EQ, 0xFFFFFFFFu, TIOCSTI));
  /* Linux virtual console copy/paste (CVE-2023-28100) */
  ret |= block_syscall_arg(ctx, SCMP_SYS(ioctl), EPERM,
                           SCMP_A1(SCMP_CMP_MASKED_EQ, 0xFFFFFFFFu, TIOCLINUX));

  /* seccomp can't inspect clone3()'s struct clone_args, so block it entirely.
   * Return ENOSYS so userspace falls back to clone(). (CVE-2021-41133) */
  ret |= block_syscall(ctx, SCMP_SYS(clone3), ENOSYS);

  /* New mount manipulation APIs (CVE-2021-41133) */
  ret |= block_syscall(ctx, SCMP_SYS(open_tree), ENOSYS);
  ret |= block_syscall(ctx, SCMP_SYS(move_mount), ENOSYS);
  ret |= block_syscall(ctx, SCMP_SYS(fsopen), ENOSYS);
  ret |= block_syscall(ctx, SCMP_SYS(fsconfig), ENOSYS);
  ret |= block_syscall(ctx, SCMP_SYS(fsmount), ENOSYS);
  ret |= block_syscall(ctx, SCMP_SYS(fspick), ENOSYS);
  ret |= block_syscall(ctx, SCMP_SYS(mount_setattr), ENOSYS);

  /* ---- Non-devel blocklist ---- */

  /* Profiling operations (perf has been the source of many CVEs) */
  ret |= block_syscall(ctx, SCMP_SYS(perf_event_open), EPERM);
  /* Don't allow switching to BSD emulation or other personalities.
   * Allow personality(0) (PER_LINUX), block everything else. */
  ret |= block_syscall_arg(ctx, SCMP_SYS(personality), EPERM,
                           SCMP_A0(SCMP_CMP_NE, ALLOWED_PERSONALITY));
  /* Don't allow ptrace */
  ret |= block_syscall(ctx, SCMP_SYS(ptrace), EPERM);

  /* ---- Non-multiarch blocklist ---- */

  if (!multiarch) {
    /* modify_ldt is a historic source of information leaks.
     * Required for 16-bit apps and some Wine patches in multiarch. */
    ret |= block_syscall(ctx, SCMP_SYS(modify_ldt), EPERM);
  }

  if (ret != 0) {
    fprintf(stderr, "setup-seccomp: failed to add blocklist rules\n");
    seccomp_release(ctx);
    return 1;
  }

  /* ---- Socket family filtering ---- */
  /* Blocklist all but AF_UNSPEC, AF_LOCAL, AF_INET, AF_INET6, AF_NETLINK.
   * Optionally allow AF_CAN and AF_BLUETOOTH.
   * The array MUST be sorted in ascending order for the gap-filling logic. */
  int allowed_families[7] = {
      AF_UNSPEC,  /* 0 */
      AF_LOCAL,   /* 1 */
      AF_INET,    /* 2 */
      AF_INET6,   /* 10 */
      AF_NETLINK, /* 16 */
  };
  int n_allowed = 5;

  if (allow_can)
    allowed_families[n_allowed++] = AF_CAN; /* 29 */
  if (allow_bluetooth)
    allowed_families[n_allowed++] = AF_BLUETOOTH; /* 31 */

  int last_allowed = -1;
  for (int i = 0; i < n_allowed; i++) {
    int family = allowed_families[i];
    for (int d = last_allowed + 1; d < family; d++)
      ret |= block_socket_family_eq(ctx, d);
    last_allowed = family;
  }
  /* Block everything above the last allowed family */
  ret |= block_socket_family_ge(ctx, last_allowed + 1);

  if (ret != 0) {
    fprintf(stderr, "setup-seccomp: failed to add socket filtering rules\n");
    seccomp_release(ctx);
    return 1;
  }

  /* ---- Export BPF to stdout ---- */
  int r = seccomp_export_bpf(ctx, STDOUT_FILENO);
  if (r != 0) {
    fprintf(stderr, "setup-seccomp: failed to export BPF: %d\n", r);
    seccomp_release(ctx);
    return 1;
  }

  seccomp_release(ctx);
  return 0;
}
// NOLINTEND(clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling)
