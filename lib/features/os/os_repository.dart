// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
//os_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'os_models.dart';

class OsRepository {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<OsModel>> listarOs({
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
      // Pesquisa por cliente, nroos e arquivo_nome
      q = q.or('cliente.ilike.%$s%,nroos.ilike.%$s%,arquivo_nome.ilike.%$s%');
    }

    final res = await q
        .order('arquivo_mtime', ascending: false)
        .limit(limit);

    final list = (res as List).cast<Map<String, dynamic>>();
    return list.map(OsModel.fromMap).toList();
  }

  Future<OsModel> obterOsPorId(String id) async {
    final res = await _db.from('os').select().eq('id', id).single();
    return OsModel.fromMap(res as Map<String, dynamic>);
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

  Future<List<OsApontamento>> listarApontamentos(String osId) async {
    final res = await _db
        .from('os_apontamentos')
        .select()
        .eq('os_id', osId)
        .order('data', ascending: false)
        .order('inicio', ascending: false);

    final list = (res as List).cast<Map<String, dynamic>>();
    return list.map(OsApontamento.fromMap).toList();
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
    await _db.from('os_apontamentos').insert({
      'os_id': osId,
      'data': _dateToYmd(data),
      'inicio': inicioHHmmss,
      'fim': fimHHmmss,
      'horas': horas,
      'descricao': descricao,
      'tecnico': tecnico,
    });
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
    await _db.from('os_apontamentos').update({
      'data': _dateToYmd(data),
      'inicio': inicioHHmmss,
      'fim': fimHHmmss,
      'horas': horas,
      'descricao': descricao,
      'tecnico': tecnico,
    }).eq('id', id);
  }

  Future<void> excluirApontamento(String id) async {
    await _db.from('os_apontamentos').delete().eq('id', id);
  }

  static String _dateToYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
