import Charts
import SwiftUI

struct AccountBalanceChartView: View {
    let presentation: AccountBalanceChartService.Presentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Balance Chart")
                    .font(.headline)
                Spacer()
                Text(presentation.currency)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if presentation.points.isEmpty {
                ContentUnavailableView(
                    "No transactions found with the set filters",
                    systemImage: "chart.xyaxis.line"
                )
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Chart(presentation.points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Lower", point.lowerBound),
                            yEnd: .value("Upper", point.upperBound)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(by: .value("Account", point.seriesName))
                    }
                    .chartLegend(.hidden)
                    .chartForegroundStyleScale(
                        domain: presentation.seriesNames,
                        range: palette
                    )
                    .chartXScale(domain: presentation.startDate...presentation.endDate)
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 260)

                    customXAxis
                }

                legend
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Array(presentation.seriesNames.enumerated()), id: \.element) { index, seriesName in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette[index % palette.count])
                        .frame(width: 12, height: 12)
                    Text(seriesName)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
    }

    private var customXAxis: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(axisDates.enumerated()), id: \.offset) { index, date in
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: 6)

                        Text(axisLabel(for: date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .position(
                        x: max(0, min(proxy.size.width, xPosition(for: date, width: proxy.size.width))),
                        y: 10
                    )
                }
            }
        }
        .frame(height: 26)
    }

    private var palette: [Color] {
        [
            Color(red: 0.27, green: 0.48, blue: 0.59),
            Color(red: 0.42, green: 0.63, blue: 0.46),
            Color(red: 0.72, green: 0.56, blue: 0.34),
            Color(red: 0.59, green: 0.41, blue: 0.66),
            Color(red: 0.77, green: 0.42, blue: 0.43),
            Color(red: 0.45, green: 0.67, blue: 0.69),
            Color(red: 0.58, green: 0.55, blue: 0.38),
            Color(red: 0.36, green: 0.58, blue: 0.73)
        ]
    }

    private var axisDates: [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let start = presentation.startDate
        let end = presentation.endDate

        guard start < end else {
            return [start]
        }

        var dates: [Date] = [start]
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)

        if endYear - startYear >= 1 {
            for year in (startYear + 1)...endYear {
                var components = DateComponents()
                components.calendar = calendar
                components.timeZone = TimeZone(secondsFromGMT: 0)
                components.year = year
                components.month = 1
                components.day = 1

                if let date = components.date, date > start, date < end {
                    dates.append(date)
                }
            }
        }

        dates.append(end)
        return dates
    }

    private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
        let total = presentation.endDate.timeIntervalSince(presentation.startDate)
        guard total > 0 else {
            return 0
        }

        let offset = date.timeIntervalSince(presentation.startDate)
        return width * CGFloat(offset / total)
    }

    private func axisLabel(for date: Date) -> String {
        if Calendar(identifier: .gregorian).isDate(date, inSameDayAs: presentation.startDate)
            || Calendar(identifier: .gregorian).isDate(date, inSameDayAs: presentation.endDate) {
            return Self.endpointFormatter.string(from: date)
        }

        return Self.yearFormatter.string(from: date)
    }

    private static let endpointFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}
