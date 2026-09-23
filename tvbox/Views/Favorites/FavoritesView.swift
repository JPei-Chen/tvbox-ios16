import SwiftUI

/// 收藏页 - 对应 Android 版 CollectActivity
struct FavoritesView: View {
    /// 收藏数据源，直接观察本地缓存服务的数据变化。
    @ObservedObject private var store = CacheStore.shared
    
    /// 按更新时间倒序展示收藏，最近收藏/更新的内容靠前。
    private var favorites: [VodCollect] { store.collects }
    
    #if os(iOS)
    /// iOS 下卡片尺寸更紧凑，适配手机竖屏。
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)
    ]
    #else
    /// macOS 下卡片适度放大，提升桌面端可读性。
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]
    #endif
    
    var body: some View {
        favoritesContent
    }
    
    /// 收藏内容视图（不含 NavigationStack 包裹）。
    /// iOS 下由外层 ProfileView/SettingsView 的 NavigationStack 管理导航；
    /// macOS 下由 ContentView 的 NavigationSplitView detail 区域使用独立 NavigationStack。
    private var favoritesContent: some View {
        Group {
            if favorites.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        // 每个收藏项都可直接跳转详情，并支持右键取消收藏。
                        ForEach(favorites) { item in
                            NavigationLink(destination: DetailView(video: movieVideo(from: item))) {
                                favoriteCard(item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.removeCollect(item)
                                } label: {
                                    Label("取消收藏", systemImage: "heart.slash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .navigationTitle("收藏")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    /// 空列表占位。
    private var emptyState: some View {
        EmptyStateView(
            icon: "heart.text.square",
            title: "暂无收藏",
            message: "遇到喜欢的影片别忘了点下收藏按钮哦！"
        )
        .padding(40)
    }
    
    /// 收藏卡片。
    /// 只展示海报与标题，保持网格信息密度一致。
    private func favoriteCard(_ item: VodCollect) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: URL.posterURL(from: item.vodPic)) { image in
                image.resizable().aspectRatio(2/3, contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
                    .aspectRatio(2/3, contentMode: .fill)
                    .overlay(Image(systemName: "film").foregroundColor(.gray))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(item.vodName)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
        }
    }
    
    /// 将收藏记录映射成详情页可识别的视频对象。
    private func movieVideo(from item: VodCollect) -> Movie.Video {
        Movie.Video(id: item.vodId, name: item.vodName, pic: item.vodPic, sourceKey: item.sourceKey)
    }
}
