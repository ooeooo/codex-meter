import AppKit
import SwiftUI

enum MeterPanelLayout {
    static let width: CGFloat = 348
    static let preferredHeight: CGFloat = 680

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
        controller.preferredContentSize = size
        controller.view.setFrameSize(size)
        return controller
    }
}

/// The viewport owns its size. Its document can grow without resizing the
/// viewport, including before the first layout or after expanding daily rows.
struct MeterPanel<Header: View, Content: View>: View {
    let height: CGFloat
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.vertical, 6)
        .frame(width: MeterPanelLayout.width, height: height)
    }
}
