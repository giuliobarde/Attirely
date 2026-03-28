import SwiftUI

struct PillPickerField: View {
    let label: String
    let options: [String]
    @Binding var selection: String
    var allowsCustom: Bool = false
    var aiOriginalValue: String? = nil

    @State private var customText: String = ""

    private var isCustomValue: Bool {
        allowsCustom && !options.contains(selection) && !selection.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            FlowLayout(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(option)
                            .themePill(isActive: selection == option && !isCustomValue)
                    }
                    .buttonStyle(.plain)
                }

                if allowsCustom {
                    Button {
                        if isCustomValue {
                            // Already on custom — do nothing
                        } else {
                            selection = customText.isEmpty ? "" : customText
                        }
                    } label: {
                        Text("Other")
                            .themePill(isActive: isCustomValue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isCustomValue {
                TextField("Custom \(label.lowercased())", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .onChange(of: customText) { _, newValue in
                        if !newValue.isEmpty {
                            selection = newValue
                        }
                    }
            }

            if let original = aiOriginalValue, original != selection {
                Text("AI detected: \(original)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .onAppear {
            if isCustomValue {
                customText = selection
            }
        }
    }
}

struct OptionalPillPickerField: View {
    let label: String
    let options: [String]
    @Binding var selection: String?
    var aiOriginalValue: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            FlowLayout(spacing: 6) {
                Button {
                    selection = nil
                } label: {
                    Text("None")
                        .themePill(isActive: selection == nil)
                }
                .buttonStyle(.plain)

                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(option)
                            .themePill(isActive: selection == option)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let original = aiOriginalValue, original != (selection ?? "") {
                Text("AI detected: \(original)")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
