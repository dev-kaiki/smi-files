// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/pending/pending_media_page.dart
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'pending_media_retry_service.dart';
import 'pending_media_store.dart';

class PendingMediaPage extends StatefulWidget {
  const PendingMediaPage({super.key, required this.retryService});

  final PendingMediaRetryService retryService;

  @override
  State<PendingMediaPage> createState() => _PendingMediaPageState();
}

class _PendingMediaPageState extends State<PendingMediaPage> {
  bool _loading = false;
  bool _changed = false;

  Future<void> _retryAll() async {
    setState(() => _loading = true);
    await widget.retryService.retryAll();
    _changed = true;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _retryOne(PendingMediaItem item) async {
    setState(() => _loading = true);
    await widget.retryService.retryOne(item);
    _changed = true;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(PendingMediaItem item) async {
    await PendingMediaStore.I.remove(item.id);
    _changed = true;
    setState(() {});
  }

  Future<void> _clear() async {
    await PendingMediaStore.I.clear();
    _changed = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _changed);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mídias pendentes'),
          actions: [
            IconButton(
              tooltip: 'Reenviar tudo',
              onPressed: _loading ? null : _retryAll,
              icon: const Icon(Icons.cloud_upload),
            ),
            IconButton(
              tooltip: 'Limpar lista',
              onPressed: _loading ? null : _clear,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: FutureBuilder<List<PendingMediaItem>>(
          future: PendingMediaStore.I.list(),
          builder: (context, snap) {
            final items = snap.data ?? const <PendingMediaItem>[];
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (items.isEmpty) {
              return const Center(child: Text('Nenhuma mídia pendente 🎉'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final it = items[i];
                final name = it.storagePath.trim().isNotEmpty ? p.basename(it.storagePath) : p.basename(it.localPath);

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(it.fileType == 'video' ? Icons.videocam : Icons.image_outlined),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('T: ${it.attempts}', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('OS Folder: ${it.osFolderId}', style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('Path: ${it.storagePath}', style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 8),
                        if (it.lastError.trim().isNotEmpty)
                          Text(
                            it.lastError,
                            style: TextStyle(fontSize: 12, color: Colors.red.shade400),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _loading ? null : () => _retryOne(it),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reenviar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'Remover',
                              onPressed: _loading ? null : () => _remove(it),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
