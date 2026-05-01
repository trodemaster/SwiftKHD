import Foundation
import Darwin
import CHelpers

public func forkAndExec(shell: String, command: String, verbose: Bool) {
    var captureFd: Int32 = -1
    let pid = shell.withCString { shellPtr in
        command.withCString { cmdPtr in
            skhd_fork_and_exec(shellPtr, cmdPtr, verbose ? 1 : 0, &captureFd)
        }
    }
    guard pid > 0 else { return }

    let cmd = command
    let fd = captureFd
    DispatchQueue.global(qos: .utility).async {
        // Drain the pipe while the child runs; readDataToEndOfFile blocks until
        // the child closes its write end (i.e. exits), preventing pipe-buffer deadlock.
        var captured = Data()
        if fd != -1 {
            let fh = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            captured = fh.readDataToEndOfFile()
            Darwin.close(fd)
        }

        var status: Int32 = 0
        Darwin.waitpid(pid, &status, 0)

        let exited   = (status & 0x7f) == 0
        let code     = exited ? (status >> 8) & 0xff : 0
        let signaled = !exited && ((status & 0x7f) != 0x7f)

        if exited && code == 0 { return }

        if exited {
            fputs("swiftkhd: command failed (exit \(code)): \(cmd)\n", stderr)
        } else if signaled {
            fputs("swiftkhd: command killed (signal \(status & 0x7f)): \(cmd)\n", stderr)
        }

        if !captured.isEmpty, let text = String(data: captured, encoding: .utf8) {
            fputs(text.hasSuffix("\n") ? text : text + "\n", stderr)
        }
    }
}
