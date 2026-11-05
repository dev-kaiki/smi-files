// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/pending/pending_media_store.dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingMediaItem {
  final String id;
  final String osFolderId;
  final String localPath;
  final String bucket;
  final String storagePath;
  final String fileType; // "image" | "video"
  final String? contentType;

  // Info para watermark
  final String osLabel; // ex: "2026/0003"
  final String tipo;
  final String setor;

  final String createdBy;
  final DateTime createdAt;

  final int attempts;
  final String lastError;
  final DateTime? lastAttemptAt;

  const PendingMediaItem({
    required this.id,
    required this.osFolderId,
    required this.localPath,
    required this.bucket,
    required this.storagePath,
    required this.fileType,
    required this.contentType,
    required this.osLabel,
    required this.tipo,
    required this.setor,
    required this.createdBy,
    required this.createdAt,
    required this.attempts,
    required this.lastError,
    required this.lastAttemptAt,
  });

  PendingMediaItem copyWith({
    int? attempts,
    String? lastError,
    DateTime? lastAttemptAt,
  }) {
    return PendingMediaItem(
      id: id,
      osFolderId: osFolderId,
      localPath: localPath,
      bucket: bucket,
      storagePath: storagePath,
      fileType: fileType,
      contentType: contentType,
      osLabel: osLabel,
      tipo: tipo,
      setor: setor,
      createdBy: createdBy,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'osFolderId': osFolderId,
        'localPath': localPath,
        'bucket': bucket,
        'storagePath': storagePath,
        'fileType': fileType,
        'contentType': contentType,
        'osLabel': osLabel,
        'tipo': tipo,
        'setor': setor,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'attempts': attempts,
        'lastError': lastError,
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      };

  static PendingMediaItem fromMap(Map<String, dynamic> m) => PendingMediaItem(
        id: (m['id'] ?? '').toString(),
        osFolderId: (m['osFolderId'] ?? '').toString(),
        localPath: (m['localPath'] ?? '').toString(),
        bucket: (m['bucket'] ?? '').toString(),
        storagePath: (m['storagePath'] ?? '').toString(),
        fileType: (m['fileType'] ?? '').toString(),
        contentType: (m['contentType'] == null) ? null : (m['contentType']).toString(),
        osLabel: (m['osLabel'] ?? '').toString(),
        tipo: (m['tipo'] ?? '').toString(),
        setor: (m['setor'] ?? '').toString(),
        createdBy: (m['createdBy'] ?? '').toString(),
        createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()) ?? DateTime.now(),
        attempts: (m['attempts'] is int) ? m['attempts'] as int : int.tryParse('${m['attempts']}') ?? 0,
        lastError: (m['lastError'] ?? '').toString(),
        lastAttemptAt: (m['lastAttemptAt'] == null) ? null : DateTime.tryParse('${m['lastAttemptAt']}'),
      );
}

class PendingMediaStore {
  PendingMediaStore._();
  static final PendingMediaStore I = PendingMediaStore._();

  static const String _key = 'pending_media_queue_v1';

  late SharedPreferences _prefs;

  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  static String newId() {
    final r = Random();
    return '${DateTime.now().microsecondsSinceEpoch}_${r.nextInt(1 << 20)}';
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    pendingCount.value = (await list()).length;
  }

  Future<List<PendingMediaItem>> list() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return <PendingMediaItem>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <PendingMediaItem>[];
    return decoded
        .whereType<Map>()
        .map((e) => PendingMediaItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _save(List<PendingMediaItem> items) async {
    final raw = jsonEncode(items.map((e) => e.toMap()).toList());
    await _prefs.setString(_key, raw);
    pendingCount.value = items.length;
  }

  Future<void> addOrUpdate(PendingMediaItem item) async {
    final items = await list();
    final idx = items.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.add(item);
    }
    await _save(items);
  }

  Future<void> remove(String id) async {
    final items = await list();
    items.removeWhere((e) => e.id == id);
    await _save(items);
  }

  Future<void> clear() async => _save(<PendingMediaItem>[]);
}
