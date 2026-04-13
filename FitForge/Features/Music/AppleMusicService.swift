import Foundation
import MusicKit

/// Apple Music 服务（需用户有 Apple Music 订阅）
@MainActor
class AppleMusicService: ObservableObject {
    @Published var isAuthorized = false
    @Published var searchResults: [Song] = []
    @Published var isPlaying = false
    @Published var currentSong: Song?

    private var player = ApplicationMusicPlayer.shared

    // MARK: - 授权

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        isAuthorized = (status == .authorized)
    }

    // MARK: - 搜索

    func searchSongs(query: String) async {
        guard isAuthorized else { return }

        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 25
            let response = try await request.response()
            searchResults = Array(response.songs)
        } catch {
            searchResults = []
        }
    }

    /// 按健身音乐类型搜索
    func searchByGenre(_ genre: MusicGenre) async {
        let keyword = genre.searchKeywords.first ?? genre.displayName
        await searchSongs(query: keyword)
    }

    // MARK: - 播放控制

    func play(song: Song) async {
        do {
            player.queue = [song]
            try await player.play()
            currentSong = song
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func playQueue(songs: [Song]) async {
        guard !songs.isEmpty else { return }
        do {
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            try await player.play()
            currentSong = songs.first
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func resume() async {
        do {
            try await player.play()
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func skipToNext() async {
        do {
            try await player.skipToNextEntry()
        } catch {}
    }

    func skipToPrevious() async {
        do {
            try await player.skipToPreviousEntry()
        } catch {}
    }
}
