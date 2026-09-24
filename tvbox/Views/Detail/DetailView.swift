import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 详情页 - 对应 Android 版 DetailActivity
struct DetailView: View {
    let video: Movie.Video
    @StateObject private var viewModel = DetailViewModel()
    @StateObject private var sharedSystemController = SystemPlayerSessionController()
    @StateObject private var sharedVLCController = VLCPlayerController()
    @EnvironmentObject var appState: AppState
    @State private var showFullScreen = false
    /// VLC 全屏退出动画期间为 true，防止内联播放器与全屏播放器同时争抢 drawable
    @State private var isFullScreenDismissing = false
    #if os(macOS)
    @State private var pendingMacWindowFullScreen = false
    #endif
    @State private var lastPersistedProgress: Double = 0
    @State private var isCollected = false
    /// 换源后的当前视频（nil 表示仍使用初始传入的视频）。
    @State private var switchedVideo: Movie.Video?
    /// 换源源站选择弹窗。
    @State private var showSourceSwitcher = false
    /// 换源搜索进行中。
    @State private var isSwitchingSource = false
    /// 换源失败提示。
    @State private var sourceSwitchMessage: String?

    /// 当前展示的视频：换源成功后指向新源站条目，否则为初始视频。
    private var displayVideo: Movie.Video { switchedVideo ?? video }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 播放器区域
                if !showFullScreen, !isFullScreenDismissing, viewModel.isPlaying, let url = viewModel.playUrl {
                    PlayerView(
                        urlString: url,
                        startPosition: viewModel.currentPlaybackSeconds(),
                        onProgressChanged: handlePlaybackProgress,
                        onPlaybackEnded: playNextEpisodeIfNeeded,
                        onToggleFullScreen: {
                            openFullScreenPlayer()
                        },
                        canPlayNext: canPlayNextEpisode,
                        onPlayNext: playNextEpisodeIfNeeded,
                        systemController: sharedSystemController,
                        vlcController: sharedVLCController
                    )
                        .id("\(viewModel.selectedFlag)-\(viewModel.selectedEpisodeIndex)-\(url)")
                        .aspectRatio(16/9, contentMode: .fit)
                        .background(Color.black)
                        .onTapGesture(count: 2) {
                            openFullScreenPlayer()
                        }
                }
                
                // 视频信息
                videoInfoSection
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                
                // 线路选择
                if viewModel.flags.count > 1 {
                    flagSelector
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }
                
                // 清晰度选择
                if viewModel.hasQualityChoices {
                    qualitySelector
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }
                
                // 剧集列表
                if !viewModel.currentEpisodes.isEmpty {
                    episodeSection
                        .padding(.top, 16)
                }
                
                // 简介
                if let info = viewModel.vodInfo, !info.des.isEmpty {
                    descriptionSection(info.des)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .background(AppTheme.primaryGradient)
        .navigationTitle(displayVideo.name)
        #if os(macOS)
        .toolbar((showFullScreen || pendingMacWindowFullScreen) ? .hidden : .visible, for: .windowToolbar)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sourceSwitchMessage = nil
                    showSourceSwitcher = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right.square")
                        Text(isSwitchingSource ? "搜索中..." : "换源")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
                }
                .disabled(isSwitchingSource)
            }
        }
        #endif
        .task(id: "\(displayVideo.sourceKey)-\(displayVideo.id)") {
            await viewModel.loadDetail(video: displayVideo)
            restorePlaybackFromHistory()
            refreshCollectState()
        }
        .onDisappear {
            viewModel.commitPlaybackProgressSnapshot()
            persistHistoryIfNeeded(force: true)
            showFullScreen = false
            sharedSystemController.stop()
            sharedVLCController.stop()
            #if os(macOS)
            pendingMacWindowFullScreen = false
            appState.exitPlayerFullScreen()
            #endif
        }
        #if os(macOS)
        .overlay {
            if showFullScreen, let url = viewModel.playUrl {
                FullScreenPlayerView(
                    urlString: url,
                    startPosition: viewModel.currentPlaybackSeconds(),
                    onProgressChanged: handlePlaybackProgress,
                    onPlaybackEnded: playNextEpisodeIfNeeded,
                    canPlayNext: canPlayNextEpisode,
                    onPlayNext: playNextEpisodeIfNeeded,
                    systemController: sharedSystemController,
                    vlcController: sharedVLCController,
                    onCloseRequested: closeMacFullScreenOverlay,
                    title: fullscreenTitle
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            guard pendingMacWindowFullScreen else { return }
            pendingMacWindowFullScreen = false
            showFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            pendingMacWindowFullScreen = false
            if showFullScreen {
                showFullScreen = false
            }
            appState.exitPlayerFullScreen()
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullScreen, onDismiss: {
            isFullScreenDismissing = false
        }) {
            if let url = viewModel.playUrl {
                FullScreenPlayerView(
                    urlString: url,
                    startPosition: viewModel.currentPlaybackSeconds(),
                    onProgressChanged: handlePlaybackProgress,
                    onPlaybackEnded: playNextEpisodeIfNeeded,
                    canPlayNext: canPlayNextEpisode,
                    onPlayNext: playNextEpisodeIfNeeded,
                    systemController: sharedSystemController,
                    vlcController: sharedVLCController,
                    onCloseRequested: {
                        isFullScreenDismissing = true
                        showFullScreen = false
                    },
                    title: fullscreenTitle
                )
            }
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showSourceSwitcher) {
            sourceSwitcherSheet
        }
        #endif
    }

    // MARK: - 换源

    /// 换源源站选择弹窗：列出配置内所有可用源站，点击后在该站搜索当前片名并切换。
    private var sourceSwitcherSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ApiConfig.shared.sourceBeanList.filter { $0.isSupportedInSwift && $0.key != displayVideo.sourceKey }) { source in
                        Button {
                            Task { await switchToSource(source) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white)
                                    Text(source.key)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                                Spacer()
                                if isSwitchingSource {
                                    ProgressView()
                                        .tint(.orange)
                                }
                            }
                        }
                        .disabled(isSwitchingSource)
                    }
                } header: {
                    Text("在以下源站搜索「\(displayVideo.name)」")
                } footer: {
                    if let message = sourceSwitchMessage {
                        Text(message)
                            .foregroundColor(.orange)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.08, green: 0.08, blue: 0.1))
            .navigationTitle("切换源站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showSourceSwitcher = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// 在目标源站搜索当前片名并切换到最佳匹配结果。
    private func switchToSource(_ source: SourceBean) async {
        guard !isSwitchingSource else { return }
        isSwitchingSource = true
        defer { isSwitchingSource = false }

        do {
            let results = try await SourceService.shared.search(sourceBean: source, keyword: displayVideo.name)
            let exact = results.first(where: { $0.name == displayVideo.name })
            if let target = exact ?? results.first {
                showSourceSwitcher = false
                switchedVideo = target
                sourceSwitchMessage = nil
            } else {
                sourceSwitchMessage = "「\(source.name)」没有找到「\(displayVideo.name)」"
            }
        } catch {
            sourceSwitchMessage = "搜索失败：\(error.localizedDescription)"
        }
    }
    
    #if os(iOS)
    @ViewBuilder
    private var videoInfoSection: some View {
        VStack(spacing: 16) {
            // Poster centered, height capped to 30% of screen
            let posterHeight = UIScreen.main.bounds.height * 0.30
            CachedAsyncImage(url: URL.posterURL(from: displayVideo.pic)) { image in
                image.resizable().aspectRatio(2/3, contentMode: .fit)
            } placeholder: {
                Color.white.opacity(0.05)
                    .aspectRatio(2/3, contentMode: .fit)
            }
            .frame(maxHeight: posterHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))

            // Info below poster
            videoDetails

            // Action buttons with 48pt height
            HStack(spacing: 12) {
                playButton
                collectButton
            }
            .frame(minHeight: 48)
        }
        .padding(15)
        .glassCard(cornerRadius: AppTheme.glassRadius)
    }
    #else
    @ViewBuilder
    private var videoInfoSection: some View {
        HStack(alignment: .top, spacing: 20) {
            videoPoster
            
            videoDetails
            
            Spacer()
        }
        .padding(15)
        .glassCard(cornerRadius: AppTheme.glassRadius)
    }
    #endif

    @ViewBuilder
    private var videoPoster: some View {
        CachedAsyncImage(url: URL.posterURL(from: displayVideo.pic)) { image in
            image.resizable().aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            ZStack {
                Color.white.opacity(0.05)
                Image(systemName: "film.fill").foregroundColor(.white.opacity(0.2))
            }
            .aspectRatio(2/3, contentMode: .fill)
        }
        .frame(width: 130)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
    }

    @ViewBuilder
    private var videoDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.vodInfo?.name ?? displayVideo.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            if let info = viewModel.vodInfo {
                VStack(alignment: .leading, spacing: 6) {
                    infoRow("年份", info.year)
                    infoRow("地区", info.area)
                    infoRow("类型", info.typeName)
                    infoRow("导演", info.director)
                    infoRow("演员", info.actor)
                }
            }
            
            #if os(macOS)
            Spacer(minLength: 10)
            
            HStack(spacing: 10) {
                playButton
                collectButton
            }
            #endif
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if !viewModel.isPlaying && viewModel.vodInfo != nil {
            Button {
                viewModel.selectEpisode(index: 0)
                saveHistoryForCurrentEpisode()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("立即播放")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(AppTheme.accentGradient)
                .clipShape(Capsule())
                .shadow(color: .red.opacity(0.4), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var collectButton: some View {
        Button {
            toggleCollect()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCollected ? "heart.fill" : "heart")
                Text(isCollected ? "已收藏" : "收藏")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Group {
                    if isCollected {
                        AppTheme.accentGradient
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isCollected ? 0 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(width: 36, alignment: .leading)
                Text(value)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
            }
        }
    }
    
    // MARK: - 线路选择
    
    @ViewBuilder
    private var flagSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放线路")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            flagScrollView
        }
        .padding(15)
        .glassCard(cornerRadius: AppTheme.glassRadius)
    }

    @ViewBuilder
    private var flagScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.flags, id: \.self) { flag in
                    flagButton(flag)
                }
            }
        }
    }

    @ViewBuilder
    private func flagButton(_ flag: String) -> some View {
        Button {
            withAnimation {
                viewModel.selectFlag(flag)
            }
            if viewModel.isPlaying {
                saveHistoryForCurrentEpisode()
            }
        } label: {
            Text(flag)
                .font(.system(size: 14, weight: viewModel.selectedFlag == flag ? .bold : .medium))
                .foregroundColor(viewModel.selectedFlag == flag ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if viewModel.selectedFlag == flag {
                            AppTheme.accentGradient
                        } else {
                            Color.white.opacity(0.05)
                        }
                    }
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 清晰度选择
    
    @ViewBuilder
    private var qualitySelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("视频清晰度")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.qualityOptions) { option in
                        qualityButton(option)
                    }
                }
            }
        }
        .padding(15)
        .glassCard(cornerRadius: AppTheme.glassRadius)
    }
    
    @ViewBuilder
    private func qualityButton(_ option: PlaybackQualityOption) -> some View {
        Button {
            withAnimation {
                viewModel.selectQuality(option)
            }
            if viewModel.isPlaying {
                saveHistoryForCurrentEpisode()
            }
        } label: {
            Text(option.name)
                .font(.system(size: 14, weight: viewModel.selectedQualityId == option.id ? .bold : .medium))
                .foregroundColor(viewModel.selectedQualityId == option.id ? .white : .white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if viewModel.selectedQualityId == option.id {
                            AppTheme.accentGradient
                        } else {
                            Color.white.opacity(0.05)
                        }
                    }
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 剧集列表
    
    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选集播放")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
            
            EpisodeListView(
                episodes: viewModel.currentEpisodes,
                selectedIndex: viewModel.selectedEpisodeIndex,
                onSelect: { index in
                    withAnimation {
                        viewModel.selectEpisode(index: index)
                    }
                    saveHistoryForCurrentEpisode()
                }
            )
        }
    }
    
    // MARK: - 简介
    
    private func descriptionSection(_ des: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("影片简介")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text(des)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .lineSpacing(4)
                .lineLimit(nil)
        }
        .padding(15)
        .glassCard(cornerRadius: AppTheme.glassRadius)
    }

    private var canPlayNextEpisode: Bool {
        viewModel.selectedEpisodeIndex + 1 < viewModel.currentEpisodes.count
    }
    
    private func saveHistoryForCurrentEpisode(progressOverride: Double? = nil) {
        let episodeName = viewModel.vodInfo?.currentEpisode?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let episodeLabel = episodeName.isEmpty ? "第\(viewModel.selectedEpisodeIndex + 1)集" : episodeName
        let progress = max(progressOverride ?? viewModel.currentPlaybackSeconds(), 0)
        let timeLabel = progress > 0 ? Int(progress).durationString : ""
        let playNote = timeLabel.isEmpty ? episodeLabel : "\(episodeLabel) \(timeLabel)"
        
        let playbackState = VodPlaybackState(
            flag: viewModel.selectedFlag,
            episodeIndex: viewModel.selectedEpisodeIndex,
            progressSeconds: progress
        )
        
        Task { @MainActor in
            CacheStore.shared.addRecord(
                displayVideo,
                playNote: playNote,
                playbackState: playbackState
            )
        }
    }
    
    private func handlePlaybackProgress(_ seconds: Double, _: Double?) {
        viewModel.updatePlaybackProgress(seconds: seconds)
        persistHistoryIfNeeded(force: false, currentProgress: seconds)
    }
    
    private func persistHistoryIfNeeded(force: Bool, currentProgress: Double? = nil) {
        guard viewModel.isPlaying else { return }
        let progress = max(currentProgress ?? viewModel.currentPlaybackSeconds(), 0)
        guard progress.isFinite else { return }
        
        if !force && abs(progress - lastPersistedProgress) < 20 {
            return
        }
        
        lastPersistedProgress = progress
        saveHistoryForCurrentEpisode(progressOverride: progress)
    }
    
    private func restorePlaybackFromHistory() {
        guard let playbackState = CacheStore.shared.getPlaybackState(
            vodId: displayVideo.id,
            sourceKey: displayVideo.sourceKey
        ) else { return }
        
        viewModel.applyPlaybackState(playbackState)
        lastPersistedProgress = max(playbackState.progressSeconds, 0)
    }
    
    private func refreshCollectState() {
        isCollected = CacheStore.shared.isCollected(
            vodId: displayVideo.id,
            sourceKey: displayVideo.sourceKey
        )
    }
    
    private func toggleCollect() {
        if isCollected {
            CacheStore.shared.removeCollect(
                vodId: displayVideo.id,
                sourceKey: displayVideo.sourceKey
            )
        } else {
            CacheStore.shared.addCollect(displayVideo)
        }
        refreshCollectState()
    }
    
    private func playNextEpisodeIfNeeded() {
        var moved = false
        withAnimation {
            moved = viewModel.playNext()
        }
        
        if moved {
            saveHistoryForCurrentEpisode()
        }
    }
    
    /// 全屏播放器顶部标题：当前剧集名，取不到时回退片名。
    private var fullscreenTitle: String {
        let episodes = viewModel.currentEpisodes
        let index = viewModel.selectedEpisodeIndex
        if episodes.indices.contains(index) {
            let name = episodes[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                return name
            }
        }
        return displayVideo.name
    }

    private func openFullScreenPlayer() {
        #if os(iOS)
        // 全屏呈现后由 FullScreenPlayerView 内部处理旋转：
        // 先请求系统转横屏，被拒绝时自动启用"内容旋转 90°"的兜底布局。
        showFullScreen = true
        #else
        guard viewModel.playUrl != nil else { return }
        appState.enterPlayerFullScreen()
        
        if let window = NSApp.keyWindow ?? NSApp.mainWindow,
           window.styleMask.contains(.fullScreen) {
            showFullScreen = true
            return
        }
        
        pendingMacWindowFullScreen = requestMacWindowFullScreen(enter: true)
        if !pendingMacWindowFullScreen {
            showFullScreen = true
        }
        #endif
    }
    
    #if os(macOS)
    @discardableResult
    private func requestMacWindowFullScreen(enter: Bool) -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        guard enter != isFullScreen else { return false }
        window.toggleFullScreen(nil)
        return true
    }
    
    private func closeMacFullScreenOverlay() {
        pendingMacWindowFullScreen = false
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if window?.styleMask.contains(.fullScreen) == true {
            requestMacWindowFullScreen(enter: false)
            return
        }
        showFullScreen = false
        appState.exitPlayerFullScreen()
    }
    #endif
}

/// 全屏播放器
///
/// 横屏策略（双保险）：
/// 1. 呈现后用 requestGeometryUpdate 请求系统转到横屏（未开竖排锁时自动横屏）；
/// 2. 若系统拒绝旋转（如控制中心竖排方向锁定开启），则把播放器内容旋转 90°
///    铺满竖屏画面——用户横持手机即为标准横屏效果，保证任何情况下都能"全屏"。
struct FullScreenPlayerView: View {
    let urlString: String
    var startPosition: Double = 0
    var onProgressChanged: ((Double, Double?) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil
    var canPlayNext: Bool = false
    var onPlayNext: (() -> Void)? = nil
    var systemController: SystemPlayerSessionController? = nil
    var vlcController: VLCPlayerController? = nil
    var onCloseRequested: (() -> Void)? = nil
    /// 顶部标题（如「第3集」）。
    var title: String = ""
    @Environment(\.dismiss) private var dismiss
    /// 当前界面方向是否已是横屏（决定是否使用旋转兜底布局）。
    @State private var isLandscapeInterface = false

    var body: some View {
        #if os(iOS)
        fullScreenBody
            .onAppear {
                refreshInterfaceOrientation()
                Self.requestOrientation(.landscapeRight)
                // 稍后复查一次：若系统已转横屏，切换到原生横屏布局。
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    refreshInterfaceOrientation()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                refreshInterfaceOrientation()
            }
            .onDisappear {
                Self.requestOrientation(.portrait)
            }
        #else
        ZStack {
            Color.black.ignoresSafeArea()
            playerContent
        }
        .ignoresSafeArea()
        #endif
    }

    private var playerContent: some View {
        PlayerView(
            urlString: urlString,
            startPosition: startPosition,
            onProgressChanged: onProgressChanged,
            onPlaybackEnded: onPlaybackEnded,
            onToggleFullScreen: {
                if let onCloseRequested {
                    onCloseRequested()
                } else {
                    dismiss()
                }
            },
            canPlayNext: canPlayNext,
            onPlayNext: onPlayNext,
            systemController: systemController,
            vlcController: vlcController,
            isFullScreenPresentation: true,
            fullScreenTitle: title.isEmpty ? "播放中" : title
        )
    }

    #if os(iOS)
    @ViewBuilder
    private var fullScreenBody: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if isLandscapeInterface {
                    // 系统已转横屏：原生铺满。
                    playerContent
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    // 竖屏兜底：内容旋转 90°，宽高互换铺满整屏。
                    playerContent
                        .frame(width: geo.size.height, height: geo.size.width)
                        .rotationEffect(.degrees(90))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .ignoresSafeArea()
        }
        .statusBarHidden(true)
    }

    private func refreshInterfaceOrientation() {
        switch Self.currentInterfaceOrientation() {
        case .landscapeLeft, .landscapeRight:
            isLandscapeInterface = true
        default:
            isLandscapeInterface = false
        }
    }

    private static func currentInterfaceOrientation() -> UIInterfaceOrientation? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation
    }

    /// 请求系统切换到目标方向（尽力而为；被拒绝时由竖屏兜底布局接管）。
    @MainActor
    static func requestOrientation(_ target: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target))
            scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        }
    }
    #endif
}
