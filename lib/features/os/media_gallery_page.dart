// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/os/media_gallery_page.dart
//
// Visualizador estilo galeria (swipe) com zoom nas imagens.
// - Não salva nada local (usa URLs assinadas do Supabase Storage)
// - Ações: compartilhar link / definir capa / excluir
// - Retorna Navigator.pop(context, true) quando algo muda (para a tela anterior recarregar)

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/supabase/supabase_manager.dart';
import 'video_preview_page.dart';

class MediaGalleryPage extends StatefulWidget {
  final String osFolderId;
  final List<Map<String, dynamic>> files; // lista já filtrada/ordenada
  final int initialIndex;
  final String? currentCoverPath;

  const MediaGalleryPage({
    super.key,
    required this.osFolderId,
    required this.files,
    required this.initialIndex,
    required this.currentCoverPath,
  });

  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage> {
  late final PageController _controller;
  late List<Map<String, dynamic>> _items;
  int _index = 0;

  bool _busy = false;

  // cache de url assinada
  final Map<String, Future<String>> _urlFuture = {};
  final Map<String, String> _urlCache = {};

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.files);
    _index = max(0, min(widget.initialIndex, _items.isEmpty ? 0 : _items.length - 1));
    _controller = PageController(initialPage: _index);
    _prefetchAround(_index);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Map<String, dynamic>? get _current => (_items.isEmpty) ? null : _items[_index];

  bool get _isImage => (_current?['file_type'] == 'image');
  bool get _isCover => (_current?['is_cover'] == true);
  String get _storagePath => (_current?['storage_path'] ?? '').toString();
  String get _id => (_current?['id'] ?? '').toString();

  String _fileTitle() {
    final path = _storagePath;
    if (path.isEmpty) return 'Mídia';
    return p.basename(path);
  }

  Future<String?> _signedUrl(String storagePath) async {
    final path = storagePath.trim();
    if (path.isEmpty) return null;

    final cached = _urlCache[path];
    if (cached != null && cached.isNotEmpty) return cached;

    final fut = _urlFuture.putIfAbsent(path, () async {
      final url = await SupabaseManager.client.storage.from('smi_midias').createSignedUrl(path, 3600);
      _urlCache[path] = url;
      return url;
    });

    return fut;
  }

  void _prefetchAround(int center) {
    if (_items.isEmpty) return;
    final idxs = <int>{center, center + 1, center + 2, center - 1}
        .where((i) => i >= 0 && i < _items.length)
        .toList();
    for (final i in idxs) {
      final path = (_items[i]['storage_path'] ?? '').toString().trim();
      if (path.isEmpty) continue;
      _signedUrl(path); // dispara cache
    }
  }


  Future<void> _share() async {
    final path = _storagePath;
    if (path.isEmpty) return;
    setState(() => _busy = true);
    try {
      final url = await SupabaseManager.client.storage.from('smi_midias').createSignedUrl(path, 3600);
      await Share.share(url);
    } catch (e) {
      _snack('Erro ao compartilhar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setCover() async {
    if (!_isImage) {
      _snack('A capa deve ser uma imagem.');
      return;
    }
    if (_isCover) return;

    final id = _id;
    final path = _storagePath;
    if (id.isEmpty || path.isEmpty) return;

    setState(() => _busy = true);
    try {
      final client = SupabaseManager.client;

      await client.from('media_files').update({'is_cover': false}).eq('os_folder_id', widget.osFolderId);
      await client.from('media_files').update({'is_cover': true}).eq('id', id);
      await client.from('os_folders').update({'cover_path': path}).eq('id', widget.osFolderId);

      // atualiza estado local
      for (final it in _items) {
        it['is_cover'] = false;
      }
      _items[_index]['is_cover'] = true;

      if (mounted) setState(() {});
      _snack('Capa atualizada.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('Erro ao definir capa: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recalculateCoverAfterDelete() async {
    final list = await SupabaseManager.client
        .from('media_files')
        .select('id, file_type, storage_path, is_cover, created_at')
        .eq('os_folder_id', widget.osFolderId)
        .order('created_at', ascending: true);

    final files = List<Map<String, dynamic>>.from(list);

    if (files.isEmpty) {
      await SupabaseManager.client.from('os_folders').update({'cover_path': null}).eq('id', widget.osFolderId);
      return;
    }

    Map<String, dynamic>? newCover;
    try {
      newCover = files.firstWhere((e) => e['is_cover'] == true);
    } catch (_) {
      newCover = null;
    }

    if (newCover == null) {
      final imgs = files.where((e) => e['file_type'] == 'image').toList();
      newCover = imgs.isNotEmpty ? imgs.first : files.first;

      await SupabaseManager.client.from('media_files').update({'is_cover': false}).eq('os_folder_id', widget.osFolderId);
      await SupabaseManager.client.from('media_files').update({'is_cover': true}).eq('id', newCover['id']);
    }

    await SupabaseManager.client.from('os_folders').update({'cover_path': newCover['storage_path']}).eq('id', widget.osFolderId);
  }

  Future<void> _delete() async {
    final id = _id;
    final path = _storagePath;
    if (id.isEmpty || path.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir'),
        content: Text('Excluir permanentemente?\n\n${p.basename(path)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await SupabaseManager.client.storage.from('smi_midias').remove([path]);
      await SupabaseManager.client.from('media_files').delete().eq('id', id);

      final wasCover = _isCover || (widget.currentCoverPath ?? '') == path;
      _items.removeAt(_index);

      if (_items.isEmpty) {
        if (wasCover) await SupabaseManager.client.from('os_folders').update({'cover_path': null}).eq('id', widget.osFolderId);
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // ajusta índice e page
      _index = max(0, min(_index, _items.length - 1));
      _controller.jumpToPage(_index);

      if (wasCover) {
        await _recalculateCoverAfterDelete();
      }

      if (mounted) setState(() {});
      _snack('Arquivo excluído.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('Erro ao excluir: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildImage(String storagePath) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<String?>(
      future: _signedUrl(storagePath),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
          );
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant, size: 36),
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                    value: progress.expectedTotalBytes == null
                        ? null
                        : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildVideoCard(String storagePath) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              p.basename(storagePath),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VideoPreviewPage(storagePath: storagePath)),
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Reproduzir'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final cur = _current;
    final title = _fileTitle();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_items.isEmpty ? 0 : (_index + 1)}/${_items.length} • $title',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Compartilhar',
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.share),
          ),
          if (_isImage)
            IconButton(
              tooltip: _isCover ? 'Já é capa' : 'Definir capa',
              onPressed: (_busy || _isCover) ? null : _setCover,
              icon: Icon(Icons.star, color: _isCover ? Colors.amber : null),
            ),
          IconButton(
            tooltip: 'Excluir',
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: (_items.isEmpty || cur == null)
                ? Center(child: Text('Sem mídia', style: TextStyle(color: cs.onSurfaceVariant)))
                : PageView.builder(
              controller: _controller,
              onPageChanged: (i) {
                setState(() => _index = i);
                _prefetchAround(i);
              },
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final f = _items[i];
                final isImage = f['file_type'] == 'image';
                final path = (f['storage_path'] ?? '').toString();
                if (path.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: isImage ? _buildImage(path) : _EmbeddedVideoPlayer(signedUrlFuture: _signedUrl(path)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


class _EmbeddedVideoPlayer extends StatefulWidget {
  final Future<String?> signedUrlFuture;
  const _EmbeddedVideoPlayer({required this.signedUrlFuture});

  @override
  State<_EmbeddedVideoPlayer> createState() => _EmbeddedVideoPlayerState();
}

class _EmbeddedVideoPlayerState extends State<_EmbeddedVideoPlayer> {
  VideoPlayerController? _ctl;
  Future<void>? _init;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _EmbeddedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signedUrlFuture != widget.signedUrlFuture) {
      _disposeCtl();
      _load();
    }
  }

  void _disposeCtl() {
    final c = _ctl;
    _ctl = null;
    _init = null;
    if (c != null) c.dispose();
  }

  Future<void> _load() async {
    _error = false;
    try {
      final url = await widget.signedUrlFuture;
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        setState(() => _error = true);
        return;
      }
      final ctl = VideoPlayerController.networkUrl(Uri.parse(url));
      _ctl = ctl;
      _init = ctl.initialize().then((_) {
        ctl.setLooping(true);
      });
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = true);
    }
  }

  @override
  void dispose() {
    _disposeCtl();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_error) {
      return Center(child: Icon(Icons.error_outline, color: cs.error, size: 40));
    }

    final init = _init;
    final ctl = _ctl;
    if (init == null || ctl == null) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
        ),
      );
    }

    return FutureBuilder<void>(
      future: init,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
          );
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: ctl.value.aspectRatio == 0 ? 16 / 9 : ctl.value.aspectRatio,
              child: VideoPlayer(ctl),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      icon: Icon(ctl.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          ctl.value.isPlaying ? ctl.pause() : ctl.play();
                        });
                      },
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        ctl,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        colors: VideoProgressColors(
                          playedColor: cs.primary,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                    Text(
                      '${_fmt(ctl.value.position)} / ${_fmt(ctl.value.duration)}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
