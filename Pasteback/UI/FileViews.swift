import SwiftUI
import AppKit

actor FileIconLoader {
    static let shared = FileIconLoader()
    func icon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }
}

struct FileReferenceRow: View {
    let file: FileReference
    @State private var exists = true
    @State private var icon: NSImage?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
            else { Image(systemName: file.isDirectory ? "folder" : "doc").frame(width: 28, height: 28) }
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).lineLimit(1)
                Text(file.abbreviatedFolder).font(.caption2).lineLimit(1).truncationMode(.middle)
                if !exists { Text(tr("文件已不存在")).font(.caption2) }
                else if !file.isDirectory, let size = file.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.caption2)
                }
            }
        }.foregroundStyle(exists ? .primary : .secondary).opacity(exists ? 1 : 0.55)
        .task(id: file.path) {
            icon = await FileIconLoader.shared.icon(file.path)
            while !Task.isCancelled {
                exists = await FileReferenceService.shared.status(file).exists
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}
