//
//  Modernist.swift
//  AquaShield
//
//  The "Modernist" look from the AquaShield Redesign (Claude Design, turns 4–5): a light beige ground, ink
//  type in light weights, square corners, thin rules instead of cards, and one red for "over the limit".
//  Colors are the design's OKLCH values converted to sRGB; dark mode uses the same hues on a dark ground.
//  Type uses the system font in light weights (the design's Archivo isn't bundled).
//

import SwiftUI

enum M {}

// MARK: - Color

extension M {
    enum Colors {
        static let ground = Color(light: 0xE6DDCE, dark: 0x17130E)
        static let surface = Color(light: 0xF2ECE2, dark: 0x231E19)
        static let tabBar = Color(light: 0xDFD6C8, dark: 0x130F0A)
        /// Rules between sections and cells.
        static let line = Color(light: 0xC7BCAC, dark: 0x423C35)
        /// Row separators.
        static let hairline = Color(light: 0xD3C9BB, dark: 0x342F2A)
        static let ink = Color(light: 0x201E1D, dark: 0xF1EDE6)
        static let muted = Color(light: 0x554B42, dark: 0xB3A99E)

        // Zones: low → over the limit.
        static let good = Color(light: 0x1E7546, dark: 0x60BB83)
        static let fine = Color(light: 0x6E9441, dark: 0x9EC773)
        static let watch = Color(light: 0xCD9C1F, dark: 0xEEC05B)
        static let poor = Color(light: 0xD36C00, dark: 0xF59145)
        static let over = Color(light: 0xCC291F, dark: 0xF75F4F)
        /// Red for text (darker, for contrast on beige).
        static let overText = Color(light: 0xBA0C09, dark: 0xFF7F6E)
    }
}

// MARK: - Type

extension M {
    /// System font in the design's weights; every style follows Dynamic Type.
    enum Font {
        static let screenTitle = SwiftUI.Font.system(.largeTitle, weight: .light)
        /// Step and sheet headings: one size below the screen title.
        static let heading = SwiftUI.Font.system(.title2, weight: .light)
        static let bigNumber = SwiftUI.Font.system(.title, weight: .light).monospacedDigit()
        static let number = SwiftUI.Font.system(.title2, weight: .regular).monospacedDigit()
        static let section = SwiftUI.Font.system(.subheadline, weight: .semibold)
        static let row = SwiftUI.Font.system(.subheadline, weight: .regular)
        static let value = SwiftUI.Font.system(.footnote, weight: .semibold).monospacedDigit()
        static let small = SwiftUI.Font.system(.caption, weight: .regular)
        static let tiny = SwiftUI.Font.system(.caption2, weight: .regular)
        static let label = SwiftUI.Font.system(.caption2, weight: .semibold)

        /// A big thin number that still scales (size from @ScaledMetric).
        static func thin(_ size: CGFloat) -> SwiftUI.Font {
            .system(size: size, weight: .light).monospacedDigit()
        }
    }
}

// MARK: - Zones

extension M {
    /// The four bands every reading and score is drawn in. Each has a word, so color is never alone.
    enum Zone: Int, CaseIterable, Sendable {
        case low, fine, watch, over

        /// From a reading's multiple of its limit.
        init(ratio: Double) {
            self = ratio >= 1 ? .over : ratio >= 0.5 ? .watch : ratio >= 0.2 ? .fine : .low
        }

        var color: Color {
            switch self {
            case .low: M.Colors.good
            case .fine: M.Colors.fine
            case .watch: M.Colors.watch
            case .over: M.Colors.over
            }
        }

        var textColor: Color { self == .over ? M.Colors.overText : M.Colors.ink }

        var label: String {
            switch self {
            case .low: String(localized: "Low")
            case .fine: String(localized: "Fine")
            case .watch: String(localized: "Watch")
            case .over: String(localized: "Over")
            }
        }
    }

    /// Position (0–1) on the log-scale "× of limit" track: 0.05× at the left, the limit at 65%, 5× at the right.
    static func logPosition(_ ratio: Double) -> Double {
        min(0.98, max(0.02, (log10(max(ratio, 0.0001)) + 1.301) / 2))
    }

    static let limitPosition = 0.65

    /// "1.8×", "0.15×".
    static func times(_ ratio: Double) -> String {
        ratio >= 10 ? "\(Int(ratio.rounded()))×" : ratio >= 1 ? String(format: "%.1f×", ratio) : String(format: "%.2g×", ratio)
    }

    /// Score bands on the dial: unsafe ≤40, poor ≤60, fair ≤80, good above.
    static func scoreColor(_ score: Double) -> Color {
        score <= 40 ? M.Colors.over : score <= 60 ? M.Colors.poor : score <= 80 ? M.Colors.watch : M.Colors.good
    }
}

// MARK: - Pieces

extension M {
    /// A full-width thin rule.
    struct Rule: View {
        var color: Color = M.Colors.line
        var body: some View { Rectangle().fill(color).frame(height: 1).accessibilityHidden(true) }
    }

    /// A small round status dot, always beside a word.
    struct Dot: View {
        let color: Color
        var size: CGFloat = 7
        var body: some View { Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true) }
    }

    /// Section heading with an optional right-aligned note.
    struct SectionHeader: View {
        let title: String
        var note: String?
        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(M.Font.section).foregroundStyle(M.Colors.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                if let note { Text(note).font(M.Font.tiny).foregroundStyle(M.Colors.muted) }
            }
        }
    }

    /// The four-zone gradient track with the limit tick, a dot at `ratio`, and an optional county tick.
    struct LimitTrack: View {
        let ratio: Double?
        var countyRatio: Double?
        var dotColor: Color?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var shown = false

        static let gradient = LinearGradient(stops: [
            .init(color: M.Colors.good, location: 0), .init(color: M.Colors.good, location: 0.30),
            .init(color: M.Colors.fine, location: 0.30), .init(color: M.Colors.fine, location: 0.50),
            .init(color: M.Colors.watch, location: 0.50), .init(color: M.Colors.watch, location: 0.65),
            .init(color: M.Colors.over, location: 0.65), .init(color: M.Colors.over, location: 1),
        ], startPoint: .leading, endPoint: .trailing)

        var body: some View {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    if ratio != nil {
                        Rectangle().fill(Self.gradient).frame(height: 2).opacity(0.42)
                    } else {
                        // Untested: dashed track.
                        Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: w, y: 1)) }
                            .stroke(M.Colors.line, style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
                            .frame(height: 2)
                    }
                    if let countyRatio {
                        Rectangle().fill(M.Colors.ink.opacity(0.55)).frame(width: 1, height: 12)
                            .offset(x: w * M.logPosition(countyRatio))
                    }
                    if let ratio {
                        Circle().fill(dotColor ?? Zone(ratio: ratio).color)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(M.Colors.ground, lineWidth: 2))
                            .offset(x: (shown ? w * M.logPosition(ratio) : 0) - 5)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            .onAppear {
                if reduceMotion { shown = true } else { withAnimation(.spring(duration: 1.1, bounce: 0.1)) { shown = true } }
            }
            .accessibilityHidden(true)
        }
    }

    /// The flat tab-bar-free cell used for tiles: surface fill, square corners.
    struct Cell<Content: View>: View {
        @ViewBuilder let content: Content
        var body: some View {
            content
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(M.Colors.surface)
                .foregroundStyle(M.Colors.ink)
        }
    }

    /// Square ink button ("Fix →"), flush-left label.
    struct InkButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(M.Font.value)
                .foregroundStyle(M.Colors.surface)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(M.Colors.ink.opacity(configuration.isPressed ? 0.75 : 1))
        }
    }

    /// Square outlined button ("Find lab").
    struct OutlineButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(M.Font.value)
                .foregroundStyle(M.Colors.ink)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .overlay(Rectangle().strokeBorder(M.Colors.ink, lineWidth: 1))
                .background(configuration.isPressed ? M.Colors.surface : .clear)
        }
    }

    /// Underline tabs ("Latest · History · Trends").
    struct UnderlineTabs<Tab: Hashable>: View {
        let tabs: [(Tab, String)]
        @Binding var selection: Tab

        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 22) {
                    ForEach(tabs, id: \.0) { tab, label in
                        let on = tab == selection
                        Button { withAnimation(.easeOut(duration: 0.25)) { selection = tab } } label: {
                            Text(label)
                                .font(.system(.subheadline, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? M.Colors.ink : M.Colors.muted)
                                .padding(.vertical, 10)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(on ? M.Colors.ink : .clear).frame(height: 1.5)
                                }
                                .frame(minHeight: DS.Size.tapTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    }
                    Spacer()
                }
                M.Rule()
            }
        }
    }

    /// The standard footer line.
    struct Footer: View {
        var sample: Bool = false
        var body: some View {
            Text(sample ? String(localized: "General information, not medical advice · County data is sample")
                        : String(localized: "General information, not medical advice"))
                .font(M.Font.tiny)
                .foregroundStyle(M.Colors.muted)
                .padding(.vertical, 18)
        }
    }
}

extension View {
    /// The Modernist screen: beige ground, ink text.
    func modernistScreen() -> some View {
        background(M.Colors.ground.ignoresSafeArea())
            .foregroundStyle(M.Colors.ink)
    }

    /// A Form or List on the beige ground instead of system gray. Rows set their own surface background.
    func modernistList() -> some View {
        scrollContentBackground(.hidden)
            .background(M.Colors.ground.ignoresSafeArea())
            .foregroundStyle(M.Colors.ink)
    }
}

extension M {
    /// System bars and controls in the brown theme, so no system blue or gray shows through.
    static func applyAppearance() {
        let ground = UIColor(M.Colors.ground)
        let ink = UIColor(M.Colors.ink)
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = ground
        bar.shadowColor = UIColor(M.Colors.line)
        bar.titleTextAttributes = [.foregroundColor: ink]
        bar.largeTitleTextAttributes = [.foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().tintColor = UIColor(Color.brandPrimary)

        let segments = UISegmentedControl.appearance()
        segments.backgroundColor = UIColor(M.Colors.tabBar)
        segments.selectedSegmentTintColor = UIColor(M.Colors.surface)
        segments.setTitleTextAttributes([.foregroundColor: ink], for: .normal)

        UISwitch.appearance().onTintColor = UIColor(Color.brandPrimary)
        UIPageControl.appearance().currentPageIndicatorTintColor = ink
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(M.Colors.line)
        UITableView.appearance().backgroundColor = ground
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(Color.brandPrimary)
    }
}
