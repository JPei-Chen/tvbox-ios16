import Foundation
import Combine

/// 源站浏览页 ViewModel：手动选择数据源，直接浏览该源的分类与内容列表。
/// 对应 TVBox Android 版「切换源后浏览分类」的能力，区别于详情页的「换源搜索」。
@MainActor
class SourceBrowserViewModel: ObservableObject {
    /// 配置内的全部源站列表。
    @Published var sources: [SourceBean] = []
    /// 当前浏览的源站。
    @Published var selectedSource: SourceBean?
    /// 当前源站的分类列表（含本地注入的「推荐」分类）。
    @Published var sorts: [MovieSort.SortData] = []
    /// 当前选中的分类。
    @Published var selectedSort: MovieSort.SortData?
    /// 「推荐」分类内容（来自 getSort 的首页推荐）。
    @Published var homeVideos: [Movie.Video] = []
    /// 普通分类内容（分页加载）。
    @Published var videos: [Movie.Video] = []
    /// 首次加载（源/分类切换）进行中。
    @Published var isLoading = false
    /// 翻页加载进行中。
    @Published var isLoadingMore = false
    /// 当前分类页码。
    @Published var currentPage = 1
    /// 是否还有下一页。
    @Published var hasMore = true
    /// 错误提示。
    @Published var errorMessage: String?
    /// 当前源是否为主页源（用于「设为主页源」按钮状态）。
    @Published var isHomeSource = false

    /// 网格实际展示的列表：推荐分类展示 homeVideos，其余展示 videos。
    var displayVideos: [Movie.Video] {
        selectedSort?.id == "home" ? homeVideos : videos
    }

    private let sourceService = SourceService.shared
    /// 加载令牌：源切换后丢弃旧请求结果。
    private var loadToken = UUID()

    /// 从全局配置读取源站列表，默认选中当前主页源。
    func loadSources() {
        sources = ApiConfig.shared.sourceBeanList
        let savedKey = UserDefaults.standard.string(forKey: HawkConfig.HOME_API)
        let current = sources.first(where: { $0.key == savedKey })
            ?? ApiConfig.shared.homeSourceBean
            ?? sources.first(where: { $0.isSupportedInSwift })
            ?? sources.first
        selectedSource = current
        refreshHomeSourceFlag()
    }

    /// 首次进入页面时加载选中源的内容。
    func loadInitialContent() async {
        guard let source = selectedSource else { return }
        await selectSource(source, force: true)
    }

    /// 切换源站：重置状态并加载该源分类（推荐为空时自动拉第一个分类的第一页）。
    func selectSource(_ source: SourceBean, force: Bool = false) async {
        if !force, source.key == selectedSource?.key, !sorts.isEmpty { return }

        loadToken = UUID()
        let token = loadToken
        selectedSource = source
        sorts = []
        selectedSort = nil
        homeVideos = []
        videos = []
        currentPage = 1
        hasMore = true
        errorMessage = nil
        refreshHomeSourceFlag()

        guard source.isSupportedInSwift else {
            errorMessage = "暂不支持 JAR/蜘蛛类型源（\(source.typeDescription)），请选择其他源"
            return
        }
        guard source.isHttpApi else {
            errorMessage = "该源接口地址无效，请选择其他源"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await sourceService.getSort(sourceBean: source)
            guard token == loadToken else { return }

            var allSorts = [MovieSort.SortData.home()]
            allSorts.append(contentsOf: result.sorts)
            sorts = allSorts
            homeVideos = result.homeVideos

            // 推荐内容为空时自动落到第一个可用分类，并直接拉取其第一页，
            // 避免先闪一下「暂无内容」再出列表。
            if result.homeVideos.isEmpty, allSorts.count > 1 {
                selectedSort = allSorts[1]
            } else {
                selectedSort = allSorts.first
            }

            if let sort = selectedSort, sort.id != "home" {
                let list = try await sourceService.getList(sourceBean: source, sortData: sort, page: 1)
                guard token == loadToken, selectedSort?.id == sort.id else { return }
                videos = list
                currentPage = 1
                hasMore = !list.isEmpty
            }
        } catch {
            guard token == loadToken else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// 切换分类。
    func selectSort(_ sort: MovieSort.SortData) async {
        guard sort.id != selectedSort?.id else { return }
        loadToken = UUID()
        let token = loadToken
        selectedSort = sort
        videos = []
        currentPage = 1
        hasMore = true
        errorMessage = nil

        guard sort.id != "home" else { return }
        isLoading = true
        defer { isLoading = false }
        await loadVideos(page: 1, sort: sort, token: token)
    }

    /// 滚动到最后一个卡片时加载下一页。
    func loadMoreIfNeeded(currentItem: Movie.Video) async {
        guard let sort = selectedSort, sort.id != "home" else { return }
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard videos.last?.id == currentItem.id else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        await loadVideos(page: currentPage + 1, sort: sort, token: loadToken)
    }

    /// 将当前浏览的源设为主页源（首页推荐内容随之切换）。
    func setAsHomeSource() {
        guard let source = selectedSource else { return }
        ApiConfig.shared.setHomeSource(source)
        refreshHomeSourceFlag()
    }

    private func loadVideos(page: Int, sort: MovieSort.SortData, token: UUID) async {
        guard let source = selectedSource else { return }

        do {
            let list = try await sourceService.getList(sourceBean: source, sortData: sort, page: page)
            guard token == loadToken, selectedSort?.id == sort.id else { return }

            if page == 1 {
                videos = list
            } else {
                videos.append(contentsOf: list)
            }
            currentPage = page
            hasMore = !list.isEmpty
        } catch {
            guard token == loadToken, selectedSort?.id == sort.id else { return }
            if page == 1 {
                videos = []
            }
            errorMessage = error.localizedDescription
        }
    }

    private func refreshHomeSourceFlag() {
        isHomeSource = selectedSource?.key == UserDefaults.standard.string(forKey: HawkConfig.HOME_API)
    }
}
