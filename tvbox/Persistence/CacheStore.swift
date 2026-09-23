import Foundation
import Combine

/// 本地持久化层。
///
/// 说明：本文件已从 SwiftData（iOS 17+）改写为基于 JSON 文件的实现，
/// 以便在 iOS 16.x 上运行。对外的业务方法与原本保持一致，仅去掉了
/// `ModelContext` 参数（调用方无需再传入上下文）。
///
/// 数据落盘位置：`Application Support/TVBoxCacheStore/*.json`

/// 收藏/历史的业务唯一键（source + vodId）。
private func makeVodBusinessKey(vodId: String, sourceKey: String) -> String {
    let normalizedVodId = vodId.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedSourceKey = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(normalizedSourceKey)::\(normalizedVodId)"
}

/// 单部剧的续播状态
struct VodPlaybackState: Codable, Equatable {
    /// 当前播放线路标识。
    var flag: String
    /// 剧集索引。
    var episodeIndex: Int
    /// 播放进度（秒）。
    var progressSeconds: Double
}

/// 视频收藏
struct VodCollect: Codable, Identifiable, Equatable {
    /// 业务唯一键（sourceKey + vodId）。
    var bizKey: String = ""
    /// 视频 ID（与 sourceKey 组成唯一语义键）。
    var vodId: String = ""
    /// 片名。
    var vodName: String = ""
    /// 海报地址。
    var vodPic: String = ""
    /// 来源站点 key。
    var sourceKey: String = ""
    /// 最近更新时间（收藏创建/刷新时间）。
    var updateTime: Date = Date()

    /// 列表渲染使用的稳定标识。
    var id: String {
        bizKey.isEmpty ? makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey) : bizKey
    }

    init(vodId: String, vodName: String, vodPic: String, sourceKey: String) {
        self.bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.sourceKey = sourceKey
        self.updateTime = Date()
    }
}

/// 播放历史记录
struct VodRecord: Codable, Identifiable, Equatable {
    /// 业务唯一键（sourceKey + vodId）。
    var bizKey: String = ""
    /// 视频 ID。
    var vodId: String = ""
    /// 片名。
    var vodName: String = ""
    /// 海报地址。
    var vodPic: String = ""
    /// 来源站点 key。
    var sourceKey: String = ""
    /// 播放标记，如“第5集 03:45”。
    var playNote: String = ""
    /// 续播状态 JSON（`VodPlaybackState` 编码结果）。
    var dataJson: String = ""
    /// 最近播放时间。
    var updateTime: Date = Date()

    /// 列表渲染使用的稳定标识。
    var id: String {
        bizKey.isEmpty ? makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey) : bizKey
    }

    init(vodId: String, vodName: String, vodPic: String, sourceKey: String, playNote: String = "") {
        self.bizKey = makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
        self.vodId = vodId
        self.vodName = vodName
        self.vodPic = vodPic
        self.sourceKey = sourceKey
        self.playNote = playNote
        self.updateTime = Date()
    }
}

/// 通用缓存
struct CacheItem: Codable, Identifiable, Equatable {
    /// 唯一缓存键。
    var key: String = ""
    /// 缓存值（字符串形式）。
    var value: String = ""
    /// 更新时间。
    var updateTime: Date = Date()

    var id: String { key }

    init(key: String, value: String) {
        self.key = key
        self.value = value
        self.updateTime = Date()
    }
}

/// 缓存管理器。
///
/// 内存中持有三张表，任何写操作后立即落盘；视图通过 `ObservableObject`
/// 的发布机制自动刷新（收藏页 / 历史页据此实时更新）。
@MainActor
final class CacheStore: ObservableObject {
    static let shared = CacheStore()

    /// 收藏列表（按更新时间倒序）。
    @Published private(set) var collects: [VodCollect] = []
    /// 历史记录列表（按更新时间倒序）。
    @Published private(set) var records: [VodRecord] = []
    /// 通用缓存列表。
    @Published private(set) var cacheItems: [CacheItem] = []

    private let collectsURL: URL
    private let recordsURL: URL
    private let cacheItemsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("TVBoxCacheStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        collectsURL = directory.appendingPathComponent("collects.json")
        recordsURL = directory.appendingPathComponent("records.json")
        cacheItemsURL = directory.appendingPathComponent("cache_items.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        loadFromDisk()
    }

    // MARK: - 磁盘读写

    private func loadFromDisk() {
        collects = read([VodCollect].self, from: collectsURL) ?? []
        records = read([VodRecord].self, from: recordsURL) ?? []
        cacheItems = read([CacheItem].self, from: cacheItemsURL) ?? []
        collects.sort { $0.updateTime > $1.updateTime }
        records.sort { $0.updateTime > $1.updateTime }
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else {
            print("本地持久化编码失败: \(url.lastPathComponent)")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            print("本地持久化写入失败: \(error)")
        }
    }

    private func saveCollects() {
        collects.sort { $0.updateTime > $1.updateTime }
        write(collects, to: collectsURL)
    }

    private func saveRecords() {
        records.sort { $0.updateTime > $1.updateTime }
        write(records, to: recordsURL)
    }

    private func saveCacheItems() {
        write(cacheItems, to: cacheItemsURL)
    }

    // MARK: - 匹配规则

    /// 兼容旧数据的匹配：优先比较业务键，业务键为空时退化为字段比对。
    private func matchesCollect(_ item: VodCollect, vodId: String, sourceKey: String) -> Bool {
        if item.bizKey.isEmpty {
            return item.vodId == vodId && item.sourceKey == sourceKey
        }
        return item.bizKey == makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
    }

    private func matchesRecord(_ item: VodRecord, vodId: String, sourceKey: String) -> Bool {
        if item.bizKey.isEmpty {
            return item.vodId == vodId && item.sourceKey == sourceKey
        }
        return item.bizKey == makeVodBusinessKey(vodId: vodId, sourceKey: sourceKey)
    }

    // MARK: - 收藏

    /// 新增或刷新收藏（同一影片只保留一条，重复项会被清理）。
    func addCollect(_ video: Movie.Video) {
        collects.removeAll { matchesCollect($0, vodId: video.id, sourceKey: video.sourceKey) }
        collects.append(
            VodCollect(
                vodId: video.id,
                vodName: video.name,
                vodPic: video.pic,
                sourceKey: video.sourceKey
            )
        )
        saveCollects()
    }

    /// 按影片标识取消收藏。
    func removeCollect(vodId: String, sourceKey: String) {
        collects.removeAll { matchesCollect($0, vodId: vodId, sourceKey: sourceKey) }
        saveCollects()
    }

    /// 按收藏条目取消收藏（供收藏页列表使用）。
    func removeCollect(_ item: VodCollect) {
        collects.removeAll { $0.id == item.id }
        saveCollects()
    }

    /// 查询某影片是否已收藏。
    func isCollected(vodId: String, sourceKey: String) -> Bool {
        collects.contains { matchesCollect($0, vodId: vodId, sourceKey: sourceKey) }
    }

    // MARK: - 播放历史

    /// 写入或更新播放记录。
    /// - Note: 未传入 `playbackState` 时会保留该记录已有的续播状态。
    func addRecord(
        _ video: Movie.Video,
        playNote: String,
        playbackState: VodPlaybackState? = nil
    ) {
        let encodedState = Self.encodePlaybackState(playbackState)
        let previousStateJson = records
            .first { matchesRecord($0, vodId: video.id, sourceKey: video.sourceKey) }?
            .dataJson

        records.removeAll { matchesRecord($0, vodId: video.id, sourceKey: video.sourceKey) }

        var record = VodRecord(
            vodId: video.id,
            vodName: video.name,
            vodPic: video.pic,
            sourceKey: video.sourceKey,
            playNote: playNote
        )
        if let encodedState {
            record.dataJson = encodedState
        } else if let previousStateJson {
            record.dataJson = previousStateJson
        }
        records.append(record)
        saveRecords()
    }

    /// 读取续播状态（若无记录或 JSON 无法解码则返回 `nil`）。
    func getPlaybackState(vodId: String, sourceKey: String) -> VodPlaybackState? {
        guard let record = records.first(where: {
            matchesRecord($0, vodId: vodId, sourceKey: sourceKey)
        }) else {
            return nil
        }
        return Self.decodePlaybackState(record.dataJson)
    }

    /// 按历史条目删除单条记录（供历史页列表使用）。
    func removeRecord(_ item: VodRecord) {
        records.removeAll { $0.id == item.id }
        saveRecords()
    }

    /// 清空全部播放历史。
    func clearHistory() {
        records.removeAll()
        saveRecords()
    }

    // MARK: - 通用缓存

    func setCache(key: String, value: String) {
        if let index = cacheItems.firstIndex(where: { $0.key == key }) {
            cacheItems[index].value = value
            cacheItems[index].updateTime = Date()
        } else {
            cacheItems.append(CacheItem(key: key, value: value))
        }
        saveCacheItems()
    }

    func getCache(key: String) -> String? {
        cacheItems.first { $0.key == key }?.value
    }

    func removeCache(key: String) {
        cacheItems.removeAll { $0.key == key }
        saveCacheItems()
    }

    func clearCacheItems() {
        cacheItems.removeAll()
        saveCacheItems()
    }

    /// 通用缓存占用的字节数（供设置页展示）。
    func cacheItemsByteCount() -> Int {
        cacheItems.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
    }

    // MARK: - 续播状态编解码

    private static func encodePlaybackState(_ state: VodPlaybackState?) -> String? {
        guard let state else { return nil }
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从 JSON 字符串反序列化续播状态。
    private static func decodePlaybackState(_ json: String) -> VodPlaybackState? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(VodPlaybackState.self, from: data)
    }
}
