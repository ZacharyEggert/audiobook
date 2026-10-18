import AudiobookCore
import Charts
import Library
import SwiftData
import SwiftUI

/// Listening time per day or week, streak and totals (PLAN §5 Stats and polish).
struct StatsScreen: View {
    @Query private var sessions: [ListeningSessionRecord]
    @Query private var progressRecords: [ProgressRecord]
    @State private var span = Span.days

    enum Span: String, CaseIterable, Identifiable {
        case days = "Daily"
        case weeks = "Weekly"

        var id: Self {
            self
        }

        var count: Int {
            self == .days ? 7 : 8
        }

        var unit: Calendar.Component {
            self == .days ? .day : .weekOfYear
        }
    }

    var body: some View {
        let stats = ListeningStats(entries: sessions.entries)
        let total = stats.total
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Listening Yet",
                        systemImage: "chart.bar",
                        description: Text("Play a book and your listening shows up here."),
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            Picker("Range", selection: $span) {
                                ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            ListeningChart(buckets: buckets(of: stats), span: span)
                            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                                GridRow {
                                    StatTile(title: "Streak", value: streakText(stats.streak(asOf: .now)), systemImage: "flame")
                                    StatTile(title: "Listened", value: BookProgress.format(total.real), systemImage: "headphones")
                                }
                                GridRow {
                                    StatTile(title: "Finished", value: "\(finishedCount)", systemImage: "checkmark.circle")
                                    StatTile(title: "Time Saved", value: BookProgress.format(total.saved), systemImage: "hare")
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Stats")
        }
    }

    private var finishedCount: Int {
        progressRecords.latestByBook.values.count(where: \.isFinished)
    }

    private func buckets(of stats: ListeningStats) -> [ListeningBucket] {
        switch span {
        case .days: stats.daily(count: span.count, endingAt: .now)
        case .weeks: stats.weekly(count: span.count, endingAt: .now)
        }
    }

    private func streakText(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }
}

private struct ListeningChart: View {
    let buckets: [ListeningBucket]
    let span: StatsScreen.Span

    var body: some View {
        Chart(buckets, id: \.start) { bucket in
            BarMark(x: .value("Date", bucket.start, unit: span.unit), y: .value("Hours", bucket.totals.real / 3600))
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(bucket.start
                    .formatted(span == .days ? .dateTime.weekday(.wide).month().day() : .dateTime.month().day()))
                .accessibilityValue(BookProgress.format(bucket.totals.real))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: span.unit)) { _ in
                AxisValueLabel(format: span == .days ? .dateTime.weekday(.narrow) : .dateTime.month(.defaultDigits).day(), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(BookProgress.format(hours * 3600))
                    }
                }
            }
        }
        .frame(height: 200)
        .padding()
        .background(Theme.surface, in: .rect(cornerRadius: 12))
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.surface, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    let day: TimeInterval = 86400
    for offset in 0 ..< 6 {
        container.mainContext.insert(ListeningSessionRecord(
            bookID: UUID(), start: .now.addingTimeInterval(-day * Double(offset)), realSeconds: 1800 + Double(offset) * 600,
            contentSeconds: 2400 + Double(offset) * 800,
        ))
    }
    return StatsScreen().modelContainer(container)
}
