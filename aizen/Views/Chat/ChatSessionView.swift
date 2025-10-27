//
//  ChatSessionView.swift
//  aizen
//
//  Chat session interface with messages and input
//

import SwiftUI
import CoreData
import Combine
import UniformTypeIdentifiers

struct ChatSessionView: View {
    let worktree: Worktree
    @ObservedObject var session: ChatSession
    let sessionManager: ChatSessionManager

    @Environment(\.managedObjectContext) private var viewContext

    @StateObject private var agentRouter = AgentRouter()
    @State private var inputText = ""
    @State private var messages: [MessageItem] = []
    @State private var toolCalls: [ToolCall] = []
    @State private var isProcessing = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var currentAgentSession: AgentSession?
    @State private var showingPermissionAlert: Bool = false
    @State private var currentPermissionRequest: RequestPermissionRequest?
    @State private var cancellables = Set<AnyCancellable>()

    @State private var attachments: [URL] = []
    @State private var showingAttachmentPicker = false
    @State private var isHoveringInput = false
    @State private var showingAuthSheet = false
    @State private var showingAgentPlan = false
    @State private var showingCommandAutocomplete = false
    @State private var commandSuggestions: [AvailableCommand] = []
    @State private var showingAgentPicker = false
    @State private var showingAgentSwitchWarning = false
    @State private var pendingAgentSwitch: String?
    @State private var dashPhase: CGFloat = 0

    var selectedAgent: String {
        session.agentName ?? "claude"
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 20) {
                                ForEach(messages) { message in
                                    let _ = print("ChatSessionView: Rendering message \(message.id) - role: \(message.role), content: \(message.content.prefix(50))...")
                                    VStack(alignment: .leading, spacing: 8) {
                                        MessageBubbleView(message: message, agentName: message.role == .agent ? selectedAgent : nil)
                                            .id(message.id)

                                        if message.role == .agent, !message.toolCalls.isEmpty {
                                            toolCallsSummaryView(for: message.toolCalls)
                                                .padding(.leading, 0)
                                        }
                                    }
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                }

                                if isProcessing {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .controlSize(.small)

                                        if let thought = currentAgentSession?.currentThought {
                                            Text(thought)
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .modifier(ShimmerEffect())
                                                .transition(.opacity)
                                        } else {
                                            Text("Agent is thinking...")
                                                .font(.callout)
                                                .foregroundStyle(.secondary)
                                                .modifier(ShimmerEffect())
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .id("processing")
                                    .transition(.opacity)
                                }
                            }
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                        }
                        .onAppear {
                            scrollProxy = proxy
                            loadMessages()
                        }
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        if let agentSession = currentAgentSession, showingPermissionAlert, let request = currentPermissionRequest {
                            HStack {
                                permissionButtonsView(session: agentSession, request: request)
                                    .transition(.opacity)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        if !attachments.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(attachments, id: \.self) { attachment in
                                    attachmentChip(for: attachment)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        HStack(spacing: 8) {
                            Menu {
                                ForEach(AgentRegistry.shared.availableAgents, id: \.self) { agent in
                                    Button {
                                        requestAgentSwitch(to: agent)
                                    } label: {
                                        HStack {
                                            AgentIconView(agent: agent, size: 14)
                                            Text(agent.capitalized)
                                            Spacer()
                                            if agent == selectedAgent {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    AgentIconView(agent: selectedAgent, size: 12)
                                    Text(selectedAgent.capitalized)
                                        .font(.system(size: 11, weight: .medium))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .menuStyle(.borderlessButton)
                            .buttonStyle(.plain)

                            if let agentSession = currentAgentSession, !agentSession.availableModes.isEmpty {
                                modeSelectorView
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 20)

                        inputView
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                }

                if showingAgentPlan, let plan = currentAgentSession?.agentPlan {
                    agentPlanSidebar(plan: plan)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .focusedSceneValue(\.chatActions, ChatActions(cycleModeForward: cycleModeForward))
        .onAppear {
            setupAgentSession()
        }
        .onChange(of: selectedAgent) { _ in
            setupAgentSession()
        }
        .onChange(of: inputText) { newText in
            updateCommandSuggestions(newText)
        }
        .sheet(isPresented: $showingAuthSheet) {
            if let agentSession = currentAgentSession {
                AuthenticationSheet(session: agentSession)
            }
        }
        .alert("Switch Agent?", isPresented: $showingAgentSwitchWarning) {
            Button("Cancel", role: .cancel) {
                pendingAgentSwitch = nil
            }
            Button("Switch", role: .destructive) {
                if let newAgent = pendingAgentSwitch {
                    performAgentSwitch(to: newAgent)
                }
            }
        } message: {
            Text("Switching agents will clear the current conversation and start a new session. This cannot be undone.")
        }
    }

    private func cycleModeForward() {
        guard let session = currentAgentSession else { return }
        let modes = session.availableModes
        guard !modes.isEmpty else { return }

        if let currentIndex = modes.firstIndex(where: { $0.id == session.currentModeId }) {
            let nextIndex = (currentIndex + 1) % modes.count
            Task {
                try? await session.setModeById(modes[nextIndex].id)
            }
        }
    }

    private func requestAgentSwitch(to newAgent: String) {
        guard newAgent != selectedAgent else { return }
        pendingAgentSwitch = newAgent
        showingAgentSwitchWarning = true
    }

    private func performAgentSwitch(to newAgent: String) {
        session.agentName = newAgent
        session.title = newAgent.capitalized
        try? viewContext.save()

        if let sessionId = session.id {
            sessionManager.removeAgentSession(for: sessionId)
        }
        currentAgentSession = nil
        messages = []

        setupAgentSession()

        pendingAgentSwitch = nil
    }

    private func setupAgentSession() {
        guard let sessionId = session.id else { return }

        if let existingSession = sessionManager.getAgentSession(for: sessionId) {
            currentAgentSession = existingSession
            setupSessionObservers(session: existingSession)

            if !existingSession.isActive {
                Task {
                    try? await existingSession.start(agentName: selectedAgent, workingDir: worktree.path!)
                }
            }
            return
        }

        agentRouter.ensureSession(for: selectedAgent)
        if let newSession = agentRouter.getSession(for: selectedAgent) {
            sessionManager.setAgentSession(newSession, for: sessionId)
            currentAgentSession = newSession

            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                messages = newSession.messages
                toolCalls = newSession.toolCalls
            }

            setupSessionObservers(session: newSession)

            if !newSession.isActive {
                Task {
                    try? await newSession.start(agentName: selectedAgent, workingDir: worktree.path!)
                }
            }
        }
    }

    private func loadMessages() {
        guard let messageSet = session.messages as? Set<ChatMessage> else {
            return
        }

        let sortedMessages = messageSet.sorted { $0.timestamp! < $1.timestamp! }

        let loadedMessages = sortedMessages.map { msg in
            MessageItem(
                id: msg.id!.uuidString,
                role: messageRoleFromString(msg.role!),
                content: msg.contentJSON!,
                timestamp: msg.timestamp!
            )
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages = loadedMessages
        }

        scrollToBottom()
    }

    private var inputView: some View {
        HStack(alignment: .center, spacing: 12) {
                Button(action: { showingAttachmentPicker.toggle() }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(!isSessionReady ? .tertiary : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isSessionReady)

                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text(isSessionReady ? "Ask anything..." : "Starting session...")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }

                    CustomTextEditor(
                        text: $inputText,
                        onSubmit: {
                            if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                sendMessage()
                            }
                        }
                    )
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(height: textEditorHeight)
                    .disabled(!isSessionReady)
                }
                .frame(maxWidth: .infinity)

                if let agentSession = currentAgentSession, !agentSession.availableModels.isEmpty {
                    Menu {
                        ForEach(agentSession.availableModels, id: \.modelId) { modelInfo in
                            Button {
                                Task {
                                    try? await agentSession.setModel(modelInfo.modelId)
                                }
                            } label: {
                                HStack {
                                    Text(modelInfo.name)
                                    Spacer()
                                    if modelInfo.modelId == agentSession.currentModelId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            AgentIconView(agent: selectedAgent, size: 12)
                            if let currentModel = agentSession.availableModels.first(where: { $0.modelId == agentSession.currentModelId }) {
                                Text(currentModel.name)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.plain)
                    .help("Select model")
                }

                Button(action: sendMessage) {
                    Image(systemName: canSend ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(canSend ? Color.blue : Color.secondary.opacity(0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous))
            .overlay {
                if currentAgentSession?.currentModeId != "plan" {
                    RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                        .strokeBorder(.separator.opacity(isHoveringInput ? 0.5 : 0.2), lineWidth: 0.5)
                }

                if currentAgentSession?.currentModeId == "plan" {
                    RoundedRectangle(cornerRadius: inputCornerRadius, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [8], dashPhase: dashPhase)
                        )
                        .foregroundStyle(.blue.opacity(0.6))
                        .onAppear {
                            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                dashPhase = -20
                            }
                        }
                        .onDisappear {
                            dashPhase = 0
                        }
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHoveringInput = hovering
                }
            }
            .overlay(alignment: .bottom) {
                if showingCommandAutocomplete && !commandSuggestions.isEmpty {
                    commandAutocompleteView
                        .offset(y: -60)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .fileImporter(
            isPresented: $showingAttachmentPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    attachments.append(contentsOf: urls)
                }
            }
        }
    }

    private func attachmentChip(for url: URL) -> some View {
        AttachmentChipWithDelete(url: url) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                attachments.removeAll { $0 == url }
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing && isSessionReady
    }

    private var isSessionReady: Bool {
        currentAgentSession?.isActive == true && currentAgentSession?.needsAuthentication == false
    }

    private var inputCornerRadius: CGFloat {
        let lineCount = inputText.components(separatedBy: .newlines).count
        return lineCount > 1 ? 16 : 24
    }

    private var textEditorHeight: CGFloat {
        let lineCount = max(1, inputText.components(separatedBy: .newlines).count)
        let lineHeight: CGFloat = 18
        let baseHeight: CGFloat = lineHeight + 12
        return min(max(baseHeight, CGFloat(lineCount) * lineHeight + 12), 120)
    }

    private func sendMessage() {
        let messageText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty else { return }

        let messageAttachments = attachments

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            inputText = ""
            attachments = []
            isProcessing = true
        }

        let userMessage = MessageItem(
            id: UUID().uuidString,
            role: .user,
            content: messageText,
            timestamp: Date()
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages.append(userMessage)
        }

        Task.detached { @MainActor in
            do {
                guard let agentSession = self.currentAgentSession else {
                    throw NSError(domain: "ChatSessionView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No agent session"])
                }

                if !agentSession.isActive {
                    try await agentSession.start(agentName: self.selectedAgent, workingDir: self.worktree.path!)
                }

                try await agentSession.sendMessage(content: messageText, attachments: messageAttachments)

                self.saveMessage(content: messageText, role: "user", agentName: self.selectedAgent)

                self.scrollToBottom()
            } catch {
                let errorMessage = MessageItem(
                    id: UUID().uuidString,
                    role: .system,
                    content: "Error: \(error.localizedDescription)",
                    timestamp: Date()
                )

                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.messages.append(errorMessage)
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.attachments = messageAttachments
                }
            }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isProcessing = false
            }
        }
    }

    private func setupSessionObservers(session: AgentSession) {
        cancellables.removeAll()

        session.$messages
            .receive(on: DispatchQueue.main)
            .sink { newMessages in
                print("ChatSessionView: Received \(newMessages.count) messages")
                if let lastMsg = newMessages.last {
                    print("ChatSessionView: Last message - role: \(lastMsg.role), content length: \(lastMsg.content.count), first 100 chars: \(String(lastMsg.content.prefix(100)))")
                }
                messages = newMessages

                DispatchQueue.main.async {
                    if let lastMessage = newMessages.last {
                        scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .store(in: &cancellables)

        session.$toolCalls
            .receive(on: DispatchQueue.main)
            .sink { newToolCalls in
                toolCalls = newToolCalls

                DispatchQueue.main.async {
                    if let lastCall = newToolCalls.last {
                        scrollProxy?.scrollTo(lastCall.id, anchor: .bottom)
                    } else if let lastMessage = messages.last {
                        scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .store(in: &cancellables)

        session.$isActive
            .receive(on: DispatchQueue.main)
            .sink { isActive in
                if !isActive {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isProcessing = false
                    }
                }
            }
            .store(in: &cancellables)

        session.$needsAuthentication
            .receive(on: DispatchQueue.main)
            .sink { needsAuth in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingAuthSheet = needsAuth
                }
            }
            .store(in: &cancellables)

        session.$agentPlan
            .receive(on: DispatchQueue.main)
            .sink { plan in
                if let p = plan {
                    print("ChatSessionView: Received agent plan with \(p.entries.count) entries")
                    for entry in p.entries {
                        print("ChatSessionView: Plan entry - \(entry.content)")
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showingAgentPlan = true
                    }
                    print("ChatSessionView: Set showingAgentPlan = true")
                } else {
                    print("ChatSessionView: Agent plan cleared")
                }
            }
            .store(in: &cancellables)

        session.$showingPermissionAlert
            .receive(on: DispatchQueue.main)
            .sink { showing in
                print("ChatSessionView: Permission alert visibility changed to: \(showing)")
                showingPermissionAlert = showing
            }
            .store(in: &cancellables)

        session.$permissionRequest
            .receive(on: DispatchQueue.main)
            .sink { request in
                print("ChatSessionView: Permission request updated: \(request?.toolCall?.toolCallId ?? "nil")")
                currentPermissionRequest = request
            }
            .store(in: &cancellables)
    }

    private func saveMessage(content: String, role: String, agentName: String) {
        let message = ChatMessage(context: viewContext)
        message.id = UUID()
        message.timestamp = Date()
        message.role = role
        message.agentName = agentName
        message.contentJSON = content
        message.session = session

        session.lastMessageAt = Date()

        do {
            try viewContext.save()
        } catch {
            print("Failed to save message: \(error)")
        }
    }

    private func messageRoleFromString(_ role: String) -> MessageRole {
        switch role.lowercased() {
        case "user":
            return .user
        case "agent":
            return .agent
        default:
            return .system
        }
    }

    private func scrollToBottom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                if let lastMessage = messages.last {
                    scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
                } else if isProcessing {
                    scrollProxy?.scrollTo("processing", anchor: .bottom)
                }
            }
        }
    }

    private func updateCommandSuggestions(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("/") {
            let commandPart = String(trimmed.dropFirst()).lowercased()

            guard let agentSession = currentAgentSession else {
                showingCommandAutocomplete = false
                return
            }

            if commandPart.isEmpty {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    commandSuggestions = agentSession.availableCommands
                    showingCommandAutocomplete = !commandSuggestions.isEmpty
                }
            } else {
                let filtered = agentSession.availableCommands.filter { command in
                    command.name.lowercased().hasPrefix(commandPart) ||
                    command.description.lowercased().contains(commandPart)
                }

                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    commandSuggestions = filtered
                    showingCommandAutocomplete = !filtered.isEmpty
                }
            }
        } else {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                showingCommandAutocomplete = false
                commandSuggestions = []
            }
        }
    }

    private var commandAutocompleteView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commandSuggestions.prefix(5), id: \.name) { command in
                Button {
                    selectCommand(command)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("/\(command.name)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)

                        Text(command.description)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.clear)

                if command.name != commandSuggestions.prefix(5).last?.name {
                    Divider()
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        .padding(.horizontal, 12)
    }

    private func selectCommand(_ command: AvailableCommand) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            inputText = "/\(command.name) "
            showingCommandAutocomplete = false
        }
    }

    private func modeIcon(for mode: SessionMode) -> some View {
        Group {
            switch mode {
            case .chat:
                Image(systemName: "message")
            case .code:
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            case .ask:
                Image(systemName: "questionmark.circle")
            }
        }
        .font(.system(size: 13))
    }

    private var modeSelectorView: some View {
        Menu {
            ForEach(currentAgentSession?.availableModes ?? [], id: \.id) { modeInfo in
                Button {
                    Task {
                        try? await currentAgentSession?.setModeById(modeInfo.id)
                    }
                } label: {
                    HStack {
                        if let mode = SessionMode(rawValue: modeInfo.id) {
                            modeIcon(for: mode)
                        }
                        Text(modeInfo.name)
                        Spacer()
                        if modeInfo.id == currentAgentSession?.currentModeId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let currentModeId = currentAgentSession?.currentModeId,
                   let mode = SessionMode(rawValue: currentModeId) {
                    modeIcon(for: mode)
                }
                if let currentModeId = currentAgentSession?.currentModeId,
                   let currentMode = currentAgentSession?.availableModes.first(where: { $0.id == currentModeId }) {
                    Text(currentMode.name)
                        .font(.system(size: 12, weight: .medium))
                }

            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private func buttonForeground(for option: PermissionOption) -> Color {
        if option.kind.contains("allow") {
            return .white
        } else if option.kind.contains("reject") {
            return .white
        } else {
            return .primary
        }
    }

    private func buttonBackground(for option: PermissionOption) -> Color {
        if option.kind == "allow_always" {
            return .green
        } else if option.kind.contains("allow") {
            return .blue
        } else if option.kind.contains("reject") {
            return .red
        } else {
            return .clear
        }
    }

    private func permissionButtonsView(session: AgentSession, request: RequestPermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let toolCall = request.toolCall, let rawInput = toolCall.rawInput?.value as? [String: Any] {
                if let plan = rawInput["plan"] as? String {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Plan:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(plan)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                } else if let filePath = rawInput["file_path"] as? String {
                    Text("Write \(URL(fileURLWithPath: filePath).lastPathComponent)?")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if let command = rawInput["command"] as? String {
                    Text("Run `\(command)`?")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {

            if let options = request.options {
                ForEach(options, id: \.optionId) { option in
                    Button {
                        session.respondToPermission(optionId: option.optionId)
                    } label: {
                        HStack(spacing: 3) {
                            if option.kind.contains("allow") {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                            } else if option.kind.contains("reject") {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                            }
                            Text(option.name)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(buttonForeground(for: option))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            buttonBackground(for: option)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toolCallsSummaryView(for messagToolCalls: [ToolCall]) -> some View {
        let allCompleted = messagToolCalls.allSatisfy { $0.status == .completed || $0.status == .failed }

        return Group {
            if allCompleted && !messagToolCalls.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)

                    Text("Ran \(messagToolCalls.count) tool\(messagToolCalls.count == 1 ? "" : "s")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    let failedCount = messagToolCalls.filter { $0.status == .failed }.count
                    if failedCount > 0 {
                        Text("(\(failedCount) failed)")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.3))
                .cornerRadius(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(messagToolCalls) { toolCall in
                        ToolCallView(toolCall: toolCall)
                    }
                }
            }
        }
    }

    private func agentPlanSidebar(plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Agent Plan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Button { showingAgentPlan = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(plan.entries.enumerated()), id: \.offset) { index, entry in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(statusColor(for: entry.status))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.content)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)

                                if let activeForm = entry.activeForm, entry.status == .inProgress {
                                    Text(activeForm)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .italic()
                                }

                                Text(statusLabel(for: entry.status))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(statusColor(for: entry.status))
                                    .textCase(.uppercase)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(entry.status == .inProgress ? Color.blue.opacity(0.05) : Color.clear)
                        )

                        if index < plan.entries.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.separator)
                .frame(width: 1)
        }
    }

    private func statusColor(for status: PlanEntryStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .cancelled:
            return .red
        }
    }

    private func statusLabel(for status: PlanEntryStatus) -> String {
        switch status {
        case .pending:
            return "Pending"
        case .inProgress:
            return "In Progress"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        }
    }

}

// MARK: - Shimmer Effect

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.clear)
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .secondary,
                            .white.opacity(0.8),
                            .secondary
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 1.5)
                    .offset(x: -geometry.size.width * 0.75 + phase * geometry.size.width * 2.25)
                    .mask(content)
                }
            }
            .onAppear {
                withAnimation(
                    .linear(duration: 2.0)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
    }
}

// MARK: - Authentication Sheet

struct AuthenticationSheet: View {
    @ObservedObject var session: AgentSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethodId: String?
    @State private var isAuthenticating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Authentication Required")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !session.authMethods.isEmpty {
                        ForEach(session.authMethods, id: \.id) { method in
                            authMethodButton(for: method)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text("Authentication needed to continue")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Follow the instructions below to authenticate")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 12) {
                if isAuthenticating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .controlSize(.small)
                    Text("Authenticating...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Skip Authentication") {
                    Task {
                        isAuthenticating = true
                        do {
                            try await session.createSessionWithoutAuth()
                            await MainActor.run {
                                isAuthenticating = false
                                dismiss()
                            }
                        } catch {
                            await MainActor.run {
                                isAuthenticating = false
                                print("Skip auth failed: \(error)")
                            }
                        }
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isAuthenticating)

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 400)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func authMethodButton(for method: AuthMethod) -> some View {
        Button {
            selectedMethodId = method.id
            performAuthentication(methodId: method.id)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: selectedMethodId == method.id ? "checkmark.circle.fill" : "key.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(selectedMethodId == method.id ? .green : .blue)

                    Text(method.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if let description = method.description {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if method.id == "claude-login" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("⚠️ This auth method is not implemented in claude-code-acp.")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Text("Instead, run this command in your terminal:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("claude /login")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("claude /login", forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Then click 'Skip Authentication' below to start chatting.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(16)
            .background(.quaternary.opacity(selectedMethodId == method.id ? 0.8 : 0.3), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selectedMethodId == method.id ? Color.blue : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(isAuthenticating)
    }

    private func performAuthentication(methodId: String) {
        isAuthenticating = true

        Task {
            do {
                try await session.authenticate(authMethodId: methodId)
                await MainActor.run {
                    isAuthenticating = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    print("Authentication failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Chat Actions for Keyboard Shortcuts

struct ChatActions {
    let cycleModeForward: () -> Void
}

private struct ChatActionsKey: FocusedValueKey {
    typealias Value = ChatActions
}

extension FocusedValues {
    var chatActions: ChatActions? {
        get { self[ChatActionsKey.self] }
        set { self[ChatActionsKey.self] = newValue }
    }
}
