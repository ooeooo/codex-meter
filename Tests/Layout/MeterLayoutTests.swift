import AppKit
import SwiftUI
import XCTest
@testable import CodexMeter

final class MeterLayoutTests: XCTestCase {
    func testPanelFitsCommonScreenHeights() {
        for visibleHeight: CGFloat in [600, 768, 900, 1080, 1440] {
            let size = MeterPanelLayout.size(visibleHeight: visibleHeight)
            XCTAssertEqual(size.width, 348)
            XCTAssertGreaterThanOrEqual(size.height, 400)
            XCTAssertLessThanOrEqual(size.height, visibleHeight - 80)
            XCTAssertLessThanOrEqual(size.height, 680)
        }
        for invalid: CGFloat? in [nil, 0, -.infinity, .nan] {
            XCTAssertEqual(MeterPanelLayout.size(visibleHeight: invalid).height, 680)
        }
    }

    @MainActor
    func testRealPopoverShowsBodyOnFirstOpenAndReopen() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: "usageWindowsExpanded")
        defaults.set(true, forKey: "usageWindowsExpanded")
        defer {
            if let saved { defaults.set(saved, forKey: "usageWindowsExpanded") }
            else { defaults.removeObject(forKey: "usageWindowsExpanded") }
        }

        let screen = try XCTUnwrap(NSScreen.main, "A WindowServer is required for the macOS layout check")
        let anchor = NSWindow(
            contentRect: NSRect(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.maxY - 30, width: 80, height: 20),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        anchor.isReleasedWhenClosed = false
        anchor.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
        anchor.orderFrontRegardless()
        defer { anchor.close() }

        // Cover cold startup with no quota, populated quota/chart and a smaller
        // viewport, before and after closing and reopening the real popover.
        for preview in [false, true] {
            let store = UsageStore(previewMode: preview)
            let size = MeterPanelLayout.size(visibleHeight: min(600, screen.visibleFrame.height))
            let controller = MeterPanelLayout.controller(store: store, size: size)
            let popover = NSPopover()
            popover.animates = false
            popover.behavior = .applicationDefined
            popover.contentViewController = controller
            popover.contentSize = size
            defer { popover.close() }
            for _ in 0..<2 {
                let view = try XCTUnwrap(anchor.contentView)
                popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
                try await Task.sleep(for: .milliseconds(250))
                controller.view.layoutSubtreeIfNeeded()
                XCTAssertTrue(popover.isShown)
                XCTAssertEqual(popover.contentSize.height, size.height, accuracy: 2)
                XCTAssertGreaterThan(controller.view.bounds.height, 300)
                let scroll = try XCTUnwrap(findScrollView(in: controller.view))
                XCTAssertGreaterThan(scroll.contentSize.height, 200, "The body must not collapse to a header-only popover")
                XCTAssertGreaterThan(try XCTUnwrap(scroll.documentView).frame.height, 180)
                popover.close()
            }
        }
    }

    @MainActor
    func testExpandedDocumentScrollsWithoutShrinkingViewport() async throws {
        _ = NSApplication.shared
        let size = NSSize(width: 348, height: 480)
        let panel = MeterPanel(height: size.height) {
            Text("Codex Meter").padding(16)
        } content: {
            // Daily details and settings can be much taller than the screen.
            VStack {
                ForEach(0..<40) { index in
                    Text("Daily record \(index)").frame(height: 30)
                }
                Text("Account totals").frame(height: 80)
            }
        } footer: {
            FooterProbe().frame(height: 44)
        }
        let controller = NSHostingController(rootView: panel)
        controller.view.setFrameSize(size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        controller.view.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(findScrollView(in: controller.view))
        let document = try XCTUnwrap(scroll.documentView)
        let footer = try XCTUnwrap(findFooter(in: controller.view))
        let footerFrame = controller.view.convert(footer.bounds, from: footer)
        XCTAssertGreaterThan(scroll.contentSize.height, 300)
        XCTAssertGreaterThan(document.frame.height, 1_000)
        XCTAssertLessThan(scroll.contentSize.height, size.height)
        document.scroll(NSPoint(x: 0, y: document.frame.height))
        XCTAssertGreaterThan(scroll.documentVisibleRect.minY, 0, "Account totals must be reachable by scrolling")
        XCTAssertEqual(controller.view.bounds.height, size.height, accuracy: 2)
        XCTAssertEqual(controller.view.convert(footer.bounds, from: footer), footerFrame, "Settings must stay pinned while daily rows scroll")
        assertFooterAtBottom(footerFrame, in: controller.view)
    }

    @MainActor
    func testShortContentKeepsSettingsAtBottom() async throws {
        _ = NSApplication.shared
        let panel = MeterPanel(height: 480) {
            Text("Codex Meter").frame(height: 50)
        } content: {
            Text("Collapsed usage windows and history").frame(height: 80)
        } footer: {
            FooterProbe().frame(height: 44)
        }
        let controller = NSHostingController(rootView: panel)
        controller.view.setFrameSize(NSSize(width: 348, height: 480))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        controller.view.layoutSubtreeIfNeeded()
        let footer = try XCTUnwrap(findFooter(in: controller.view))
        assertFooterAtBottom(controller.view.convert(footer.bounds, from: footer), in: controller.view)
    }

    @MainActor
    func testPopoverResizesFromExpansionStateWithoutHeightFeedback() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let keys = ["usageWindowsExpanded", "accountUsageHistoryExpanded", "settingsExpanded"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: keys[0])
        defaults.set(true, forKey: keys[1])
        defaults.set(false, forKey: keys[2])
        let screen = try XCTUnwrap(NSScreen.main)
        let anchor = NSWindow(contentRect: NSRect(x: screen.visibleFrame.minX + 100,
            y: screen.visibleFrame.maxY - 30, width: 80, height: 20), styleMask: .borderless, backing: .buffered, defer: false)
        anchor.isReleasedWhenClosed = false
        anchor.orderFrontRegardless()
        defer { anchor.close() }
        let size = MeterPanelLayout.size(visibleHeight: min(600, screen.visibleFrame.height))
        let controller = MeterPanelLayout.controller(store: UsageStore(previewMode: true), size: size)
        let popover = NSPopover()
        popover.animates = false
        popover.contentViewController = controller
        popover.contentSize = size
        let view = try XCTUnwrap(anchor.contentView)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        defer { popover.close() }
        try await Task.sleep(for: .milliseconds(250))
        defaults.set(false, forKey: keys[0])
        defaults.set(false, forKey: keys[1])
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(popover.contentSize.height, MeterPanelLayout.compactHeight, accuracy: 2)
        XCTAssertGreaterThan(try XCTUnwrap(findScrollView(in: controller.view)).contentSize.height, 70)
        defaults.set(true, forKey: keys[2])
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(popover.contentSize.height, size.height, accuracy: 2)
        XCTAssertGreaterThan(try XCTUnwrap(findScrollView(in: controller.view)).contentSize.height, 100)
    }

    @MainActor
    private func assertFooterAtBottom(_ frame: NSRect, in view: NSView) {
        let inset = view.isFlipped ? view.bounds.maxY - frame.maxY : frame.minY - view.bounds.minY
        XCTAssertEqual(inset, 6, accuracy: 2)
    }

    @MainActor
    private func findFooter(in view: NSView) -> NSView? {
        if view.identifier?.rawValue == "pinned-settings" { return view }
        for child in view.subviews {
            if let footer = findFooter(in: child) { return footer }
        }
        return nil
    }

    @MainActor
    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let scroll = findScrollView(in: child) { return scroll }
        }
        return nil
    }
}

private struct FooterProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier("pinned-settings")
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
