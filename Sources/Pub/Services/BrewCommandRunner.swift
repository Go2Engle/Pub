import Foundation

struct BrewCommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum BrewCommandError: LocalizedError {
    case executableNotFound
    case nonZeroExit(arguments: [String], result: BrewCommandResult)
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Homebrew was not found. Expected to find `brew` in /opt/homebrew/bin, /usr/local/bin, or your PATH."
        case let .nonZeroExit(arguments, result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderr.isEmpty {
                return "`brew \(arguments.joined(separator: " "))` failed with exit code \(result.exitCode)."
            }
            return stderr
        case .invalidUTF8:
            return "Homebrew returned output that could not be decoded as UTF-8."
        }
    }
}

actor BrewCommandRunner {
    private let fileManager = FileManager.default
    private let preferredPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    func brewLocation() -> String? {
        resolveExecutableURL()?.path
    }

    func run(
        _ arguments: [String],
        stream: (@Sendable (String) -> Void)? = nil
    ) async throws -> BrewCommandResult {
        guard let executableURL = resolveExecutableURL() else {
            throw BrewCommandError.executableNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let accumulator = CommandOutputAccumulator()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = mergedEnvironment(brewURL: executableURL)

            let stdoutHandle = stdoutPipe.fileHandleForReading
            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                accumulator.appendStdout(data)
                if let chunk = String(data: data, encoding: .utf8) {
                    stream?(chunk)
                }
            }

            let stderrHandle = stderrPipe.fileHandleForReading
            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                accumulator.appendStderr(data)
                if let chunk = String(data: data, encoding: .utf8) {
                    stream?(chunk)
                }
            }

            process.terminationHandler = { process in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil

                let remainingStdout = stdoutHandle.readDataToEndOfFile()
                let remainingStderr = stderrHandle.readDataToEndOfFile()
                accumulator.appendStdout(remainingStdout)
                accumulator.appendStderr(remainingStderr)
                let (finalStdout, finalStderr) = accumulator.snapshot()

                guard
                    let stdoutString = String(data: finalStdout, encoding: .utf8),
                    let stderrString = String(data: finalStderr, encoding: .utf8)
                else {
                    continuation.resume(throwing: BrewCommandError.invalidUTF8)
                    return
                }

                let result = BrewCommandResult(
                    stdout: stdoutString,
                    stderr: stderrString,
                    exitCode: process.terminationStatus
                )

                if process.terminationStatus == 0 {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: BrewCommandError.nonZeroExit(arguments: arguments, result: result))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func resolveExecutableURL() -> URL? {
        for path in preferredPaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        for directory in pathEntries {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("brew")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private func mergedEnvironment(brewURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let standardPATH = [
            brewURL.deletingLastPathComponent().path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existingPATH = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        environment["PATH"] = Array(NSOrderedSet(array: standardPATH + existingPATH)).compactMap { $0 as? String }.joined(separator: ":")
        return environment
    }
}

private final class CommandOutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func appendStdout(_ data: Data) {
        lock.lock()
        stdout.append(data)
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        stderr.append(data)
        lock.unlock()
    }

    func snapshot() -> (Data, Data) {
        lock.lock()
        let result = (stdout, stderr)
        lock.unlock()
        return result
    }
}
