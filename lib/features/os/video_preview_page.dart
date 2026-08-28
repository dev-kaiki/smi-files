// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase/supabase_manager.dart';

class VideoPreviewPage extends StatefulWidget {
  final String storagePath;
  const VideoPreviewPage({super.key, required this.storagePath});

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> {
  String? _url;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadUrl() async {
    setState(() {
      _loading = true;
      _error = null;
      _url = null;
    });

    try {
      final url = await SupabaseManager.client.storage
          .from('smi_midias')
          .createSignedUrl(widget.storagePath, 3600);

      if (!mounted) return;
      setState(() {
        _url = url;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Falha ao gerar link do vídeo.\n$e';
      });
    }
  }

  Future<void> _openExternal() async {
    final u = _url;
    if (u == null) return;

    final uri = Uri.tryParse(u);
    if (uri == null) {
      _snack('Link inválido.');
      return;
    }

    final ok = await canLaunchUrl(uri);
    if (!ok) {
      _snack('Não foi possível abrir o player externo.');
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyLink() async {
    final u = _url;
    if (u == null) return;
    await Clipboard.setData(ClipboardData(text: u));
    _snack('Link copiado!');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Visualizar vídeo'),
        actions: [
          IconButton(
            tooltip: 'Copiar link',
            icon: const Icon(Icons.copy),
            onPressed: _url == null ? null : _copyLink,
          ),
          IconButton(
            tooltip: 'Abrir externo',
            icon: const Icon(Icons.open_in_new),
            onPressed: _url == null ? null : _openExternal,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_url == null)
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 54, color: cs.error),
                  const SizedBox(height: 10),
                  Text(
                    _error ?? 'Erro ao carregar vídeo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _loadUrl,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      )
          : Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam, size: 78, color: cs.primary),
                  const SizedBox(height: 10),
                  Text(
                    'Reprodução do vídeo é feita em player externo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Abrir vídeo'),
                    onPressed: _openExternal,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar link'),
                    onPressed: _copyLink,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Obs: link assinado (temporário).',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
