import SwiftUI

struct CollapsibleSection<Content: View, Trailing: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    var titleWeight: Font.Weight = .medium
    var showsCard: Bool = true
    let trailing: Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if isExpanded {
                Divider()
                content()
            }
        }
        .modifier(OptionalCardModifier(showsCard: showsCard))
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(titleWeight)
                .foregroundStyle(Theme.primaryText)

            Spacer()

            trailing

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.25), value: isExpanded)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        }
    }
}

// Convenience initializer when no trailing view is needed
extension CollapsibleSection where Trailing == EmptyView {
    init(
        title: String,
        isExpanded: Binding<Bool>,
        titleWeight: Font.Weight = .medium,
        showsCard: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.titleWeight = titleWeight
        self.showsCard = showsCard
        self.trailing = EmptyView()
        self.content = content
    }
}

private struct OptionalCardModifier: ViewModifier {
    let showsCard: Bool

    func body(content: Content) -> some View {
        if showsCard {
            content.themeCard()
        } else {
            content
        }
    }
}
