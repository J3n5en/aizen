//
//  XcodeDeviceService.swift
//  aizen
//
//  Created by Claude on 10.12.25.
//

import Foundation
import os.log

actor XcodeDeviceService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.aizen", category: "XcodeDeviceService")

    // MARK: - List Destinations

    func listDestinations() async throws -> [DestinationType: [XcodeDestination]] {
        var destinations: [DestinationType: [XcodeDestination]] = [:]

        // Get simulators
        let simulators = try await listSimulators()
        if !simulators.isEmpty {
            destinations[.simulator] = simulators
        }

        // Get physical devices
        let devices = try await listPhysicalDevices()
        if !devices.isEmpty {
            destinations[.device] = devices
        }

        // Add My Mac
        destinations[.mac] = [createMacDestination()]

        return destinations
    }

    // MARK: - Simulators

    private func listSimulators() async throws -> [XcodeDestination] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "--json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            logger.error("simctl list devices failed")
            return []
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(SimctlDevicesResponse.self, from: data)

        var destinations: [XcodeDestination] = []

        for (runtime, devices) in response.devices {
            // Parse runtime: com.apple.CoreSimulator.SimRuntime.iOS-17-0
            let runtimeComponents = runtime.components(separatedBy: ".")
            guard let lastComponent = runtimeComponents.last else { continue }

            // Parse platform and version: iOS-17-0 -> iOS, 17.0
            let platformVersion = lastComponent.components(separatedBy: "-")
            guard platformVersion.count >= 2 else { continue }

            let platform = platformVersion[0]
            let version = platformVersion.dropFirst().joined(separator: ".")

            // Filter to iOS and common platforms
            guard ["iOS", "watchOS", "tvOS", "visionOS"].contains(platform) else { continue }

            for device in devices {
                // Skip unavailable simulators
                guard device.isAvailable else { continue }

                let destination = XcodeDestination(
                    id: device.udid,
                    name: device.name,
                    type: .simulator,
                    platform: platform,
                    osVersion: version,
                    isAvailable: device.isAvailable
                )
                destinations.append(destination)
            }
        }

        // Sort by platform, then by version (newest first), then by name
        destinations.sort { lhs, rhs in
            if lhs.platform != rhs.platform {
                // iOS first
                if lhs.platform == "iOS" { return true }
                if rhs.platform == "iOS" { return false }
                return lhs.platform < rhs.platform
            }
            if lhs.osVersion != rhs.osVersion {
                return (lhs.osVersion ?? "") > (rhs.osVersion ?? "")
            }
            return lhs.name < rhs.name
        }

        return destinations
    }

    // MARK: - Physical Devices

    private func listPhysicalDevices() async throws -> [XcodeDestination] {
        // Use devicectl to get devices with CoreDevice UUIDs (required for xcodebuild)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("devicectl_\(UUID().uuidString).json")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["devicectl", "list", "devices", "--json-output", tempFile.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        guard process.terminationStatus == 0,
              let jsonData = try? Data(contentsOf: tempFile) else {
            logger.warning("Failed to list devices via devicectl")
            return []
        }

        let response = try JSONDecoder().decode(DeviceCtlResponse.self, from: jsonData)

        var destinations: [XcodeDestination] = []

        for device in response.result.devices {
            // Skip Macs (we add separately), watches, and unavailable devices
            let deviceType = device.hardwareProperties.deviceType.lowercased()
            guard deviceType == "iphone" || deviceType == "ipad" else { continue }

            // Check if device is available
            let isPaired = device.connectionProperties?.pairingState == "paired"
            guard isPaired else { continue }

            // Use UDID for xcodebuild (not CoreDevice identifier)
            guard let udid = device.hardwareProperties.udid else { continue }

            let destination = XcodeDestination(
                id: udid,
                name: device.deviceProperties.name,
                type: .device,
                platform: device.hardwareProperties.platform,
                osVersion: device.deviceProperties.osVersionNumber,
                isAvailable: isPaired
            )
            destinations.append(destination)
        }

        // Sort by name
        destinations.sort { $0.name < $1.name }

        return destinations
    }

    private func createMacDestination() -> XcodeDestination {
        var macName = "My Mac"

        // Get Mac model name
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "-detailLevel", "mini"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: "\n") {
                    if line.contains("Model Name:") {
                        let parts = line.components(separatedBy: ":")
                        if parts.count >= 2 {
                            macName = parts[1].trimmingCharacters(in: .whitespaces)
                        }
                        break
                    }
                }
            }
        } catch {
            logger.warning("Failed to get Mac model name")
        }

        return XcodeDestination(
            id: "macos",
            name: macName,
            type: .mac,
            platform: "macOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            isAvailable: true
        )
    }

    // MARK: - Simulator Control

    func bootSimulatorIfNeeded(id: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "boot", id]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        // Exit code 149 means already booted, which is fine
        if process.terminationStatus != 0 && process.terminationStatus != 149 {
            logger.warning("Failed to boot simulator \(id), exit code: \(process.terminationStatus)")
        }
    }

    func launchInSimulator(deviceId: String, bundleId: String) async throws {
        // First boot the simulator
        try await bootSimulatorIfNeeded(id: deviceId)

        // Small delay to ensure simulator is ready
        try await Task.sleep(nanoseconds: 500_000_000)

        // Launch the app
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "launch", deviceId, bundleId]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw XcodeError.launchFailed(errorMessage)
        }
    }

    func openSimulatorApp() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Simulator"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try? process.run()
    }

    // MARK: - App Termination

    func terminateInSimulator(deviceId: String, bundleId: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "terminate", deviceId, bundleId]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            logger.debug("Terminated \(bundleId) on simulator \(deviceId)")
        } catch {
            logger.debug("Failed to terminate app (may not be running): \(error.localizedDescription)")
        }
    }

    func terminateMacApp(bundleId: String) async {
        // Use osascript to quit the app gracefully by bundle ID
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(bundleId)\" to quit"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            // Give the app a moment to quit gracefully
            try? await Task.sleep(nanoseconds: 500_000_000)
            logger.debug("Terminated Mac app with bundle ID \(bundleId)")
        } catch {
            logger.debug("Failed to terminate Mac app (may not be running): \(error.localizedDescription)")
        }
    }

    func terminateMacAppByPath(_ appPath: String) async {
        // Extract app name from path and use killall
        let appName = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [appName]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            logger.debug("Terminated Mac app: \(appName)")
        } catch {
            logger.debug("Failed to terminate Mac app (may not be running): \(error.localizedDescription)")
        }
    }

    // MARK: - Physical Device Control

    func installOnDevice(deviceId: String, appPath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["devicectl", "device", "install", "app", "--device", deviceId, appPath]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            logger.error("Failed to install app on device: \(errorMessage)")
            throw XcodeError.installFailed(errorMessage)
        }

        logger.info("Installed \(appPath) on device \(deviceId)")
    }

    func terminateOnDevice(deviceId: String, bundleId: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["devicectl", "device", "process", "terminate", "--device", deviceId, bundleId]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            logger.debug("Terminated \(bundleId) on device \(deviceId)")
        } catch {
            logger.debug("Failed to terminate app on device (may not be running): \(error.localizedDescription)")
        }
    }

    /// Launch app on physical device with console output capture
    /// Returns the process that's streaming console output (caller must handle pipes)
    func launchOnDeviceWithConsole(deviceId: String, bundleId: String) async throws -> Process {
        // First terminate any existing instance
        await terminateOnDevice(deviceId: deviceId, bundleId: bundleId)
        try await Task.sleep(nanoseconds: 300_000_000)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "devicectl", "device", "process", "launch",
            "--device", deviceId,
            "--terminate-existing",
            "--console",
            bundleId
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        logger.info("Launched \(bundleId) on device \(deviceId) with console")

        return process
    }
}
