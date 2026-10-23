import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../novel/novel_image_provider.dart';
import 'cinema_api.dart';

class CinemaPlayerPage extends StatefulWidget {
  const CinemaPlayerPage({super.key, required this.chapterId, this.workId});
  final int chapterId;
  final int? workId;

  @override
  State<CinemaPlayerPage> createState() => _CinemaPlayerPageState();
}

class _CinemaPlayerPageState extends State<CinemaPlayerPage> {
  final _api = CinemaApi();
  final _audio = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  List<Map<String, dynamic>> _items = [];
  int _index = 0;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _stateSub = _audio.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          _index + 1 < _items.length) {
        unawaited(_play(_index + 1));
      }
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.playback(widget.chapterId);
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      if (items.isNotEmpty) unawaited(_play(0));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _play(int i) async {
    if (i < 0 || i >= _items.length) return;
    setState(() => _index = i);
    final item = _items[i];
    final assets = (item['assets'] as List? ?? []).whereType<Map>();
    final audio = assets
        .map((e) => e['asset_type'] == 'image' ? '' : e['url']?.toString() ?? '')
        .firstWhere((x) => x.isNotEmpty, orElse: () => '');
    if (audio.isNotEmpty) {
      await _audio.setUrl(audio);
      await _audio.play();
    }
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    unawaited(_audio.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error.isNotEmpty) {
      return Scaffold(body: Center(child: Text(_error)));
    }
    if (_items.isEmpty) {
      return const Scaffold(body: Center(child: Text('本章节还没有内容')));
    }

    final item = _items[_index];
    final assets = (item['assets'] as List? ?? []).whereType<Map>();
    final image = assets
        .map((e) => e['asset_type'] == 'image' ? e['url']?.toString() ?? '' : '')
        .firstWhere((x) => x.isNotEmpty, orElse: () => '');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(item['speaker']?.toString() ?? '旁白')),
      body: Column(
        children: [
          Expanded(
            child: image.isEmpty
                ? const Center(
                    child: Icon(Icons.movie, color: Colors.white54, size: 64),
                  )
                : Image(
                    image: NovelImageProvider.network(image),
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              item['text']?.toString() ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _play(_index - 1),
                icon: const Icon(Icons.skip_previous, color: Colors.white),
              ),
              Text(
                '${_index + 1}/${_items.length}',
                style: const TextStyle(color: Colors.white),
              ),
              IconButton(
                onPressed: () => _play(_index + 1),
                icon: const Icon(Icons.skip_next, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}