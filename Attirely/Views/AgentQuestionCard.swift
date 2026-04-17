import SwiftUI

struct AgentQuestionCard: View {
    let question: AgentQuestion
    let onSubmit: (AgentQuestionAnswer) -> Void

    @State private var selectedOptions: Set<String> = []
    @State private var isOtherSelected: Bool = false
    @State private var otherText: String = ""

    private var canSubmit: Bool {
        if !selectedOptions.isEmpty { return true }
        if isOtherSelected, !otherText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.question)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 6) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        tap(option: option)
                    } label: {
                        Text(option)
                            .themePill(isActive: selectedOptions.contains(option))
                    }
                    .buttonStyle(.plain)
                }

                if question.allowsOther {
                    Button {
                        tapOther()
                    } label: {
                        Text("Other")
                            .themePill(isActive: isOtherSelected)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isOtherSelected {
                TextField("Type your answer", text: $otherText)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .submitLabel(.send)
                    .onSubmit {
                        if question.multiSelect {
                            // In multi-select, Enter should not auto-submit — user uses the Submit button
                            return
                        }
                        if canSubmit { submit() }
                    }
            }

            if question.multiSelect {
                Button {
                    submit()
                } label: {
                    Text("Submit")
                }
                .buttonStyle(.themePrimary)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.4)
            }
        }
        .padding(12)
        .background(Theme.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 0.5)
        )
    }

    private func tap(option: String) {
        if question.multiSelect {
            if selectedOptions.contains(option) {
                selectedOptions.remove(option)
            } else {
                selectedOptions.insert(option)
            }
        } else {
            // Single-select: immediate submit
            selectedOptions = [option]
            isOtherSelected = false
            otherText = ""
            submit()
        }
    }

    private func tapOther() {
        if question.multiSelect {
            isOtherSelected.toggle()
            if !isOtherSelected { otherText = "" }
        } else {
            // Single-select: toggle the field open; user types then submits via keyboard return
            isOtherSelected = true
            selectedOptions = []
        }
    }

    private func submit() {
        let trimmed = otherText.trimmingCharacters(in: .whitespaces)
        let other = (isOtherSelected && !trimmed.isEmpty) ? trimmed : nil
        let selected = Array(selectedOptions).sorted {
            (question.options.firstIndex(of: $0) ?? 0) < (question.options.firstIndex(of: $1) ?? 0)
        }
        guard !selected.isEmpty || other != nil else { return }
        onSubmit(AgentQuestionAnswer(selectedOptions: selected, otherText: other))
    }
}
