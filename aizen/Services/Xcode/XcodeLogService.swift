//
//  XcodeLogService.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 10.12.25.
//

import Foundation
import os.log

actor XcodeLogService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeLogService")

    private var isStreamingFlag = false

    // MARK: - Log Streaming from Process Pipes (for Mac apps)

    func startStreamingFromPipes(outputPipe: Pipe?, errorPipe: Pipe?, appName: String) -> AsyncStream<String> {
        isStreamingFlag = true

        return AsyncStream { continuation in
            continuation.yield("Streaming stdout/stderr for \(appName)...")
            continuation.yield("---")

            guard let outputPipe = outputPipe, let errorPipe = errorPipe else {
                continuation.yield("Error: No output pipes available")
                continuation.finish()
                return
            }

            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading

            // Read stdout in background
            DispatchQueue.global(qos: .userInitiated).async {
                outputHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }

                    if let text = String(data: data, encoding: .utf8) {
                        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                        for line in lines {
                            continuation.yield(line)
                        }
                    }
                }
            }

            // Read stderr in background
            DispatchQueue.global(qos: .userInitiated).async {
                errorHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }

                    if let text = String(data: data, encoding: .utf8) {
                        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                        for line in lines {
                            continuation.yield("[stderr] \(line)")
                        }
                    }
                }
            }

            continuation.onTermination = { _ in
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
            }
        }
    }

    // MARK: - Log Streaming via log command (for simulators)

    private var currentProcess: Process?

    func startStreaming(bundleId: String, destination: XcodeDestination) -> AsyncStream<String> {
        stopStreamingSync()
        isStreamingFlag = true

        return AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                await self.runLogStream(bundleId: bundleId, destination: destination, continuation: continuation)
            }
        }
    }

    private func runLogStream(bundleId: String, destination: XcodeDestination, continuation: AsyncStream<String>.Continuation) async {
        let process = Process()

        // Extract app name from bundle ID (last component)
        let appName = bundleId.components(separatedBy: ".").last ?? bundleId
        let predicate = "(subsystem BEGINSWITH '\(bundleId)') OR (process == '\(appName)') OR (processImagePath CONTAINS '\(appName)')"

        // For simulators, use xcrun simctl spawn to access the simulator's log stream
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "simctl", "spawn", destination.id,
            "log", "stream",
            "--predicate", predicate,
            "--style", "compact",
            "--level", "debug"
        ]

        continuation.yield("Streaming unified logs for \(bundleId)...")
        continuation.yield("Predicate: \(predicate)")
        continuation.yield("---")

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let outputHandle = outputPipe.fileHandleForReading

        do {
            try process.run()
            self.currentProcess = process
            logger.info("Started log streaming for \(bundleId) on \(destination.name)")

            await withTaskCancellationHandler {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    process.terminationHandler = { _ in
                        cont.resume()
                    }

                    DispatchQueue.global(qos: .userInitiated).async {
                        while process.isRunning {
                            let data = outputHandle.availableData
                            if data.isEmpty {
                                Thread.sleep(forTimeInterval: 0.1)
                                continue
                            }

                            if let text = String(data: data, encoding: .utf8) {
                                let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                                for line in lines {
                                    continuation.yield(line)
                                }
                            }
                        }

                        let remainingData = outputHandle.readDataToEndOfFile()
                        if let text = String(data: remainingData, encoding: .utf8), !text.isEmpty {
                            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                            for line in lines {
                                continuation.yield(line)
                            }
                        }
                    }
                }
            } onCancel: {
                process.terminate()
            }

            logger.info("Log streaming ended for \(bundleId)")
        } catch {
            logger.error("Failed to start log streaming: \(error.localizedDescription)")
            continuation.yield("Error: Failed to start log streaming - \(error.localizedDescription)")
        }

        continuation.finish()
        self.currentProcess = nil
        isStreamingFlag = false
    }

    func stopStreaming() {
        stopStreamingSync()
    }

    private func stopStreamingSync() {
        if let process = currentProcess, process.isRunning {
            process.terminate()
            logger.info("Stopped log streaming")
        }
        currentProcess = nil
        isStreamingFlag = false
    }

    var isStreaming: Bool {
        isStreamingFlag
    }
}
