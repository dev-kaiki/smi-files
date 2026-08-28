// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/supabase/supabase_manager.dart';

class ImagePreviewPage extends StatefulWidget {
  final String storagePath;

  const ImagePreviewPage({super.key, required this.storagePath});

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  String? _url;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final url = await SupabaseManager.client.storage
          .from('smi_midias')
          .createSignedUrl(widget.storagePath, 3600)
          .timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw TimeoutException('Tempo esgotado ao carregar a imagem.'),
      );

      if (!mounted) return;
      setState(() {
        _url = url;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _url = null;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visualizar imagem'),
        actions: [
          IconButton(
            tooltip: 'Recarregar',
            onPressed: _loading ? null : _loadUrl,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _url == null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 56, color: cs.onSurfaceVariant),
              const SizedBox(height: 10),
              const Text(
                'Não foi possível carregar a imagem.',
                style: TextStyle(fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _error ?? 'Tente novamente.',
                style: TextStyle(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
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
      )
          : Container(
        color: Colors.black,
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 6.0,
          child: Center(
            child: Image.network(
              _url!,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (context, error, stack) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_outlined, size: 56, color: cs.onSurface),
                        const SizedBox(height: 10),
                        const Text(
                          'Erro ao renderizar a imagem.',
                          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _loadUrl,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Recarregar'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
