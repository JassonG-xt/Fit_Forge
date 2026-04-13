import Foundation
import MediaPlayer

/// 本地音乐库服务（播放用户手机中的音乐）
@MainActor
class LocalMusicService: ObservableObject {
    @Published var isAuthorized = false
    @Published var playlists: [MPMediaPlaylist] = []
    @Published var songs: [MPMediaItem] = []
    @Published var isPlaying = false
    @Published var currentItem: MPMediaItem?

    private let player = MPMusicPlayerController.applicationMusicPlayer

    // MARK: - 授权

    func requestAuthorization() async {
        let status = await MPMediaLibrary.requestAuthorization()
        isAuthorized = (status == .authorized)
        if isAuthorized {
            loadPlaylists()
        }
    }

    // MARK: - 加载本地音乐

    func loadPlaylists() {
        let query = MPMediaQuery.playlists()
        playlists = (query.collections as? [MPMediaPlaylist]) ?? []
    }

    func loadSongs(for genre: MusicGenre) {
        let query = MPMediaQuery.songs()

        // 尝试按流派筛选
        let genreMapping: [MusicGenre: String] = [
            .hiphop: "Hip-Hop",
            .electronic: "Electronic",
            .rock: "Rock",
            .pop: "Pop",
            .metal: "Metal",
            .latin: "Latin",
        ]

        if let genreString = genreMapping[genre] {
            let predicate = MPMediaPropertyPredicate(
                value: genreString,
                forProperty: MPMediaItemPropertyGenre,
                comparisonType: .contains
            )
            query.addFilterPredicate(predicate)
        }

        songs = query.items ?? []
    }

    func loadAllSongs() {
        let query = MPMediaQuery.songs()
        songs = query.items ?? []
    }

    // MARK: - 播放控制

    func play(item: MPMediaItem) {
        let collection = MPMediaItemCollection(items: [item])
        player.setQueue(with: collection)
        player.play()
        currentItem = item
        isPlaying = true
    }

    func playItems(_ items: [MPMediaItem]) {
        guard !items.isEmpty else { return }
        let collection = MPMediaItemCollection(items: items)
        player.setQueue(with: collection)
        player.shuffleMode = .songs
        player.play()
        currentItem = items.first
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func resume() {
        player.play()
        isPlaying = true
    }

    func skipToNext() {
        player.skipToNextItem()
        currentItem = player.nowPlayingItem
    }

    func skipToPrevious() {
        player.skipToPreviousItem()
        currentItem = player.nowPlayingItem
    }

    func stop() {
        player.stop()
        isPlaying = false
        currentItem = nil
    }
}
