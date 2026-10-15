import AppKit

// The supplied artwork is split into 1x/2x template images. AppKit supplies the
// menu bar's foreground color while the background remains transparent.
enum StatusBarIcon: CaseIterable {
    case normal, speaking, mouse

    var label: String {
        switch self {
        case .normal: return L("遥控语音")
        case .speaking: return L("遥控语音 · 语音中")
        case .mouse: return L("遥控语音 · 鼠标")
        }
    }

    private static let images: [StatusBarIcon: NSImage] = Dictionary(uniqueKeysWithValues: allCases.map { state in
        let image = NSImage(named: NSImage.Name(state.assetName)) ??
            NSImage(systemSymbolName: state.fallbackSymbol, accessibilityDescription: state.label) ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = state.label
        return (state, image)
    })
    var image: NSImage { Self.images[self]! }

    var assetName: String {
        switch self {
        case .normal: return "StatusBarNormalTemplate"
        case .speaking: return "StatusBarSpeakingTemplate"
        case .mouse: return "StatusBarMouseTemplate"
        }
    }
    private var fallbackSymbol: String {
        switch self {
        case .normal: return "mic"
        case .speaking: return "waveform"
        case .mouse: return "computermouse"
        }
    }
}
