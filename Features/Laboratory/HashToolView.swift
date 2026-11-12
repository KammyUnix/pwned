import SwiftUI
import UniformTypeIdentifiers

/// Hashes typed text or a chosen file, and compares a file's hash with a
/// published checksum.
struct HashToolView: View {
    private enum FileResult {
        case idle
        case hashing(name: String)
        case done(name: String, byteCount: Int64, digest: String)
        case failed(String)
    }

    @State private var algorithm: HashAlgorithm = .sha256
    @State private var text = ""
    @State private var fileResult: FileResult = .idle
    @State private var fileURL: URL?
    @State private var fileTask: Task<Void, Never>?
    @State private var expected = ""
    @State private var isImporting = false

    var body: some View {
        List {
            Section {
                Picker("Algorithm", selection: $algorithm) {
                    ForEach(HashAlgorithm.allCases) { algorithm in
                        Text(algorithm.rawValue).tag(algorithm)
                    }
                }
            } footer: {
                if algorithm.isInsecure {
                    Text("\(algorithm.rawValue) is broken for security uses. Use it only to match a published checksum.")
                }
            }

            textSection
            fileSection
        }
        .navigationTitle("Hashing")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: algorithm) {
            if let fileURL { hashFile(fileURL) }
        }
        .onDisappear { fileTask?.cancel() }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                fileURL = url
                expected = ""
                hashFile(url)
            case .failure(let error):
                fileResult = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Text

    private var textSection: some View {
        Section {
            TextField("Text to hash", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !text.isEmpty {
                digestRow(HashEngine.hexDigest(of: text, algorithm: algorithm))
            }
        } header: {
            Text("Text")
        } footer: {
            Text("The text is hashed as UTF-8 exactly as typed, including spaces and line breaks.")
        }
    }

    // MARK: File

    private var fileSection: some View {
        Section {
            Button {
                isImporting = true
            } label: {
                Label("Choose File…", systemImage: "doc.badge.plus")
            }

            switch fileResult {
            case .idle:
                EmptyView()
            case .hashing(let name):
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Hashing \(name)…")
                        .foregroundStyle(.secondary)
                }
            case .done(let name, let byteCount, let digest):
                LabeledContent("File", value: name)
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                digestRow(digest)

                TextField("Expected checksum", text: $expected)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let verdict = HashEngine.matches(digest, expected) {
                    Label(verdict ? "Matches" : "Does not match",
                          systemImage: verdict ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(verdict ? .green : .red)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("File")
        } footer: {
            Text("Files are read in pieces, so large files are fine. The file is not copied or stored.")
        }
    }

    private func digestRow(_ digest: String) -> some View {
        Text(digest)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .accessibilityLabel("\(algorithm.rawValue) digest")
            .accessibilityValue(digest)
    }

    private func hashFile(_ url: URL) {
        fileTask?.cancel()
        let algorithm = algorithm
        let name = url.lastPathComponent
        fileResult = .hashing(name: name)

        fileTask = Task {
            let outcome: Result<(digest: String, byteCount: Int64), Error> = await Task.detached(priority: .userInitiated) { () -> Result<(digest: String, byteCount: Int64), Error> in
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                return Result { try HashEngine.hexDigest(ofFileAt: url, algorithm: algorithm) }
            }.value

            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let value):
                fileResult = .done(name: name, byteCount: value.byteCount, digest: value.digest)
            case .failure(let error):
                fileResult = .failed("Couldn't read \(name): \(error.localizedDescription)")
            }
        }
    }
}
