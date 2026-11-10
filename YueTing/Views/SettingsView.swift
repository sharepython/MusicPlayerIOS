import SwiftUI

/// 设置：歌曲页左上角的齿轮进来。放的是歌词在 App 外面怎么显示（锁屏 / 控制中心和桌面歌词），和在线整理专辑
struct SettingsView: View {
    @Environment(SystemLyrics.self) private var system
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var system = system
        NavigationStack {
            Form {
                Section {
                    Toggle("锁屏和控制中心显示歌词", isOn: $system.lockScreen)
                        .accessibilityIdentifier("lockScreenLyrics")
                } footer: {
                    Text("锁屏、控制中心、车载屏幕上歌名的位置换成正在唱的那句，歌名和歌手显示在第二行。")
                }
                Section {
                    Toggle("桌面歌词", isOn: Binding(get: { system.desktopOn }, set: { system.setDesktop($0) }))
                        .disabled(!system.desktopSupported)
                        .accessibilityIdentifier("desktopLyrics")
                } footer: {
                    Text(system.desktopSupported
                         ? "打开后，小狗音乐退到后台时正在唱的那句歌词会以一根细长条浮在桌面和其他 App 上面，回到小狗音乐时自动收起。按住长条可以拖动；点长条上的关闭只收起这一次，下次退到后台还会出来。"
                         : "这台设备不支持画中画，开不了桌面歌词。")
                }
                Section {
                    if let p = library.albumProgress {
                        HStack {
                            ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                            Text("\(p.done) / \(p.total)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("albumProgress")
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        Button("停止", role: .destructive) { library.stopOrganizing() }
                    } else {
                        Button("在线整理专辑") { library.organizeAlbums() }
                            .disabled(library.albumTodo.isEmpty)
                            .accessibilityIdentifier("organizeAlbums")
                        Button("还原专辑信息", role: .destructive) { library.restoreAlbums() }
                            .disabled(!library.hasAlbumFixes)
                    }
                } header: {
                    Text("专辑")
                } footer: {
                    Text((library.albumProgress == nil ? "专辑页「单曲」里还有 \(library.albumTodo.count) 首没查过。" : "") + "按歌名和歌手到 QQ 音乐、iTunes 查出每首歌所在的专辑，同一张专辑的歌就能归到一起；不要演唱会和精选集，查到的繁体专辑名转成简体。只发送歌名和歌手，不改歌曲文件，随时可以还原。")
                }
                Section {
                    if let p = library.coverProgress {
                        HStack {
                            ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                            Text("\(p.done) / \(p.total)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("coverProgress")
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        Button("停止", role: .destructive) { library.stopFindingCovers() }
                    } else {
                        Button("在线补封面") { library.findCovers() }
                            .disabled(library.coverTodo.isEmpty)
                            .accessibilityIdentifier("findCovers")
                        Button("清除在线封面", role: .destructive) { library.clearCovers() }
                            .disabled(!library.hasOnlineCovers)
                    }
                } header: {
                    Text("封面")
                } footer: {
                    Text((library.coverProgress == nil ? "还有 \(library.coverTodo.count) 首没查过，文件里有封面的会直接跳过。" : "") + "按每首歌的歌名和歌手到 QQ 音乐、iTunes 找这首歌的封面，搜不到这首歌时用歌手照片。建议先整理专辑再补封面。只发送歌名和歌手，不改歌曲文件，随时可以清除。")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 桌面歌词的画面要挂在窗口里系统才让开画中画；放在 RootView 最底下，被界面盖住看不见
struct DesktopLyricsHost: UIViewRepresentable {
    let desktop: DesktopLyrics
    func makeUIView(context: Context) -> UIView {
        desktop.hostView
    }

    func updateUIView(_ view: UIView, context: Context) {
    }
}
