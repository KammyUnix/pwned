import SwiftUI

/// Number base conversion and text conversion (hex, Base64, binary).
struct ConverterToolView: View {
    @State private var base: NumberBase = .hexadecimal
    @State private var numberText = ""
    @State private var conversion: TextConversion = .textToHex
    @State private var input = ""

    var body: some View {
        List {
            numberSection
            textSection
        }
        .navigationTitle("Converters")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Numbers

    private var numberSection: some View {
        Section {
            Picker("Input Base", selection: $base) {
                ForEach(NumberBase.allCases) { base in
                    Text(base.title).tag(base)
                }
            }
            .pickerStyle(.segmented)

            TextField("Number", text: $numberText)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !numberText.trimmingCharacters(in: .whitespaces).isEmpty {
                if let value = NumberConverter.parse(numberText, base: base) {
                    ForEach(NumberBase.allCases) { target in
                        LabeledContent(target.title) {
                            Text(NumberConverter.format(value, base: target))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    LabeledContent("Bits", value: "\(NumberConverter.bitWidth(of: value))")
                    if let character = NumberConverter.printableASCII(value) {
                        LabeledContent("ASCII", value: String(character))
                    }
                } else {
                    Label("Not a valid unsigned \(base.title.lowercased()) number that fits in 64 bits.",
                          systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Numbers")
        } footer: {
            Text("Unsigned, up to 64 bits. Prefixes such as 0x, spaces and underscores are accepted.")
        }
    }

    // MARK: Text

    private var textSection: some View {
        Section {
            Picker("Conversion", selection: $conversion) {
                ForEach(TextConversion.allCases) { conversion in
                    Text(conversion.title).tag(conversion)
                }
            }

            TextField("Input", text: $input, axis: .vertical)
                .lineLimit(2...8)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !input.isEmpty {
                if let output = TextConverter.convert(input, conversion) {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Label("This input isn't valid for \(conversion.title.lowercased()), or it doesn't decode to UTF-8 text.",
                          systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Text")
        } footer: {
            Text("Conversions use the UTF-8 bytes of the text.")
        }
    }
}
