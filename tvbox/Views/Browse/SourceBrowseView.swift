import SwiftUI

/// 资源库页：选择任意源站，浏览其分类与影片列表。
/// 首页保持「继续观看 + 热门榜单」精简形态，本页承接原首页的"选源看内容"能力。
struct SourceBrowseView: View {
    @StateObject private var viewModel = SourceBrowseViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sourceChipRow
                    categoryChipRow
                    contentArea
                }
                .padding(.bottom, 30)
            }
            .background(AppTheme.primaryGradient.ignoresSafeArea())
            .navigationDestination(for: Movie.Video.self) { video in
                DetailView(video: video)
            }
        }
        .task { await viewModel.initializeIfNeeded() }
        .refreshable { await viewModel.refresh() }
    }

    // MARK: - 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.orange)
                Text("资源库")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.orange)
                }
            }
            Text("切换源站浏览全部影片")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 源站选择

    private var sourceChipRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("源站")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.sources) { source in
                        Button {
                            HapticManager.shared.selection()
                            viewModel.selectSource(source)
                        } label: {
                            chipLabel(
                                title: source.name,
                                isSelected: viewModel.selectedSource?.key == source.key
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - 分类选择

    @ViewBuilder
    private var categoryChipRow: some View {
        if !viewModel.sorts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("分类")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.sorts) { sort in
                            Button {
                                HapticManager.shared.selection()
                                viewModel.selectSort(sort)
                            } label: {
                                chipLabel(
                                    title: sort.name,
                                    isSelected: viewModel.selectedSort?.id == sort.id,
                                    compact: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    /// 胶囊按钮样式：选中态橙色渐变，未选中态半透明深色。
    private func chipLabel(title: String, isSelected: Bool, compact: Bool = false) -> some View {
        Text(title)
            .font(.system(size: compact ? 12 : 13, weight: isSelected ? .bold : .medium))
            .foregroundColor(isSelected ? .white : .white.opacity(0.65))
            .padding(.horizontal, compact ? 12 : 14)
            .padding(.vertical, compact ? 7 : 9)
            .background(
                isSelected
                    ? AnyShapeStyle(AppTheme.accentGradient)
                    : AnyShapeStyle(Color.white.opacity(0.07))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(isSelected ? 0 : 0.12), lineWidth: 0.5)
            )
    }

    // MARK: - 内容区

    @ViewBuilder
    private var contentArea: some View {
        if let message = viewModel.errorMessage, viewModel.videos.isEmpty {
            errorCard(message)
        } else if viewModel.videos.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if let sort = viewModel.selectedSort {
                    Text(sort.id == "home" ? "推荐内容" : sort.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.videos) { video in
                        NavigationLink(value: video) {
                            VodCardView(video: video)
                        }
                        #if os(iOS)
                        .buttonStyle(VodCardPressStyle())
                        #else
                        .buttonStyle(.plain)
                        #endif
                        .onAppear {
                            if video.id == viewModel.videos.last?.id {
                                Task { await viewModel.loadMoreIfNeeded(currentItem: video) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                if viewModel.isLoading && !viewModel.videos.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.orange)
                            .padding(.vertical, 16)
                        Spacer()
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12)
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 34))
                .foregroundColor(.white.opacity(0.25))
            Text("这个源暂无内容，换个分类或源站试试")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - ViewModel

/// 资源库页 ViewModel：按源站加载分类与分页影片列表。
@MainActor
class SourceBrowseViewModel: ObservableObject {
    /// 可选源站列表（仅含本 App 支持的 HTTP 接口源）。
    @Published var sources: [SourceBean] = []
    /// 当前选中源站。
    @Published var selectedSource: SourceBean?
    /// 当前源站的分类列表（首位为本地"推荐"）。
    @Published var sorts: [MovieSort.SortData] = []
    /// 当前选中分类。
    @Published var selectedSort: MovieSort.SortData?
    /// 影片列表。
    @Published var videos: [Movie.Video] = []
    /// 加载状态。
    @Published var isLoading = false
    /// 错误提示。
    @Published var errorMessage: String?

    private var currentPage = 1
    private var hasMore = true
    /// 请求代际标记：切源/切分类后丢弃旧请求结果，防止过期数据覆盖。
    private var loadGeneration = UUID()

    func initializeIfNeeded() async {
        guard sources.isEmpty else { return }
        sources = ApiConfig.shared.sourceBeanList.filter { $0.isSupportedInSwift && $0.isHttpApi }
        if let home = ApiConfig.shared.homeSourceBean,
           sources.contains(where: { $0.key == home.key }) {
            selectedSource = home
        } else {
            selectedSource = sources.first
        }
        await loadSource()
    }

    func refresh() async {
        guard selectedSource != nil else { return }
        await loadSource()
    }

    func selectSource(_ source: SourceBean) {
        guard source.key != selectedSource?.key else { return }
        selectedSource = source
        sorts = [MovieSort.SortData.home()]
        selectedSort = sorts.first
        videos = []
        errorMessage = nil
        Task { await loadSource() }
    }

    func selectSort(_ sort: MovieSort.SortData) {
        guard sort.id != selectedSort?.id else { return }
        selectedSort = sort
        videos = []
        errorMessage = nil
        if sort.id == "home" {
            Task { await loadSource() }
        } else {
            Task { await loadCategory(sort, page: 1) }
        }
    }

    func loadMoreIfNeeded(currentItem: Movie.Video) async {
        guard hasMore, !isLoading, currentItem.id == videos.last?.id,
              let sort = selectedSort, sort.id != "home" else { return }
        await loadCategory(sort, page: currentPage + 1)
    }

    /// 加载当前源的推荐内容与分类列表。
    private func loadSource() async {
        guard let source = selectedSource else { return }
        let gen = UUID()
        loadGeneration = gen
        isLoading = true
        defer { if loadGeneration == gen { isLoading = false } }

        do {
            let result = try await SourceService.shared.getSort(sourceBean: source)
            guard loadGeneration == gen else { return }
            var all = [MovieSort.SortData.home()]
            all.append(contentsOf: result.sorts)
            sorts = all
            selectedSort = all.first
            videos = result.homeVideos
            currentPage = 1
            hasMore = false
            errorMessage = nil
        } catch {
            guard loadGeneration == gen else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// 分页加载分类影片。
    private func loadCategory(_ sort: MovieSort.SortData, page: Int) async {
        guard let source = selectedSource else { return }
        let gen = UUID()
        loadGeneration = gen
        isLoading = true
        defer { if loadGeneration == gen { isLoading = false } }

        do {
            let list = try await SourceService.shared.getList(sourceBean: source, sortData: sort, page: page)
            guard loadGeneration == gen, selectedSort?.id == sort.id else { return }
            if page == 1 {
                videos = list
            } else {
                videos.append(contentsOf: list)
            }
            currentPage = page
            hasMore = !list.isEmpty
            errorMessage = nil
        } catch {
            guard loadGeneration == gen else { return }
            errorMessage = error.localizedDescription
        }
    }
}
