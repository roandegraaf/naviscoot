import SwiftUI

struct TripTimeSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case now
        case departAt
        case arriveBy

        var id: String { rawValue }
    }

    let onDone: (RouteTime?) -> Void

    @State private var mode: Mode
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(time: RouteTime?, now: Date = Date(), onDone: @escaping (RouteTime?) -> Void) {
        self.onDone = onDone
        switch time {
        case nil:
            _mode = State(initialValue: .now)
            _date = State(initialValue: Self.nextWholeHour(after: now))
        case let .departAt(date):
            _mode = State(initialValue: .departAt)
            _date = State(initialValue: date)
        case let .arriveBy(date):
            _mode = State(initialValue: .arriveBy)
            _date = State(initialValue: date)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker(Strings.timeTitle, selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(Strings.timeMode(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("time.mode")

                if mode != .now {
                    DatePicker(Strings.timeTitle, selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.locale, locale)
                        .accessibilityIdentifier("time.date")
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle(Strings.timeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) { dismiss() }
                        .font(.system(size: 18, weight: .semibold))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.done) {
                        onDone(selectedTime)
                        dismiss()
                    }
                    .font(.system(size: 18, weight: .bold))
                    .accessibilityIdentifier("time.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var selectedTime: RouteTime? {
        switch mode {
        case .now: nil
        case .departAt: .departAt(date)
        case .arriveBy: .arriveBy(date)
        }
    }

    static func nextWholeHour(after date: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? date
    }
}
