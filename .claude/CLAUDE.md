# Aizen Project - Claude Instructions

## Project Overview

Aizen is a macOS developer tool for managing Git worktrees with integrated terminal and AI agent support via the Agent Client Protocol (ACP).

## Architecture

### Domain Organization

The codebase is organized by domain:
- **App/**: Application entry point
- **Models/**: Data models and protocol types
- **Services/**: Business logic (Agent, Git, Persistence)
- **Views/**: SwiftUI views organized by feature (Chat, Terminal, Workspace, Worktree, Settings)
- **Managers/**: State managers
- **Utilities/**: Helper functions

### Design Patterns

- **MVVM**: Views observe `@ObservableObject` models (e.g., `AgentSession`, `RepositoryManager`)
- **Actor Model**: Thread-safe services (`ACPClient`, `GitService`, `AgentInstaller`)
- **Core Data**: Persistent entities (Workspace, Repository, Worktree, ChatSession)
- **Modern Concurrency**: async/await throughout

### Key Components

**Agent Client Protocol (ACP)**:
- `ACPClient` (actor): Manages subprocess communication with agents
- `AgentSession` (@MainActor): Observable session state wrapper
- `ACPTypes`: JSON-RPC 2.0 protocol definitions
- Supports Claude, Codex (OpenAI), and Gemini

**Git Operations**:
- `GitService` (actor): Executes git commands
- `RepositoryManager`: CRUD for repositories and worktrees

**Chat Interface**:
- `ChatTabView`: Tab management
- `ChatSessionView`: Full session UI (messages, input, controls)
- `MessageBubbleView`: Individual message rendering
- `Components/`: Reusable chat components (markdown, code blocks, input)

**Terminal Integration**:
- SwiftTerm-based terminal emulator
- Split pane support via `TerminalSplitLayout`
- Terminal creation/management delegated through `AgentSession`

## Development Guidelines

### When Working on Features

1. **Respect domain boundaries**:
   - Agent logic → `Services/Agent/`
   - Git operations → `Services/Git/`
   - UI components → `Views/{feature}/`

2. **Keep files focused**:
   - Extract large views into components
   - Split files over 500 lines when logical
   - Put reusable components in `Components/` folders

3. **Use modern Swift patterns**:
   - Actors for concurrent operations
   - @MainActor for UI state
   - async/await over completion handlers
   - Combine for reactive streams

4. **Follow SwiftUI best practices**:
   - Minimize `useEffect`-style logic (use declarative state)
   - Extract complex views into subviews
   - Use `@FetchRequest` for Core Data
   - Prefer composition over inheritance

### File Organization Rules

- Place new agent-related code in `Services/Agent/`
- Place new Git functionality in `Services/Git/`
- Create new view folders when adding major features (e.g., `Views/Search/`)
- Extract components to `Components/` subfolder when reused 3+ times
- Keep utilities generic in `Utilities/`

### Testing

- Services expose clean interfaces for mocking
- Actors can be tested with `@MainActor` or Task contexts
- Use Core Data preview context for view testing

### Protocol Communication

**ACP Flow**:
1. User input → `ChatSessionView`
2. → `AgentSession.sendMessage(_:)`
3. → `ACPClient.sendRequest(_:)`
4. → Subprocess (agent binary)
5. ← JSON-RPC notifications (streamed)
6. → `ACPClient` delegates to `AgentSession`
7. → Published state updates
8. → SwiftUI view refreshes

**File Operations**:
- Agent requests file read → `ACPClient` delegates → `AgentSession` → FileHandle

**Terminal Operations**:
- Agent requests terminal → `ACPClient` delegates → `AgentSession` → Process spawn

### Common Tasks

**Add new agent support**:
1. Update `AgentRegistry.swift` with agent config
2. Add icon to `Assets.xcassets/AgentIcons.xcassetcatalog/`
3. Update `AgentIconView.swift` for icon mapping
4. Add installation logic to `AgentInstaller.swift` if needed

**Add new view feature**:
1. Create folder in `Views/{Feature}/`
2. Add main view file
3. Extract components to `Components/` if complex
4. Update `ContentView.swift` or appropriate parent for navigation

**Modify ACP protocol**:
1. Update `ACPTypes.swift` with new types
2. Handle in `ACPClient.handleNotification(_:)` or `handleRequest(_:)`
3. Update `AgentSession` delegate methods if needed
4. Update UI in relevant view

### Dependencies

- **SwiftTerm**: Terminal emulator (no custom modifications)
- **swift-markdown**: Markdown parsing (Apple official)
- **HighlightSwift**: Syntax highlighting (wrapper around highlight.js)

### Build Notes

- Minimum: macOS 26.0+
- Xcode 16.0+
- Swift 5.0+
- All file paths must be absolute in tool operations
- Use git mv for file moves to preserve history

### Important Patterns to Follow

**Observable State**:
```swift
@MainActor
class AgentSession: ObservableObject {
    @Published var messages: [MessageItem] = []
    // ...
}
```

**Actor Services**:
```swift
actor GitService {
    func listWorktrees(at path: String) async throws -> [WorktreeInfo] {
        // Thread-safe operations
    }
}
```

**Core Data Integration**:
```swift
@FetchRequest(
    sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.order, ascending: true)]
)
private var workspaces: FetchedResults<Workspace>
```

## Code Style

- Use Swift naming conventions (camelCase, PascalCase for types)
- Prefer explicit types for clarity in complex code
- Add comments for non-obvious logic, especially in ACP protocol handling
- Group related properties/methods with `// MARK: - Section`
- Keep line length reasonable (~120 chars)

## Common Issues

**Build fails after file move**:
- Xcode project references must be updated manually if not using git mv
- Clean build folder: Cmd+Shift+K

**Agent not connecting**:
- Check agent binary path in Settings > Agents
- Verify agent supports ACP protocol
- Check console logs for subprocess stderr

**Terminal not displaying**:
- SwiftTerm requires proper frame size
- Check terminal theme configuration
- Verify process spawn permissions

## Resources

- [Agent Client Protocol Spec](https://agentclientprotocol.com)
- [SwiftTerm Docs](https://github.com/migueldeicaza/SwiftTerm)
- [swift-markdown](https://github.com/apple/swift-markdown)
