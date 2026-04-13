import SwiftUI

struct MusicHubView: View {
    @StateObject private var appleMusicService = AppleMusicService()
    @StateObject private var localMusicService = LocalMusicService()

    @State private var selectedSource: MusicSource = .appleMusic
    @State private var selectedGenre: MusicGenre?

    enum MusicSource: String, CaseIterable, Identifiable {
        case appleMusic = "Apple Music"
        case local = "本地音乐"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 来源切换
            Picker("音乐来源", selection: $selectedSource) {
                ForEach(MusicSource.allCases) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // 音乐类型选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MusicGenre.allCases) { genre in
                        genreChip(genre)
                    }
                }
                .padding(.horizontal)
            }

            Divider().padding(.top, 8)

            // 歌曲列表
            switch selectedSource {
            case .appleMusic:
                appleMusicContent
            case .local:
                localMusicContent
            }

            Spacer()

            // 迷你播放器
            miniPlayerBar
        }
        .navigationTitle("训练音乐")
        .task {
            await appleMusicService.requestAuthorization()
            await localMusicService.requestAuthorization()
        }
    }

    // MARK: - 类型芯片

    private func genreChip(_ genre: MusicGenre) -> some View {
        Button {
            selectedGenre = genre
            Task {
                if selectedSource == .appleMusic {
                    await appleMusicService.searchByGenre(genre)
                } else {
                    localMusicService.loadSongs(for: genre)
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: genre.icon)
                    .font(.title3)
                Text(genre.displayName)
                    .font(.caption)
            }
            .frame(width: 70, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedGenre == genre ? Color.orange : Color(.systemGray6))
            )
            .foregroundStyle(selectedGenre == genre ? .white : .primary)
        }
    }

    // MARK: - Apple Music

    private var appleMusicContent: some View {
        Group {
            if !appleMusicService.isAuthorized {
                unauthorizedView(source: "Apple Music")
            } else if appleMusicService.searchResults.isEmpty {
                emptyStateView
            } else {
                List(appleMusicService.searchResults, id: \.id) { song in
                    Button {
                        Task { await appleMusicService.play(song: song) }
                    } label: {
                        HStack(spacing: 12) {
                            if let artwork = song.artwork {
                                ArtworkImage(artwork, width: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.systemGray4))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "music.note")
                                            .foregroundStyle(.secondary)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(song.artistName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - 本地音乐

    private var localMusicContent: some View {
        Group {
            if !localMusicService.isAuthorized {
                unauthorizedView(source: "音乐库")
            } else if localMusicService.songs.isEmpty {
                emptyStateView
            } else {
                List(localMusicService.songs, id: \.persistentID) { item in
                    Button {
                        localMusicService.play(item: item)
                    } label: {
                        HStack(spacing: 12) {
                            if let artwork = item.artwork {
                                Image(uiImage: artwork.image(at: CGSize(width: 44, height: 44)) ?? UIImage())
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.systemGray4))
                                    .frame(width: 44, height: 44)
                                    .overlay(Image(systemName: "music.note"))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title ?? "未知歌曲")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(item.artist ?? "未知歌手")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - 迷你播放器

    private var miniPlayerBar: some View {
        let isPlaying = selectedSource == .appleMusic ?
            appleMusicService.isPlaying : localMusicService.isPlaying

        let songTitle: String = {
            if selectedSource == .appleMusic {
                return appleMusicService.currentSong?.title ?? "未在播放"
            } else {
                return localMusicService.currentItem?.title ?? "未在播放"
            }
        }()

        return HStack(spacing: 16) {
            Image(systemName: "music.note")
                .foregroundStyle(.orange)

            Text(songTitle)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Button {
                Task {
                    if selectedSource == .appleMusic {
                        await appleMusicService.skipToPrevious()
                    } else {
                        localMusicService.skipToPrevious()
                    }
                }
            } label: {
                Image(systemName: "backward.fill")
            }

            Button {
                if isPlaying {
                    if selectedSource == .appleMusic {
                        appleMusicService.pause()
                    } else {
                        localMusicService.pause()
                    }
                } else {
                    Task {
                        if selectedSource == .appleMusic {
                            await appleMusicService.resume()
                        } else {
                            localMusicService.resume()
                        }
                    }
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }

            Button {
                Task {
                    if selectedSource == .appleMusic {
                        await appleMusicService.skipToNext()
                    } else {
                        localMusicService.skipToNext()
                    }
                }
            } label: {
                Image(systemName: "forward.fill")
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    // MARK: - 状态视图

    private func unauthorizedView(source: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("需要 \(source) 访问权限")
                .font(.headline)
            Text("请在设置中允许 FitForge 访问你的音乐")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("选择一种音乐类型开始")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
