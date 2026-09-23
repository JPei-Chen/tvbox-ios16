import SwiftUI

/// 首页：不展示源站推荐与分类标签，只保留「继续观看」和「热门榜单」。
/// 看什么内容通过榜单/搜索进入；源站的切换在详情页「换源」完成。
struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var appState: AppState
    /// 观看历史（用于「继续观看」区块），实时响应增删。
    @ObservedObject private var historyStore = CacheStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                // 页面标题
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.orange)
                    Text("推荐")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // 继续观看
                continueWatchingSection

                // 热门榜单（取源站分类前几名，横向海报排 + 排名角标）
                ForEach(viewModel.recommendSections) { section in
                    rankingRow(section)
                }

                Color.clear.frame(height: 24)
            }
            .background(AppTheme.primaryGradient)
            .navigationDestination(for: Movie.Video.self) { video in
                DetailView(video: video)
            }
            .overlay {
                if viewModel.isLoading && viewModel.recommendSections.isEmpty && recentRecords.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.orange)
                        Text("加载中...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 12)
                        Spacer()
                    }
                }
            }
        }
        .task {
            await viewModel.loadSorts()
            await viewModel.loadRecommendSections()
        }
        .refreshable {
            await viewModel.refresh()
            await viewModel.loadRecommendSections()
        }
    }

    // MARK: - 热门榜单

    /// 榜单分区：标题 + 横向海报排，海报左上角带排名角标（前三名高亮）。
    @ViewBuilder
    private func rankingRow(_ section: HomeRecommendSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.accentGradient)
                    .frame(width: 4, height: 16)
                Text("热门\(section.sort.name)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 20)

            if section.videos.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.orange)
                        .padding(.vertical, 34)
                    Spacer()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(section.videos.enumerated()), id: \.1.id) { index, video in
                            NavigationLink(value: video) {
                                VodCardView(video: video)
                                    .frame(width: 112)
                                    .overlay(alignment: .topLeading) {
                                        rankBadge(number: index + 1)
                                            .offset(x: -5, y: -5)
                                    }
                            }
                            #if os(iOS)
                            .buttonStyle(VodCardPressStyle())
                            #else
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 18)
    }

    /// 排名角标：前三名橙色实心，其余深色半透明。
    private func rankBadge(number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .heavy))
            .foregroundColor(number <= 3 ? .black : .white.opacity(0.85))
            .frame(width: 20, height: 20)
            .background(
                Circle().fill(number <= 3 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.black.opacity(0.6)))
            )
            .overlay(
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }

    // MARK: - 继续观看

    /// 最近 10 条观看记录，最新在前。
    private var recentRecords: [VodRecord] {
        Array(historyStore.records.prefix(10))
    }

    @ViewBuilder
    private var continueWatchingSection: some View {
        if !recentRecords.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                    Text("继续观看")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentRecords) { record in
                            NavigationLink(value: movieVideo(from: record)) {
                                ContinueWatchingCard(record: record)
                            }
                            #if os(iOS)
                            .buttonStyle(VodCardPressStyle())
                            #else
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    /// 从观看记录还原可导航的视频对象（与历史页同一规则）。
    private func movieVideo(from item: VodRecord) -> Movie.Video {
        Movie.Video(id: item.vodId, name: item.vodName, pic: item.vodPic, sourceKey: item.sourceKey)
    }
}

/// 「继续观看」卡片：横向封面 + 片名 + 上次看到的位置。
struct ContinueWatchingCard: View {
    let record: VodRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                CachedAsyncImage(url: URL.posterURL(from: record.vodPic)) { image in
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                        .fill(Color.white.opacity(0.05))
                        .aspectRatio(2/3, contentMode: .fill)
                        .overlay(
                            Image(systemName: "film.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white.opacity(0.2))
                        )
                }
                .frame(width: 110, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .overlay(alignment: .bottom) {
                    // 底部渐变，保护进度文字可读性
                    LinearGradient(
                        colors: [.black.opacity(0.75), .clear],
                        startPoint: .bottom,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                }
                .overlay(alignment: .bottomLeading) {
                    if !record.playNote.isEmpty {
                        Text(record.playNote)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .padding(.bottom, 6)
                            .padding(.leading, 6)
                    }
                }
                .overlay(alignment: .center) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 6)
                }
            }

            Text(record.vodName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
        }
    }
}
