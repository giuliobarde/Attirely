import SwiftUI
import Charts

struct WardrobeAnalyticsView: View {
    let items: [ClothingItem]
    let viewModel: ProfileViewModel

    var body: some View {
        if items.count < 3 {
            emptyState
        } else {
            VStack(spacing: 16) {
                categoryChart
                formalityChart
                colorSwatchGrid
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.title)
                .foregroundStyle(Theme.secondaryText)
            Text("Add at least 3 items to see wardrobe analytics")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .themeCard()
    }

    // MARK: - Category Chart

    private var categoryChart: some View {
        let data = viewModel.categoryCounts(from: items)
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Categories")

            Chart(data, id: \.category) { item in
                BarMark(
                    x: .value("Count", item.count),
                    y: .value("Category", item.category)
                )
                .foregroundStyle(Theme.champagne.gradient)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .frame(height: CGFloat(max(data.count, 1)) * 36)
        }
        .themeCard()
    }

    // MARK: - Formality Chart

    private var formalityChart: some View {
        let data = viewModel.formalityCounts(from: items)
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Formality")

            Chart(data, id: \.formality) { item in
                SectorMark(
                    angle: .value("Count", item.count),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("Formality", item.formality))
            }
            .chartForegroundStyleScale([
                "Casual": Color(red: 0.788, green: 0.663, blue: 0.431),
                "Smart Casual": Color(red: 0.910, green: 0.816, blue: 0.765),
                "Business Casual": Color(red: 0.741, green: 0.710, blue: 0.675),
                "Business": Color(red: 0.45, green: 0.42, blue: 0.38),
                "Formal": Color(red: 0.102, green: 0.094, blue: 0.090)
            ])
            .chartLegend(position: .bottom, alignment: .center, spacing: 8)
            .frame(height: 200)
        }
        .themeCard()
    }

    // MARK: - Color Swatches

    private var colorSwatchGrid: some View {
        let data = viewModel.colorCounts(from: items)
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Colors")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(data, id: \.color) { item in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(ColorMapping.color(for: item.color))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(Theme.cardBorder, lineWidth: 0.5)
                            )
                        Text(item.color)
                            .font(.caption2)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("\(item.count)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .themeCard()
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(Theme.primaryText)
    }
}
