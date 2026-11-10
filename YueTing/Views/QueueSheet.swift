import SwiftUI

/// 播放队列：点一首直接播，拖动排序，左滑移除，可一键清空
struct QueueSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(player.queue.enumerated()), id: \.element.id) { i, entry in
                        if let song = library.song(entry.songID) {
                            HStack {
                                SongRow(song: song)
                                    .opacity(i < player.index ? 0.45 : 1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { player.playQueueItem(i) }
                            .id(entry.id)
                        }
                    }
                    .onMove { player.moveQueue(from: $0, to: $1) }
                    .onDelete { player.removeFromQueue(at: $0) }
                }
                .listStyle(.plain)
                // 打开时滚到正在播放的那首
                .onAppear {
                    if let id = player.currentEntry?.id {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .navigationTitle("播放队列 · \(player.queue.count) 首")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空", role: .destructive) { confirmClear = true }.disabled(player.queue.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            .confirmationDialog("清空播放队列？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) { dismiss(); player.stop() }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
