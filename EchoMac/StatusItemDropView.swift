import AppKit

struct DroppedSocialLink {
    let url: URL
    let tab: SocialTab

    static func read(from pasteboard: NSPasteboard) -> Self? {
        for item in pasteboard.pasteboardItems ?? [] {
            guard let text = item.string(forType: .URL) ?? item.string(forType: .string),
                  let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines), encodingInvalidCharacters: false),
                  let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
                  case .openInApp(let mapped, let tab) = IncomingURLRouter.route(url) else { continue }
            return Self(url: mapped, tab: tab)
        }
        return nil
    }
}

// A transparent drag destination keeps the native status button responsible
// for clicks, its context menu, accessibility, and menu-bar rearrangement.
final class StatusItemDropView: NSView {
    private weak var button: NSStatusBarButton?
    private let onOpen: (DroppedSocialLink) -> Void

    init(button: NSStatusBarButton, onOpen: @escaping (DroppedSocialLink) -> Void) {
        self.button = button
        self.onOpen = onOpen
        super.init(frame: button.bounds)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(false)
        registerForDraggedTypes([.URL, .string])
    }

    required init?(coder: NSCoder) { fatalError("StatusItemDropView is created programmatically") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { updateFeedback(sender) }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { updateFeedback(sender) }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) { button?.highlight(false) }

    override func draggingEnded(_ sender: any NSDraggingInfo) { button?.highlight(false) }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { !operation(for: sender).isEmpty }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        button?.highlight(false)
        guard !operation(for: sender).isEmpty, let link = DroppedSocialLink.read(from: sender.draggingPasteboard) else { return false }
        onOpen(link)
        return true
    }

    private func updateFeedback(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = operation(for: sender)
        button?.highlight(!operation.isEmpty)
        if !operation.isEmpty { sender.numberOfValidItemsForDrop = 1 }
        return operation
    }

    private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
        guard DroppedSocialLink.read(from: sender.draggingPasteboard) != nil else { return [] }
        if sender.draggingSourceOperationMask.contains(.copy) { return .copy }
        if sender.draggingSourceOperationMask.contains(.link) { return .link }
        return []
    }
}
