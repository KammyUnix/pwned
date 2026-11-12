import SwiftUI

/// The Laboratory: small offline tools for reverse-engineering work. Tools that
/// exist open; tools that don't are listed as planned, so the list is an
/// accurate picture of what the app can do.
struct LaboratoryView: View {
    private struct PlannedTool: Identifiable {
        let name: String
        let systemImage: String
        var id: String { name }
    }

    private let planned: [PlannedTool] = [
        PlannedTool(name: "File Metadata and Mach-O Headers", systemImage: "doc.text.magnifyingglass"),
        PlannedTool(name: "XML Viewer", systemImage: "chevron.left.forwardslash.chevron.right"),
        PlannedTool(name: "ARM64 Instructions and Registers", systemImage: "cpu"),
        PlannedTool(name: "Mach-O Structure Reference", systemImage: "square.stack.3d.up"),
        PlannedTool(name: "Crash, IPS and Panic Log Viewers", systemImage: "waveform.path.ecg")
    ]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    HashToolView()
                } label: {
                    Label("Hashing", systemImage: "number")
                }
                NavigationLink {
                    ConverterToolView()
                } label: {
                    Label("Converters", systemImage: "arrow.left.arrow.right")
                }
                NavigationLink {
                    DataViewerView()
                } label: {
                    Label("JSON and Property List Viewer", systemImage: "curlybraces")
                }
            } header: {
                Text("Tools")
            } footer: {
                Text("Everything runs on this device. Text and files you use here are not saved or sent anywhere.")
            }

            Section("Planned") {
                ForEach(planned) { tool in
                    LabeledContent {
                        Text("Not built yet")
                    } label: {
                        Label(tool.name, systemImage: tool.systemImage)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Laboratory")
        .navigationBarTitleDisplayMode(.inline)
    }
}
