import SwiftUI

struct ScanProgressView: View {
    let progress: ScanProgress
    let imageCount: Int
    let onRetry: () -> Void

    @State private var currentMessageIndex = 0
    @State private var iconScale: CGFloat = 1.0

    private let analysingMessages = [
        "Identifying garments...",
        "Detecting colors and patterns...",
        "Analyzing fabrics and materials...",
        "Checking formality and style..."
    ]

    var body: some View {
        VStack(spacing: 20) {
            switch progress {
            case .idle:
                EmptyView()

            case .analyzing:
                analyzingView

            case .checkingDuplicates:
                checkingDuplicatesView

            case .error(let message):
                errorView(message)

            case .complete:
                EmptyView()
            }
        }
        .padding(.top, 40)
        .padding(.horizontal)
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Theme.champagne.opacity(0.1))
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Theme.champagne, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .rotationEffect(.degrees(iconScale == 1.0 ? 0 : 360))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: iconScale)

                Image(systemName: "tshirt")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.champagne)
                    .scaleEffect(iconScale)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: iconScale
                    )
            }
            .onAppear { iconScale = 1.1 }

            VStack(spacing: 8) {
                Text(imageCount > 1 ? "Analyzing \(imageCount) photos..." : "Analyzing your clothes...")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)

                Text(analysingMessages[currentMessageIndex])
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: currentMessageIndex)
            }
        }
        .onAppear { startMessageCycling() }
    }

    // MARK: - Checking Duplicates

    private var checkingDuplicatesView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.champagne)
                .controlSize(.regular)

            Text("Cross-referencing with your wardrobe...")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.champagne.opacity(0.1))
                    .frame(width: 64, height: 64)

                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.champagne)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)

            if imageCount > 1 {
                Text("Tip: Try fewer images if the issue persists.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
            }

            Button("Try Again") {
                onRetry()
            }
            .buttonStyle(.themePrimary)
        }
    }

    // MARK: - Helpers

    private func startMessageCycling() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                if !Task.isCancelled {
                    currentMessageIndex = (currentMessageIndex + 1) % analysingMessages.count
                }
            }
        }
    }
}
