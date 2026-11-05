// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/utils/video_utils.dart
import 'dart:io';

class VideoHelper {
  VideoHelper._();

  /// Sem compressão: devolve o próprio arquivo original.
  ///
  /// Se você quiser evitar uploads absurdos (ex.: 1GB),
  /// passe maxBytes e ele vai bloquear com uma exceção.
  static Future<File> compressIfPossible(
      File input, {
        int? maxBytes,
      }) async {
    if (maxBytes != null) {
      final len = await input.length();
      if (len > maxBytes) {
        throw Exception(
          'Vídeo muito grande (${(len / (1024 * 1024)).toStringAsFixed(1)} MB). '
              'Limite: ${(maxBytes / (1024 * 1024)).toStringAsFixed(1)} MB.',
        );
      }
    }
    return input;
  }

  /// Mantido por compatibilidade (não faz nada).
  static void cancelAll() {}
}
