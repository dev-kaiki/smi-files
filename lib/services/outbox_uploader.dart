// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'dart:developer' as developer;
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'outbox_service.dart';

class OutboxUploader {
  OutboxUploader._();

  bool _processing = false;

  static final OutboxUploader I = OutboxUploader._();

  void _log(String message) {
    developer.log(message, name: 'SMI_OUTBOX');
  }

  Future<void> _uploadWithRetry(SupabaseClient supabase, OutboxItem item, File file) async {
    const maxAttempts = 3;
    final isVideo = (item.fileType ?? '').toLowerCase() == 'video';
    final timeout = isVideo ? const Duration(hours: 2) : const Duration(minutes: 30);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        _log('[UPLOAD] tentativa=$attempt bucket=${item.bucket} path=${item.storagePath} local=${file.path} size=${file.lengthSync()}');
        await supabase.storage.from(item.bucket).upload(
          item.storagePath,
          file,
          fileOptions: FileOptions(
            upsert: false,
            contentType: item.contentType,
          ),
        ).timeout(timeout);
        _log('[UPLOAD] sucesso bucket=${item.bucket} path=${item.storagePath}');
        return;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('already exists') || msg.contains('duplicate') || msg.contains('409')) {
          _log('[UPLOAD] objeto já existe no Storage; seguindo para gravar/confirmar media_files. path=${item.storagePath}');
          return;
        }

        _log('[UPLOAD] falha tentativa=$attempt bucket=${item.bucket} path=${item.storagePath} erro=$e');
        if (attempt == maxAttempts) {
          throw Exception('Falha no upload para o Storage. bucket=${item.bucket} path=${item.storagePath} erro=$e');
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  /// Reenvia pendências (opcionalmente filtrando por OS).
  ///
  /// maxItems evita que um lote muito grande prenda a rotina de envio por tempo excessivo.
  Future<void> processPending({String? osFolderId, String? osLabel, int? maxItems}) async {
    if (_processing) {
      _log('[QUEUE] processamento já em andamento; chamada ignorada para evitar upload duplicado.');
      return;
    }

    _processing = true;
    try {
      final supabase = Supabase.instance.client;

      await OutboxService.I.processQueue(
        osFolderId: osFolderId,
        osLabel: osLabel,
        maxItems: maxItems,
        uploadFn: (OutboxItem item, File file) async {
          await _uploadWithRetry(supabase, item, file);

          final osFolder = (item.osFolderId ?? '').trim();
          if (osFolder.isEmpty) {
            _log('[DB] item sem os_folder_id. Storage subiu, mas não há vínculo para media_files. item=${item.id}');
            return;
          }

          bool makeCover = false;
          if ((item.fileType ?? '').toLowerCase() == 'image') {
            try {
              final row = await supabase.from('os_folders').select('cover_path').eq('id', osFolder).maybeSingle();
              final cover = (row == null ? '' : (row['cover_path'] ?? '').toString()).trim();
              makeCover = cover.isEmpty;
            } catch (_) {
              makeCover = false;
            }
          }

          final data = <String, dynamic>{
            'id': item.id,
            'os_folder_id': osFolder,
            'file_type': (item.fileType ?? 'file').toLowerCase(),
            'storage_path': item.storagePath,
            'storage_bucket': item.bucket,
            'original_name': item.originalName,
            'content_type': item.contentType,
            'size_bytes': item.sizeBytes,
            'is_cover': makeCover,
            if (item.exifTakenAt != null) 'exif_taken_at': item.exifTakenAt!.toIso8601String(),
            if (item.exifWidth != null) 'exif_width': item.exifWidth,
            if (item.exifHeight != null) 'exif_height': item.exifHeight,
          };

          final createdBy = (item.createdBy ?? '').trim();
          if (createdBy.isNotEmpty) data['created_by'] = createdBy;

          try {
            await supabase.from('media_files').upsert(data, onConflict: 'id');
            _log('[DB] upsert media_files OK id=${item.id} os_folder_id=$osFolder path=${item.storagePath}');
          } catch (e) {
            _log('[DB] upsert media_files FALHOU id=${item.id} os_folder_id=$osFolder erro=$e');
            throw Exception('Upload no Storage concluído, mas falhou ao gravar media_files. os_folder_id=$osFolder erro=$e');
          }

          if (makeCover) {
            await supabase.from('os_folders').update({'cover_path': item.storagePath}).eq('id', osFolder);
            _log('[DB] cover_path atualizado os_folder_id=$osFolder path=${item.storagePath}');
          }
        },
      );
    } finally {
      _processing = false;
    }
  }
}
