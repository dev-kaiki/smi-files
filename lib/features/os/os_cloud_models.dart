// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/os/os_cloud_models.dart

import '../../utils/setor_access.dart';

class OsFolderCloud {
  final String id; // uuid
  final int ano;
  final String osCode; // ex: "0001/001"
  final String storagePrefix; // ex: "os/2026/0001/001"
  final String? setor; // deve ser o "departamento"
  final String? tipo; // deve ser a empresa: "001"|"002"|"003" (ou texto em casos antigos)
  final String? status;
  final String? execucao;
  final String? coverPath;
  final int? clientId;
  final String? clienteNome;

  OsFolderCloud({
    required this.id,
    required this.ano,
    required this.osCode,
    required this.storagePrefix,
    this.setor,
    this.tipo,
    this.status,
    this.execucao,
    this.coverPath,
    this.clientId,
    this.clienteNome,
  });

  // =========================
  // Normalização / Correções
  // =========================

  static bool _isBlank(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    return v.isEmpty || v == 'null' || v == 'none' || v == 'undefined';
  }

  static bool _isEmpresaCode(String? v) {
    final s = (v ?? '').trim();
    return s == '001' || s == '002' || s == '003' || s == '1' || s == '2' || s == '3';
  }

  static String? _normalizeEmpresaCode(String? v) {
    final s = (v ?? '').trim();
    if (s == '1' || s == '01' || s == '001') return '001';
    if (s == '2' || s == '02' || s == '002') return '002';
    if (s == '3' || s == '03' || s == '003') return '003';
    if (s.length == 3 && int.tryParse(s) != null) return s;
    return _isBlank(s) ? null : s;
  }

  /// Corrige inversão clássica: tipo="Geral" e setor="001" -> swap
  static ({String? tipo, String? setor}) _fixSwapTipoSetor(String? tipoRaw, String? setorRaw) {
    final t = (tipoRaw ?? '').trim();
    final s = (setorRaw ?? '').trim();

    // se setor é empresa (001/002/003) e tipo NÃO é empresa -> invertido
    if (_isEmpresaCode(s) && !_isEmpresaCode(t)) {
      return (tipo: s, setor: t);
    }
    return (tipo: tipoRaw, setor: setorRaw);
  }

  static String _normalizeStoragePrefix({
    required String? raw,
    required int ano,
    required String osCode,
  }) {
    var p = (raw ?? '').trim();
    final low = p.toLowerCase();
    if (p.isEmpty || low == 'null' || low == 'none' || low == 'undefined') {
      // fallback consistente quando vier vazio
      if (ano > 0 && osCode.trim().isNotEmpty) {
        p = 'os/$ano/${osCode.trim()}';
      } else if (ano > 0) {
        p = 'os/$ano';
      } else {
        p = 'os';
      }
    }

    // remove barras duplicadas
    while (p.contains('//')) {
      p = p.replaceAll('//', '/');
    }
    // remove barra inicial
    if (p.startsWith('/')) p = p.substring(1);
    // remove barra final
    if (p.endsWith('/')) p = p.substring(0, p.length - 1);

    return p;
  }

  static String _empresaLabelFromCode(String? code) {
    final c = _normalizeEmpresaCode(code);
    switch (c) {
      case '001':
        return 'Serviços';
      case '002':
        return 'Assistência';
      case '003':
        return 'Reforma';
      default:
      // se veio texto antigo, tenta usar isso de forma humana
        final t = (code ?? '').trim();
        return _isBlank(t) ? 'Sem tipo' : t;
    }
  }

  static String _tipoDirFromCode(String? code) {
    final c = _normalizeEmpresaCode(code);
    switch (c) {
      case '001':
        return 'servicos';
      case '002':
        return 'assistencia';
      case '003':
        return 'reforma';
      default:
      // texto antigo -> slug simples
        final t = (code ?? '').trim().toLowerCase();
        if (t.contains('assist')) return 'assistencia';
        if (t.contains('serv')) return 'servicos';
        if (t.contains('reform')) return 'reforma';
        return _isBlank(t) ? 'sem_tipo' : _slug(t);
    }
  }

  static String _setorDirFromText(String? setor) {
    final normalized = normalizeSetor(setor);
    return normalized.isEmpty ? 'sem_setor' : normalized;
  }

  static String _slug(String s) {
    var out = s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll(RegExp(r'ç'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (out.isEmpty) out = 'sem_setor';
    return out;
  }

  // =========================
  // Getters úteis pro app
  // =========================

  /// "001" | "002" | "003" (quando tipo vier como código)
  String? get empresaCodigo => _normalizeEmpresaCode(tipo);

  /// "Serviços" | "Assistência" | "Reforma" (ou texto antigo)
  String get empresaLabel => _empresaLabelFromCode(tipo);

  /// "servicos" | "assistencia" | "reforma"
  String get tipoDir => _tipoDirFromCode(tipo);

  /// "geral", "lab_eletronico", "usinagem" etc (sempre vindo do departamento)
  String get setorDir => _setorDirFromText(setor);

  factory OsFolderCloud.fromMap(Map<String, dynamic> map) {
    final cliente = map['clientes'];
    String? clienteNome;
    if (cliente is Map<String, dynamic>) {
      clienteNome = (cliente['razao_social'] ?? cliente['codigo'])?.toString();
    } else if (cliente is List && cliente.isNotEmpty && cliente.first is Map) {
      final m = cliente.first as Map;
      clienteNome = (m['razao_social'] ?? m['codigo'])?.toString();
    }

    final ano = (map['ano'] as num?)?.toInt() ?? 0;
    final osCode = (map['os_code'] ?? '').toString();

    // pega bruto
    final tipoRaw = map['tipo']?.toString();
    final setorRaw = map['setor']?.toString();

    // auto-correção se estiver invertido
    final fixed = _fixSwapTipoSetor(tipoRaw, setorRaw);

    // normaliza prefix
    final storagePrefix = _normalizeStoragePrefix(
      raw: map['storage_prefix']?.toString(),
      ano: ano,
      osCode: osCode,
    );

    return OsFolderCloud(
      id: map['id'].toString(),
      ano: ano,
      osCode: osCode,
      storagePrefix: storagePrefix,
      setor: fixed.setor,
      tipo: fixed.tipo,
      status: map['status']?.toString(),
      execucao: map['execucao']?.toString(),
      coverPath: map['cover_path']?.toString(),
      clientId: (map['client_id'] as num?)?.toInt(),
      clienteNome: clienteNome,
    );
  }
}

class MediaFileCloud {
  final String id; // uuid
  final String osFolderId; // uuid
  final String storagePath; // "os/2026/0001/001/arquivo.jpg"
  final String? fileType; // "jpg", "mp4" etc
  final bool isCover;

  final String? tag;
  final String? obs;
  final DateTime? createdAt;

  MediaFileCloud({
    required this.id,
    required this.osFolderId,
    required this.storagePath,
    this.fileType,
    required this.isCover,
    this.tag,
    this.obs,
    this.createdAt,
  });

  factory MediaFileCloud.fromMap(Map<String, dynamic> map) {
    DateTime? dt;
    final raw = map['created_at'];
    if (raw is String && raw.isNotEmpty) dt = DateTime.tryParse(raw);

    // suporta os dois nomes (pra não quebrar se o banco mudar)
    final folderId = (map['os_folder_id'] ?? map['folder_id'] ?? '').toString();

    return MediaFileCloud(
      id: map['id'].toString(),
      osFolderId: folderId,
      storagePath: (map['storage_path'] ?? '').toString(),
      fileType: map['file_type']?.toString(),
      isCover: (map['is_cover'] as bool?) ?? false,
      tag: map['tag']?.toString(),
      obs: map['obs']?.toString(),
      createdAt: dt,
    );
  }

  bool get isImage {
    final ext = (fileType ?? '').toLowerCase();
    return [
      'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'image'
    ].contains(ext);
  }

  bool get isVideo {
    final ext = (fileType ?? '').toLowerCase();
    return [
      'mp4', 'mov', 'mkv', 'webm', 'avi', '3gp', 'm4v', 'video'
    ].contains(ext);
  }
}