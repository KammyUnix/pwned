import SwiftUI
import UniformTypeIdentifiers

/// Shows JSON and property list data (XML or binary) as readable text, from
/// pasted text or a chosen file.
struct DataViewerView: View {
    /// Files larger than this aren't opened here.
    private static let maxFileBytes = 5 * 1024 * 1024

    @State private var input = ""
    @State private var fileOutput: StructuredDataFormatter.Output?
    @State private var fileName: String?
    @State private var fileError: String?
    @State private var isLoadingFile = false
    @State private var isImporting = false

    var body: some View {
        List {
            Section {
                TextField("Paste JSON or a property list", text: $input, axis: .vertical)
                    .lineLimit(4...12)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: input) {
                        if !input.isEmpty {
                            fileOutput = nil
                            fileName = nil
                            fileError = nil
                        }
                    }

                Button {
                    isImporting = true
                } label: {
                    Label("Open File…", systemImage: "doc.badge.plus")
                }
            } header: {
                Text("Input")
            } footer: {
                Text("Binary property lists (bplist) can be opened from a file. Nothing is saved or sent anywhere.")
            }

            if isLoadingFile {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Reading \(fileName ?? "file")…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let fileError {
                Section {
                    Label(fileError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } else if let fileOutput {
                outputSection(fileOutput, title: fileName)
            } else if !input.isEmpty {
                switch StructuredDataFormatter.format(input) {
                case .success(let output):
                    outputSection(output, title: nil)
                case .failure:
                    Section {
                        Label("This isn't JSON or a property list Pwned can read.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Data Viewer")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                open(url)
            case .failure(let error):
                fileError = error.localizedDescription
            }
        }
    }

    private func outputSection(_ output: StructuredDataFormatter.Output, title: String?) -> some View {
        Section {
            Text(output.text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        } header: {
            Text([title, output.format.rawValue].compactMap { $0 }.joined(separator: " · "))
        } footer: {
            if output.format != .json {
                Text("Property lists are shown as XML.")
            }
        }
    }

    private func open(_ url: URL) {
        input = ""
        fileOutput = nil
        fileError = nil
        fileName = url.lastPathComponent
        isLoadingFile = true
        let limit = Self.maxFileBytes

        Task {
            let outcome: Result<StructuredDataFormatter.Output, StructuredDataFormatter.Failure>? = await Task.detached(priority: .userInitiated) { () -> Result<StructuredDataFormatter.Output, StructuredDataFormatter.Failure>? in
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
                guard data.count <= limit else { return .failure(.unrecognized) }
                return StructuredDataFormatter.format(data)
            }.value

            isLoadingFile = false
            switch outcome {
            case .success(let output):
                fileOutput = output
            case .failure(let failure):
                fileError = failure == .empty
                    ? "This file is empty."
                    : "This file isn't JSON or a property list, or it is larger than \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file))."
            case nil:
                fileError = "Couldn't read this file."
            }
        }
    }
}
