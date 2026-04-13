import SwiftUI
import SwiftData
import Charts

struct BodyMetricsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMetric.date, order: .reverse) private var metrics: [BodyMetric]

    @State private var showAddSheet = false
    @State private var selectedMetricType = MetricType.weight

    enum MetricType: String, CaseIterable, Identifiable {
        case weight, bodyFat, chest, waist, arm, thigh
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .weight: return "体重"
            case .bodyFat: return "体脂率"
            case .chest: return "胸围"
            case .waist: return "腰围"
            case .arm: return "臂围"
            case .thigh: return "腿围"
            }
        }
        var unit: String {
            switch self {
            case .weight: return "kg"
            case .bodyFat: return "%"
            default: return "cm"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 指标选择
                Picker("指标", selection: $selectedMetricType) {
                    ForEach(MetricType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                // 图表
                chartSection

                // 历史记录
                historySection
            }
            .padding()
        }
        .navigationTitle("数据追踪")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddBodyMetricView()
        }
    }

    // MARK: - 图表

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(selectedMetricType.displayName)趋势")
                .font(.headline)

            let chartData = dataForChart()
            if chartData.isEmpty {
                Text("暂无数据，请先记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(chartData, id: \.date) { item in
                    LineMark(
                        x: .value("日期", item.date),
                        y: .value(selectedMetricType.displayName, item.value)
                    )
                    .foregroundStyle(.orange)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("日期", item.date),
                        y: .value(selectedMetricType.displayName, item.value)
                    )
                    .foregroundStyle(.orange)
                }
                .frame(height: 200)
                .chartYAxisLabel(selectedMetricType.unit)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemGray6)))
    }

    // MARK: - 历史记录

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("记录历史").font(.headline)

            ForEach(metrics.prefix(20)) { metric in
                HStack {
                    Text(metric.date, style: .date)
                        .font(.subheadline)
                    Spacer()
                    if let weight = metric.weightKg {
                        metricBadge("体重", String(format: "%.1f", weight), "kg")
                    }
                    if let bf = metric.bodyFatPercentage {
                        metricBadge("体脂", String(format: "%.1f", bf), "%")
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    private func metricBadge(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)\(unit)")
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 70)
    }

    // MARK: - 数据

    struct ChartDataPoint {
        let date: Date
        let value: Double
    }

    private func dataForChart() -> [ChartDataPoint] {
        metrics.reversed().compactMap { metric in
            let value: Double?
            switch selectedMetricType {
            case .weight: value = metric.weightKg
            case .bodyFat: value = metric.bodyFatPercentage
            case .chest: value = metric.chestCm
            case .waist: value = metric.waistCm
            case .arm: value = metric.armCm
            case .thigh: value = metric.thighCm
            }
            guard let v = value else { return nil }
            return ChartDataPoint(date: metric.date, value: v)
        }
    }
}

// MARK: - 添加身体数据

struct AddBodyMetricView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var weightKg = ""
    @State private var bodyFat = ""
    @State private var chestCm = ""
    @State private var waistCm = ""
    @State private var armCm = ""
    @State private var thighCm = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本数据") {
                    numberField("体重 (kg)", text: $weightKg)
                    numberField("体脂率 (%)", text: $bodyFat)
                }
                Section("围度 (cm)") {
                    numberField("胸围", text: $chestCm)
                    numberField("腰围", text: $waistCm)
                    numberField("臂围", text: $armCm)
                    numberField("腿围", text: $thighCm)
                }
            }
            .navigationTitle("记录身体数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    private func numberField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("--", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func save() {
        let metric = BodyMetric(
            weightKg: Double(weightKg),
            bodyFatPercentage: Double(bodyFat),
            chestCm: Double(chestCm),
            waistCm: Double(waistCm),
            armCm: Double(armCm),
            thighCm: Double(thighCm)
        )
        context.insert(metric)
        try? context.save()
        dismiss()
    }
}
