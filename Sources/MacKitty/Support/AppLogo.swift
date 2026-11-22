import AppKit
import SwiftUI

enum AppLogo {
    static let nsImage: NSImage? = {
        for url in [Bundle.module.url(forResource: "logo", withExtension: "png"),
                    Bundle.main.url(forResource: "logo", withExtension: "png")].compactMap({ $0 }) {
            if let image = thumbnail(at: url) { return image }
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        return nil
    }()

    /// The logo is shown at most 72pt (144px on Retina); decoding the 1024px PNG cost 4 MB.
    private static func thumbnail(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 144
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 72, height: 72))
    }
}

struct AppLogoView: View {
    var size: CGFloat = 28
    var cornerRadius: CGFloat? = nil

    var body: some View {
        if let image = AppLogo.nsImage {
            if let cornerRadius = cornerRadius {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        } else {
            Image(systemName: "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}
