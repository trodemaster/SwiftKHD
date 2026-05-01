#include "fork_exec.h"
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>

pid_t skhd_fork_and_exec(const char *shell, const char *command, int verbose, int *out_capture_fd) {
    int pipefd[2] = {-1, -1};
    if (!verbose) {
        if (pipe(pipefd) != 0) {
            pipefd[0] = pipefd[1] = -1;
        }
    }

    pid_t pid = fork();
    if (pid < 0) {
        perror("swiftkhd: fork");
        if (pipefd[0] != -1) { close(pipefd[0]); close(pipefd[1]); }
        *out_capture_fd = -1;
        return -1;
    }

    if (pid == 0) {
        // Child: create new session so it survives swiftkhd restart
        setsid();

        if (!verbose && pipefd[1] != -1) {
            // Redirect both stdout and stderr into the capture pipe
            dup2(pipefd[1], STDOUT_FILENO);
            dup2(pipefd[1], STDERR_FILENO);
            close(pipefd[1]);
            close(pipefd[0]);
        } else {
            // Verbose: inherit parent fds (go to log); close unused pipe ends
            if (pipefd[0] != -1) close(pipefd[0]);
            if (pipefd[1] != -1) close(pipefd[1]);
        }

        char *argv[] = {(char *)shell, "-c", (char *)command, NULL};
        execvp(shell, argv);
        _exit(127);
    }

    // Parent: close the write end so EOF is detected when child exits
    if (pipefd[1] != -1) close(pipefd[1]);
    *out_capture_fd = pipefd[0]; // read end, or -1 in verbose mode
    return pid;
}
