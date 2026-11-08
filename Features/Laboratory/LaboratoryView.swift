import SwiftUI

/// Phase 1 placeholder for the Laboratory. The catalog below lists the planned
/// tools only; none of them is functional yet and the UI says so.
struct LaboratoryView: View {
    private struct PlannedTool: Identifiable {
        let name: String
        let systemImage: String
        var id: String { name }
    }

    private struct ToolGroup: Identifiable {
        let title: String
        let tools: [PlannedTool]
        var id: String { title }
    }

    private let groups: [ToolGroup] = [
        ToolGroup(title: "Converters", tools: [
            PlannedTool(name: "Hex, Binary, Decimal and ASCII", systemImage: "arrow.left.arrow.right"),
            PlannedTool(name: "UTF-8 and Base64", systemImage: "textformat")
        ]),
        ToolGroup(title: "Cryptographic Utilities", tools: [
            PlannedTool(name: "SHA-256, SHA-384 and SHA-512", systemImage: "number"),
            PlannedTool(name: "File Hashing and Comparison", systemImage: "doc.badge.gearshape")
        ]),
        ToolGroup(title: "File Inspection", tools: [
            PlannedTool(name: "JSON, XML and Property List Viewers", systemImage: "curlybraces"),
            PlannedTool(name: "File Metadata and Mach-O Headers", systemImage: "doc.text.magnifyingglass")
        ]),
        ToolGroup(title: "References and Logs", tools: [
            PlannedTool(name: "ARM64 Instructions and Registers", systemImage: "cpu"),
            PlannedTool(name: "Mach-O Structure Reference", systemImage: "square.stack.3d.up"),
            PlannedTool(name: "Crash, IPS and Panic Log Viewers", systemImage: "waveform.path.ecg")
        ])
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Laboratory tools are built in Phase 5. None of the tools below works yet.",
                          systemImage: "hammer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.tools) { tool in
                            LabeledContent {
                                Text("Planned")
                            } label: {
                                Label(tool.name, systemImage: tool.systemImage)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Laboratory")
        }
    }
}
