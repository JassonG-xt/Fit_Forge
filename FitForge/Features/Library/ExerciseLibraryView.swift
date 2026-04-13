import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @Query private var exercises: [Exercise]
    @State private var selectedBodyPart: BodyPart?
    @State private var searchText = ""

    private var filteredExercises: [Exercise] {
        var result = exercises
        if let part = selectedBodyPart {
            result = result.filter { $0.bodyPart == part }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    private var groupedExercises: [(BodyPart, [Exercise])] {
        let grouped = Dictionary(grouping: filteredExercises) { $0.bodyPart }
        return BodyPart.allCases.compactMap { part in
            guard let exercises = grouped[part], !exercises.isEmpty else { return nil }
            return (part, exercises)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 部位筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("全部", isSelected: selectedBodyPart == nil) {
                        selectedBodyPart = nil
                    }
                    ForEach(BodyPart.allCases) { part in
                        filterChip(part.displayName, isSelected: selectedBodyPart == part) {
                            selectedBodyPart = part
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            List {
                ForEach(groupedExercises, id: \.0) { part, exercises in
                    Section {
                        ForEach(exercises) { exercise in
                            NavigationLink(destination: ExerciseDetailView(exerciseId: exercise.id)) {
                                exerciseRow(exercise)
                            }
                        }
                    } header: {
                        Label(part.displayName, systemImage: part.icon)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("动作库")
        .searchable(text: $searchText, prompt: "搜索动作")
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 12) {
            Image(systemName: exercise.bodyPart.icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.orange.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    Text(exercise.equipment.displayName)
                        .font(.caption)
                    Text(exercise.difficulty.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if exercise.isCompound {
                Text("复合")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.2)))
            }
        }
    }

    private func filterChip(_ text: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Color.orange : Color(.systemGray5))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}
