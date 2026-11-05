// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/pending/pending_media_retry_service.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../core/supabase/supabase_manager.dart';
import '../utils/smi_watermark.dart';
import 'pending_media_store.dart';

class PendingMediaRetryService {
  const PendingMediaRetryService();

  Future<void> retryOne(PendingMediaItem item) async {
    final file = File(item.localPath);
    if (!await file.exists()) {
      await PendingMediaStore.I.addOrUpdate(
        item.copyWith(
          attempts: item.attempts + 1,
          lastAttemptAt: DateTime.now(),
          lastError: 'Arquivo não encontrado no aparelho: ${item.localPath}',
        ),
      );
      return;
    }

    File? processedTemp;
    File fileToSend = file;

    DateTime? exifTakenAt;
    int? exifWidth;
    int? exifHeight;

    try {
      try {
        exifTakenAt = await file.lastModified();
      } catch (_) {}

      if (item.fileType == 'image') {
        // lê tamanho (aprox) para salvar metadados
        try {
          final bytes = await file.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          exifWidth = frame.image.width;
          exifHeight = frame.image.height;
        } catch (_) {}

        processedTemp = await SmiWatermark.addWatermark(
          original: file,
          osLabel: item.osLabel,
          tipo: item.tipo,
          setor: item.setor,
          dateTime: DateTime.now(),
        );

        fileToSend = processedTemp;
      }

      await _uploadWithRetry(
        bucket: item.bucket,
        storagePath: item.storagePath,
        file: fileToSend,
        isVideo: item.fileType == 'video',
        contentType: item.contentType,
      );

      // define capa se for a primeira imagem
      bool makeCover = false;
      if (item.fileType == 'image') {
        final exists = await SupabaseManager.client
            .from('media_files')
            .select('id')
            .eq('os_folder_id', item.osFolderId)
            .eq('file_type', 'image')
            .limit(1);
        makeCover = (exists as List).isEmpty;
      }

      // V9.4 FIX: inclui todos os campos obrigatórios para que o servidor
      // Python consiga montar a URL de download via vw_media_backup.
      // storage_bucket, original_name, content_type e size_bytes eram omitidos,
      // o que excluía a mídia do backup automático.
      final int uploadedSizeBytes = await fileToSend.length();

      await SupabaseManager.client.from('media_files').insert({
        'os_folder_id': item.osFolderId,
        'file_type': item.fileType,
        'storage_path': item.storagePath,
        'storage_bucket': item.bucket,
        'original_name': PendingMediaRetryService.filename(item),
        'content_type': item.contentType,
        'size_bytes': uploadedSizeBytes,
        'is_cover': makeCover,
        'exif_taken_at': exifTakenAt?.toIso8601String(),
        'exif_width': exifWidth,
        'exif_height': exifHeight,
      });

      if (makeCover) {
        await SupabaseManager.client.from('os_folders').update({'cover_path': item.storagePath}).eq('id', item.osFolderId);
      }

      // sucesso
      await PendingMediaStore.I.remove(item.id);
    } catch (e) {
      await PendingMediaStore.I.addOrUpdate(
        item.copyWith(
          attempts: item.attempts + 1,
          lastAttemptAt: DateTime.now(),
          lastError: e.toString(),
        ),
      );
    } finally {
      // apaga temp do watermark
      try {
        if (processedTemp != null && await processedTemp.exists()) {
          await processedTemp.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> retryAll() async {
    final items = await PendingMediaStore.I.list();
    for (final it in items) {
      await retryOne(it);
    }
  }

  Future<void> _uploadWithRetry({
    required String bucket,
    required String storagePath,
    required File file,
    required bool isVideo,
    String? contentType,
  }) async {
    const maxAttempts = 3;
    final timeout = isVideo ? const Duration(hours: 2) : const Duration(minutes: 30);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final storage = SupabaseManager.client.storage.from(bucket);
        if (contentType != null && contentType.trim().isNotEmpty) {
          await storage
              .upload(storagePath, file, fileOptions: FileOptions(contentType: contentType))
              .timeout(timeout);
        } else {
          await storage.upload(storagePath, file).timeout(timeout);
        }
        return;
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  static String filename(PendingMediaItem item) {
    final sp = item.storagePath;
    if (sp.trim().isEmpty) return p.basename(item.localPath);
    return p.basename(sp);
  }
}
