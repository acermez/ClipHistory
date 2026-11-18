import AppKit
import SwiftUI

struct PopupView: View {
    static let size = CGSize(width: 400, height: 460)

    @ObservedObject var model: PopupModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if model.ordered.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
        )
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("Search history", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            Text(model.settings.hotKey.label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !model.pinned.isEmpty {
                        sectionHeader("Pinned")
                        ForEach(Array(model.pinned.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index)
                        }
                    }
                    if !model.recent.isEmpty {
                        sectionHeader("Recent")
                        ForEach(Array(model.recent.enumerated()), id: \.element.id) { index, item in
                            row(item, index: model.pinned.count + index)
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.scrollRequest) { _, _ in
                if let id = model.selectedID { proxy.scrollTo(id) }
            }
        }
    }

    private func row(_ item: ClipItem, index: Int) -> some View {
        ClipRow(item: item, index: index, selected: item.id == model.selectedID,
                thumbnail: model.store.thumbnail(for: item),
                onPin: { model.togglePin(item.id) })
            .id(item.id)
            .onTapGesture { model.paste(item) }
            .onHover { inside in if inside { model.selectedID = item.id } }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "Copy something and it shows up here" : "No matches")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("↩ paste")
            Text("⌘1–9 quick paste")
            Text("⌘P pin")
            Text("⌘⌫ remove")
            Text("esc close")
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let selected: Bool
    let thumbnail: NSImage?
    let onPin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onPin) {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(item.pinned ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.pinned ? "Unpin" : "Pin")
            Text(index < 9 ? "⌘\(index + 1)" : "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(item.kind == .image ? Color.blue.opacity(0.15) : Color.primary.opacity(0.06))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(item.kind == .image ? Color.blue : Color.secondary)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var symbol: String {
        switch item.kind {
        case .image: return "photo"
        case .files:
            if item.isDirectory == true { return "folder" }
            return (item.fileCount ?? 1) > 1 ? "doc.on.doc" : "doc"
        case .text:
            let t = item.title
            if t.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil { return "envelope" }
            if t.hasPrefix("http://") || t.hasPrefix("https://") { return "link" }
            return "text.alignleft"
        }
    }

    private var subtitle: String {
        let when = Self.relative(item.date)
        if let app = item.sourceAppName { return "\(app) · \(when)" }
        return when
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if Calendar.current.isDateInToday(date) { return "\(Int(seconds / 3600)) h ago" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
