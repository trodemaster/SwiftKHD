import Foundation
import CHelpers

/// Execute a shell command using the double-fork technique via C helper.
/// The C implementation avoids Swift's unavailability restriction on fork().
public func forkAndExec(shell: String, command: String, verbose: Bool) {
    shell.withCString { shellPtr in
        command.withCString { cmdPtr in
            skhd_fork_and_exec(shellPtr, cmdPtr, verbose ? 1 : 0)
        }
    }
}
