//
//  SettingsManager.swift
//  SubtitleApp
//
//  Manages all persistent settings using @Observable + UserDefaults.
//  iOS 17+ Observation framework.
//

import SwiftUI
import Observation

// MARK: - Supported Languages

enum RecognitionLanguage: String, CaseIterable, Identifiable, Codable {
    case japanese = "ja-JP"
    case english  = "en-US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .japanese: "日本語"
        case .english:  "English"
        }
    }
}

// MARK: - Font Choice

enum FontChoice: String, CaseIterable, Identifiable, Codable {
    case system      = "system"
    case rounded     = "rounded"
    case serif       = "serif"       // 明朝体
    case monospaced  = "monospaced"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:     "システムフォント"
        case .rounded:    "丸ゴシック"
        case .serif:      "明朝体"
        case .monospaced: "等幅フォント"
        }
    }

    func uiFont(size: CGFloat) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: .bold)
        case .rounded:
            return .system(size: size, weight: .bold, design: .rounded)
        case .serif:
            return .system(size: size, weight: .regular, design: .serif)
        case .monospaced:
            return .system(size: size, weight: .medium, design: .monospaced)
        }
    }
}

// MARK: - Background Theme

enum BackgroundTheme: String, CaseIterable, Identifiable, Codable {
    case black      = "black"
    case darkRed    = "darkRed"
    case darkBlue   = "darkBlue"
    case darkGreen  = "darkGreen"
    case wagara     = "wagara"      // 和柄（麻の葉模様）

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .black:     "黒"
        case .darkRed:   "赤"
        case .darkBlue:  "青"
        case .darkGreen: "緑"
        case .wagara:    "和柄"
        }
    }

    /// Base background color
    var backgroundColor: Color {
        switch self {
        case .black:     Color.black
        case .darkRed:   Color(red: 0.15, green: 0.02, blue: 0.02)
        case .darkBlue:  Color(red: 0.02, green: 0.05, blue: 0.18)
        case .darkGreen: Color(red: 0.02, green: 0.12, blue: 0.05)
        case .wagara:    Color(red: 0.08, green: 0.04, blue: 0.02)
        }
    }

    /// Whether this theme uses a pattern overlay
    var hasPattern: Bool {
        self == .wagara
    }
}

// MARK: - Ripple Color Theme

enum RippleColorTheme: String, CaseIterable, Identifiable, Codable {
    case white    = "white"
    case cyan     = "cyan"
    case gold     = "gold"
    case sakura   = "sakura"    // 桜色
    case emerald  = "emerald"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white:    "白"
        case .cyan:     "水色"
        case .gold:     "金"
        case .sakura:   "桜"
        case .emerald:  "翠"
        }
    }

    /// Primary ripple ring color
    var ringColor: Color {
        switch self {
        case .white:    .white
        case .cyan:     Color(red: 0.4, green: 0.9, blue: 1.0)
        case .gold:     Color(red: 1.0, green: 0.84, blue: 0.0)
        case .sakura:   Color(red: 1.0, green: 0.6, blue: 0.7)
        case .emerald:  Color(red: 0.2, green: 1.0, blue: 0.6)
        }
    }

    /// Inner glow color
    var glowColor: Color {
        switch self {
        case .white:    .cyan
        case .cyan:     Color(red: 0.0, green: 0.5, blue: 1.0)
        case .gold:     Color(red: 1.0, green: 0.6, blue: 0.1)
        case .sakura:   Color(red: 1.0, green: 0.3, blue: 0.5)
        case .emerald:  Color(red: 0.0, green: 0.8, blue: 0.4)
        }
    }

    /// Preview swatch color (for settings UI)
    var previewColor: Color {
        ringColor
    }
}

// MARK: - Settings Manager

@Observable
final class SettingsManager {

    // Singleton for convenience — injected via @Environment in SwiftUI
    static let shared = SettingsManager()

    // ------ Persisted via UserDefaults ------

    var language: RecognitionLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    var fontChoice: FontChoice {
        didSet { UserDefaults.standard.set(fontChoice.rawValue, forKey: Keys.fontChoice) }
    }

    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Keys.fontSize) }
    }

    var textColorHex: String {
        didSet { UserDefaults.standard.set(textColorHex, forKey: Keys.textColorHex) }
    }

    /// Comma-separated specialized terms (CSV style)
    var specialTermsCSV: String {
        didSet {
            UserDefaults.standard.set(specialTermsCSV, forKey: Keys.specialTermsCSV)
        }
    }

    /// Subtitle display duration in seconds
    var subtitleDuration: Double {
        didSet { UserDefaults.standard.set(subtitleDuration, forKey: Keys.subtitleDuration) }
    }

    /// RMS threshold to trigger audio ripple (0.0 – 1.0)
    var rmsThreshold: Double {
        didSet { UserDefaults.standard.set(rmsThreshold, forKey: Keys.rmsThreshold) }
    }

    /// Background theme
    var backgroundTheme: BackgroundTheme {
        didSet { UserDefaults.standard.set(backgroundTheme.rawValue, forKey: Keys.backgroundTheme) }
    }

    /// Ripple color theme
    var rippleColorTheme: RippleColorTheme {
        didSet { UserDefaults.standard.set(rippleColorTheme.rawValue, forKey: Keys.rippleColorTheme) }
    }

    /// Whether ripple effects are enabled
    var rippleEnabled: Bool {
        didSet { UserDefaults.standard.set(rippleEnabled, forKey: Keys.rippleEnabled) }
    }

    // ------ Computed ------

    /// Parsed array of contextual strings for SFSpeechRecognizer
    var specialTerms: [String] {
        specialTermsCSV
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var subtitleFont: Font {
        fontChoice.uiFont(size: fontSize)
    }

    var textColor: Color {
        Color(hex: textColorHex) ?? .white
    }

    // ------ Init ------

    private init() {
        let defaults = UserDefaults.standard

        self.language = RecognitionLanguage(
            rawValue: defaults.string(forKey: Keys.language) ?? RecognitionLanguage.japanese.rawValue
        ) ?? .japanese

        self.fontChoice = FontChoice(
            rawValue: defaults.string(forKey: Keys.fontChoice) ?? FontChoice.system.rawValue
        ) ?? .system

        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 42.0

        self.textColorHex = defaults.string(forKey: Keys.textColorHex) ?? "#FFFFFF"

        self.specialTermsCSV = defaults.string(forKey: Keys.specialTermsCSV) ?? ""

        self.subtitleDuration = defaults.object(forKey: Keys.subtitleDuration) as? Double ?? 5.0

        self.rmsThreshold = defaults.object(forKey: Keys.rmsThreshold) as? Double ?? 0.05

        self.backgroundTheme = BackgroundTheme(
            rawValue: defaults.string(forKey: Keys.backgroundTheme) ?? BackgroundTheme.black.rawValue
        ) ?? .black

        self.rippleColorTheme = RippleColorTheme(
            rawValue: defaults.string(forKey: Keys.rippleColorTheme) ?? RippleColorTheme.white.rawValue
        ) ?? .white

        self.rippleEnabled = defaults.object(forKey: Keys.rippleEnabled) == nil
            ? true
            : defaults.bool(forKey: Keys.rippleEnabled)
    }

    // ------ Keys ------

    private enum Keys {
        static let language         = "settings.language"
        static let fontChoice       = "settings.fontChoice"
        static let fontSize         = "settings.fontSize"
        static let textColorHex     = "settings.textColorHex"
        static let specialTermsCSV  = "settings.specialTermsCSV"
        static let subtitleDuration = "settings.subtitleDuration"
        static let rmsThreshold     = "settings.rmsThreshold"
        static let backgroundTheme  = "settings.backgroundTheme"
        static let rippleColorTheme = "settings.rippleColorTheme"
        static let rippleEnabled    = "settings.rippleEnabled"
    }
}

// MARK: - Color hex helper

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
