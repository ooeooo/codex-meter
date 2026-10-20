import AppKit
import SwiftUI

enum MeterPanelLayout {
    static let width: CGFloat = 348
    static let preferredHeight: CGFloat = 680
    static let compactHeight: CGFloat = 260

    static func height(maximum: CGFloat, usageExpanded: Bool, historyExpanded: Bool, settingsExpanded: Bool) -> CGFloat {
        usageExpanded || historyExpanded || settingsExpanded ? maximum : min(compactHeight, maximum)
    }

    static func presentationSize(maximum: NSSize, defaults: UserDefaults = .standard) -> NSSize {
        let usage = defaults.object(forKey: "usageWindowsExpanded") as? Bool ?? true
        let history = defaults.object(forKey: "accountUsageHistoryExpanded") as? Bool ?? true
        let settings = defaults.bool(forKey: "settingsExpanded")
        return NSSize(width: maximum.width, height: height(maximum: maximum.height,
            usageExpanded: usage, historyExpanded: history, settingsExpanded: settings))
    }

    static func size(visibleHeight: CGFloat?) -> NSSize {
        let height: CGFloat
        if let visibleHeight, visibleHeight.isFinite, visibleHeight > 0 {
            height = min(preferredHeight, max(200, visibleHeight - 80))
        } else {
            height = preferredHeight
        }
        return NSSize(width: width, height: height)
    }

    @MainActor
    static func controller(store: UsageStore, size: NSSize) -> NSHostingController<MeterView> {
        let controller = NSHostingController(rootView: MeterView(store: store, panelHeight: size.height))
        controller.sizingOptions = [.preferredContentSize]
        let presentation = presentationSize(maximum: size)
        controller.preferredContentSize = presentation
        controller.view.setFrameSize(presentation)
        return controller
    }
}

/// One scroll document fills the viewport or grows beyond it. Spare space
/// pushes settings to the bottom; overflowing content scrolls settings with it.
struct MeterPanel<Header: View, Content: View, Footer: View>: View {
    let height: CGFloat
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            Divider()
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        content.fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Divider()
                        footer.fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: viewport.size.height, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.vertical, 6)
        .frame(width: MeterPanelLayout.width, height: height)
    }
}
