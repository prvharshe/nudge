import SwiftUI

struct RoutinesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var routines = RoutineStore.routines
    @State private var refresh = 0          // bump to re-read done state
    @State private var editing: Routine?
    @State private var isNew = false

    private var today: [Routine] { RoutineStore.scheduled(on: .now, in: routines) }

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    if today.isEmpty {
                        Text("Nothing scheduled today").foregroundStyle(.secondary)
                    }
                    ForEach(today) { routine in
                        let done = RoutineStore.isDone(routine.id, on: .now)
                        Button {
                            RoutineStore.setDone(routine.id, !done, on: .now)
                            Haptics.impact(.light)
                            refresh += 1
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(done ? Color.green : Color.secondary)
                                RoutineRow(routine: routine)
                                    .strikethrough(done)
                                    .opacity(done ? 0.5 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(routine.name), \(done ? "done" : "not done")")
                    }
                }
                .id(refresh)

                Section("All routines") {
                    ForEach(routines) { routine in
                        Button {
                            isNew = false
                            editing = routine
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                RoutineRow(routine: routine)
                                Text(Self.daysLabel(routine.weekdays))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        routines.remove(atOffsets: offsets)
                        RoutineStore.routines = routines
                    }
                }
            }
            .navigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isNew = true
                        editing = Routine(name: "", minutes: 9 * 60)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add routine")
                }
            }
            .sheet(item: $editing) { routine in
                RoutineEditor(routine: routine, isNew: isNew) { saved in
                    if let i = routines.firstIndex(where: { $0.id == saved.id }) {
                        routines[i] = saved
                    } else {
                        routines.append(saved)
                    }
                    RoutineStore.routines = routines
                } onDelete: { deleted in
                    routines.removeAll { $0.id == deleted.id }
                    RoutineStore.routines = routines
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Pick up ticks made from the widget while the app was in the background.
                if phase == .active {
                    routines = RoutineStore.routines
                    refresh += 1
                }
            }
        }
    }

    static func daysLabel(_ weekdays: Set<Int>) -> String {
        if weekdays.isEmpty || weekdays.count == 7 { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}

private struct RoutineRow: View {
    let routine: Routine

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name).font(.body.weight(.medium))
                if !routine.detail.isEmpty {
                    Text(routine.detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(routine.time(on: .now), format: .dateTime.hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct RoutineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var routine: Routine
    let isNew: Bool
    let onSave: (Routine) -> Void
    let onDelete: (Routine) -> Void

    private var time: Binding<Date> {
        Binding(
            get: { routine.time(on: .now) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                routine.minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Vitamin D)", text: $routine.name)
                    TextField("Details (e.g. 1 tablet after lunch)", text: $routine.detail)
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                }
                Section {
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            let on = routine.weekdays.isEmpty || routine.weekdays.contains(day)
                            Button {
                                toggle(day)
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(on ? Color.accentColor.opacity(0.2) : Color(.systemGray6),
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                } header: {
                    Text("Days")
                } footer: {
                    Text(RoutinesView.daysLabel(routine.weekdays))
                }
                if !isNew {
                    Section {
                        Button("Delete routine", role: .destructive) {
                            onDelete(routine)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        routine.name = routine.name.trimmingCharacters(in: .whitespaces)
                        onSave(routine)
                        dismiss()
                    }
                    .disabled(routine.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // Empty set means "every day"; deselecting from that state starts from all 7.
    private func toggle(_ day: Int) {
        var days = routine.weekdays.isEmpty ? Set(1...7) : routine.weekdays
        if days.contains(day) { days.remove(day) } else { days.insert(day) }
        guard !days.isEmpty else { return }   // keep at least one day
        routine.weekdays = days.count == 7 ? [] : days
    }
}
