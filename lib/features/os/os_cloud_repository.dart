// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/os/os_cloud_repository.dart
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'os_cloud_models.dart';

class OsCloudRepository {
  OsCloudRepository({
    SupabaseClient? client,
    this.bucket = 'smi_midias',
  }) : _sb = client ?? Supabase.instance.client;

  final SupabaseClient _sb;
  final String bucket;

  String? _mediaFolderColCache; // "os_folder_id" | "folder_id"

  // =========================
  // Normalização (empresa/tipo)
  // =========================

  bool _isBlank(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    return v.isEmpty || v == 'null' || v == 'none' || v == 'undefined';
  }

  String? _normalizeEmpresaCode(String? input) {
    // Retorna "001"|"002"|"003" quando reconhece; caso contrário null.
    final t = (input ?? '').trim();
    if (_isBlank(t)) return null;

    final low = t.toLowerCase();

    if (t == '1' || t == '01' || t == '001') return '001';
    if (t == '2' || t == '02' || t == '002') return '002';
    if (t == '3' || t == '03' || t == '003') return '003';

    if (low.contains('serv')) return '001';
    if (low.contains('assist')) return '002';
    if (low.contains('reform')) return '003';

    return null;
  }

  String? _normalizeTipoEnum(String? input) {
    // Retorna o enum textual do banco: "servicos" | "assistencia" | "reforma"
    final code = _normalizeEmpresaCode(input);
    if (code == '001') return 'servicos';
    if (code == '002') return 'assistencia';
    if (code == '003') return 'reforma';

    final t = (input ?? '').trim();
    if (_isBlank(t)) return null;

    final low = t.toLowerCase();
    if (low.contains('serv')) return 'servicos';
    if (low.contains('assist')) return 'assistencia';
    if (low.contains('reform')) return 'reforma';

    // se o banco estiver com texto legado, deixa passar
    return t;
  }

  // =========================
  // OS Folders
  // =========================

  Future<List<OsFolderCloud>> fetchFolders({
    int? ano,
    String? query,
    String? setor,
    String? tipo,
    String? status,
    int limit = 200,
  }) async {
    final s = (query ?? '').trim();

    final empresaCode = _normalizeEmpresaCode(tipo);
    final tipoEnum = _normalizeTipoEnum(tipo);
    final setorDb = (setor ?? '').trim();
    final statusDb = (status ?? '').trim();

    if (s.isEmpty) {
      final rows = await _fetchFoldersBase(
        ano: ano,
        setor: setorDb.isEmpty ? null : setorDb,
        empresaCode: empresaCode,
        tipoEnum: tipoEnum,
        status: statusDb.isEmpty ? null : statusDb,
        limit: limit,
      );
      return rows.map(OsFolderCloud.fromMap).toList();
    }

    // Sem .or() -> 3 consultas e junta
    final a = await _fetchFoldersBase(
      ano: ano,
      setor: setorDb.isEmpty ? null : setorDb,
      empresaCode: empresaCode,
      tipoEnum: tipoEnum,
      status: statusDb.isEmpty ? null : statusDb,
      limit: limit,
      extraFilter: (q) => q.ilike('os_code', '%$s%'),
    );

    final b = await _fetchFoldersBase(
      ano: ano,
      setor: setorDb.isEmpty ? null : setorDb,
      empresaCode: empresaCode,
      tipoEnum: tipoEnum,
      status: statusDb.isEmpty ? null : statusDb,
      limit: limit,
      extraFilter: (q) => q.ilike('clientes.razao_social', '%$s%'),
    );

    final c = await _fetchFoldersBase(
      ano: ano,
      setor: setorDb.isEmpty ? null : setorDb,
      empresaCode: empresaCode,
      tipoEnum: tipoEnum,
      status: statusDb.isEmpty ? null : statusDb,
      limit: limit,
      extraFilter: (q) => q.ilike('clientes.codigo', '%$s%'),
    );

    final map = <String, Map<String, dynamic>>{};
    for (final r in [...a, ...b, ...c]) {
      map[r['id'].toString()] = r;
    }

    final list = map.values.toList();
    list.sort((x, y) {
      final ay = (y['ano'] as num?)?.toInt() ?? 0;
      final ax = (x['ano'] as num?)?.toInt() ?? 0;
      if (ay != ax) return ay.compareTo(ax);

      // os_code desc (mais novo primeiro)
      final oy = (y['os_code'] ?? '').toString();
      final ox = (x['os_code'] ?? '').toString();
      return ox.compareTo(oy);
    });

    return list.take(limit).map(OsFolderCloud.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchFoldersBase({
    int? ano,
    String? setor,
    String? empresaCode,
    String? tipoEnum,
    String? status,
    int limit = 200,
    PostgrestFilterBuilder<PostgrestList> Function(
        PostgrestFilterBuilder<PostgrestList> q,
        )?
    extraFilter,
  }) async {
    PostgrestFilterBuilder<PostgrestList> q = _sb.from('os_folders').select(
      'id, client_id, ano, os_code, os_principal_code, is_sub, empresa_code, storage_prefix, setor, tipo, status, execucao, cover_path, created_at, '
          'clientes:client_id(codigo, razao_social)',
    );

    if (ano != null) q = q.eq('ano', ano);

    // setor: primeiro tenta eq
    if (setor != null && setor.trim().isNotEmpty) {
      q = q.eq('setor', setor.trim());
    }

    // empresa_code é a fonte de verdade quando existir
    if (empresaCode != null && empresaCode.trim().isNotEmpty) {
      q = q.eq('empresa_code', empresaCode.trim());
    } else if (tipoEnum != null && tipoEnum.trim().isNotEmpty) {
      // fallback para legado
      q = q.eq('tipo', tipoEnum.trim());
    }

    if (status != null && status.trim().isNotEmpty) {
      q = q.eq('status', status.trim());
    }

    if (extraFilter != null) q = extraFilter(q);

    try {
      final res = await q.order('ano', ascending: false).order('os_code', ascending: false).limit(limit);
      return (res as List).cast<Map<String, dynamic>>();
    } on PostgrestException catch (e) {
      // Se o schema ainda não tem empresa_code/is_sub/os_principal_code, faz fallback automático
      final msg = (e.message ?? '').toLowerCase();
      final isMissingColumn = e.code == '42703' ||
          msg.contains('empresa_code') ||
          msg.contains('os_principal_code') ||
          msg.contains('is_sub');

      if (isMissingColumn) {
        PostgrestFilterBuilder<PostgrestList> qLegacy = _sb.from('os_folders').select(
          'id, client_id, ano, os_code, storage_prefix, setor, tipo, status, execucao, cover_path, created_at, '
              'clientes:client_id(codigo, razao_social)',
        );

        if (ano != null) qLegacy = qLegacy.eq('ano', ano);

        if (setor != null && setor.trim().isNotEmpty) {
          qLegacy = qLegacy.eq('setor', setor.trim());
        }

        if (tipoEnum != null && tipoEnum.trim().isNotEmpty) {
          qLegacy = qLegacy.eq('tipo', tipoEnum.trim());
        }

        if (status != null && status.trim().isNotEmpty) {
          qLegacy = qLegacy.eq('status', status.trim());
        }

        if (extraFilter != null) qLegacy = extraFilter(qLegacy);

        final resLegacy = await qLegacy.order('ano', ascending: false).order('os_code', ascending: false).limit(limit);
        return (resLegacy as List).cast<Map<String, dynamic>>();
      }

      // fallback para setor: se eq falhar por mismatch, tenta ilike
      if (setor != null && setor.trim().isNotEmpty) {
        PostgrestFilterBuilder<PostgrestList> q2 = _sb.from('os_folders').select(
          'id, client_id, ano, os_code, storage_prefix, setor, tipo, status, execucao, cover_path, created_at, '
              'clientes:client_id(codigo, razao_social)',
        );

        if (ano != null) q2 = q2.eq('ano', ano);
        if (tipoEnum != null && tipoEnum.trim().isNotEmpty) q2 = q2.eq('tipo', tipoEnum.trim());
        if (status != null && status.trim().isNotEmpty) q2 = q2.eq('status', status.trim());
        if (extraFilter != null) q2 = extraFilter(q2);

        // setor ilike
        q2 = q2.ilike('setor', '%${setor.trim()}%');

        final res2 = await q2.order('ano', ascending: false).order('os_code', ascending: false).limit(limit);

        return (res2 as List).cast<Map<String, dynamic>>();
      }

      throw e;
    }
  }

  // =========================
  // Media Files
  // =========================

  Future<String> _detectMediaFolderColumn() async {
    // cache
    final cached = _mediaFolderColCache;
    if (cached == 'os_folder_id' || cached == 'folder_id') return cached!;

    // tenta os_folder_id
    try {
      await _sb.from('media_files').select('id,os_folder_id').limit(1);
      _mediaFolderColCache = 'os_folder_id';
      return 'os_folder_id';
    } on PostgrestException {
      // tenta folder_id
      await _sb.from('media_files').select('id,folder_id').limit(1);
      _mediaFolderColCache = 'folder_id';
      return 'folder_id';
    }
  }

  Future<List<MediaFileCloud>> fetchMediaFiles({
    required String osFolderId,
    int limit = 500,
  }) async {
    final col = await _detectMediaFolderColumn();

    final q = _sb
        .from('media_files')
        .select('id, $col, file_type, storage_path, created_at, tag, obs, is_cover')
        .eq(col, osFolderId);

    final res = await q.order('created_at', ascending: false).limit(limit);
    final list = (res as List).cast<Map<String, dynamic>>();

    return list.map(MediaFileCloud.fromMap).toList();
  }

  Future<String> signedUrl(String storagePath, {int expiresInSeconds = 3600}) async {
    return _sb.storage.from(bucket).createSignedUrl(storagePath, expiresInSeconds);
  }

  Future<MediaFileCloud> uploadMediaBytes({
    required OsFolderCloud folder,
    required Uint8List bytes,
    required String fileName,
    required String fileType, // "jpg" | "mp4" | "image/jpeg" etc
    String? tag,
    String? obs,
    bool isCover = false,
  }) async {
    final cleanName = _sanitizeFileName(fileName);

    final path = '${folder.storagePrefix}/$cleanName';

    await _sb.storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        contentType: _guessMime(fileType),
      ),
    );

    final col = await _detectMediaFolderColumn();

    final inserted = await _sb.from('media_files').insert({
      col: folder.id,
      'file_type': _normalizeExt(fileType),
      'storage_path': path,
      'tag': tag,
      'obs': obs,
      'is_cover': isCover,
      'created_by': _sb.auth.currentUser?.id,
    }).select('id, $col, file_type, storage_path, created_at, tag, obs, is_cover').single();

    return MediaFileCloud.fromMap(inserted);
  }

  // =========================
  // Utils
  // =========================

  String _sanitizeFileName(String name) {
    var n = name.trim();
    if (n.isEmpty) n = 'arquivo';
    n = n.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    while (n.endsWith(' ') || n.endsWith('.')) {
      n = n.substring(0, n.length - 1).trimRight();
    }
    if (n.isEmpty) n = 'arquivo';
    return n;
  }

  String _normalizeExt(String input) {
    final t = input.trim().toLowerCase();
    if (t.contains('/')) {
      if (t == 'image/jpeg') return 'jpg';
      if (t == 'image/png') return 'png';
      if (t == 'image/webp') return 'webp';
      if (t == 'image/gif') return 'gif';
      if (t == 'video/mp4') return 'mp4';
      if (t == 'video/quicktime') return 'mov';
      return 'bin';
    }
    return t.replaceAll('.', '');
  }

  String _guessMime(String extOrMime) {
    final e = extOrMime.toLowerCase().trim();
    if (e.contains('/')) return e;
    final ext = e.replaceAll('.', '');

    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    if (ext == 'gif') return 'image/gif';
    if (ext == 'mp4') return 'video/mp4';
    if (ext == 'mov') return 'video/quicktime';
    if (ext == 'mkv') return 'video/x-matroska';
    return 'application/octet-stream';
  }
}