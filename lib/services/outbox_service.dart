// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Status do item na Outbox.
enum OutboxStatus { pending, uploading, uploaded, missing, failed }

/// Item pendente (ou já enviado) armazenado localmente para reenvio.
/// A ideia é: se o upload falhar ou o app fechar, existe uma cópia persistente
/// no diretório do app, então o usuário NÃO perde a mídia.
class OutboxItem {
  final String id;

  /// Supabase Storage bucket
  final String bucket;

  /// Caminho remoto no bucket (Storage) - equivalente ao "storage_path"
  final String storagePath;

  /// Caminho local (cópia persistida na Outbox)
  final String localPath;

  final int sizeBytes;
  final String ext;
  final String? originalName;

  /// Metadados opcionais (usados na UI / DB)
  final String? osFolderId;
  final String? osLabel; // ex: "2026/0003"
  final String? fileType; // "image" | "video" | "file"
  final String? contentType;
  final String? setor;
  final String? tipo;
  final String? createdBy;

  // EXIF (opcional)
  final DateTime? exifTakenAt;
  final int? exifWidth;
  final int? exifHeight;

  OutboxStatus status;
  int attempts;
  String? lastError;
  DateTime createdAt;
  DateTime? lastTryAt;

  OutboxItem({
    required this.id,
    required this.bucket,
    required this.storagePath,
    required this.localPath,
    required this.sizeBytes,
    required this.ext,
    this.originalName,
    this.osFolderId,
    this.osLabel,
    this.fileType,
    this.contentType,
    this.setor,
    this.tipo,
    this.createdBy,
    this.exifTakenAt,
    this.exifWidth,
    this.exifHeight,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.lastError,
    DateTime? createdAt,
    this.lastTryAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Compat: caso algum lugar ainda chame "remotePath"
  String get remotePath => storagePath;

  Map<String, dynamic> toJson() => {
    "id": id,
    "bucket": bucket,
    "storagePath": storagePath,
    "localPath": localPath,
    "sizeBytes": sizeBytes,
    "ext": ext,
    "originalName": originalName,
    "osFolderId": osFolderId,
    "osLabel": osLabel,
    "fileType": fileType,
    "contentType": contentType,
    "setor": setor,
    "tipo": tipo,
    "createdBy": createdBy,
    "exifTakenAt": exifTakenAt?.toIso8601String(),
    "exifWidth": exifWidth,
    "exifHeight": exifHeight,
    "status": status.name,
    "attempts": attempts,
    "lastError": lastError,
    "createdAt": createdAt.toIso8601String(),
    "lastTryAt": lastTryAt?.toIso8601String(),
  };

  static OutboxItem fromJson(Map<String, dynamic> j) => OutboxItem(
    id: (j["id"] ?? "") as String,
    bucket: (j["bucket"] ?? "") as String,
    storagePath: (j["storagePath"] ?? j["remotePath"] ?? "") as String,
    localPath: (j["localPath"] ?? "") as String,
    sizeBytes: (j["sizeBytes"] ?? 0) as int,
    ext: (j["ext"] ?? "") as String,
    originalName: j["originalName"] as String?,
    osFolderId: j["osFolderId"] as String?,
    osLabel: j["osLabel"] as String?,
    fileType: j["fileType"] as String?,
    contentType: j["contentType"] as String?,
    setor: j["setor"] as String?,
    tipo: j["tipo"] as String?,
    createdBy: j["createdBy"] as String?,
    exifTakenAt: j["exifTakenAt"] == null ? null : DateTime.tryParse(j["exifTakenAt"].toString()),
    exifWidth: (j["exifWidth"] is int) ? j["exifWidth"] as int : int.tryParse("${j["exifWidth"]}"),
    exifHeight: (j["exifHeight"] is int) ? j["exifHeight"] as int : int.tryParse("${j["exifHeight"]}"),
    status: OutboxStatus.values.firstWhere(
          (e) => e.name == (j["status"] ?? "pending"),
      orElse: () => OutboxStatus.pending,
    ),
    attempts: (j["attempts"] ?? 0) as int,
    lastError: j["lastError"] as String?,
    createdAt: DateTime.tryParse((j["createdAt"] ?? "") as String) ?? DateTime.now(),
    lastTryAt: j["lastTryAt"] != null ? DateTime.tryParse(j["lastTryAt"] as String) : null,
  );
}

class OutboxService {
  OutboxService._();

  static final OutboxService I = OutboxService._();

  final _uuid = const Uuid();

  Directory? _root;
  File? _stateFile;

  final List<OutboxItem> _items = [];
  List<OutboxItem> get items => List.unmodifiable(_items);

  /// Para UI (badge/banner): quantidade de pendentes (pending + failed)
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    _root = Directory(p.join(docs.path, "smi_outbox"));
    if (!await _root!.exists()) {
      await _root!.create(recursive: true);
    }
    _stateFile = File(p.join(_root!.path, "outbox_state.json"));
    await _loadState();
  }

  Future<void> _loadState() async {
    _items.clear();
    if (_stateFile == null) return;

    if (await _stateFile!.exists()) {
      try {
        final raw = await _stateFile!.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            _items.addAll(decoded.map((e) => OutboxItem.fromJson(Map<String, dynamic>.from(e))));
          }
        }
      } catch (e) {
        final corrupt = File('${_stateFile!.path}.corrupt_${DateTime.now().millisecondsSinceEpoch}');
        try {
          await _stateFile!.rename(corrupt.path);
        } catch (_) {}
        if (kDebugMode) {
          print('Outbox state corrompido; arquivo preservado em ${corrupt.path}. Erro: $e');
        }
      }
    }

    // Se o app fechou no meio do envio, volta pra pending
    for (final it in _items) {
      if (it.status == OutboxStatus.uploading) it.status = OutboxStatus.pending;
    }

    await _saveState();
  }

  Future<void> _saveState() async {
    if (_stateFile != null) {
      final tmp = File('${_stateFile!.path}.tmp');
      await tmp.writeAsString(jsonEncode(_items.map((e) => e.toJson()).toList()), flush: true);
      if (await tmp.exists()) {
        if (await _stateFile!.exists()) {
          try {
            await _stateFile!.delete();
          } catch (_) {}
        }
        await tmp.rename(_stateFile!.path);
      }
    }
    _recalcPendingCount();
  }

  void _recalcPendingCount() {
    final c = _items.where((e) => e.status == OutboxStatus.pending || e.status == OutboxStatus.failed).length;
    if (pendingCount.value != c) pendingCount.value = c;
  }

  String _inferFileType(String extLower) {
    switch (extLower) {
      case ".jpg":
      case ".jpeg":
      case ".png":
      case ".webp":
      case ".heic":
        return "image";
      case ".mp4":
      case ".mov":
      case ".mkv":
      case ".avi":
        return "video";
      default:
        return "file";
    }
  }

  /// Adiciona item na Outbox copiando para uma pasta persistente.
  ///
  /// Você pode passar:
  /// - storagePath (full path remoto no bucket), OU
  /// - remotePrefix (prefixo remoto) para gerar automaticamente um nome.
  Future<OutboxItem> enqueueFromFile({
    required File sourceFile,
    required String bucket,
    String? storagePath,
    String? remotePrefix,
    String? originalName,
    String? osFolderId,
    String? osLabel,
    String? fileType,
    String? contentType,
    String? setor,
    String? tipo,
    String? createdBy,
    DateTime? exifTakenAt,
    int? exifWidth,
    int? exifHeight,
    String? lastError,
    bool persistImmediately = true,
  }) async {
    if (_root == null) {
      throw StateError("OutboxService.I.init() não foi chamado.");
    }
    if (!await sourceFile.exists()) {
      throw FileSystemException("Arquivo de origem não existe", sourceFile.path);
    }

    final ext = p.extension(sourceFile.path).toLowerCase();
    final id = _uuid.v4();

    final destPath = p.join(_root!.path, "$id${ext.isEmpty ? "" : ext}");
    await sourceFile.copy(destPath);

    final size = await File(destPath).length();

    String finalStoragePath = (storagePath ?? "").trim();
    if (finalStoragePath.isEmpty) {
      final prefix = (remotePrefix ?? "").trim();
      if (prefix.isEmpty) {
        throw ArgumentError("Informe storagePath ou remotePrefix.");
      }
      finalStoragePath = p.posix.join(prefix, "$id${ext.isEmpty ? "" : ext}");
    }

    final item = OutboxItem(
      id: id,
      bucket: bucket,
      storagePath: finalStoragePath,
      localPath: destPath,
      sizeBytes: size,
      ext: ext,
      originalName: originalName ?? p.basename(sourceFile.path),
      osFolderId: osFolderId,
      osLabel: osLabel,
      fileType: fileType ?? _inferFileType(ext),
      contentType: contentType,
      setor: setor,
      tipo: tipo,
      createdBy: createdBy,
      exifTakenAt: exifTakenAt,
      exifWidth: exifWidth,
      exifHeight: exifHeight,
      status: OutboxStatus.pending,
      attempts: 0,
      lastError: lastError,
      lastTryAt: null,
    );

    _items.insert(0, item);
    if (persistImmediately) {
      await _saveState();
    } else {
      _recalcPendingCount();
    }
    return item;
  }

  /// Persiste manualmente o estado da fila.
  Future<void> persistState() => _saveState();

  int countPending({String? osFolderId, String? osLabel}) {
    return _items.where((e) {
      final st = (e.status == OutboxStatus.pending || e.status == OutboxStatus.failed);
      final f1 = osFolderId == null || e.osFolderId == osFolderId;
      final f2 = osLabel == null || e.osLabel == osLabel;
      return st && f1 && f2;
    }).length;
  }

  List<OutboxItem> itemsFor({String? osFolderId, String? osLabel}) {
    return _items.where((e) {
      final f1 = osFolderId == null || e.osFolderId == osFolderId;
      final f2 = osLabel == null || e.osLabel == osLabel;
      return f1 && f2;
    }).toList();
  }

  Future<int> outboxSizeBytes({String? osFolderId, String? osLabel}) async {
    int sum = 0;
    for (final it in _items) {
      if (osFolderId != null && it.osFolderId != osFolderId) continue;
      if (osLabel != null && it.osLabel != osLabel) continue;
      final f = File(it.localPath);
      if (await f.exists()) sum += await f.length();
    }
    return sum;
  }

  Future<void> cleanupUploaded({String? osFolderId, String? osLabel}) async {
    final toRemove = _items.where((e) {
      if (e.status != OutboxStatus.uploaded) return false;
      if (osFolderId != null && e.osFolderId != osFolderId) return false;
      if (osLabel != null && e.osLabel != osLabel) return false;
      return true;
    }).toList();

    for (final it in toRemove) {
      final f = File(it.localPath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
      _items.remove(it);
    }
    await _saveState();
  }

  /// Processa a fila pendente.
  ///
  /// IMPORTANTE: o `uploadFn` deve fazer TODO o fluxo necessário para que a mídia volte a aparecer no app,
  /// ou seja, não basta subir no Storage — tem que garantir o `upsert` no Postgres (`media_files`) também.
  ///
  /// O item só é removido da Outbox quando `uploadFn` termina sem erro.
  Future<void> processQueue({
    required Future<void> Function(OutboxItem item, File file) uploadFn,
    int maxAttempts = 20,
    int? maxItems,
    String? originalName,
    String? osFolderId,
    String? osLabel,
  }) async {
    var candidates = _items.where((e) {
      final st = (e.status == OutboxStatus.pending || e.status == OutboxStatus.failed);
      final f1 = osFolderId == null || e.osFolderId == osFolderId;
      final f2 = osLabel == null || e.osLabel == osLabel;
      return st && f1 && f2;
    }).toList();

    if (maxItems != null && maxItems > 0 && candidates.length > maxItems) {
      candidates = candidates.take(maxItems).toList(growable: false);
    }

    for (final it in candidates) {
      if (it.attempts >= maxAttempts) continue;

      final file = File(it.localPath);
      if (!await file.exists()) {
        it.status = OutboxStatus.missing;
        it.lastError = "Arquivo não existe mais na Outbox.";
        await _saveState();
        continue;
      }

      it.status = OutboxStatus.uploading;
      it.attempts += 1;
      it.lastTryAt = DateTime.now();
      await _saveState();

      try {
        await uploadFn(it, file);

        // OK -> apaga cópia local
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }

        it.status = OutboxStatus.uploaded;
        it.lastError = null;
        await _saveState();
      } catch (e) {
        it.status = OutboxStatus.failed;
        it.lastError = e.toString();
        await _saveState();
      }
    }

    await cleanupUploaded(osFolderId: osFolderId, osLabel: osLabel);
  }
}