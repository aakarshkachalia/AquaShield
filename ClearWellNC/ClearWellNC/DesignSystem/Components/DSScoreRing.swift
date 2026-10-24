//
//  DSScoreRing.swift
//  ClearWellNC
//
//  Water Health Score ring. Fills to the score on appear; the number and level word in the center carry
//  the meaning, the ring and its color only reinforce them.
//

import SwiftUI

extension DS {
    struct ScoreRing: View {
        let score: Int?
        let level: Level?
        var title: String = String(localized: "Water Health Score")
        /// 1 is the hero size; smaller for summary cards.
        var scale: CGFloat = 1

        @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 188
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var shownFraction: Double = 0

        private var fraction: Double { Double(min(max(score ?? 0, 0), 100)) / 100 }
        private var color: Color { level?.color ?? DS.Colors.textSecondary }
        /// Grows with text size, but never wider than a phone screen.
        private var size: CGFloat { min(diameter * scale, 300 * scale) }
        private var lineWidth: CGFloat { size * 0.085 }

        var body: some View {
            ZStack {
                Circle()
                    .stroke(DS.Colors.track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: shownFraction)
                    .stroke(AngularGradient(colors: [color.opacity(0.65), color], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(shownFraction, 0.01))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                center
                    .padding(lineWidth * 1.6)
            }
            .frame(width: size, height: size)
            .onAppear { reveal() }
            .onChange(of: fraction) { _, _ in reveal() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }

        private var center: some View {
            VStack(spacing: DS.Space.xs) {
                Text(score.map { "\($0)" } ?? "—")
                    .font(DS.Typography.score)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .contentTransition(.numericText())
                if let level {
                    Label(level.label, systemImage: level.symbol)
                        .font(DS.Typography.caption)
                        .foregroundStyle(level.color)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text("Not enough tests")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.4)   // stays inside the ring at the largest text sizes
        }

        private var accessibilityText: Text {
            guard let score else { return Text("\(title): not enough tests for a score yet") }
            if let level {
                return Text("\(title) \(score) out of 100, \(level.label)")
            }
            return Text("\(title) \(score) out of 100")
        }

        private func reveal() {
            if let animation = DS.Motion.animation(DS.Motion.reveal, reduceMotion: reduceMotion) {
                withAnimation(animation) { shownFraction = fraction }
            } else {
                shownFraction = fraction
            }
        }
    }
}

extension DS.ScoreRing {
    init(result: WellHealthScore.Result, scale: CGFloat = 1) {
        self.init(score: result.score, level: result.band.map { DS.Level($0) }, scale: scale)
    }
}

private struct ScoreRingSamples: View {
    var body: some View {
        VStack(spacing: DS.Space.xl) {
            DS.ScoreRing(score: 92, level: .excellent)
            DS.ScoreRing(score: 72, level: .fair)
            DS.ScoreRing(score: 10, level: .unsafe)
            DS.ScoreRing(score: nil, level: nil)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Light") { ScoreRingSamples().dsPreview(.light) }
#Preview("Dark") { ScoreRingSamples().dsPreview(.dark) }
#Preview("Largest text") { ScoreRingSamples().dsPreview(.largestText) }
