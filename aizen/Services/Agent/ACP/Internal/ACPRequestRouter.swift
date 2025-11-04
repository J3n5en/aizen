//
//  ACPRequestRouter.swift
//  aizen
//
//  Routes incoming ACP requests to appropriate handlers
//

import Foundation

protocol ACPRequestDelegate: AnyObject {
    func handleFileReadRequest(_ path: String, startLine: Int?, endLine: Int?) async throws -> ReadTextFileResponse
    func handleFileWriteRequest(_ path: String, content: String) async throws -> WriteTextFileResponse
    func handleTerminalCreate(command: String, args: [String]?, cwd: String?, env: [String: String]?, outputLimit: Int?) async throws -> CreateTerminalResponse
    func handleTerminalOutput(terminalId: TerminalId) async throws -> TerminalOutputResponse
    func handlePermissionRequest(request: RequestPermissionRequest) async throws -> RequestPermissionResponse
}

actor ACPRequestRouter {
    // MARK: - Properties

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    weak var delegate: ACPRequestDelegate?

    // MARK: - Initialization

    init(encoder: JSONEncoder, decoder: JSONDecoder) {
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - Delegate Management

    func setDelegate(_ delegate: ACPRequestDelegate?) {
        self.delegate = delegate
    }

    // MARK: - Request Routing

    func routeRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        switch request.method {
        case "fs/read_text_file":
            return try await handleFileRead(request)
        case "fs/write_text_file":
            return try await handleFileWrite(request)
        case "terminal/create":
            return try await handleTerminalCreateRequest(request)
        case "terminal/output":
            return try await handleTerminalOutputRequest(request)
        case "terminal/wait_for_exit":
            return try await handleTerminalWaitForExit(request)
        case "terminal/kill":
            return try await handleTerminalKill(request)
        case "terminal/release":
            return try await handleTerminalRelease(request)
        case "request_permission", "session/request_permission":
            return try await handlePermissionRequestMethod(request)
        default:
            throw ACPClientError.invalidResponse
        }
    }

    // MARK: - Request Handlers

    private func handleFileRead(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate = delegate else {
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(ReadTextFileRequest.self, from: data)

        let response = try await delegate.handleFileReadRequest(
            req.path,
            startLine: req.startLine,
            endLine: req.endLine
        )

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleFileWrite(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate = delegate else {
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(WriteTextFileRequest.self, from: data)

        let response = try await delegate.handleFileWriteRequest(req.path, content: req.content)

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalCreateRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate = delegate else {
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(CreateTerminalRequest.self, from: data)

        let response = try await delegate.handleTerminalCreate(
            command: req.command,
            args: req.args,
            cwd: req.cwd,
            env: req.env,
            outputLimit: req.outputLimit
        )

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalOutputRequest(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate = delegate else {
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(TerminalOutputRequest.self, from: data)

        let response = try await delegate.handleTerminalOutput(terminalId: req.terminalId)

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    // MARK: - Terminal Lifecycle Methods (Stub Implementations)
    // Note: These methods are intentionally stubbed because:
    // 1. Terminal lifecycle is managed by AgentTerminalDelegate via handleTerminalCreate/handleTerminalOutput
    // 2. SwiftTerm-based terminals are long-lived and managed externally
    // 3. The ACP protocol requires these methods but agents rarely call them
    // 4. Full implementation would require integrating with terminal cleanup lifecycle
    // TODO: Implement if agents start using terminal/wait_for_exit, terminal/kill, or terminal/release

    private func handleTerminalWaitForExit(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(WaitForExitRequest.self, from: data)

        // Stub: Terminal lifecycle managed externally
        let response = ["terminal_id": req.terminalId.value]

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalKill(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(KillTerminalRequest.self, from: data)

        // Stub: Terminal lifecycle managed externally via AgentTerminalDelegate.cleanup()
        let response = ["success": true]

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handleTerminalRelease(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(ReleaseTerminalRequest.self, from: data)

        // Stub: Terminal lifecycle managed externally
        let response = ["success": true]

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }

    private func handlePermissionRequestMethod(_ request: JSONRPCRequest) async throws -> AnyCodable {
        guard let delegate = delegate else {
            throw ACPClientError.delegateNotSet
        }

        guard let params = request.params else {
            throw ACPClientError.invalidResponse
        }

        let data = try encoder.encode(params)
        let req = try decoder.decode(RequestPermissionRequest.self, from: data)

        let response = try await delegate.handlePermissionRequest(request: req)

        let responseData = try encoder.encode(response)
        return try decoder.decode(AnyCodable.self, from: responseData)
    }
}
