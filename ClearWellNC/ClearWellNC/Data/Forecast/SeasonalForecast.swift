//
//  SeasonalForecast.swift
//  ClearWellNC
//
//  Self-contained seasonal trend + forecast model. Pure functions, no UI or SwiftData,
//  so it can be unit-tested on synthetic data.
//

import Foundation

nonisolated enum SeasonalForecast {
    // MARK: Parameters

    /// Preferred moving-average window, in monthly points.
    static let preferredWindow = 20
    /// Uncertainty band: ± this many standard deviations of historical residuals.
    static let bandSDs = 1.5
    static let horizonMonths = 12
    /// Never fit a model to fewer points than this.
    static let minimumPoints = 3

    // MARK: Types

    struct Point: Sendable, Hashable {
        let year: Int
        /// 1–12
        let month: Int
        let value: Double

        /// Months since year 0, for ordering and spacing.
        var index: Int { year * 12 + (month - 1) }

        var date: Date {
            Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 15)) ?? .distantPast
        }

        init(year: Int, month: Int, value: Double) {
            self.year = year
            self.month = month
            self.value = value
        }

        init(index: Int, value: Double) {
            self.year = index / 12
            self.month = index % 12 + 1
            self.value = value
        }
    }

    struct ForecastPoint: Sendable, Hashable {
        let point: Point
        let lower: Double
        let upper: Double
        var date: Date { point.date }
        var value: Double { point.value }
    }

    struct Result: Sendable {
        let history: [Point]
        /// Seasonal deviation from the annual average, index 0 = January. Sums to ~0 across observed months.
        let seasonal: [Double]
        /// Trailing moving average of the deseasonalized series, aligned with `history`.
        let movingAverage: [Point]
        let window: Int
        /// True when the full preferred window (20) was used; false means "largest available".
        var usedPreferredWindow: Bool { window == SeasonalForecast.preferredWindow }
        let residualSD: Double
        /// Monthly trend slope used for extrapolation (units per month).
        let slope: Double
        let forecast: [ForecastPoint]

        /// Calendar month (1–12) with the highest seasonal component.
        var peakMonth: Int { (seasonal.indices.max { seasonal[$0] < seasonal[$1] } ?? 0) + 1 }
        var troughMonth: Int { (seasonal.indices.min { seasonal[$0] < seasonal[$1] } ?? 0) + 1 }
        var amplitude: Double { (seasonal.max() ?? 0) - (seasonal.min() ?? 0) }
        var meanLevel: Double { history.map(\.value).reduce(0, +) / Double(max(history.count, 1)) }
    }

    // MARK: Fit

    /// Fits the model. Returns nil for fewer than `minimumPoints` points.
    ///
    /// 1. **Seasonal profile:** for each year, subtract that year's mean; average the deviations by
    ///    calendar month; center so observed months sum to zero.
    /// 2. **Trend:** trailing moving average of the *deseasonalized* series. Window = 20 points when at
    ///    least 20 are available, otherwise all points (labeled in the UI). Early points use as many
    ///    points as exist (expanding window) so every point has a trend value.
    /// 3. **Residuals:** observed − (trend + seasonal); their sample SD sets the ±1.5 SD band.
    /// 4. **Forecast:** last trend value + least-squares slope of the last ≤12 trend values × h,
    ///    plus the seasonal component for that month. Concentrations are clamped at zero.
    static func fit(_ input: [Point]) -> Result? {
        // Sort and keep one value per month (last wins).
        var byIndex: [Int: Point] = [:]
        for p in input { byIndex[p.index] = p }
        let history = byIndex.values.sorted { $0.index < $1.index }
        guard history.count >= minimumPoints else { return nil }

        let seasonal = seasonalProfile(history)
        let deseasonalized = history.map { $0.value - seasonal[$0.month - 1] }

        let window = history.count >= preferredWindow ? preferredWindow : history.count
        var trend: [Double] = []
        for i in deseasonalized.indices {
            let start = max(0, i - window + 1)
            let slice = deseasonalized[start...i]
            trend.append(slice.reduce(0, +) / Double(slice.count))
        }
        let movingAverage = zip(history, trend).map { Point(index: $0.0.index, value: $0.1) }

        let residuals = history.indices.map { history[$0].value - (trend[$0] + seasonal[history[$0].month - 1]) }
        let residualSD = sampleSD(residuals)

        let slope = trendSlope(Array(movingAverage.suffix(12)))

        guard let last = history.last, let lastTrend = trend.last else { return nil }
        let forecast = (1...horizonMonths).map { h -> ForecastPoint in
            let index = last.index + h
            let month = index % 12 + 1
            let value = lastTrend + slope * Double(h) + seasonal[month - 1]
            let band = bandSDs * residualSD
            return ForecastPoint(point: Point(index: index, value: max(0, value)),
                                 lower: max(0, value - band), upper: max(0, value + band))
        }

        return Result(history: history, seasonal: seasonal, movingAverage: movingAverage, window: window,
                      residualSD: residualSD, slope: slope, forecast: forecast)
    }

    // MARK: Pieces (internal for tests)

    static func seasonalProfile(_ history: [Point]) -> [Double] {
        var yearSums: [Int: (sum: Double, count: Int)] = [:]
        for p in history {
            yearSums[p.year, default: (0, 0)].sum += p.value
            yearSums[p.year, default: (0, 0)].count += 1
        }
        var monthDeviation = Array(repeating: (sum: 0.0, count: 0), count: 12)
        for p in history {
            guard let year = yearSums[p.year] else { continue }
            let yearMean = year.sum / Double(year.count)
            monthDeviation[p.month - 1].sum += p.value - yearMean
            monthDeviation[p.month - 1].count += 1
        }
        var profile = monthDeviation.map { $0.count > 0 ? $0.sum / Double($0.count) : 0 }
        let observed = monthDeviation.indices.filter { monthDeviation[$0].count > 0 }
        if !observed.isEmpty {
            let mean = observed.map { profile[$0] }.reduce(0, +) / Double(observed.count)
            for i in observed { profile[i] -= mean }
        }
        return profile
    }

    static func sampleSD(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    /// Least-squares slope (per month) of the given points; 0 for fewer than 3.
    static func trendSlope(_ points: [Point]) -> Double {
        guard points.count >= 3 else { return 0 }
        let xs = points.map { Double($0.index) }
        let ys = points.map(\.value)
        let xMean = xs.reduce(0, +) / Double(xs.count)
        let yMean = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - xMean) * ($1.1 - yMean) }
        let denominator = xs.reduce(0) { $0 + ($1 - xMean) * ($1 - xMean) }
        return denominator == 0 ? 0 : numerator / denominator
    }

    /// Personal overlay rule: only plot a user's own points when they have at least 3.
    static func shouldShowPersonalOverlay(pointCount: Int) -> Bool {
        pointCount >= minimumPoints
    }
}

// MARK: - Insight text

nonisolated enum SeasonalInsight {
    struct Insight: Sendable {
        let text: String
        /// Forecast months where the upper band reaches the limit.
        let limitRiskMonths: [Date]
        let limitText: String?
    }

    /// Seasonal swing smaller than this share of the mean level counts as "no strong pattern".
    static let minimumRelativeAmplitude = 0.10

    static func make(for result: SeasonalForecast.Result, contaminant: ContaminantID, county: String) -> Insight {
        let info = contaminant.info
        let name = info.name
        var sentences: [String] = []

        let strong = result.meanLevel > 0 && result.amplitude / result.meanLevel >= minimumRelativeAmplitude
        if strong {
            let range = peakRange(result)
            sentences.append(String(localized: "\(name) in \(county) County wells usually peaks in \(range)."))
            if let context = info.seasonalContext { sentences.append(context) }
            sentences.append(String(localized: "Consider testing in \(range) to catch the high point."))
        } else {
            sentences.append(String(localized: "\(name) in \(county) County wells doesn't show a strong seasonal pattern, so any time of year is fine for testing."))
        }

        var riskMonths: [Date] = []
        var limitText: String?
        if let limit = info.maximumLimit {
            riskMonths = result.forecast.filter { $0.upper >= limit }.map(\.date)
            if riskMonths.isEmpty {
                limitText = String(localized: "The forecast stays below the limit, even at the top of the range.")
            } else {
                let months = riskMonths.map { $0.formatted(.dateTime.month(.wide).year()) }.formatted(.list(type: .and))
                limitText = String(localized: "The upper forecast range reaches the limit in \(months).")
            }
            if let limitText { sentences.append(limitText) }
        }
        return Insight(text: sentences.joined(separator: " "), limitRiskMonths: riskMonths, limitText: limitText)
    }

    /// "April–May" when a neighboring month is nearly as high as the peak, else "April".
    static func peakRange(_ result: SeasonalForecast.Result) -> String {
        let peak = result.peakMonth - 1
        let prev = (peak + 11) % 12
        let next = (peak + 1) % 12
        let threshold = result.seasonal[peak] - 0.25 * result.amplitude
        let symbols = Calendar.current.monthSymbols
        let neighbor = [prev, next]
            .filter { result.seasonal[$0] >= threshold }
            .max { result.seasonal[$0] < result.seasonal[$1] }
        guard let neighbor else { return symbols[peak] }
        return neighbor == prev ? "\(symbols[prev])–\(symbols[peak])" : "\(symbols[peak])–\(symbols[next])"
    }

    /// One-sentence summary for VoiceOver.
    static func accessibilitySummary(for result: SeasonalForecast.Result, contaminant: ContaminantID, county: String) -> String {
        let name = contaminant.info.name
        let first = result.movingAverage.first?.value ?? 0
        let last = result.movingAverage.last?.value ?? 0
        let change = first == 0 ? 0 : (last - first) / abs(first)
        let direction: String = abs(change) < 0.05
            ? String(localized: "steady")
            : (change > 0 ? String(localized: "rising") : String(localized: "falling"))
        let start = result.history.first?.date.formatted(.dateTime.month(.abbreviated).year()) ?? ""
        let end = result.history.last?.date.formatted(.dateTime.month(.abbreviated).year()) ?? ""
        return String(localized: "\(name) median in \(county) County wells from \(start) to \(end). The trend is \(direction). Highest in \(Calendar.current.monthSymbols[result.peakMonth - 1]). Forecast for the next 12 months shown as a dashed line with a shaded range.")
    }
}
