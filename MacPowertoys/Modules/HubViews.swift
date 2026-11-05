import SwiftUI
import Combine

/// Hub card of one module. Observes the model so the status text stays live; exposes only `AnyView`.
struct HubCardHost<M: ModuleModel>: View {
    @ObservedObject var model: M
    let descriptor: ModuleDescriptor<M>
    let open: () -> Void

    var body: some View {
        if let custom = descriptor.customCard {
            custom(model, open)
        } else {
            CompactFeatureCard(
                title: descriptor.title,
                icon: descriptor.icon,
                statusText: descriptor.status(model),
                isEnabled: descriptor.toggle.map { kp in
                    Binding(get: { model[keyPath: kp] }, set: { model[keyPath: kp] = $0 })
                },
                action: open
            )
        }
    }
}

/// Hub card of a group (Mouse Utilities); refreshes when any child changes.
struct GroupCardView: View {
    let group: HubGroup
    let children: [LoadedModule]
    let open: () -> Void
    @State private var refresh = 0

    var body: some View {
        let _ = refresh // read so a child change re-renders this view
        CompactFeatureCard(title: group.title, icon: group.icon, statusText: statusText, isEnabled: nil, action: open)
            .onReceive(Publishers.MergeMany(children.map(\.changes)).receive(on: DispatchQueue.main)) { refresh &+= 1 }
    }

    private var statusText: String {
        let count = children.filter { $0.toggle?.wrappedValue ?? false }.count
        if count == 0 { return "All off" }
        return "\(count) of \(children.count) enabled"
    }
}

/// Group screen: one row per child module.
struct GroupHubView: View {
    let group: HubGroup
    let children: [(meta: AnyModule, loaded: LoadedModule)]
    let onBack: () -> Void
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            FeatureHeader(title: group.title, onBack: onBack)

            Divider()

            ForEach(children, id: \.meta.id) { child in
                GroupRow(meta: child.meta, loaded: child.loaded, open: { open(child.meta.id) })
            }

            Spacer()
        }
    }
}

private struct GroupRow: View {
    let meta: AnyModule
    let loaded: LoadedModule
    let open: () -> Void
    @State private var refresh = 0

    var body: some View {
        let _ = refresh // read so a model change re-renders this view
        HStack(spacing: 10) {
            Image(systemName: meta.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 0.8)
                )

            Button(action: open) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(meta.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    HStack(spacing: 4) {
                        if let description = meta.rowSubtitle {
                            Text(description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let shortcut = meta.rowShortcut {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(shortcut)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if let binding = loaded.toggle {
                Toggle("Enable \(meta.title)", isOn: binding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .onReceive(loaded.changes.receive(on: DispatchQueue.main)) { refresh &+= 1 }
    }
}
