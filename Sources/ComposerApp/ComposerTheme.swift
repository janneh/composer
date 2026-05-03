import AppKit
import SwiftUI

enum ComposerTheme {
    static let canvas = Color.dynamicComposerColor(light: 0xFFFFFF, dark: 0x101012)
    static let windowChrome = Color.dynamicComposerColor(light: 0xFFFFFF, dark: 0x202024)
    static let sidebarBackground = Color.dynamicComposerColor(light: 0xF4F4F6, dark: 0x19191C)
    static let panelBackground = Color.dynamicComposerColor(light: 0xFFFFFF, dark: 0x202024)
    static let raisedPanelBackground = Color.dynamicComposerColor(light: 0xFBFBFC, dark: 0x242428)
    static let subtlePanelBackground = Color.dynamicComposerColor(light: 0xF5F5F6, dark: 0x2A2A2E)
    static let border = Color.dynamicComposerColor(light: 0xE7E7EA, dark: 0x34343A)
    static let strongBorder = Color.dynamicComposerColor(light: 0xD9D9DE, dark: 0x45454C)
    static let mutedText = Color.dynamicComposerColor(light: 0x898A90, dark: 0xA5A6AD)
    static let quietText = Color.dynamicComposerColor(light: 0xB0B1B6, dark: 0x73747B)
    static let accent = Color.dynamicComposerColor(light: 0x2487FF, dark: 0x5EA2FF)
    static let sendButton = Color.dynamicComposerColor(light: 0x8D8F94, dark: 0x6E7077)

    static let titleFont = Font.system(size: 28, weight: .medium)
    static let sectionFont = Font.system(size: 13, weight: .regular)
    static let bodyFont = Font.system(size: 14, weight: .regular)
    static let smallFont = Font.system(size: 12, weight: .regular)
    static let labelFont = Font.system(size: 12, weight: .medium)
    static let chipFont = Font.system(size: 13, weight: .regular)

    static let smallRadius: CGFloat = 6
    static let cardRadius: CGFloat = 8
    static let panelRadius: CGFloat = 8
}

enum ComposerLayout {
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarIdealWidth: CGFloat = 260
    static let sidebarMaxWidth: CGFloat = 300
    static let windowMinWidth: CGFloat = 920
    static let windowMinHeight: CGFloat = 620
    static let compactWorkspaceWidth: CGFloat = 900
    static let inspectorWidth: CGFloat = 360
    static let boardMinWidth: CGFloat = 560
    static let boardColumnWidth: CGFloat = 276
    static let boardMinHeight: CGFloat = 160
    static let workspaceHorizontalPadding: CGFloat = 28
    static let workspaceTopPadding: CGFloat = 22
    static let workspaceBottomPadding: CGFloat = 26
    static let panelSpacing: CGFloat = 22
    static let columnSpacing: CGFloat = 14
    static let inspectorSpacing: CGFloat = 18
}

struct ComposerMaterialBackground: View {
    var tint: Color
    var tintOpacity: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            tint
                .opacity(tintOpacity)
        }
        .ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder
    func composerWindowMaterial() -> some View {
        if #available(macOS 15.0, *) {
            self.containerBackground(.regularMaterial, for: .window)
        } else {
            self
        }
    }
}

extension Color {
    static func dynamicComposerColor(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            return NSColor(hex: bestMatch == .darkAqua ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
