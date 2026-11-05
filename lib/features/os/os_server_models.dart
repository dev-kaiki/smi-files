// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'package:flutter/material.dart';

class OsServerModel {
  final String id;

  final String empresa;
  final String filial;
  final String anomovto;
  final String nroos;
  final String seqos;

  final DateTime? dataAbertura;
  final String? departamento;
  final String? cliente;

  final String? servicoSolicitado;
  final String? servicoExecutado;

  final String statusArquivo; // inc|alt|exc
  final bool deleted;

  final String? arquivoNome;
  final DateTime? arquivoMtime;

  OsServerModel({
    required this.id,
    required this.empresa,
    required this.filial,
    required this.anomovto,
    required this.nroos,
    required this.seqos,
    required this.dataAbertura,
    required this.departamento,
    required this.cliente,
    required this.servicoSolicitado,
    required this.servicoExecutado,
    required this.statusArquivo,
    required this.deleted,
    required this.arquivoNome,
    required this.arquivoMtime,
  });

  String get osKey => 'OS$empresa$filial$anomovto$nroos$seqos';

  static DateTime? _tryParseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // Se vier só "YYYY-MM-DD", DateTime.parse funciona.
    // Se vier ISO completo também.
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  factory OsServerModel.fromMap(Map<String, dynamic> m) {
    return OsServerModel(
      id: (m['id'] ?? '').toString(),
      empresa: (m['empresa'] ?? '').toString(),
      filial: (m['filial'] ?? '').toString(),
      anomovto: (m['anomovto'] ?? '').toString(),
      nroos: (m['nroos'] ?? '').toString(),
      seqos: (m['seqos'] ?? '').toString(),
      dataAbertura: _tryParseDate(m['dataabertura']),
      departamento: m['departamento']?.toString(),
      cliente: m['cliente']?.toString(),
      servicoSolicitado: m['servico_solicitado']?.toString(),
      servicoExecutado: m['servico_executado']?.toString(),
      statusArquivo: (m['status_arquivo'] ?? 'inc').toString(),
      deleted: (m['deleted'] ?? false) == true,
      arquivoNome: m['arquivo_nome']?.toString(),
      arquivoMtime: _tryParseDate(m['arquivo_mtime']),
    );
  }
}

class OsApontamentoModel {
  final String id;

  /// ✅ Nome “oficial” compatível com tabelas que usam os_folder_id
  final String osFolderId;

  /// Data (YYYY-MM-DD ou ISO)
  final DateTime data;

  /// HH:mm
  final TimeOfDay? inicio;
  final TimeOfDay? fim;

  final double? horas;
  final String? descricao;
  final String? tecnico;

  OsApontamentoModel({
    required this.id,
    required this.osFolderId,
    required this.data,
    required this.inicio,
    required this.fim,
    required this.horas,
    required this.descricao,
    required this.tecnico,
  });

  /// ✅ Compatibilidade: caso algum lugar ainda use "osId"
  String get osId => osFolderId;

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();

    final s = v.toString().trim();
    if (s.isEmpty) return DateTime.now();

    try {
      return DateTime.parse(s);
    } catch (_) {
      return DateTime.now();
    }
  }

  static TimeOfDay? _parseTime(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // aceita "HH:MM:SS" ou "HH:MM"
    final parts = s.split(':');
    if (parts.length < 2) return null;

    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;

    return TimeOfDay(
      hour: h.clamp(0, 23),
      minute: m.clamp(0, 59),
    );
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(',', '.');
    return double.tryParse(s);
  }

  static String _toYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String? _toHHmmss(TimeOfDay? t) {
    if (t == null) return null;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
    // se sua coluna for TIME sem segundos, pode trocar pra '$hh:$mm'
  }

  /// ✅ Lê tanto "os_folder_id" quanto "os_id"
  factory OsApontamentoModel.fromMap(Map<String, dynamic> m) {
    final folderId = (m['os_folder_id'] ?? m['os_id'] ?? '').toString();

    return OsApontamentoModel(
      id: (m['id'] ?? '').toString(),
      osFolderId: folderId,
      data: _parseDate(m['data']),
      inicio: _parseTime(m['inicio']),
      fim: _parseTime(m['fim']),
      horas: _parseDouble(m['horas']),
      descricao: m['descricao']?.toString(),
      tecnico: m['tecnico']?.toString(),
    );
  }

  /// ✅ Map pronto para INSERT (usa os_folder_id)
  Map<String, dynamic> toInsertMap() {
    return {
      'os_folder_id': osFolderId,
      'data': _toYmd(data),
      'inicio': _toHHmmss(inicio),
      'fim': _toHHmmss(fim),
      'horas': horas,
      'descricao': (descricao?.trim().isEmpty ?? true) ? null : descricao!.trim(),
      'tecnico': (tecnico?.trim().isEmpty ?? true) ? null : tecnico!.trim(),
    };
  }

  /// ✅ Map pronto para UPDATE
  Map<String, dynamic> toUpdateMap() {
    return {
      'data': _toYmd(data),
      'inicio': _toHHmmss(inicio),
      'fim': _toHHmmss(fim),
      'horas': horas,
      'descricao': (descricao?.trim().isEmpty ?? true) ? null : descricao!.trim(),
      'tecnico': (tecnico?.trim().isEmpty ?? true) ? null : tecnico!.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  OsApontamentoModel copyWith({
    String? id,
    String? osFolderId,
    DateTime? data,
    TimeOfDay? inicio,
    TimeOfDay? fim,
    double? horas,
    String? descricao,
    String? tecnico,
  }) {
    return OsApontamentoModel(
      id: id ?? this.id,
      osFolderId: osFolderId ?? this.osFolderId,
      data: data ?? this.data,
      inicio: inicio ?? this.inicio,
      fim: fim ?? this.fim,
      horas: horas ?? this.horas,
      descricao: descricao ?? this.descricao,
      tecnico: tecnico ?? this.tecnico,
    );
  }
}
