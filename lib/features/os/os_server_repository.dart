// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'package:postgrest/postgrest.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'os_server_models.dart';

class OsServerRepository {
  final SupabaseClient _db = Supabase.instance.client;

  // Ajuste aqui se quiser forçar um nome específico.
  // Deixo os dois para fallback automático.
  static const List<String> _apontTables = <String>[
    'os_folder_apontamentos',
    'os_apontamentos',
  ];

  // =========================
  // OS (tabela: os)
  // =========================

  Future<List<OsServerModel>> listarOs({
    String? search,
    bool incluirExcluidas = true,
    int limit = 200,
  }) async {
    var q = _db.from('os').select();

    if (!incluirExcluidas) {
      q = q.eq('deleted', false);
    }

    if (search != null && search.trim().isNotEmpty) {
      final s = search.trim();
      // Campos comuns no seu modelo/tabela
      q = q.or(
        'cliente.ilike.%$s%,'
            'nroos.ilike.%$s%,'
            'seqos.ilike.%$s%,'
            'arquivo_nome.ilike.%$s%,'
            'servico_solicitado.ilike.%$s%,'
            'servico_executado.ilike.%$s%',
      );
    }

    final res = await q.order('arquivo_mtime', ascending: false).limit(limit);

    final list = (res as List).cast<Map<String, dynamic>>();
    return list.map(OsServerModel.fromMap).toList();
  }

  Future<OsServerModel> obterPorId(String id) async {
    final res = await _db.from('os').select().eq('id', id).single();
    return OsServerModel.fromMap(res as Map<String, dynamic>);
  }

  Future<void> atualizarServicoExecutado({
    required String osId,
    required String? servicoExecutado,
  }) async {
    await _db.from('os').update({
      'servico_executado': servicoExecutado,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', osId);
  }

  // =========================
  // APONTAMENTOS (fallback os_folder_id <-> os_id, e tabela)
  // =========================

  Future<List<OsApontamentoModel>> listarApontamentos(String osId) async {
    final res = await _trySelectApontamentos(osId);

    final list = (res as List).cast<Map<String, dynamic>>();
    return list.map(OsApontamentoModel.fromMap).toList();
  }

  Future<void> criarApontamento({
    required String osId,
    required DateTime data,
    required String? inicioHHmmss,
    required String? fimHHmmss,
    required double? horas,
    required String? descricao,
    required String? tecnico,
  }) async {
    final payloadBase = <String, dynamic>{
      'data': _dateToYmd(data),
      'inicio': inicioHHmmss,
      'fim': fimHHmmss,
      'horas': horas,
      'descricao': (descricao?.trim().isEmpty ?? true) ? null : descricao!.trim(),
      'tecnico': (tecnico?.trim().isEmpty ?? true) ? null : tecnico!.trim(),
    };

    await _tryInsertApontamento(osId, payloadBase);
  }

  Future<void> atualizarApontamento({
    required String id,
    required DateTime data,
    required String? inicioHHmmss,
    required String? fimHHmmss,
    required double? horas,
    required String? descricao,
    required String? tecnico,
  }) async {
    final payload = <String, dynamic>{
      'data': _dateToYmd(data),
      'inicio': inicioHHmmss,
      'fim': fimHHmmss,
      'horas': horas,
      'descricao': (descricao?.trim().isEmpty ?? true) ? null : descricao!.trim(),
      'tecnico': (tecnico?.trim().isEmpty ?? true) ? null : tecnico!.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await _tryUpdateApontamento(id, payload);
  }

  Future<void> excluirApontamento(String id) async {
    await _tryDeleteApontamento(id);
  }

  // =========================
  // Internos (fallback)
  // =========================

  Future<dynamic> _trySelectApontamentos(String osId) async {
    PostgrestException? last;

    // tenta: tabela1/os_folder_id -> tabela1/os_id -> tabela2/os_folder_id -> tabela2/os_id
    for (final table in _apontTables) {
      // 1) os_folder_id
      try {
        return await _db
            .from(table)
            .select()
            .eq('os_folder_id', osId)
            .order('data', ascending: false)
            .order('inicio', ascending: false);
      } on PostgrestException catch (e) {
        last = e;
        if (!_isMissingColumnOrTable(e)) rethrow;
      }

      // 2) os_id
      try {
        return await _db
            .from(table)
            .select()
            .eq('os_id', osId)
            .order('data', ascending: false)
            .order('inicio', ascending: false);
      } on PostgrestException catch (e) {
        last = e;
        if (!_isMissingColumnOrTable(e)) rethrow;
      }
    }

    // se chegou aqui, não achou tabela/coluna compatível
    throw last ?? Exception('Não foi possível listar apontamentos (tabela/coluna não encontrada).');
  }

  Future<void> _tryInsertApontamento(String osId, Map<String, dynamic> payloadBase) async {
    PostgrestException? last;

    for (final table in _apontTables) {
      // 1) tenta os_folder_id
      try {
        final payload = Map<String, dynamic>.from(payloadBase)..['os_folder_id'] = osId;
        await _db.from(table).insert(payload);
        return;
      } on PostgrestException catch (e) {
        last = e;
        if (!_isMissingColumnOrTable(e)) rethrow;
      }

      // 2) tenta os_id
      try {
        final payload = Map<String, dynamic>.from(payloadBase)..['os_id'] = osId;
        await _db.from(table).insert(payload);
        return;
      } on PostgrestException catch (e) {
        last = e;
        if (!_isMissingColumnOrTable(e)) rethrow;
      }
    }

    throw last ?? Exception('Não foi possível inserir apontamento (tabela/coluna não encontrada).');
  }

  Future<void> _tryUpdateApontamento(String id, Map<String, dynamic> payload) async {
    PostgrestException? last;

    for (final table in _apontTables) {
      try {
        await _db.from(table).update(payload).eq('id', id);
        return;
      } on PostgrestException catch (e) {
        last = e;
        if (!_isMissingColumnOrTable(e)) rethrow;
      }
    }

    throw last ?? Exception('Não foi possível atualizar apontamento (tabela não encontrada).');
  }

  Future<void> _tryDeleteApontamento(String id) async {
    PostgrestException? last;

    for (final table in _apontTables) {
      try {
        await _db.from(table).delete().eq('id', id);
        return;
      } on PostgrestException catch (e) {
        last = e;
        if (!_isMissingColumnOrTable(e)) rethrow;
      }
    }

    throw last ?? Exception('Não foi possível excluir apontamento (tabela não encontrada).');
  }

  bool _isMissingColumnOrTable(PostgrestException e) {
    final msg = (e.message).toLowerCase();
    final details = (e.details ?? '').toString().toLowerCase();
    final hint = (e.hint ?? '').toString().toLowerCase();
    final all = '$msg $details $hint';

    // PostgREST costuma falar "column ... does not exist" / "relation ... does not exist"
    return all.contains('does not exist') ||
        all.contains('column') && all.contains('exist') ||
        all.contains('relation') && all.contains('exist') ||
        all.contains('schema cache');
  }

  static String _dateToYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
