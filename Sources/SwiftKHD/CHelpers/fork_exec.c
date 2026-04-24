#include "fork_exec.h"
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>

void skhd_fork_and_exec(const char *shell, const char *command, int verbose) {
    pid_t pid1 = fork();
    if (pid1 < 0) {
        perror("swiftkHD: fork");
        return;
    }

    if (pid1 == 0) {
        // Child 1: create new session
        setsid();

        pid_t pid2 = fork();
        if (pid2 < 0) { _exit(1); }
        if (pid2 > 0) { _exit(0); } // Child 1 exits

        // Child 2: redirect unless verbose
        if (!verbose) {
            int devnull = open("/dev/null", O_WRONLY);
            if (devnull >= 0) {
                dup2(devnull, STDOUT_FILENO);
                dup2(devnull, STDERR_FILENO);
                close(devnull);
            }
        }

        // execvp: shell -c command
        char *argv[] = { (char *)shell, "-c", (char *)command, NULL };
        execvp(shell, argv);
        _exit(1);
    }

    // Parent: wait for child1 (exits almost immediately)
    int status;
    waitpid(pid1, &status, 0);
}
