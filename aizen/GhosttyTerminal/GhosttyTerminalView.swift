//
//  GhosttyTerminalView.swift
//  aizen
//
//  NSView subclass that integrates Ghostty terminal rendering
//

import AppKit
import Metal
import OSLog
import SwiftUI

/// NSView that embeds a Ghostty terminal surface with Metal rendering
///
/// This view handles:
/// - Metal layer setup for terminal rendering
/// - Input forwarding (keyboard, mouse, scroll)
/// - Focus management
/// - Surface lifecycle management
@MainActor
class GhosttyTerminalView: NSView {
    // MARK: - Properties

    private var ghosttyApp: ghostty_app_t?
    private weak var ghosttyAppWrapper: Ghostty.App?
    internal var surface: Ghostty.Surface?
    private var surfaceReference: Ghostty.SurfaceReference?
    private let worktreePath: String

    /// Callback invoked when the terminal process exits
    var onProcessExit: (() -> Void)?

    /// Callback invoked when the terminal title changes
    var onTitleChange: ((String) -> Void)?

    private static let logger = Logger(subsystem: "com.aizen.app", category: "GhosttyTerminal")

    // MARK: - IME State

    /// Track marked text for IME (Input Method Editor)
    private var markedText: String = ""
    private var markedTextAttributes: [NSAttributedString.Key: Any] = [
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .underlineColor: NSColor.textColor
    ]

    /// Accumulates text from insertText calls during keyDown
    /// Set to non-nil during keyDown to track if IME inserted text
    private var keyTextAccumulator: [String]?

    // MARK: - Terminal Settings from AppStorage

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalBackgroundColor") private var terminalBackgroundColor = "#1e1e2e"
    @AppStorage("terminalForegroundColor") private var terminalForegroundColor = "#cdd6f4"
    @AppStorage("terminalCursorColor") private var terminalCursorColor = "#f5e0dc"
    @AppStorage("terminalSelectionBackground") private var terminalSelectionBackground = "#585b70"
    @AppStorage("terminalPalette") private var terminalPalette = "#45475a,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#f5c2e7,#94e2d5,#a6adc8,#585b70,#f37799,#89d88b,#ebd391,#74a8fc,#f2aede,#6bd7ca,#bac2de"

    /// Observation for appearance changes
    private var appearanceObservation: NSKeyValueObservation?

    // MARK: - Initialization

    /// Create a new Ghostty terminal view
    ///
    /// - Parameters:
    ///   - frame: The initial frame for the view
    ///   - worktreePath: Working directory for the terminal session
    ///   - ghosttyApp: The shared Ghostty app instance (C pointer)
    ///   - appWrapper: The Ghostty.App wrapper for surface tracking (optional)
    init(frame: NSRect, worktreePath: String, ghosttyApp: ghostty_app_t, appWrapper: Ghostty.App? = nil) {
        self.worktreePath = worktreePath
        self.ghosttyApp = ghosttyApp
        self.ghosttyAppWrapper = appWrapper

        // Use a reasonable default size if frame is zero
        let initialFrame = frame.width > 0 && frame.height > 0 ? frame : NSRect(x: 0, y: 0, width: 800, height: 600)
        super.init(frame: initialFrame)

        setupLayer()
        setupSurface()
        setupTrackingArea()
        setupAppearanceObservation()
        setupFrameObservation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        // Surface cleanup happens via Surface's deinit
        // Note: Cannot access @MainActor properties in deinit
        // Tracking areas are automatically cleaned up by NSView
        // Appearance observation is automatically invalidated

        // Surface reference cleanup needs to happen on main actor
        // We capture the values before the Task to avoid capturing self
        let wrapper = self.ghosttyAppWrapper
        let ref = self.surfaceReference
        if let wrapper = wrapper, let ref = ref {
            Task { @MainActor in
                wrapper.unregisterSurface(ref)
            }
        }
    }

    // MARK: - Setup

    /// Configure the Metal-backed layer for terminal rendering
    ///
    /// CRITICAL: Must set layer property BEFORE setting wantsLayer = true
    /// This ensures Metal rendering works correctly
    private func setupLayer() {
        // Create Metal layer
        let metalLayer = CAMetalLayer()
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true

        // IMPORTANT: Set layer before wantsLayer for proper Metal initialization
        self.layer = metalLayer
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .duringViewResize

        Self.logger.debug("Metal layer configured")
    }

    /// Create and configure the Ghostty surface
    private func setupSurface() {
        guard let app = ghosttyApp else {
            Self.logger.error("Cannot create surface: ghostty_app_t is nil")
            return
        }

        // Configure surface with working directory
        var surfaceConfig = ghostty_surface_config_new()

        // CRITICAL: Set platform information
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()

        // Set userdata
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()

        // Set scale factor for retina displays
        surfaceConfig.scale_factor = Double(window?.backingScaleFactor ?? 2.0)

        // Set font size from Aizen settings
        surfaceConfig.font_size = Float(terminalFontSize)

        // Set working directory
        if let workingDir = strdup(worktreePath) {
            surfaceConfig.working_directory = UnsafePointer(workingDir)
        }

        // DO NOT set command - let Ghostty handle shell integration
        // Ghostty will detect shell, wrap it with proper env vars, and launch via /usr/bin/login
        surfaceConfig.command = nil

        defer {
            if let wd = surfaceConfig.working_directory {
                free(UnsafeMutableRawPointer(mutating: wd))
            }
        }

        // Create the surface
        // NOTE: subprocess spawns during ghostty_surface_new, so size warnings may appear
        // if view frame isn't set yet - this is unavoidable with current API
        guard let cSurface = ghostty_surface_new(app, &surfaceConfig) else {
            Self.logger.error("ghostty_surface_new failed")
            return
        }

        // Immediately set size after creation to minimize "small grid" warnings
        let scaledSize = convertToBacking(bounds.size.width > 0 ? bounds.size : NSSize(width: 800, height: 600))
        ghostty_surface_set_size(
            cSurface,
            UInt32(scaledSize.width),
            UInt32(scaledSize.height)
        )

        // Set content scale for retina displays
        let scale = window?.backingScaleFactor ?? 1.0
        ghostty_surface_set_content_scale(cSurface, scale, scale)

        // Wrap in Swift Surface class
        self.surface = Ghostty.Surface(cSurface: cSurface)

        // Register surface with app wrapper for config update tracking
        if let wrapper = ghosttyAppWrapper {
            self.surfaceReference = wrapper.registerSurface(cSurface)
        }

        Self.logger.info("Ghostty surface created at: \(self.worktreePath)")
    }

    /// Setup mouse tracking area for the entire view
    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .inVisibleRect,
            .activeAlways  // Track even when not focused
        ]

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    /// Setup observation for system appearance changes (light/dark mode)
    /// Setup appearance observation to track light/dark mode changes
    /// Implementation copied from Ghostty's SurfaceView_AppKit.swift
    private func setupAppearanceObservation() {
        appearanceObservation = observe(\.effectiveAppearance, options: [.new, .initial]) { view, change in
            guard let appearance = change.newValue else { return }
            guard let surface = view.surface?.unsafeCValue else { return }

            let scheme: ghostty_color_scheme_e
            switch (appearance.name) {
            case .aqua, .vibrantLight:
                scheme = GHOSTTY_COLOR_SCHEME_LIGHT

            case .darkAqua, .vibrantDark:
                scheme = GHOSTTY_COLOR_SCHEME_DARK

            default:
                scheme = GHOSTTY_COLOR_SCHEME_DARK
            }

            ghostty_surface_set_color_scheme(surface, scheme)
            Self.logger.debug("Color scheme updated to: \(scheme == GHOSTTY_COLOR_SCHEME_DARK ? "dark" : "light")")
        }
    }

    private func setupFrameObservation() {
        // Observe frame changes to resize terminal when split panes are resized
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self = self,
                  let surface = self.surface?.unsafeCValue else { return }

            let scaledSize = self.convertToBacking(self.bounds.size)
            ghostty_surface_set_size(
                surface,
                UInt32(scaledSize.width),
                UInt32(scaledSize.height)
            )
        }

        // Enable frame change notifications
        self.postsFrameChangedNotifications = true
    }

    // MARK: - NSView Overrides

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface = surface?.unsafeCValue {
            ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface = surface?.unsafeCValue {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove old tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }

        // Recreate with current bounds
        setupTrackingArea()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        guard let surface = surface?.unsafeCValue else { return }

        // Update Metal layer content scale
        if let window = window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }

        // Update surface scale factors
        let fbFrame = convertToBacking(frame)
        let xScale = fbFrame.size.width / frame.size.width
        let yScale = fbFrame.size.height / frame.size.height
        ghostty_surface_set_content_scale(surface, xScale, yScale)

        // Update surface size (framebuffer dimensions changed)
        ghostty_surface_set_size(
            surface,
            UInt32(fbFrame.size.width),
            UInt32(fbFrame.size.height)
        )
    }

    // Track last size sent to Ghostty to avoid redundant updates
    private var lastSurfaceSize: CGSize = .zero

    // Override safe area insets to use full available space, including rounded corners
    // This matches Ghostty's SurfaceScrollView implementation
    override var safeAreaInsets: NSEdgeInsets {
        return NSEdgeInsetsZero
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        // Force layout to be called to fix up subviews
        // This matches Ghostty's SurfaceScrollView.setFrameSize
        needsLayout = true
    }

    override func layout() {
        super.layout()

        // Update Metal layer frame to match view bounds
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.frame = bounds
        }

        // Update Ghostty surface size during layout pass
        // Only update if backing pixel size actually changed to prevent flicker
        guard let surface = surface?.unsafeCValue else { return }
        guard bounds.width > 0 && bounds.height > 0 else { return }

        let scaledSize = convertToBacking(bounds.size)

        // Only update if size changed by at least 1 pixel
        let widthChanged = abs(scaledSize.width - lastSurfaceSize.width) >= 1.0
        let heightChanged = abs(scaledSize.height - lastSurfaceSize.height) >= 1.0

        guard widthChanged || heightChanged else { return }

        lastSurfaceSize = scaledSize
        ghostty_surface_set_size(
            surface,
            UInt32(scaledSize.width),
            UInt32(scaledSize.height)
        )
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let surface = surface else {
            Self.logger.warning("keyDown: no surface")
            // Even without surface, call interpretKeyEvents for IME support
            interpretKeyEvents([event])
            return
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // Track if we had marked text before this event
        // Important for handling ESC and backspace during IME composition
        let markedTextBefore = !markedText.isEmpty

        // Set up key text accumulator to track insertText calls
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }

        // Call interpretKeyEvents to allow IME processing
        // This may call insertText (text committed) or setMarkedText (composing)
        interpretKeyEvents([event])

        // If we have accumulated text, it means insertText was called
        // Send the composed text to the terminal
        if let texts = keyTextAccumulator, !texts.isEmpty {
            for text in texts {
                text.withCString { ptr in
                    var keyEvent = event.ghosttyKeyEvent(action)
                    keyEvent.text = ptr
                    keyEvent.composing = false
                    ghostty_surface_key(surface.unsafeCValue, keyEvent)
                }
            }
            return
        }

        // If we're still composing (have marked text), don't send key event
        // OR if we had marked text before and pressed a key like backspace/ESC,
        // we're still in composing mode
        let isComposing = !markedText.isEmpty || markedTextBefore
        if isComposing {
            // ESC or backspace during composition shouldn't be sent to terminal
            return
        }

        // Normal key event - no IME involvement
        var keyEvent = event.ghosttyKeyEvent(action)

        // Set text field if we have printable characters
        if let chars = event.ghosttyCharacters,
           let codepoint = chars.utf8.first,
           codepoint >= 0x20 {
            chars.withCString { textPtr in
                keyEvent.text = textPtr
                keyEvent.composing = false
                surface.sendKeyEvent(Ghostty.Input.KeyEvent(cValue: keyEvent)!)
            }
        } else {
            keyEvent.text = nil
            keyEvent.composing = false
            if let inputEvent = Ghostty.Input.KeyEvent(cValue: keyEvent) {
                surface.sendKeyEvent(inputEvent)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface = surface else { return }

        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_RELEASE)
        keyEvent.text = nil

        if let inputEvent = Ghostty.Input.KeyEvent(cValue: keyEvent) {
            surface.sendKeyEvent(inputEvent)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface = surface?.unsafeCValue else { return }

        // Determine which modifier key changed
        let mods = Ghostty.ghosttyMods(event.modifierFlags)
        let mod: UInt32

        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }

        // Determine if press or release
        let action: ghostty_input_action_e = (mods.rawValue & mod != 0)
            ? GHOSTTY_ACTION_PRESS
            : GHOSTTY_ACTION_RELEASE

        // Send to Ghostty
        var keyEvent = event.ghosttyKeyEvent(action)
        keyEvent.text = nil
        ghostty_surface_key(surface, keyEvent)
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .press,
            button: .left,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .release,
            button: .left,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .press,
            button: .right,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .release,
            button: .right,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .press,
            button: .middle,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        guard let surface = surface else { return }

        let mouseEvent = Ghostty.Input.MouseButtonEvent(
            action: .release,
            button: .middle,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMouseButton(mouseEvent)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let surface = surface else { return }

        // Convert window coords to view coords
        // Ghostty expects top-left origin (y inverted from AppKit)
        let pos = convert(event.locationInWindow, from: nil)
        let mouseEvent = Ghostty.Input.MousePosEvent(
            x: pos.x,
            y: frame.height - pos.y,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMousePos(mouseEvent)
    }

    override func mouseDragged(with event: NSEvent) {
        // Mouse dragging is just mouse movement with a button held
        mouseMoved(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)

        guard let surface = surface else { return }

        // Report mouse entering the viewport
        let pos = convert(event.locationInWindow, from: nil)
        let mouseEvent = Ghostty.Input.MousePosEvent(
            x: pos.x,
            y: frame.height - pos.y,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMousePos(mouseEvent)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface = surface else { return }

        // Negative values signal cursor left viewport
        let mouseEvent = Ghostty.Input.MousePosEvent(
            x: -1,
            y: -1,
            mods: Ghostty.Input.Mods(nsFlags: event.modifierFlags)
        )
        surface.sendMousePos(mouseEvent)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface = surface else { return }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas

        if precision {
            // 2x speed multiplier for precise scrolling (trackpad)
            x *= 2
            y *= 2
        }

        let scrollEvent = Ghostty.Input.MouseScrollEvent(
            x: x,
            y: y,
            mods: Ghostty.Input.ScrollMods(
                precision: precision,
                momentum: Ghostty.Input.Momentum(event.momentumPhase)
            )
        )
        surface.sendMouseScroll(scrollEvent)
    }

    // MARK: - Process Lifecycle

    /// Check if the terminal process has exited
    var processExited: Bool {
        guard let surface = surface?.unsafeCValue else { return true }
        return ghostty_surface_process_exited(surface)
    }
}

// MARK: - NSTextInputClient Implementation

/// NSTextInputClient protocol conformance for IME (Input Method Editor) support
///
/// This enables proper input for languages like Japanese, Chinese, Korean, etc.
/// Marked text is pre-edit text shown during composition before final character selection
extension GhosttyTerminalView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = anyToString(string) else { return }

        // Clear any marked text when committing
        if !markedText.isEmpty {
            markedText = ""
            needsDisplay = true
        }

        // If we're in a keyDown event (accumulator exists), accumulate the text
        // The keyDown handler will send it to the terminal
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
            return
        }

        // Otherwise send directly to terminal (e.g., paste operation)
        surface?.sendText(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let text = anyToString(string) else { return }

        // Update marked text state
        markedText = text

        // Tell system we've handled the marked text
        inputContext?.invalidateCharacterCoordinates()
        needsDisplay = true

        Self.logger.debug("IME marked text: \(text)")
    }

    func unmarkText() {
        // Commit any pending marked text
        if !markedText.isEmpty {
            surface?.sendText(markedText)
            markedText = ""
            needsDisplay = true
        }
    }

    func selectedRange() -> NSRange {
        // Terminals don't have text selection in the traditional sense for IME
        return NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        // Return range of marked text if we have any
        if markedText.isEmpty {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.utf16.count)
    }

    func hasMarkedText() -> Bool {
        return !markedText.isEmpty
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        // Return attributed marked text for IME window
        guard !markedText.isEmpty else { return nil }

        let attributedString = NSAttributedString(
            string: markedText,
            attributes: markedTextAttributes
        )

        if actualRange != nil {
            actualRange?.pointee = NSRange(location: 0, length: markedText.utf16.count)
        }

        return attributedString
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return [
            .underlineStyle,
            .underlineColor,
            .backgroundColor,
            .foregroundColor
        ]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Get cursor position from Ghostty for IME window placement
        guard let surface = surface?.unsafeCValue else {
            return NSRect(x: frame.origin.x, y: frame.origin.y, width: 0, height: 0)
        }

        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0

        // Get IME cursor position from Ghostty
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        // Ghostty coordinates are in top-left (0, 0) origin, but AppKit expects bottom-left
        // Convert Y coordinate by subtracting from frame height
        let viewRect = NSRect(
            x: x,
            y: frame.size.height - y,
            width: range.length == 0 ? 0 : max(width, 1),
            height: max(height, 1)
        )

        // Convert to window coordinates
        let windowRect = convert(viewRect, to: nil)

        // Convert to screen coordinates
        guard let window = window else { return windowRect }
        return window.convertToScreen(windowRect)
    }

    func characterIndex(for point: NSPoint) -> Int {
        return NSNotFound
    }

    // MARK: - Helper

    private func anyToString(_ string: Any) -> String? {
        switch string {
        case let string as NSString:
            return string as String
        case let string as NSAttributedString:
            return string.string
        default:
            return nil
        }
    }
}

// MARK: - Ghostty Helpers
// Note: ghosttyMods function is defined in Ghostty.Input.swift

extension NSEvent {
    /// Create a Ghostty key event from NSEvent
    func ghosttyKeyEvent(_ action: ghostty_input_action_e) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(keyCode)
        keyEvent.mods = Ghostty.ghosttyMods(modifierFlags)
        keyEvent.consumed_mods = Ghostty.ghosttyMods(
            modifierFlags.subtracting([.control, .command])
        )

        // Unshifted codepoint for key identification
        if type == .keyDown || type == .keyUp,
           let chars = characters(byApplyingModifiers: []),
           let codepoint = chars.unicodeScalars.first {
            keyEvent.unshifted_codepoint = codepoint.value
        } else {
            keyEvent.unshifted_codepoint = 0
        }

        keyEvent.text = nil
        keyEvent.composing = false

        return keyEvent
    }

    /// Get characters appropriate for Ghostty (excluding control chars and PUA)
    var ghosttyCharacters: String? {
        guard let characters = characters else { return nil }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            // Skip control characters (Ghostty handles internally)
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }

            // Skip Private Use Area (function keys)
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }
}
