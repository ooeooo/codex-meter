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
        XCTAssertGreaterThan(scroll.contentSize.height, 300)
        XCTAssertGreaterThan(document.frame.height, 1_000)
        XCTAssertLessThan(scroll.contentSize.height, size.height)
        document.scroll(NSPoint(x: 0, y: document.frame.height))
        XCTAssertGreaterThan(scroll.documentVisibleRect.minY, 0, "Account totals must be reachable by scrolling")
        XCTAssertEqual(controller.view.bounds.height, size.height, accuracy: 2)
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
