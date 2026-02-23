//
//  SettingsView.swift
//  SubtitleApp
//
//  Settings screen presented as a modal sheet.
//  Controls language, font, size, color, background theme,
//  ripple color, subtitle duration, RMS threshold,
//  and specialized term registration (CSV).
//

import SwiftUI

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    let settings = SettingsManager.shared

    // Local editing state for the CSV text area
    @State private var termsText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // ──── Language ────
                Section("認識言語 / Language") {
                    Picker("言語", selection: Binding(
                        get: { settings.language },
                        set: { settings.language = $0 }
                    )) {
                        ForEach(RecognitionLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // ──── Font ────
                Section("フォント / Font") {
                    Picker("書体", selection: Binding(
                        get: { settings.fontChoice },
                        set: { settings.fontChoice = $0 }
                    )) {
                        ForEach(FontChoice.allCases) { font in
                            Text(font.displayName).tag(font)
                        }
                    }
                }

                // ──── Font Size ────
                Section("文字サイズ / Font Size") {
                    VStack(alignment: .leading) {
                        Text("\(Int(settings.fontSize)) pt")
                            .font(.headline)
                            .monospacedDigit()

                        Slider(
                            value: Binding(
                                get: { settings.fontSize },
                                set: { settings.fontSize = $0 }
                            ),
                            in: 20...120,
                            step: 2
                        )
                    }

                    // Preview
                    Text("プレビュー / Preview")
                        .font(settings.subtitleFont)
                        .foregroundStyle(settings.textColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(settings.backgroundTheme.backgroundColor.cornerRadius(8))
                }

                // ──── Text Color ────
                Section("文字色 / Text Color") {
                    HStack {
                        colorButton("#FFFFFF", label: "白")
                        colorButton("#FFD700", label: "金")
                        colorButton("#00FF88", label: "緑")
                        colorButton("#00BFFF", label: "青")
                        colorButton("#FF6B6B", label: "赤")
                    }
                }

                // ──── Background Theme ────
                Section("背景 / Background") {
                    HStack {
                        ForEach(BackgroundTheme.allCases) { theme in
                            themeButton(theme)
                        }
                    }
                }

                // ──── Ripple Color ────
                Section("波紋の色 / Ripple Color") {
                    HStack {
                        ForEach(RippleColorTheme.allCases) { ripple in
                            rippleButton(ripple)
                        }
                    }
                }

                // ──── Subtitle Duration ────
                Section("字幕表示時間 / Duration") {
                    VStack(alignment: .leading) {
                        Text("\(String(format: "%.1f", settings.subtitleDuration)) 秒")
                            .font(.headline)
                            .monospacedDigit()

                        Slider(
                            value: Binding(
                                get: { settings.subtitleDuration },
                                set: { settings.subtitleDuration = $0 }
                            ),
                            in: 2...15,
                            step: 0.5
                        )
                    }
                }

                // ──── Sound Ripple ────
                Section("音波紋 / Sound Ripple") {
                    Toggle("波紋エフェクト", isOn: Binding(
                        get: { settings.rippleEnabled },
                        set: { settings.rippleEnabled = $0 }
                    ))

                    VStack(spacing: 8) {
                        HStack {
                            Text("敏感")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Slider(
                                value: Binding(
                                    get: { settings.rmsThreshold },
                                    set: { settings.rmsThreshold = $0 }
                                ),
                                in: 0.01...0.3,
                                step: 0.005
                            )

                            Text("鈍感")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("音に反応して波紋が発生します")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(!settings.rippleEnabled)
                    .opacity(settings.rippleEnabled ? 1.0 : 0.4)
                }

                // ──── Specialized Terms (CSV) ────
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("カンマ区切りまたは改行区切りで入力してください。\n音声認識の精度が向上します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $termsText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        HStack {
                            Text("\(parsedTermCount) 語登録中")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("保存") {
                                settings.specialTermsCSV = termsText
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text("専門用語登録 / Custom Terms (CSV)")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                termsText = settings.specialTermsCSV
            }
        }
    }

    // MARK: - Helpers

    private var parsedTermCount: Int {
        termsText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .count
    }

    @ViewBuilder
    private func colorButton(_ hex: String, label: String) -> some View {
        let isSelected = settings.textColorHex.uppercased() == hex.uppercased()

        Button {
            settings.textColorHex = hex
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: hex) ?? .white)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                    )
                Text(label)
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func themeButton(_ theme: BackgroundTheme) -> some View {
        let isSelected = settings.backgroundTheme == theme

        Button {
            settings.backgroundTheme = theme
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.backgroundColor)
                        .frame(width: 40, height: 32)

                    // Wagara pattern preview
                    if theme.hasPattern {
                        wagaraPreview()
                            .frame(width: 40, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                )

                Text(theme.displayName)
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rippleButton(_ ripple: RippleColorTheme) -> some View {
        let isSelected = settings.rippleColorTheme == ripple

        Button {
            settings.rippleColorTheme = ripple
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 32, height: 32)

                    // Ripple ring preview
                    Circle()
                        .stroke(ripple.ringColor, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(ripple.glowColor.opacity(0.5), lineWidth: 4)
                        .frame(width: 16, height: 16)
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )

                Text(ripple.displayName)
                    .font(.caption2)
            }
        }
        .buttonStyle(.plain)
    }

    /// Mini wagara (asanoha) pattern for theme preview
    @ViewBuilder
    private func wagaraPreview() -> some View {
        Canvas { context, size in
            let step: CGFloat = 10
            let color = Color(red: 0.25, green: 0.15, blue: 0.08)
            for x in stride(from: 0, through: size.width, by: step) {
                for y in stride(from: 0, through: size.height, by: step) {
                    // Simple diamond pattern
                    let path = Path { p in
                        p.move(to: CGPoint(x: x + step / 2, y: y))
                        p.addLine(to: CGPoint(x: x + step, y: y + step / 2))
                        p.addLine(to: CGPoint(x: x + step / 2, y: y + step))
                        p.addLine(to: CGPoint(x: x, y: y + step / 2))
                        p.closeSubpath()
                    }
                    context.stroke(path, with: .color(color), lineWidth: 0.5)
                }
            }
        }
    }
}
