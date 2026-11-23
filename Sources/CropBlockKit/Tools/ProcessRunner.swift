import Foundation
import os

public struct ProcessOutput: Sendable, Equatable {
    public let terminationStatus: Int32
    public let stdout: Data
    public let stderr: Data

    public init(terminationStatus: Int32, stdout: Data, stderr: Data) {
        self.terminationStatus = terminationStatus
        self.stdout = stdout
        self.stderr = stderr
    }

    public var stdoutString: String {
        String(decoding: stdout, as: UTF8.self)
    }

    public var stderrString: String {
        String(decoding: stderr, as: UTF8.self)
    }
}

public enum ProcessRunnerError: Error, LocalizedError, Sendable {
    case launchFailed(executable: String, reason: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let executable, let reason):
            "Unable to launch \(executable): \(reason)"
        case .cancelled:
            "Operation was cancelled."
        }
    }
}

/// Async wrapper around `Foundation.Process` with cooperative Swift Task cancellation
/// and concurrent non-blocking stdout/stderr draining (prevents pipe deadlocks on large ffmpeg stderr output).
public enum ProcessRunner {

    private final class Box: Sendable {
        let process: Process
        let state: OSAllocatedUnfairLock<State>

        struct State {
            var stdout = Data()
            var stderr = Data()
            var cancelled = false
            var resumed = false
        }

        init(process: Process) {
            self.process = process
            self.state = OSAllocatedUnfairLock(initialState: State())
        }

        func cancel() {
            let shouldTerminate = state.withLock { s -> Bool in
                s.cancelled = true
                return !s.resumed
            }
            if shouldTerminate && process.isRunning {
                process.terminate()
                let proc = process
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { @Sendable in
                    if proc.isRunning {
                        kill(proc.processIdentifier, SIGKILL)
                    }
                }
            }
        }
    }

    public static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> ProcessOutput {
        try Task.checkCancellation()

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let box = Box(process: process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async { @Sendable in
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    box.state.withLock { $0.stdout = data }
                    group.leave()
                }

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async { @Sendable in
                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    box.state.withLock { $0.stderr = data }
                    group.leave()
                }

                process.terminationHandler = { @Sendable finishedProc in
                    group.notify(queue: DispatchQueue.global(qos: .userInitiated)) { @Sendable in
                        let outcome = box.state.withLock { s -> (shouldResume: Bool, cancelled: Bool, out: Data, err: Data) in
                            guard !s.resumed else { return (false, false, Data(), Data()) }
                            s.resumed = true
                            return (true, s.cancelled, s.stdout, s.stderr)
                        }
                        guard outcome.shouldResume else { return }
                        if outcome.cancelled {
                            continuation.resume(throwing: ProcessRunnerError.cancelled)
                        } else {
                            continuation.resume(returning: ProcessOutput(
                                terminationStatus: finishedProc.terminationStatus,
                                stdout: outcome.out,
                                stderr: outcome.err
                            ))
                        }
                    }
                }

                do {
                    try process.run()
                    // Close parent copies of write ends so readers observe EOF cleanly when child exits.
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                } catch {
                    try? stdoutPipe.fileHandleForWriting.close()
                    try? stderrPipe.fileHandleForWriting.close()
                    let shouldResume = box.state.withLock { s -> Bool in
                        guard !s.resumed else { return false }
                        s.resumed = true
                        return true
                    }
                    if shouldResume {
                        continuation.resume(throwing: ProcessRunnerError.launchFailed(
                            executable: executable.lastPathComponent,
                            reason: error.localizedDescription
                        ))
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}
