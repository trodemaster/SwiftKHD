#pragma once
#include <unistd.h>

// Forks and execs: shell -c command.
// Returns the child pid (> 0), or -1 on error.
// If not verbose, *out_capture_fd receives the read end of a pipe capturing
// the child's combined stdout+stderr; the caller must close() it after use.
// If verbose, child inherits the parent's fds and *out_capture_fd is set to -1.
pid_t skhd_fork_and_exec(const char *shell, const char *command, int verbose, int *out_capture_fd);
