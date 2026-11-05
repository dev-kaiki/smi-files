// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase/supabase_manager.dart';
import '../../utils/worktime_rules.dart';

class OsFolderApontamentosPage extends StatefulWidget {
  final String osFolderId;
  final String? titleLabel;

  const OsFolderApontamentosPage({
    super.key,
    required this.osFolderId,
    this.titleLabel,
  });

  @override
  State<OsFolderApontamentosPage> createState() => _OsFolderApontamentosPageState();
}

class _OsFolderApontamentosPageState extends State<OsFolderApontamentosPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _osId;
  String? _osStatus;
  String? _osExecucao;
  String? _osSituacaoEquipamento;
  List<_ApontamentoItem> _items = const [];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('pt_BR');
    _load();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }


  bool _osFinalizada() {
    // Considera finalizada se status='encerrada' OU execucao='finalizada'/'encerrada'
    for (final raw in [_osStatus, _osExecucao]) {
      final s = (raw ?? '').trim().toLowerCase();
      if (s == 'encerrada' || s == 'encerrado' || s == 'finalizada' ||
          s == 'finalizado' || s == 'fechada' || s == 'fechado' ||
          s == 'closed' || s == 'concluida' || s == 'concluido') {
        return true;
      }
    }
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final folderRes = await SupabaseManager.client
          .from('os_folders')
          .select('id, os_id, status, execucao, situacao_equipamento')
          .eq('id', widget.osFolderId)
          .limit(1);

      final folderList = (folderRes as List).cast<Map<String, dynamic>>();
      if (folderList.isEmpty) {
        throw Exception('Pasta da OS não encontrada.');
      }

      final folder = folderList.first;
      final osId = (folder['os_id'] ?? '').toString().trim();
      final osStatus   = (folder['status']   ?? '').toString().trim();
      final osExecucao = (folder['execucao'] ?? '').toString().trim();
      final osSituacaoEquipamento = (folder['situacao_equipamento'] ?? '').toString().trim();
      if (osId.isEmpty) {
        throw Exception('A pasta não possui os_id vinculado.');
      }

      final res = await SupabaseManager.client
          .from('os_apontamentos')
          .select('id, os_id, os_folder_id, data, inicio, fim, horas, descricao, tecnico, tecnico_codigo, os_finalizada, teve_almoco, breakdown')
          .eq('os_id', osId)
          .order('data', ascending: false)
          .order('inicio', ascending: false);

      final list = (res as List).cast<Map<String, dynamic>>();
      final items = list.map(_ApontamentoItem.fromMap).toList();

      if (!mounted) return;
      setState(() {
        _osId      = osId;
        _osStatus  = osStatus;
        _osExecucao = osExecucao;
        _osSituacaoEquipamento = osSituacaoEquipamento.isEmpty ? null : osSituacaoEquipamento;
        _items     = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveDialog({_ApontamentoItem? edit}) async {
    final result = await showDialog<_ApontDialogResult>(
      context: context,
      builder: (_) => _ApontDialog(
        initial: edit,
        defaultOsFinalizada: edit?.osFinalizada ?? _osFinalizada(),
        osStatusLabel: _osExecucao?.isNotEmpty == true ? _osExecucao : _osStatus,
      ),
    );
    if (result == null || _osId == null) return;

    // Verifica conflito de horário: o mesmo técnico não pode ter dois apontamentos
    // com intervalos sobrepostos no mesmo dia (em qualquer OS)
    setState(() => _saving = true);
    try {
      final dataStr = _toYmd(result.data);
      final tecCodigo = result.tecnicoCodigo.trim();
      final tecNome = result.tecnico.trim();
      final inicioPrev = result.inicioHHmmss;
      final fimPrev = result.fimHHmmss;

      // Busca todos os apontamentos do técnico naquele dia (exceto o que está sendo editado)
      dynamic conflictQuery = SupabaseManager.client
          .from('os_apontamentos')
          .select('id, inicio, fim, os_id')
          .eq('data', dataStr);

      if (tecCodigo.isNotEmpty) {
        conflictQuery = conflictQuery.eq('tecnico_codigo', tecCodigo);
      } else {
        conflictQuery = conflictQuery.eq('tecnico', tecNome);
      }

      if (edit != null) {
        conflictQuery = conflictQuery.neq('id', edit.id);
      }

      final conflictRows = (await conflictQuery) as List;

      // Verifica sobreposição: A e B se sobrepõem se inicio_A < fim_B E fim_A > inicio_B
      int _toMin(String t) {
        final parts = t.split(':');
        if (parts.length < 2) return 0;
        return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      }

      Map<String, dynamic>? conflito;
      for (final row in conflictRows.cast<Map<String, dynamic>>()) {
        final ini = (row['inicio'] ?? '').toString();
        final fim = (row['fim'] ?? '').toString();
        if (ini.isEmpty || fim.isEmpty) continue;
        if (_toMin(inicioPrev) < _toMin(fim) && _toMin(fimPrev) > _toMin(ini)) {
          conflito = row;
          break;
        }
      }

      if (conflito != null) {
        setState(() => _saving = false);
        final osConflito = (conflito['os_id'] ?? '').toString();
        _snack('Conflito de horário: $tecNome já tem apontamento neste período'
            '${osConflito.isNotEmpty ? ' (OS $osConflito)' : ''}. Corrija o horário antes de salvar.');
        return;
      }
    } catch (e) {
      setState(() => _saving = false);
      _snack('Erro ao verificar conflito de horário: $e');
      return;
    }

    try {
      final payload = {
        'os_id': _osId,
        'os_folder_id': widget.osFolderId,
        'data': _toYmd(result.data),
        'inicio': result.inicioHHmmss,
        'fim': result.fimHHmmss,
        'horas': result.breakdown.horasTotais,
        'descricao': result.descricao.trim(),
        'tecnico': result.tecnico.trim(),
        'tecnico_codigo': result.tecnicoCodigo.trim(),
        'os_finalizada': result.osFinalizada,
        'teve_almoco': result.teveAlmoco,
        'breakdown': {
          'horas_normais': result.breakdown.horasNormais,
          'horas_50': result.breakdown.horas50,
          'horas_100': result.breakdown.horas100,
          'horas_total': result.breakdown.horasTotais,
          'teve_almoco': result.teveAlmoco,
          'regra': 'seg_sex_07_17_normal_fora_50_sabado_50_domingo_feriado_100${result.teveAlmoco ? '_menos_1h12_almoco' : ''}',
        },
        'sync_exportado': false,
        'sync_exportado_em': null,
        'nome_arquivo_exportado': null,
        'export_error': null,
      };

      if (edit == null) {
        await SupabaseManager.client.from('os_apontamentos').insert(payload);
      } else {
        await SupabaseManager.client.from('os_apontamentos').update(payload).eq('id', edit.id);
      }

      // Sincroniza o status da OS folder com o toggle "OS finalizada?"
      // status permanece 'aberta' — só 'encerrada' é um estado diferente (arquivada)
      final novoExecucao = result.osFinalizada ? 'finalizada' : 'em_execucao';
      await SupabaseManager.client
          .from('os_folders')
          .update({'execucao': novoExecucao, 'status': 'aberta'})
          .eq('id', widget.osFolderId);

      await _load();
    } catch (e) {
      _snack('Erro ao salvar apontamento: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteItem(_ApontamentoItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir apontamento?'),
        content: const Text('Deseja realmente excluir este apontamento?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await SupabaseManager.client
          .from('os_apontamentos')
          .delete()
          .eq('id', item.id);
      await _load();
      _snack('Apontamento excluído.');
    } catch (e) {
      _snack('Erro ao excluir apontamento: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportJson() async {
    try {
      final payload = {
        'type': 'os_apontamentos',
        'version': 2,
        'os_folder_id': widget.osFolderId,
        'os_id': _osId,
        'title': widget.titleLabel ?? '',
        'status': _osStatus,
        'execucao': _osExecucao,
        'situacao_equipamento': _osSituacaoEquipamento,
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'items': _items.map((e) => e.toJson()).toList(),
        'totals': {
          'horas_normais': _items.fold<double>(0, (s, e) => s + e.breakdown.horasNormais),
          'horas_50': _items.fold<double>(0, (s, e) => s + e.breakdown.horas50),
          'horas_100': _items.fold<double>(0, (s, e) => s + e.breakdown.horas100),
          'horas_total': _items.fold<double>(0, (s, e) => s + e.breakdown.horasTotais),
        },
      };

      final dir = await getTemporaryDirectory();
      final safeTitle = (widget.titleLabel ?? 'OS')
          .replaceAll(RegExp(r'[^\w\d\-_ ]'), '_')
          .trim()
          .replaceAll(' ', '_');
      final file = File(
        p.join(dir.path, 'apontamentos_${safeTitle}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json'),
      );
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload), flush: true);

      await Share.shareXFiles([XFile(file.path)], text: 'Apontamentos de horas • ${widget.titleLabel ?? ''}');
    } catch (e) {
      _snack('Erro ao exportar JSON: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final totalN = _items.fold<double>(0, (s, e) => s + e.breakdown.horasNormais);
    final total50 = _items.fold<double>(0, (s, e) => s + e.breakdown.horas50);
    final total100 = _items.fold<double>(0, (s, e) => s + e.breakdown.horas100);
    final total = _items.fold<double>(0, (s, e) => s + e.breakdown.horasTotais);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titleLabel?.isNotEmpty == true ? 'Horas • ${widget.titleLabel}' : 'Apontamento de horas'),
        actions: [
          IconButton(
            tooltip: 'Exportar JSON',
            onPressed: (_loading || _saving || _items.isEmpty) ? null : _exportJson,
            icon: const Icon(Icons.data_object),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_saving || _osId == null) ? null : () => _saveDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Novo apontamento'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ChipTotal(label: 'Normais', value: totalN),
                            _ChipTotal(label: '50%', value: total50),
                            _ChipTotal(label: '100%', value: total100),
                            _ChipTotal(label: 'Total', value: total),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _items.isEmpty
                          ? const Center(child: Text('Nenhum apontamento ainda.'))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final a = _items[i];
                                return InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: _saving ? null : () => _saveDialog(edit: a),
                                  child: Ink(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: cs.surface,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: cs.outlineVariant),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${DateFormat('dd/MM/yyyy').format(a.data)} • ${a.tecnico.isEmpty ? '-' : a.tecnico}${a.tecnicoCodigo.isEmpty ? '' : ' (${a.tecnicoCodigo})'}',
                                                style: const TextStyle(fontWeight: FontWeight.w900),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: _saving ? null : () => _saveDialog(edit: a),
                                              icon: const Icon(Icons.edit),
                                            ),
                                            IconButton(
                                              onPressed: _saving ? null : () => _deleteItem(a),
                                              icon: const Icon(Icons.delete_outline),
                                            ),
                                          ],
                                        ),
                                        Text('${_fmtTime(a.inicio)} até ${_fmtTime(a.fim)} • OS ${a.osFinalizada ? 'finalizada' : 'não finalizada'}'),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            if (a.breakdown.horasNormais > 0) _MiniChip(label: 'Normais', value: a.breakdown.horasNormais),
                                            if (a.breakdown.horas50 > 0) _MiniChip(label: '50%', value: a.breakdown.horas50),
                                            if (a.breakdown.horas100 > 0) _MiniChip(label: '100%', value: a.breakdown.horas100),
                                            _MiniChip(label: 'Total', value: a.breakdown.horasTotais),
                                          ],
                                        ),
                                        if (a.descricao.trim().isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Text(a.descricao),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  String _toYmd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(TimeOfDay? t) => t == null ? '--:--' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _ApontamentoItem {
  final String id;
  final String osId;
  final DateTime data;
  final TimeOfDay inicio;
  final TimeOfDay fim;
  final double horas;
  final String descricao;
  final String tecnico;
  final String tecnicoCodigo;
  final bool osFinalizada;
  final bool teveAlmoco;
  final WorkTimeBreakdown breakdown;

  _ApontamentoItem({
    required this.id,
    required this.osId,
    required this.data,
    required this.inicio,
    required this.fim,
    required this.horas,
    required this.descricao,
    required this.tecnico,
    required this.tecnicoCodigo,
    required this.osFinalizada,
    required this.teveAlmoco,
    required this.breakdown,
  });

  factory _ApontamentoItem.fromMap(Map<String, dynamic> m) {
    final data = _parseDate(m['data']) ?? DateTime.now();
    final inicio = _parseTime(m['inicio']) ?? const TimeOfDay(hour: 7, minute: 0);
    final fim = _parseTime(m['fim']) ?? const TimeOfDay(hour: 7, minute: 0);
    var breakdown = WorkTimeRules.calculate(data: data, inicio: inicio, fim: fim);

    // Lê teve_almoco do campo direto ou do campo breakdown JSON
    bool teveAlmoco = _parseBool(m['teve_almoco']);
    if (!teveAlmoco) {
      final bj = m['breakdown'];
      if (bj is Map) teveAlmoco = _parseBool(bj['teve_almoco']);
    }
    if (teveAlmoco) {
      const descontoH = 72.0 / 60.0;
      double normais = breakdown.horasNormais - descontoH;
      double h50 = breakdown.horas50;
      double h100 = breakdown.horas100;
      if (normais < 0) {
        h50 += normais; normais = 0;
        if (h50 < 0) { h100 += h50; h50 = 0; if (h100 < 0) h100 = 0; }
      }
      breakdown = WorkTimeBreakdown(horasNormais: normais, horas50: h50, horas100: h100);
    }

    final horas = _parseDouble(m['horas']) ?? breakdown.horasTotais;

    return _ApontamentoItem(
      id: (m['id'] ?? '').toString(),
      osId: (m['os_id'] ?? '').toString(),
      data: data,
      inicio: inicio,
      fim: fim,
      horas: horas,
      descricao: (m['descricao'] ?? '').toString(),
      tecnico: (m['tecnico'] ?? '').toString(),
      tecnicoCodigo: (m['tecnico_codigo'] ?? '').toString(),
      osFinalizada: _parseBool(m['os_finalizada']),
      teveAlmoco: teveAlmoco,
      breakdown: breakdown,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'os_id': osId,
        'data': '${data.year.toString().padLeft(4, '0')}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}',
        'inicio': '${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')}:00',
        'fim': '${fim.hour.toString().padLeft(2, '0')}:${fim.minute.toString().padLeft(2, '0')}:00',
        'horas': horas,
        'descricao': descricao,
        'tecnico': tecnico,
        'tecnico_codigo': tecnicoCodigo,
        'os_finalizada': osFinalizada,
        'horas_normais': breakdown.horasNormais,
        'horas_50': breakdown.horas50,
        'horas_100': breakdown.horas100,
        'horas_total': breakdown.horasTotais,
      };

  static DateTime? _parseDate(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  static TimeOfDay? _parseTime(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    final p = s.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'sim' || s == 'yes' || s == 'finalizada';
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }
}

class _ApontDialogResult {
  final DateTime data;
  final TimeOfDay inicio;
  final TimeOfDay fim;
  final String descricao;
  final String tecnico;
  final String tecnicoCodigo;
  final bool osFinalizada;
  final bool teveAlmoco;
  final WorkTimeBreakdown breakdown;

  _ApontDialogResult({
    required this.data,
    required this.inicio,
    required this.fim,
    required this.descricao,
    required this.tecnico,
    required this.tecnicoCodigo,
    required this.osFinalizada,
    required this.teveAlmoco,
    required this.breakdown,
  });

  String get inicioHHmmss => '${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')}:00';
  String get fimHHmmss => '${fim.hour.toString().padLeft(2, '0')}:${fim.minute.toString().padLeft(2, '0')}:00';
}

class _TecnicoOption {
  final String nome;
  final String codigo;

  const _TecnicoOption({required this.nome, required this.codigo});

  String get key => codigo.isNotEmpty ? codigo : nome;
  String get label => codigo.isNotEmpty ? '$nome ($codigo)' : nome;
}

class _ApontDialog extends StatefulWidget {
  final _ApontamentoItem? initial;
  final bool defaultOsFinalizada;
  final String? osStatusLabel;

  const _ApontDialog({
    this.initial,
    this.defaultOsFinalizada = false,
    this.osStatusLabel,
  });

  @override
  State<_ApontDialog> createState() => _ApontDialogState();
}

class _ApontDialogState extends State<_ApontDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime _data = DateTime.now();
  TimeOfDay? _inicio;
  TimeOfDay? _fim;
  final _descCtrl = TextEditingController();

  List<_TecnicoOption> _tecnicos = const [];
  String? _tecnicoSelecionado;
  bool _osFinalizada = false;
  bool _teveAlmoco = false;
  bool _loadingTecnicos = true;

  // 1h12min = 72 minutos = 1.2h de desconto de almoço
  static const double _descontoAlmocoH = 72.0 / 60.0;

  WorkTimeBreakdown _aplicarAlmoco(WorkTimeBreakdown b) {
    if (!_teveAlmoco) return b;
    double normais = b.horasNormais - _descontoAlmocoH;
    double h50 = b.horas50;
    double h100 = b.horas100;
    if (normais < 0) {
      h50 += normais;
      normais = 0;
      if (h50 < 0) {
        h100 += h50;
        h50 = 0;
        if (h100 < 0) h100 = 0;
      }
    }
    return WorkTimeBreakdown(horasNormais: normais, horas50: h50, horas100: h100);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      final i = widget.initial!;
      _data = i.data;
      _inicio = i.inicio;
      _fim = i.fim;
      _descCtrl.text = i.descricao;
      _osFinalizada = i.osFinalizada;
      _teveAlmoco = i.teveAlmoco;
    } else {
      _osFinalizada = widget.defaultOsFinalizada;
    }
    _loadTecnicos();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTecnicos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedNome = (prefs.getString('current_tecnico_nome') ?? prefs.getString('tecnico_nome') ?? '').trim();
      final savedCodigo = (prefs.getString('current_tecnico_codigo') ?? prefs.getString('tecnico_codigo') ?? '').trim();

      final rows = await SupabaseManager.client
          .from('tecnicos')
          .select('nome, codigo, ativo')
          .eq('ativo', true)
          .order('nome', ascending: true);

      final mapped = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(
            (m) => _TecnicoOption(
              nome: (m['nome'] ?? '').toString().trim(),
              codigo: (m['codigo'] ?? '').toString().trim(),
            ),
          )
          .where((e) => e.nome.isNotEmpty)
          .toList();

      String? selected;
      if (widget.initial?.tecnico.trim().isNotEmpty == true) {
        final initialTecnico = widget.initial!.tecnico.trim();
        final hit = mapped.where((e) => e.nome == initialTecnico || e.codigo == widget.initial!.tecnicoCodigo || e.label == initialTecnico).cast<_TecnicoOption?>().firstWhere(
              (e) => e != null,
              orElse: () => null,
            );
        selected = hit?.key ?? initialTecnico;
        if (hit == null && initialTecnico.isNotEmpty) {
          mapped.insert(0, _TecnicoOption(nome: initialTecnico, codigo: ''));
        }
      } else if (savedNome.isNotEmpty) {
        final hit = mapped.where((e) => e.nome == savedNome || (savedCodigo.isNotEmpty && e.codigo == savedCodigo)).cast<_TecnicoOption?>().firstWhere(
              (e) => e != null,
              orElse: () => null,
            );
        selected = hit?.key ?? savedNome;
        if (hit == null) {
          mapped.insert(0, _TecnicoOption(nome: savedNome, codigo: savedCodigo));
        }
      }

      if (!mounted) return;
      setState(() {
        _tecnicos = mapped;
        _tecnicoSelecionado = selected;
        _loadingTecnicos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tecnicos = widget.initial?.tecnico.trim().isNotEmpty == true ? [_TecnicoOption(nome: widget.initial!.tecnico.trim(), codigo: widget.initial!.tecnicoCodigo)] : const [];
        _tecnicoSelecionado = widget.initial?.tecnico.trim().isNotEmpty == true ? widget.initial!.tecnico.trim() : null;
        _loadingTecnicos = false;
      });
    }
  }

  WorkTimeBreakdown? get _preview {
    if (_inicio == null || _fim == null) return null;
    try {
      final b = WorkTimeRules.calculate(data: _data, inicio: _inicio!, fim: _fim!);
      return _aplicarAlmoco(b);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _pickInicio() async {
    final t = await showTimePicker(context: context, initialTime: _inicio ?? const TimeOfDay(hour: 7, minute: 0));
    if (t != null) setState(() => _inicio = t);
  }

  Future<void> _pickFim() async {
    final t = await showTimePicker(context: context, initialTime: _fim ?? const TimeOfDay(hour: 17, minute: 0));
    if (t != null) setState(() => _fim = t);
  }

  String _tecnicoValue() {
    if ((_tecnicoSelecionado ?? '').trim().isEmpty) return '';
    final hit = _tecnicos.where((e) => e.key == _tecnicoSelecionado).cast<_TecnicoOption?>().firstWhere((e) => e != null, orElse: () => null);
    return hit?.nome ?? _tecnicoSelecionado!.trim();
  }

  String _tecnicoCodigoValue() {
    if ((_tecnicoSelecionado ?? '').trim().isEmpty) return '';
    final hit = _tecnicos.where((e) => e.key == _tecnicoSelecionado).cast<_TecnicoOption?>().firstWhere((e) => e != null, orElse: () => null);
    return hit?.codigo ?? '';
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_inicio == null || _fim == null) return;
    final breakdown = _aplicarAlmoco(WorkTimeRules.calculate(data: _data, inicio: _inicio!, fim: _fim!));

    Navigator.of(context).pop(_ApontDialogResult(
      data: _data,
      inicio: _inicio!,
      fim: _fim!,
      descricao: _descCtrl.text.trim(),
      tecnico: _tecnicoValue(),
      tecnicoCodigo: _tecnicoCodigoValue(),
      osFinalizada: _osFinalizada,
      teveAlmoco: _teveAlmoco,
      breakdown: breakdown,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final diaSemana = DateFormat('EEEE', 'pt_BR').format(_data);

    return AlertDialog(
      title: Text(widget.initial == null ? 'Novo apontamento' : 'Editar apontamento'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  readOnly: true,
                  onTap: _pickDate,
                  controller: TextEditingController(text: DateFormat('dd/MM/yyyy').format(_data)),
                  decoration: const InputDecoration(
                    labelText: 'Data',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_month),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        readOnly: true,
                        onTap: _pickInicio,
                        controller: TextEditingController(text: _inicio == null ? '' : '${_inicio!.hour.toString().padLeft(2, '0')}:${_inicio!.minute.toString().padLeft(2, '0')}'),
                        decoration: const InputDecoration(
                          labelText: 'Horário de início',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.schedule),
                        ),
                        validator: (_) => _inicio == null ? 'Selecione o início.' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        readOnly: true,
                        onTap: _pickFim,
                        controller: TextEditingController(text: _fim == null ? '' : '${_fim!.hour.toString().padLeft(2, '0')}:${_fim!.minute.toString().padLeft(2, '0')}'),
                        decoration: const InputDecoration(
                          labelText: 'Horário final',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.schedule_outlined),
                        ),
                        validator: (_) {
                          if (_fim == null) return 'Selecione o fim.';
                          if (_inicio != null) {
                            final start = _inicio!.hour * 60 + _inicio!.minute;
                            final end = _fim!.hour * 60 + _fim!.minute;
                            if (end <= start) return 'Fim deve ser maior que início.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _loadingTecnicos
                    ? const LinearProgressIndicator(minHeight: 2)
                    : DropdownButtonFormField<String>(
                        value: _tecnicoSelecionado,
                        decoration: const InputDecoration(
                          labelText: 'Técnico',
                          border: OutlineInputBorder(),
                        ),
                        items: _tecnicos
                            .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.label, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (value) => setState(() => _tecnicoSelecionado = value),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Selecione o técnico.' : null,
                      ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Descrição do serviço efetuado',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a descrição.' : null,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _osFinalizada,
                  onChanged: (v) => setState(() => _osFinalizada = v),
                  title: const Text('OS finalizada?'),
                  subtitle: Text(
                    (widget.osStatusLabel ?? '').trim().isEmpty
                        ? 'Essa informação será enviada no JSON do apontamento.'
                        : 'Assumido automaticamente pelo status da OS: ${widget.osStatusLabel}. Pode ser ajustado antes de salvar.',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _teveAlmoco,
                  onChanged: (v) => setState(() => _teveAlmoco = v),
                  title: const Text('Teve horário de almoço?'),
                  subtitle: const Text('Desconta 1h12min do total de horas trabalhadas.'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Regra: seg a sex normal das 07:00 às 17:00; fora disso 50%. Sábado 50%. Domingo e feriado 100%.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: preview == null
                      ? const Text('Selecione início e fim válidos para calcular as horas.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Dia: ${diaSemana[0].toUpperCase()}${diaSemana.substring(1)}'),
                            const SizedBox(height: 6),
                            Text('Normais: ${_fmtHoras(preview.horasNormais)}'),
                            Text('50%: ${_fmtHoras(preview.horas50)}'),
                            Text('100%: ${_fmtHoras(preview.horas100)}'),
                            const SizedBox(height: 6),
                            Text('Total: ${_fmtHoras(preview.horasTotais)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Salvar')),
      ],
    );
  }
}

String _fmtHoras(double h) {
  final totalMin = (h * 60).round();
  final hrs = totalMin ~/ 60;
  final min = totalMin % 60;
  return min == 0 ? '${hrs}h' : '${hrs}h${min.toString().padLeft(2, '0')}min';
}

class _ChipTotal extends StatelessWidget {
  final String label;
  final double value;

  const _ChipTotal({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: ${_fmtHoras(value)}'));
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final double value;

  const _MiniChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$label: ${_fmtHoras(value)}'));
  }
}
