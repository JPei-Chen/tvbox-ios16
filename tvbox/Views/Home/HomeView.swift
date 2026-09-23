import SwiftUI

/// 首页 - 对应 Android 版 HomeActivity + UserFragment
struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var appState: AppState
    /// 观看历史（用于「继续观看」区块），实时响应增删。
    @ObservedObject private var historyStore = CacheStore.shared
    @State private var categoryScrollAnchorId: String?
    
    // 网格布局
    #if os(iOS)
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 10)
    ]
    #else
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]
    #endif
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部栏
                headerBar
                
                // 分类标签栏
                if !viewModel.sorts.isEmpty {
                    categoryTabBar
                }
                
                // 内容区
                contentArea
            }
            .background(AppTheme.primaryGradient)
        }
        .task {
            await viewModel.loadSorts()
            if let first = viewModel.sorts.first {
                viewModel.selectSort(first)
            }
        }
    }
    
    // MARK: - 顶部栏（源选择器）
    
    private var headerBar: some View {
        HStack(spacing: 12) {
            // 源切换按钮
            Menu {
                ForEach(ApiConfig.shared.sourceBeanList.filter { $0.isSupportedInSwift }) { source in
                    Button {
                        ApiConfig.shared.setHomeSource(source)
                        Task { await viewModel.refresh() }
                    } label: {
                        HStack {
                            Text(source.name)
                            if source.key == ApiConfig.shared.homeSourceBean?.key {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text(ApiConfig.shared.homeSourceBean?.name ?? "TVBox")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
    
    // MARK: - 分类标签栏
    
    private var categoryTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(viewModel.sorts) { sort in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.selectSort(sort)
                            }
                            categoryScrollAnchorId = sort.id
                            scrollCategoryBar(to: sort.id, proxy: proxy)
                        } label: {
                            VStack(spacing: 6) {
                                Text(sort.name)
                                    .font(.system(size: 14, weight: viewModel.selectedSort?.id == sort.id ? .bold : .regular))
                                    .foregroundColor(viewModel.selectedSort?.id == sort.id ? .white : .white.opacity(0.6))
                                
                                // 底部指示条
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.orange)
                                    .frame(width: 20, height: 3)
                                    .opacity(viewModel.selectedSort?.id == sort.id ? 1 : 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .id(sort.id)
                    }
                }
                .padding(.horizontal, 12)
            }
            .onAppear {
                syncCategoryScrollAnchorIfNeeded()
                scrollCategoryBar(to: categoryScrollAnchorId, proxy: proxy, animated: false)
            }
            .onChange(of: viewModel.sorts.map(\.id)) { _ in
                syncCategoryScrollAnchorIfNeeded()
                scrollCategoryBar(to: categoryScrollAnchorId, proxy: proxy, animated: false)
            }
            .onChange(of: viewModel.selectedSort?.id) { newId in
                guard let newId else { return }
                categoryScrollAnchorId = newId
                scrollCategoryBar(to: newId, proxy: proxy)
            }
        }
        .padding(.bottom, 4)
    }
    
    private func categoryIndex(for id: String?) -> Int? {
        guard let id else { return nil }
        return viewModel.sorts.firstIndex(where: { $0.id == id })
    }
    
    private func syncCategoryScrollAnchorIfNeeded() {
        guard !viewModel.sorts.isEmpty else {
            categoryScrollAnchorId = nil
            return
        }
        
        if let selectedId = viewModel.selectedSort?.id,
           viewModel.sorts.contains(where: { $0.id == selectedId }) {
            categoryScrollAnchorId = selectedId
            return
        }
        
        if let anchorId = categoryScrollAnchorId,
           viewModel.sorts.contains(where: { $0.id == anchorId }) {
            return
        }
        
        categoryScrollAnchorId = viewModel.sorts.first?.id
    }
    
    private func scrollCategoryBar(to id: String?, proxy: ScrollViewProxy, animated: Bool = true) {
        guard let id else { return }
        
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
    
    // MARK: - 内容区

    private var contentArea: some View {
        Group {
            if viewModel.isLoading && viewModel.categoryVideos.isEmpty && viewModel.homeVideos.isEmpty {
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
            } else if let error = viewModel.errorMessage, viewModel.categoryVideos.isEmpty && viewModel.homeVideos.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    // 如果是不支持的源类型，显示类型信息
                    if let source = ApiConfig.shared.homeSourceBean, !source.isSupportedInSwift {
                        Text("当前源类型: \(source.typeDescription)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("重试") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    Spacer()
                }
            } else if viewModel.selectedSort?.id == "home" {
                // 推荐页：banner 轮播 + 继续观看 + 分类分区横向内容行
                recommendScrollView
            } else {
                let videos = viewModel.categoryVideos

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(videos) { video in
                            NavigationLink(value: video) {
                                VodCardView(video: video)
                            }
                            #if os(iOS)
                            .buttonStyle(VodCardPressStyle())
                            #else
                            .buttonStyle(.plain)
                            #endif
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(currentItem: video) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    // 加载更多
                    if viewModel.hasMore {
                        ProgressView()
                            .padding()
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationDestination(for: Movie.Video.self) { video in
            DetailView(video: video)
        }
    }

    // MARK: - 推荐页

    private var recommendScrollView: some View {
        ScrollView {
            // 顶部 banner 轮播（取源站推荐前 6 部）
            if !viewModel.homeVideos.isEmpty {
                BannerCarousel(videos: Array(viewModel.homeVideos.prefix(6)))
                    .padding(.top, 10)
            }

            // 继续观看
            continueWatchingSection

            // 分类分区内容行
            ForEach(viewModel.recommendSections) { section in
                recommendRow(section)
            }

            Color.clear.frame(height: 24)
        }
        .refreshable {
            await viewModel.refresh()
            await viewModel.loadRecommendSections()
        }
        .task {
            await viewModel.loadRecommendSections()
        }
    }

    /// 推荐页的单个分区：标题行 + 横向海报排。
    @ViewBuilder
    private func recommendRow(_ section: HomeRecommendSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.accentGradient)
                    .frame(width: 4, height: 16)
                Text("热门\(section.sort.name)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.selectSort(section.sort)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("更多")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
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
                        ForEach(section.videos) { video in
                            NavigationLink(value: video) {
                                VodCardView(video: video)
                                    .frame(width: 112)
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
            .padding(.top, 12)
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

/// 推荐页顶部 banner 轮播：大图背景 + 片名 + 备注 + 播放入口，每 5 秒自动切换。
struct BannerCarousel: View {
    let videos: [Movie.Video]
    @State private var currentPage = 0
    @State private var autoAdvanceTimer: Timer?

    var body: some View {
        TabView(selection: $currentPage) {
            ForEach(Array(videos.enumerated()), id: \.1.id) { index, video in
                NavigationLink(value: video) {
                    bannerCard(for: video)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius + 6))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius + 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear { startAutoAdvance() }
        .onDisappear {
            autoAdvanceTimer?.invalidate()
            autoAdvanceTimer = nil
        }
    }

    private func startAutoAdvance() {
        autoAdvanceTimer?.invalidate()
        guard videos.count > 1 else { return }
        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                currentPage = (currentPage + 1) % videos.count
            }
        }
    }

    private func bannerCard(for video: Movie.Video) -> some View {
        ZStack(alignment: .bottomLeading) {
            // 背景：海报铺满 + 底部渐变压暗
            CachedAsyncImage(url: URL.posterURL(from: video.pic)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                LinearGradient(
                    colors: [Color.orange.opacity(0.25), Color.red.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.88), .black.opacity(0.30), .clear],
                startPoint: .bottom,
                endPoint: .center
            )

            // 文案区
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(video.name)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if !video.note.isEmpty {
                            Text(video.note)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange))
                        }
                        if !video.year.isEmpty {
                            Text(video.year)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        if !video.type.isEmpty {
                            Text(video.type)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.4), radius: 6)
            }
            .padding(16)
        }
        .contentShape(Rectangle())
    }
}

