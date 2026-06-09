import AppKit
import SwiftUI

enum FloatingTokenPanelMetrics {
    static let baseSize = NSSize(width: 201, height: 68)
    static let baseCornerRadius: CGFloat = 14
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 7
    static let defaultScale = 1.0
    static let scaleRange = 0.75...2.0

    static func clampedScale(_ scale: Double) -> CGFloat {
        CGFloat(min(max(scale, scaleRange.lowerBound), scaleRange.upperBound))
    }

    static func size(scale: Double) -> NSSize {
        let clamped = clampedScale(scale)
        return NSSize(width: baseSize.width * clamped, height: baseSize.height * clamped)
    }

    static func cornerRadius(scale: Double) -> CGFloat {
        baseCornerRadius * clampedScale(scale)
    }
}

@MainActor
final class FloatingTokenPanelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isPresented = false

    private var panel: NSPanel?
    private var onClose: (() -> Void)?

    func show(store: CodexUsageStore, monitor: LiveRateMonitor, quota: AccountQuotaStore, scale: Double, onClose: @escaping () -> Void) {
        self.onClose = onClose

        if panel == nil {
            let hostingController = NSHostingController(
                rootView: FloatingTokenPanelView(store: store, monitor: monitor, quota: quota) { [weak self] in
                    self?.onClose?()
                }
            )
            let initialSize = FloatingTokenPanelMetrics.size(scale: scale)
            hostingController.view.frame = NSRect(origin: .zero, size: initialSize)
            hostingController.view.autoresizingMask = [.width, .height]

            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hostingController
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.delegate = self
            panel.contentView?.wantsLayer = true
            panel.contentView?.layer?.cornerRadius = FloatingTokenPanelMetrics.cornerRadius(scale: scale)
            panel.contentView?.layer?.cornerCurve = .continuous
            panel.contentView?.layer?.masksToBounds = true
            position(panel)
            self.panel = panel
        }

        updateSize(scale: scale)
        panel?.orderFrontRegardless()
        isPresented = true
    }

    func updateSize(scale: Double) {
        guard let panel else { return }
        resizePanel(panel, scale: scale)
        panel.contentView?.layer?.cornerRadius = FloatingTokenPanelMetrics.cornerRadius(scale: scale)
    }

    func close() {
        panel?.orderOut(nil)
        isPresented = false
    }

    func windowWillClose(_ notification: Notification) {
        isPresented = false
    }

    private func position(_ panel: NSPanel) {
        let anchorWindow = NSApp.windows.first {
            $0 !== panel && $0.isVisible && !($0 is NSPanel)
        }
        let screenFrame = anchorWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let screenFrame else {
            panel.center()
            return
        }

        let margin: CGFloat = 22
        let topInset: CGFloat = 210
        let anchorFrame = anchorWindow?.frame ?? screenFrame
        let origin = NSPoint(
            x: min(anchorFrame.minX + margin, screenFrame.maxX - panel.frame.width - margin),
            y: min(anchorFrame.maxY - panel.frame.height - topInset, screenFrame.maxY - panel.frame.height - topInset)
        )
        panel.setFrameOrigin(NSPoint(x: max(screenFrame.minX + margin, origin.x), y: max(screenFrame.minY + margin, origin.y)))
    }
}

struct FloatingTokenPanelView: View {
    @ObservedObject var store: CodexUsageStore
    @ObservedObject var monitor: LiveRateMonitor
    @ObservedObject var quota: AccountQuotaStore
    @AppStorage("floatingPanelOpacity") private var floatingPanelOpacity = 0.88
    @AppStorage("floatingPanelScale") private var floatingPanelScale = FloatingTokenPanelMetrics.defaultScale
    let onClose: () -> Void

    var body: some View {
        let scale = FloatingTokenPanelMetrics.clampedScale(floatingPanelScale)
        let size = FloatingTokenPanelMetrics.size(scale: floatingPanelScale)
        let cornerRadius = FloatingTokenPanelMetrics.cornerRadius(scale: floatingPanelScale)

        return ZStack {
            TokenGlassBackground(opacity: floatingPanelOpacity, cornerRadius: cornerRadius)
            TokenDisplayCard(snapshot: TokenDisplaySnapshot.make(store: store, monitor: monitor, quota: quota), onClose: onClose)
                .environment(\.tokenDisplayScale, scale)
                .padding(.horizontal, FloatingTokenPanelMetrics.horizontalPadding * scale)
                .padding(.vertical, FloatingTokenPanelMetrics.verticalPadding * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(FloatingPanelSizeSync(scale: floatingPanelScale))
    }
}

@MainActor
private func resizePanel(_ panel: NSPanel, scale: Double) {
    let previousFrame = panel.frame
    let topLeft = NSPoint(x: previousFrame.minX, y: previousFrame.maxY)
    let targetSize = FloatingTokenPanelMetrics.size(scale: scale)
    let targetFrame = anchoredPanelFrame(for: panel, size: targetSize, topLeft: topLeft)
    panel.contentViewController?.view.frame = NSRect(origin: .zero, size: targetSize)
    panel.contentMinSize = targetSize
    panel.contentMaxSize = targetSize
    panel.setFrame(targetFrame, display: true, animate: false)
}

@MainActor
private func anchoredPanelFrame(for panel: NSPanel, size: NSSize, topLeft: NSPoint) -> NSRect {
    let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    var origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)

    if let screenFrame {
        let margin: CGFloat = 8
        origin.x = min(max(origin.x, screenFrame.minX + margin), screenFrame.maxX - size.width - margin)
        origin.y = min(max(origin.y, screenFrame.minY + margin), screenFrame.maxY - size.height - margin)
    }

    return NSRect(origin: origin, size: size)
}

private struct FloatingPanelSizeSync: NSViewRepresentable {
    let scale: Double

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            guard let panel = nsView.window as? NSPanel else { return }
            resizePanel(panel, scale: scale)
            panel.contentView?.layer?.cornerRadius = FloatingTokenPanelMetrics.cornerRadius(scale: scale)
        }
    }
}
