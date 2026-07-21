//  ShareCardRenderer.swift
//  A small, reusable on-device renderer that turns any SwiftUI view into a
//  `UIImage` at a fixed size, for share-sheet cards (plan U4 / KTD-4). Wraps
//  SwiftUI's `ImageRenderer` (iOS 16+, no new dependency -- this app targets
//  iOS 18). Fails soft everywhere: no force unwraps, never crashes -- a
//  broken render just returns nil so callers can no-op the share action.

import SwiftUI

#if os(iOS)
import UIKit

/// Renders SwiftUI views to `UIImage`s for sharing. Stateless -- every call
/// is independent, so this is safe to use as a static utility or a value type.
public enum ShareCardRenderer {
    /// Renders `content` at a fixed `size` into a `UIImage`.
    ///
    /// - Parameters:
    ///   - content: The view to render. It is proposed exactly `size`, so the
    ///     view should be built to fill (or be `.frame`-pinned to) that size.
    ///   - size: The fixed pixel-point size of the output image. Must be
    ///     positive in both dimensions or this returns `nil`.
    ///   - scale: The render scale (defaults to the main screen's scale so
    ///     the output looks crisp on the current device).
    /// - Returns: The rendered `UIImage`, or `nil` if rendering failed for
    ///   any reason (invalid size, `ImageRenderer` producing no image, etc).
    ///   This never crashes or force-unwraps.
    @MainActor
    public static func render<Content: View>(
        _ content: Content,
        size: CGSize,
        scale: CGFloat = UIScreen.main.scale
    ) -> UIImage? {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else {
            return nil
        }

        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.isOpaque = false

        return renderer.uiImage
    }
}

/// A thin `UIViewControllerRepresentable` wrapper around `UIActivityViewController`
/// so a rendered share-card image can go through the system share sheet from
/// a SwiftUI `.sheet(item:)`. Kept here alongside the renderer since the two
/// are always used together.
public struct ActivityShareSheet: UIViewControllerRepresentable {
    public let items: [Any]

    public init(items: [Any]) {
        self.items = items
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
