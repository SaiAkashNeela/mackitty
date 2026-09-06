import AppKit
import SwiftUI

enum AppLogo {
    static let nsImage: NSImage? = {
        if let url = Bundle.module.url(forResource: "logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        return nil
    }()
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
