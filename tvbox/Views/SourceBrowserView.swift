import SwiftUI

/// 源站浏览页：手动选择数据源，直接浏览该源的分类与内容。
/// 注意：本视图不内嵌 NavigationStack —— 作为标签页使用时由 ContentView 包裹导航栈，
/// 从首页推入时复用首页导航栈；详情跳转依赖外层注册的 navigationDestination。
struct SourceBrowserView: View {
    @StateObject private var viewModel = SourceBrowserViewModel()
    @EnvironmentObject var appState: AppState

    #if os(iOS)
    /// iOS 内容网格参数。
    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 12)]
    #else
    /// macOS 内容网格参数。
    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 168), spacing: 16)]
    #endif

    var body: some View {
        VStack(spacing: 0) {
            sourceBar
            sortBar
            contentArea
        }
        .background(AppTheme.primaryGradient.ignoresSafeArea())
        .navigationTitle("源站")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                setHomeSourceButton
            }
        }
        .task {
            viewModel.loadSources()
            await viewModel.loadInitialContent()
        }
    }

    /// 将当前浏览的源设为主页源，首页「推荐」内容随之切换。
    private var setHomeSourceButton: some View {
        Button {
            viewModel.setAsHomeSource()
            appState.currentSourceKey = viewModel.selectedSource?.key ?? appState.currentSourceKey
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.isHomeSource ? "star.fill" : "star")
                Text(viewModel.isHomeSource ? "主页源" : "设为主页")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(viewModel.isHomeSource ? .orange : .white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(
                Capsule().stroke(
                    viewModel.isHomeSource ? Color.orange.opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedSource == nil)
    }

    // MARK: - 源站选择

    private var sourceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.sources) { source in
                    sourceChip(source)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .padding(.top, 12)
    }

    private func sourceChip(_ source: SourceBean) -> some View {
        let isSelected = source.key == viewModel.selectedSource?.key
        return Button {
            Task { await viewModel.selectSource(source) }
        } label: {
            HStack(spacing: 6) {
                Text(source.name)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                    .lineLimit(1)

                if !source.isSupportedInSwift {
                    Text("JAR")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.gray.opacity(0.4)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if isSelected {
                        AppTheme.accentGradient
                    } else {
                        Color.white.opacity(0.06)
                    }
                }
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分类选择

    @ViewBuilder
    private var sortBar: some View {
        if !viewModel.sorts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.sorts) { sort in
                        sortChip(sort)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .padding(.top, 8)
        }
    }

    private func sortChip(_ sort: MovieSort.SortData) -> some View {
        let isSelected = sort.id == viewModel.selectedSort?.id
        return Button {
            Task { await viewModel.selectSort(sort) }
        } label: {
            Text(sort.name)
                .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.white.opacity(0.06)))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 内容区域

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isLoading && viewModel.displayVideos.isEmpty {
            loadingState
        } else if let error = viewModel.errorMessage, viewModel.displayVideos.isEmpty {
            errorState(error)
        } else if viewModel.displayVideos.isEmpty {
            emptyState
        } else {
            videoGrid
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(.orange)
            Text("正在加载「\(viewModel.selectedSource?.name ?? "")」...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.yellow.opacity(0.85))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            Button {
                Task {
                    if let source = viewModel.selectedSource {
                        await viewModel.selectSource(source, force: true)
                    }
                }
            } label: {
                Text("重试")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(AppTheme.accentGradient)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "film")
                .font(.system(size: 34))
                .foregroundColor(.white.opacity(0.25))
            Text("该源暂无内容，换个分类或源站试试")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(viewModel.displayVideos.enumerated()), id: \.1.id) { index, video in
                    NavigationLink(value: video) {
                        VodCardView(video: video)
                    }
                    #if os(iOS)
                    .buttonStyle(VodCardPressStyle())
                    #else
                    .buttonStyle(.plain)
                    #endif
                    .onAppear {
                        if index >= viewModel.displayVideos.count - 4 {
                            Task { await viewModel.loadMoreIfNeeded(currentItem: video) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)

            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(.orange)
                    .padding(.bottom, 20)
            }
        }
    }
}
