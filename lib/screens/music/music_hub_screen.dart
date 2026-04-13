import 'package:flutter/material.dart';
import '../../models/enums.dart';

class MusicHubScreen extends StatefulWidget {
  const MusicHubScreen({super.key});

  @override
  State<MusicHubScreen> createState() => _MusicHubScreenState();
}

class _MusicHubScreenState extends State<MusicHubScreen> {
  MusicGenre? _selectedGenre;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('训练音乐')),
      body: Column(children: [
        // 类型选择
        SizedBox(
          height: 90,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: MusicGenre.values.map((g) => _genreChip(g)).toList(),
          ),
        ),
        const Divider(height: 1),
        // 内容区
        Expanded(
          child: _selectedGenre == null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.music_note, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text('选择一种音乐类型', style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Text('训练时听音乐可以提升表现 15-20%',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                  ]),
                )
              : _playlistView(),
        ),
      ]),
    );
  }

  Widget _genreChip(MusicGenre genre) {
    final selected = _selectedGenre == genre;
    final icons = {
      MusicGenre.hiphop: Icons.headphones,
      MusicGenre.electronic: Icons.graphic_eq,
      MusicGenre.rock: Icons.music_note,
      MusicGenre.pop: Icons.music_note,
      MusicGenre.metal: Icons.flash_on,
      MusicGenre.motivation: Icons.local_fire_department,
      MusicGenre.lofi: Icons.cloud,
      MusicGenre.latin: Icons.mic,
    };

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedGenre = genre),
        child: Container(
          width: 72,
          decoration: BoxDecoration(
            color: selected ? Colors.orange : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icons[genre] ?? Icons.music_note,
                color: selected ? Colors.white : Colors.grey[700], size: 24),
            const SizedBox(height: 4),
            Text(genre.displayName,
                style: TextStyle(fontSize: 11, color: selected ? Colors.white : Colors.grey[700])),
          ]),
        ),
      ),
    );
  }

  Widget _playlistView() {
    // 示例歌单（实际接入音乐 API 后替换）
    final playlists = {
      MusicGenre.hiphop: ['Workout Hip-Hop Mix', 'Gym Rap Anthems', 'Power Up Beats'],
      MusicGenre.electronic: ['EDM Energy', 'Bass Drop Workout', 'Electronic Pump'],
      MusicGenre.rock: ['Rock Workout', 'Classic Rock Gym', 'Hard Rock Power'],
      MusicGenre.pop: ['Pop Fitness', 'Chart Hits Workout', 'Feel Good Gym'],
      MusicGenre.metal: ['Metal Mayhem', 'Metalcore Workout', 'Heavy Lifting'],
      MusicGenre.motivation: ['Never Give Up', 'Champion Mindset', 'Rise & Grind'],
      MusicGenre.lofi: ['Chill Workout', 'Lo-Fi Gym', 'Relaxed Training'],
      MusicGenre.latin: ['Reggaeton Workout', 'Latin Fire', 'Salsa Fitness'],
    };

    final songs = playlists[_selectedGenre] ?? [];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: songs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('${_selectedGenre!.displayName}歌单',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          );
        }
        final song = songs[index - 1];
        return Card(
          elevation: 0, color: Colors.grey[100],
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.orange.shade50,
              child: const Icon(Icons.music_note, color: Colors.orange),
            ),
            title: Text(song, style: const TextStyle(fontSize: 14)),
            subtitle: Text('${_selectedGenre!.displayName} · 健身歌单',
                style: const TextStyle(fontSize: 12)),
            trailing: IconButton(
              icon: const Icon(Icons.play_circle_fill, color: Colors.orange, size: 32),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('播放: $song'), duration: const Duration(seconds: 1)),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
