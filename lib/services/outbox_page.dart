// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'package:flutter/material.dart';
import 'outbox_service.dart';
import 'outbox_uploader.dart';

class OutboxPage extends StatefulWidget {
  final String? osFolderId;
  final String? osLabel;

  const OutboxPage({super.key, this.osFolderId, this.osLabel});

  @override
  State<OutboxPage> createState() => _OutboxPageState();
}

class _OutboxPageState extends State<OutboxPage> {
  bool _busy = false;
  int _sizeBytes = 0;

  List<OutboxItem> get _items => OutboxService.I.itemsFor(osFolderId: widget.osFolderId, osLabel: widget.osLabel);

  @override
  void initState() {
    super.initState();
    _refreshSize();
    OutboxService.I.pendingCount.addListener(_refreshSize);
  }

  @override
  void dispose() {
    try {
      OutboxService.I.pendingCount.removeListener(_refreshSize);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _refreshSize() async {
    final b = await OutboxService.I.outboxSizeBytes(osFolderId: widget.osFolderId, osLabel: widget.osLabel);
    if (!mounted) return;
    setState(() => _sizeBytes = b);
  }

  String _fmtBytes(int b) {
    const kb = 1024;
    const mb = 1024 * 1024;
    if (b >= mb) return "${(b / mb).toStringAsFixed(2)} MB";
    if (b >= kb) return "${(b / kb).toStringAsFixed(1)} KB";
    return "$b B";
  }

  String _statusLabel(OutboxStatus s) {
    switch (s) {
      case OutboxStatus.pending:
        return "Pendente";
      case OutboxStatus.uploading:
        return "Enviando";
      case OutboxStatus.uploaded:
        return "Enviado";
      case OutboxStatus.missing:
        return "Arquivo ausente";
      case OutboxStatus.failed:
        return "Falhou";
    }
  }

  Future<void> _reenviar() async {
    setState(() => _busy = true);
    try {
      await OutboxUploader.I.processPending(osFolderId: widget.osFolderId, osLabel: widget.osLabel);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.osLabel == null ? "Outbox" : "Outbox • ${widget.osLabel}";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: "Reenviar pendentes",
            onPressed: _busy ? null : _reenviar,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Itens: ${_items.length} • Espaço: ${_fmtBytes(_sizeBytes)}",
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_busy) const SizedBox(width: 8),
                if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _reenviar,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Reenviar"),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text("Sem pendências na Outbox."))
                : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final it = _items[i];
                final subtitle = [
                  "${it.bucket}/${it.storagePath}",
                  "Tipo: ${it.fileType ?? '—'} • Tentativas: ${it.attempts} • Status: ${_statusLabel(it.status)}",
                  if ((it.setor ?? "").isNotEmpty || (it.tipo ?? "").isNotEmpty)
                    "Setor: ${it.setor ?? '—'} • Tipo: ${it.tipo ?? '—'}",
                  if ((it.lastError ?? "").isNotEmpty) "Erro: ${it.lastError}",
                ].join("\n");

                return ListTile(
                  leading: Icon(
                    it.fileType == "video"
                        ? Icons.videocam
                        : it.fileType == "image"
                        ? Icons.image
                        : Icons.insert_drive_file,
                  ),
                  title: Text(it.osLabel ?? it.id),
                  subtitle: Text(subtitle),
                  isThreeLine: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
