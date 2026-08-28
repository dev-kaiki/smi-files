// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/os/os_media_page.dart
//
// v6 + Detalhes do servidor (tabela public.os)
// - Mantém: grid/list, filtros, busca, período, ordenação, capa primeiro
// - Mantém: seleção múltipla + ações em lote
// - Mantém: upload com watermark, storage supabase + Outbox offline-first (mídia não se perde)
// - Mantém: galeria (MediaGalleryPage)
// - NOVO: Detalhes puxa info real da OS (public.os): cliente, depto, serviço solicitado, etc.
// - NOVO: Outbox (badge + banner + reenvio)

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../core/supabase/supabase_manager.dart';
import '../../utils/os_pdf_export.dart';
import '../../utils/smi_watermark.dart';
import 'media_gallery_page.dart';
import 'os_folder_apontamentos_page.dart';
import '../checklist/os_checklist_page.dart';

import '../../services/outbox_page.dart';
import '../../services/outbox_service.dart';
import '../../services/outbox_uploader.dart';


enum _MediaViewMode { grid, list }
enum _MediaFilter { all, images, videos }
enum _MediaSort { newest, oldest }
enum _MediaPeriod { all, today, d7, d30 }

const int _maxBatchMediaSelection = 600;
const int _batchUiYieldEvery = 10;
const int _outboxBatchPersistEvery = 10;

class _TecnicoPickerSheet extends StatefulWidget {
  const _TecnicoPickerSheet({required this.fetcher});

  final Future<List<Map<String, dynamic>>> Function(String query) fetcher;

  @override
  State<_TecnicoPickerSheet> createState() => _TecnicoPickerSheetState();
}

class _TecnicoPickerSheetState extends State<_TecnicoPickerSheet> {
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
    _ctrl.addListener(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await widget.fetcher(_ctrl.text);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_load);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                decoration: const InputDecoration(
                  labelText: 'Buscar técnico (nome ou código)',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final t = _items[i];
                    final nome = (t['nome'] ?? '').toString();
                    final codigo = (t['codigo'] ?? '').toString();
                    return ListTile(
                      leading: const Icon(Icons.engineering_outlined),
                      title: Text(nome.isEmpty ? 'Sem nome' : nome),
                      subtitle: codigo.isEmpty ? null : Text(codigo),
                      onTap: () => Navigator.pop(context, t),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}


class OsMediaPage extends StatefulWidget {
  final String osFolderId;

  const OsMediaPage({super.key, required this.osFolderId});

  @override
  State<OsMediaPage> createState() => _OsMediaPageState();
}

class _OsMediaPageState extends State<OsMediaPage> {
  void _log(String message) {
    developer.log(message, name: 'SMI_OS_MEDIA');
  }

  bool _loadingInfo = true;

  bool _uploading = false;
  int _uploadRefs = 0;

  bool _deletingOs = false;
  bool _generatingPdf = false;

  Map<String, dynamic>? _osInfo;

  /// dados originais (tabela public.os)
  Map<String, dynamic>? _osRaw;

  List<Map<String, dynamic>> _files = [];

  String? _situacaoEquipamento;

  final ImagePicker _picker = ImagePicker();

  // outbox (fila local)
  bool _outboxWarned = false;
  late final VoidCallback _outboxListener;

  _MediaViewMode _viewMode = _MediaViewMode.grid;
  _MediaFilter _filter = _MediaFilter.all;

  _MediaSort _sort = _MediaSort.newest;
  _MediaPeriod _period = _MediaPeriod.all;
  bool _coverFirst = true;

  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  bool _autoFixedMapping = false;

  bool _batchQueueing = false;
  int _batchQueueTotal = 0;
  int _batchQueueDone = 0;

  // cache de URL assinada (thumbs)
  final Map<String, Future<String>> _urlFuture = {};
  final Map<String, String> _urlCache = {};

  // modo seleção
  bool _selectMode = false;
  final Set<String> _selected = <String>{};

  bool get _busy => _uploading || _deletingOs || _generatingPdf;

  void _beginUpload() {
    _uploadRefs++;
    if (!mounted) return;
    if (!_uploading) setState(() => _uploading = true);
  }

  void _endUpload() {
    _uploadRefs = max(0, _uploadRefs - 1);
    if (!mounted) return;
    final should = _uploadRefs > 0;
    if (_uploading != should) setState(() => _uploading = should);
  }

  @override
  void initState() {
    super.initState();
    _loadOsInfoAndFiles();

    // Aviso/indicador: outbox
    _outboxListener = () {
      final c = OutboxService.I.pendingCount.value;
      if (c > 0 && !_outboxWarned) {
        _outboxWarned = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _snack('Você tem $c mídia(s) pendente(s). Toque no ícone ☁️ para reenviar.');
        });
      }
    };
    OutboxService.I.pendingCount.addListener(_outboxListener);

    // checa ao entrar
    WidgetsBinding.instance.addPostFrameCallback((_) => _outboxListener());
  }

  @override
  void dispose() {
    // remove listener de pendências
    try {
      OutboxService.I.pendingCount.removeListener(_outboxListener);
    } catch (_) {}

    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _currentOsLabel() {
    final ano = (_osInfo?['ano'] ?? _osRaw?['anomovto'] ?? '').toString();
    final osCode = (_osInfo?['os_code'] ?? _osRaw?['nroos'] ?? '').toString();
    if (ano.isNotEmpty && osCode.isNotEmpty) return '$ano/$osCode';
    // fallback estável
    return widget.osFolderId;
  }


  // ===============================
  // Técnico responsável (manual)
  // - obrigatório para enviar foto/vídeo
  // ===============================

  bool get _hasTecnicoResponsavel {
    final id = _osInfo == null ? null : _osInfo!['tecnico_id'];
    final nome = (_osInfo == null ? '' : (_osInfo!['tecnico_nome'] ?? '')).toString().trim();
    return id != null && nome.isNotEmpty;
  }

  Future<bool> _ensureTecnicoAntesDeMidia() async {
    if (_hasTecnicoResponsavel) return true;

    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Selecione o técnico responsável'),
        content: const Text(
          'Para adicionar fotos ou vídeos, primeiro selecione o técnico responsável em "Detalhes".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Selecionar técnico'),
          ),
        ],
      ),
    );

    if (go == true) _openDetailsSheet();
    return false;
  }

  Future<List<Map<String, dynamic>>> _fetchTecnicos(String query) async {
    final q = query.trim();

    dynamic base = SupabaseManager.client.from('tecnicos').select('id, codigo, nome, ativo');

    // tenta filtrar só ativos (se existir)
    try {
      base = base.eq('ativo', true);
    } catch (_) {}

    if (q.isEmpty) {
      final res = await base.order('nome', ascending: true).limit(200);
      return (res as List).cast<Map<String, dynamic>>();
    }

    // Sem OR: busca por nome e por código e junta
    final a = await base.ilike('nome', '%$q%').order('nome', ascending: true).limit(200);

    dynamic base2 = SupabaseManager.client.from('tecnicos').select('id, codigo, nome, ativo');
    try {
      base2 = base2.eq('ativo', true);
    } catch (_) {}

    final b = await base2.ilike('codigo', '%$q%').order('nome', ascending: true).limit(200);

    final map = <String, Map<String, dynamic>>{};
    for (final r in [...(a as List), ...(b as List)]) {
      final m = Map<String, dynamic>.from(r as Map);
      map[m['id'].toString()] = m;
    }
    return map.values.toList();
  }

  Future<Map<String, dynamic>?> _pickTecnicoBottomSheet() async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TecnicoPickerSheet(fetcher: _fetchTecnicos),
    );
  }

  Future<void> _setTecnicoResponsavel(Map<String, dynamic> t) async {
    final id = (t['id'] as num?)?.toInt();
    final nome = (t['nome'] ?? '').toString().trim();
    if (id == null || nome.isEmpty) return;

    await SupabaseManager.client.from('os_folders').update({
      'tecnico_id': id,
      'tecnico_nome': nome,
    }).eq('id', widget.osFolderId);

    if (!mounted) return;
    setState(() {
      _osInfo = {...?_osInfo, 'tecnico_id': id, 'tecnico_nome': nome};
    });
  }


  // ===============================
  // Helpers: detalhes do servidor
  // ===============================

  String? _clienteNome() {
    final os = _osInfo;
    if (os == null) return null;
    final c = os['clientes'];
    if (c is Map<String, dynamic>) {
      return (c['razao_social'] ?? c['codigo'])?.toString();
    }
    if (c is List && c.isNotEmpty && c.first is Map) {
      final m = Map<String, dynamic>.from(c.first as Map);
      return (m['razao_social'] ?? m['codigo'])?.toString();
    }
    return null;
  }

  Map<String, dynamic>? _payloadFromRaw() {
    final r = _osRaw;
    if (r == null) return null;
    final payload = r['payload'] ?? r['raw_json'];
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) return Map<String, dynamic>.from(payload);
    return null;
  }

  dynamic _rawOrPayloadValue(List<String> keys) {
    final r = _osRaw;
    if (r == null) return null;

    for (final k in keys) {
      final v = r[k];
      if (v != null && v.toString().trim().isNotEmpty && v.toString() != 'null') return v;
    }

    final payload = _payloadFromRaw();
    if (payload != null) {
      for (final k in keys) {
        final v = payload[k];
        if (v != null && v.toString().trim().isNotEmpty && v.toString() != 'null') return v;
      }
    }

    return null;
  }

  String? _servicoSolicitadoFromRaw() {
    final v = _rawOrPayloadValue(const [
      'servico_solicitado',
      'serviço',
      'servico',
      'servio',
      'serviþo',
      'servico_solicitado_desc',
    ]);
    return v?.toString();
  }

  String? _extractNested(Map<String, dynamic>? src, String key, String subKey) {
    dynamic v = src == null ? null : src[key];

    if ((v == null || v.toString().trim().isEmpty || v.toString() == 'null') && src == _osRaw) {
      final payload = _payloadFromRaw();
      if (payload != null) v = payload[key];
    }

    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      final preferred = m[subKey];
      if (preferred != null && preferred.toString().trim().isNotEmpty) return preferred.toString();
      return m.entries
          .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
          .map((e) => '${e.key}: ${e.value}')
          .join(' • ');
    }

    if (v != null && v.toString().trim().isNotEmpty && v.toString() != 'null') {
      return v.toString();
    }

    return null;
  }

  Widget _detailRow(String label, String? value) {
    final cs = Theme.of(context).colorScheme;
    final v = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? '—' : v,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadOsRawFromServer() async {
    final os = _osInfo;
    if (os == null) return;

    try {
      dynamic row;

      // Fonte correta: os_folders.os_id.
      // Antes o app buscava por ano+nroos+seqos sem empresa/filial, podendo carregar
      // os detalhes da OS errada quando havia numeração repetida entre empresas.
      final osId = (os['os_id'] ?? '').toString().trim();
      if (osId.isNotEmpty && osId != 'null') {
        row = await SupabaseManager.client
            .from('os')
            .select('*')
            .eq('id', osId)
            .maybeSingle();
      }

      // Fallback legado: usa empresa_code + ano + os_code.
      if (row == null) {
        final anoStr = (os['ano'] ?? '').toString();
        final osCode = (os['os_code'] ?? '').toString();
        final empresaCode = (os['empresa_code'] ?? '').toString();
        if (anoStr.isNotEmpty && osCode.isNotEmpty) {
          final parts = osCode.split('/');
          final nroosStr = parts.isNotEmpty ? parts[0] : '';
          final seqosStr = parts.length > 1 ? parts[1] : '';
          var q = SupabaseManager.client
              .from('os')
              .select('*')
              .eq('anomovto', anoStr)
              .eq('nroos', nroosStr)
              .eq('seqos', seqosStr);
          if (empresaCode.trim().isNotEmpty) q = q.eq('empresa', empresaCode.trim());
          row = await q.maybeSingle();
        }
      }

      if (!mounted) return;

      if (row == null) {
        setState(() => _osRaw = null);
        return;
      }

      setState(() => _osRaw = Map<String, dynamic>.from(row as Map));
    } catch (_) {
      if (!mounted) return;
      setState(() => _osRaw = null);
    }
  }

  // ===============================
  // NORMALIZAÇÃO (EMPRESA x SETOR)
  // ===============================

  bool _isEmpresaCode(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return false;
    final onlyDigits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (onlyDigits.isEmpty) return false;
    final padded = onlyDigits.padLeft(3, '0');
    return padded == '001' || padded == '002' || padded == '003';
  }

  String _normalizeEmpresaCode(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '';
    final onlyDigits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (onlyDigits.isEmpty) return '';
    final padded = onlyDigits.padLeft(3, '0');
    if (padded == '001' || padded == '002' || padded == '003') return padded;
    return '';
  }

  String _tipoLabel(String? empresaCode) {
    final code = _normalizeEmpresaCode(empresaCode);
    switch (code) {
      case '001':
        return 'Serviços';
      case '002':
        return 'Assistência';
      case '003':
        return 'Reforma';
      default:
      // se já veio label no banco, preserva
        final raw = (empresaCode ?? '').trim();
        return raw.isEmpty ? 'OS' : raw;
    }
  }

  String _sanitizeDepartamento(String? v) {
    var s = (v ?? '').trim();
    if (s.isEmpty) return '';
    // se alguém gravou empresa (001/002/003) por engano no campo departamento
    if (_isEmpresaCode(s)) return '';
    // remove múltiplos espaços
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  String _stripDiacritics(String input) {
    // cobre PT-BR sem dependências
    const map = {
      'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A',
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'Ç': 'C', 'ç': 'c',
    };
    final b = StringBuffer();
    for (final ch in input.split('')) {
      b.write(map[ch] ?? ch);
    }
    return b.toString();
  }

  String _slug(String input) {
    var s = _stripDiacritics(input.trim());
    s = s.toUpperCase();
    s = s.replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s.isEmpty ? 'SEM_VALOR' : s;
  }

  String _buildDefaultStoragePrefix({
    required String empresaCode,
    required String departamento,
  }) {
    final ano = (_osInfo?['ano'] ?? '').toString().trim();
    final osCode = (_osInfo?['os_code'] ?? '').toString().trim(); // ex: 0019/000
    final osSeg = _slug(osCode.replaceAll('/', '-'));
    final tipoSeg = '${empresaCode}_${_slug(_tipoLabel(empresaCode))}'; // 001_SERVICOS
    final deptSeg = departamento.trim().isEmpty ? 'SEM_SETOR' : _slug(departamento);

    // mantém um caminho simples e previsível (bucket: smi_midias)
    return 'os/$tipoSeg/$deptSeg/$ano/$osSeg';
  }

  Future<void> _autoFixTipoSetorAndPrefixIfNeeded() async {
    // V9: tipo/setor/storage_prefix são responsabilidade do Supabase.
    // O app não deve corrigir mapeamento operacional em produção.
    return;
    // ignore:
    if (_autoFixedMapping) return;
    if (_osInfo == null) return;
    _autoFixedMapping = true;

    final oldTipo = (_osInfo!['tipo'] ?? '').toString();
    final oldSetor = (_osInfo!['setor'] ?? '').toString();
    final oldPrefix = (_osInfo!['storage_prefix'] ?? '').toString();

    // pega do raw (tabela public.os) — fonte da verdade
    final rawEmpresa = _normalizeEmpresaCode(_osRaw?['empresa']?.toString());
    final rawDepto = _sanitizeDepartamento(_osRaw?['departamento']?.toString());

    // heurística: se o banco veio invertido, corrige
    final guessedEmpresa = rawEmpresa.isNotEmpty
        ? rawEmpresa
        : (_isEmpresaCode(oldTipo) ? _normalizeEmpresaCode(oldTipo) : _normalizeEmpresaCode(oldSetor));

    final guessedDepto = rawDepto.isNotEmpty
        ? rawDepto
        : (_sanitizeDepartamento(oldSetor).isNotEmpty ? _sanitizeDepartamento(oldSetor) : _sanitizeDepartamento(oldTipo));

    final newTipo = guessedEmpresa.isNotEmpty ? guessedEmpresa : oldTipo;
    final newSetor = guessedDepto.isNotEmpty ? guessedDepto : oldSetor;

    // decide se precisa atualizar prefix
    final looksSwapped = _isEmpresaCode(oldSetor) && !_isEmpresaCode(oldTipo);
    final prefixBad = oldPrefix.trim().isEmpty || oldPrefix.toLowerCase().startsWith('null') || oldPrefix.toLowerCase().contains('/null/');
    final shouldUpdatePrefix = prefixBad || looksSwapped;

    final updates = <String, dynamic>{};
    if (newTipo.isNotEmpty && newTipo != oldTipo) updates['tipo'] = newTipo;
    if (newSetor.isNotEmpty && newSetor != oldSetor) updates['setor'] = newSetor;

    if (shouldUpdatePrefix && _isEmpresaCode(newTipo)) {
      updates['storage_prefix'] = _buildDefaultStoragePrefix(
        empresaCode: _normalizeEmpresaCode(newTipo),
        departamento: newSetor,
      );
    }

    if (updates.isEmpty) return;

    try {
      await SupabaseManager.client.from('os_folders').update(updates).eq('id', widget.osFolderId);

      if (!mounted) return;
      setState(() {
        _osInfo = {..._osInfo!, ...updates};
      });

      // feedback discreto (só quando corrigiu algo)
      final fixedTipo = updates.containsKey('tipo');
      final fixedSetor = updates.containsKey('setor');
      final fixedPrefix = updates.containsKey('storage_prefix');

      final parts = <String>[];
      if (fixedTipo) parts.add('empresa');
      if (fixedSetor) parts.add('setor');
      if (fixedPrefix) parts.add('pasta');

      if (parts.isNotEmpty) {
        _snack('Corrigido automaticamente: ${parts.join(', ')}.');
      }
    } catch (_) {
      // se falhar, não trava o app
    }
  }



  // ===============================
  // CARREGAR OS + ARQUIVOS
  // ===============================
  Future<void> _loadOsInfoAndFiles() async {
    setState(() => _loadingInfo = true);

    try {
      final os = await SupabaseManager.client
          .from('os_folders')
          .select('''
            id, os_id, client_id, ano, os_code, tipo, setor, storage_prefix, status, execucao,
            situacao_equipamento, cover_path,
            tecnico_id,
            tecnico_nome,
            clientes:client_id(codigo, razao_social)
          ''')
          .eq('id', widget.osFolderId)
          .single();

      final files = await SupabaseManager.client
          .from('media_files')
          .select('''
            id, file_type, storage_path, created_at,
            tag, obs, is_cover, quick_tag, fase,
            exif_taken_at, exif_width, exif_height
          ''')
          .eq('os_folder_id', widget.osFolderId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _osInfo = os;
        _osRaw = null;
        _files = List<Map<String, dynamic>>.from(files);
        _situacaoEquipamento = (os['situacao_equipamento'] ?? '').toString().trim().isEmpty
            ? null
            : os['situacao_equipamento'].toString().trim();
        _loadingInfo = false;
      });

      // se algum item selecionado foi removido, limpa seleção
      _selected.removeWhere((id) => !_files.any((f) => f['id'].toString() == id));
      if (_selectMode && _selected.isEmpty) {
        setState(() => _selectMode = false);
      }

      // carrega dados originais da OS (tabela public.os)
      await _loadOsRawFromServer();
      await _autoFixTipoSetorAndPrefixIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingInfo = false);
      _snack('Erro ao carregar OS: $e');
    }
  }

  Future<void> _reloadPage() async => _loadOsInfoAndFiles();

  // ===============================
  // SIGNED URL CACHE
  // ===============================
  Future<String?> _signedUrl(String storagePath) async {
    final path = storagePath.trim();
    if (path.isEmpty) return null;

    final cached = _urlCache[path];
    if (cached != null && cached.isNotEmpty) return cached;

    final fut = _urlFuture.putIfAbsent(path, () async {
      final url = await SupabaseManager.client.storage.from('smi_midias').createSignedUrl(path, 3600);
      _urlCache[path] = url;
      return url;
    });

    return fut;
  }

  // ===============================
  // CONTENT TYPE
  // ===============================
  String? _contentTypeForPath(
      String path, {
        required bool isImage,
        required bool isVideo,
      }) {
    final ext = p.extension(path).toLowerCase();

    if (isImage) {
      switch (ext) {
        case '.png':
          return 'image/png';
        case '.webp':
          return 'image/webp';
        case '.heic':
        case '.heif':
          return 'image/heic';
        case '.jpg':
        case '.jpeg':
        default:
          return 'image/jpeg';
      }
    }

    if (isVideo) {
      switch (ext) {
        case '.mov':
          return 'video/quicktime';
        case '.mkv':
          return 'video/x-matroska';
        case '.avi':
          return 'video/x-msvideo';
        case '.webm':
          return 'video/webm';
        case '.3gp':
          return 'video/3gpp';
        case '.m4v':
          return 'video/x-m4v';
        case '.mp4':
        default:
          return 'video/mp4';
      }
    }

    return null;
  }

  // ===============================
  // UPLOAD (RETRY)
  // ===============================
  Future<void> _uploadWithRetry(
      String fullPath,
      File file, {
        required bool isVideo,
        String? contentType,
      }) async {
    const maxAttempts = 3;
    final timeout = isVideo ? const Duration(hours: 2) : const Duration(minutes: 30);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final storage = SupabaseManager.client.storage.from('smi_midias');
        if (contentType != null && contentType.trim().isNotEmpty) {
          await storage
              .upload(fullPath, file, fileOptions: FileOptions(contentType: contentType))
              .timeout(timeout);
        } else {
          await storage.upload(fullPath, file).timeout(timeout);
        }
        return;
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  // ===============================
  // PICKERS
  // ===============================
  bool _isImagePath(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'}.contains(ext);
  }

  bool _isVideoPath(String path) {
    final ext = p.extension(path).toLowerCase();
    return const {'.mp4', '.mov', '.mkv', '.avi', '.webm', '.3gp', '.m4v'}.contains(ext);
  }

  List<XFile> _limitBatch(List<XFile> files) {
    if (files.length <= _maxBatchMediaSelection) return files;
    _snack('Foram selecionados ${files.length} itens. Este lote será limitado aos primeiros $_maxBatchMediaSelection para manter estabilidade.');
    return files.take(_maxBatchMediaSelection).toList(growable: false);
  }

  Future<void> _queuePickedBatch({
    required List<XFile> picked,
    required String titleForSnack,
    bool lightweightImages = true,
  }) async {
    if (_osInfo == null) return;
    if (!await _ensureTecnicoAntesDeMidia()) return;

    final files = _limitBatch(picked);
    if (files.isEmpty) return;

    _beginUpload();
    setState(() {
      _batchQueueing = true;
      _batchQueueTotal = files.length;
      _batchQueueDone = 0;
    });

    var queued = 0;
    try {
      for (var i = 0; i < files.length; i++) {
        final x = files[i];
        final path = x.path.trim();
        if (path.isEmpty) continue;

        final isImage = _isImagePath(path);
        final isVideo = _isVideoPath(path);
        if (!isImage && !isVideo) {
          _log('[BATCH] ignorado arquivo não suportado: $path');
          continue;
        }

        await _processAndUploadMedia(
          picked: x,
          isImage: isImage,
          manageUploading: false,
          attemptSendNow: false,
          lightweightImageProcessing: true,
          showSnack: false,
          persistOutboxImmediately: false,
        );

        queued++;
        if (queued % _outboxBatchPersistEvery == 0) {
          await OutboxService.I.persistState();
        }
        if (!mounted) return;
        if (i % _batchUiYieldEvery == 0 || i == files.length - 1) {
          setState(() => _batchQueueDone = i + 1);
          await Future<void>.delayed(Duration.zero);
        }
      }

      await OutboxService.I.persistState();
      _snack('$queued $titleForSnack salvo(s) na Outbox. Envio em fila controlada; pode demorar, mas não deve travar a tela.');
      unawaited(_processOutboxAfterBatch(osLabel: _currentOsLabel()));
    } catch (e) {
      _snack('Erro ao preparar lote de mídias: $e');
    } finally {
      if (mounted) {
        setState(() {
          _batchQueueing = false;
          _batchQueueTotal = 0;
          _batchQueueDone = 0;
        });
      }
      _endUpload();
    }
  }

  Future<void> _processOutboxAfterBatch({required String osLabel}) async {
    try {
      await OutboxUploader.I.processPending(
        osFolderId: widget.osFolderId,
        osLabel: osLabel,
        maxItems: _maxBatchMediaSelection,
      );
      if (!mounted) return;
      await _loadOsInfoAndFiles();
      final left = OutboxService.I.countPending(osFolderId: widget.osFolderId, osLabel: osLabel);
      if (left == 0) {
        _snack('Envio do lote concluído.');
      } else {
        _snack('Ainda existem $left mídia(s) pendente(s). Elas ficaram salvas para reenvio.');
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Lote salvo, mas o envio ficou pendente: $e');
    }
  }

  Future<void> _pickMediaBatchFromGallery() async {
    if (_osInfo == null) return;
    if (!await _ensureTecnicoAntesDeMidia()) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'mp4', 'mov', 'mkv', 'avi', 'webm', '3gp', 'm4v'],
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;

    final files = result.files
        .where((e) => (e.path ?? '').trim().isNotEmpty)
        .map((e) => XFile(e.path!.trim(), name: e.name))
        .toList(growable: false);

    await _queuePickedBatch(
      picked: files,
      titleForSnack: 'mídia(s)',
      lightweightImages: true,
    );
  }

  Future<void> _pickImagesFromGallery({bool multiple = false}) async {
    if (_osInfo == null) return;

    if (!await _ensureTecnicoAntesDeMidia()) return;

    if (multiple) {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
        withData: false,
        withReadStream: false,
      );
      if (result == null || result.files.isEmpty) return;

      final pics = result.files
          .where((e) => (e.path ?? '').trim().isNotEmpty)
          .map((e) => XFile(e.path!.trim(), name: e.name))
          .toList(growable: false);

      await _queuePickedBatch(
        picked: pics,
        titleForSnack: 'foto(s)',
        lightweightImages: true,
      );
      return;
    }

    final pic = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pic == null) return;

    await _processAndUploadMedia(picked: pic, isImage: true);
    await _loadOsInfoAndFiles();
  }

  Future<void> _pickImageFromCamera() async {
    if (_osInfo == null) return;

    if (!await _ensureTecnicoAntesDeMidia()) return;

    final pic = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (pic == null) return;

    await _processAndUploadMedia(picked: pic, isImage: true);
    await _loadOsInfoAndFiles();
  }

  Future<void> _pickVideo({required bool useCamera}) async {
    if (_osInfo == null) return;

    if (!await _ensureTecnicoAntesDeMidia()) return;

    final vid = await _picker.pickVideo(source: useCamera ? ImageSource.camera : ImageSource.gallery);
    if (vid == null) return;

    await _processAndUploadMedia(picked: vid, isImage: false);
    await _loadOsInfoAndFiles();
  }

  // ===============================
  // PROCESSAR + UPLOAD
  // ===============================
  Future<void> _processAndUploadMedia({
    required XFile picked,
    required bool isImage,
    bool manageUploading = true,

    /// Se true, tenta enviar imediatamente após colocar na Outbox.
    /// Se false, apenas enfileira (ideal para multi-seleção) e você chama o reenviar uma vez no final.
    bool attemptSendNow = true,
    bool lightweightImageProcessing = false,
    bool showSnack = true,
    bool persistOutboxImmediately = true,
  }) async {
    if (_osInfo == null) return;
    if (manageUploading) _beginUpload();

    File? processedFile;

    final original = File(picked.path);
    File fileToQueue = original;

    try {
      // --------- metadados (opcionais) ----------
      DateTime? exifTakenAt;
      int? exifWidth;
      int? exifHeight;

      try {
        exifTakenAt = await original.lastModified();
      } catch (_) {}

      if (isImage && !lightweightImageProcessing) {
        try {
          final bytes = await original.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          exifWidth = frame.image.width;
          exifHeight = frame.image.height;
        } catch (_) {}

        final ano = _osInfo!['ano'];
        final osCode = _osInfo!['os_code'];
        final tipo = _tipoLabel((_osInfo!['tipo'] ?? '').toString());
        final setor = _osInfo!['setor'];
        final label = '$ano/$osCode';

        // Watermark (gera um arquivo temporário)
        processedFile = await SmiWatermark.addWatermark(
          original: original,
          osLabel: label,
          tipo: tipo,
          setor: setor,
          dateTime: DateTime.now(),
        );

        fileToQueue = processedFile!;
      }

      final prefix = (_osInfo!['storage_prefix'] ?? '').toString();
      if (prefix.isEmpty) {
        _log('[MEDIA] os_folder_id=${widget.osFolderId} sem storage_prefix. Upload abortado.');
        throw Exception('Esta OS está sem storage_prefix. Corrija a OS no banco ou rode o teste do Supabase para validar o prefixo.');
      }

      // Conteúdo/labels para DB e UI
      final userId = SupabaseManager.client.auth.currentUser?.id ?? '';
      final ano = (_osInfo?['ano'] ?? '').toString();
      final osCode = (_osInfo?['os_code'] ?? '').toString();
      final tipo = _tipoLabel((_osInfo?['tipo'] ?? '').toString());
      final setor = (_osInfo?['setor'] ?? '').toString();
      final osLabel = (ano.isNotEmpty && osCode.isNotEmpty) ? '$ano/$osCode' : _currentOsLabel();

      // 1) SEMPRE salva localmente primeiro (garantia contra queda de internet / app fechar)
      _log('[MEDIA] enqueue bucket=smi_midias prefix=$prefix os_folder_id=${widget.osFolderId} image=$isImage auth_user=${SupabaseManager.client.auth.currentUser?.id ?? '(anon)'}');
      await OutboxService.I.enqueueFromFile(
        sourceFile: fileToQueue,
        originalName: p.basename(original.path),
        bucket: 'smi_midias',
        remotePrefix: prefix, // gera storage_path = <prefix>/<uuid>.<ext>
        osFolderId: widget.osFolderId,
        osLabel: osLabel,
        tipo: tipo,
        setor: setor,
        fileType: isImage ? 'image' : 'video',
        contentType: _contentTypeForPath(fileToQueue.path, isImage: isImage, isVideo: !isImage),
        createdBy: userId,
        exifTakenAt: exifTakenAt,
        exifWidth: exifWidth,
        exifHeight: exifHeight,
        persistImmediately: persistOutboxImmediately,
      );

      // Já copiamos para Outbox: pode apagar o temporário do watermark
      try {
        if (processedFile != null && await processedFile.exists()) {
          await processedFile.delete();
        }
      } catch (_) {}

      // 2) Tenta enviar agora (se permitido). Se cair a internet, fica pendente e o usuário não perde.
      if (attemptSendNow) {
        await OutboxUploader.I.processPending(osFolderId: widget.osFolderId, osLabel: osLabel);

        final left = OutboxService.I.countPending(osFolderId: widget.osFolderId, osLabel: osLabel);
        final pendingItems = OutboxService.I.itemsFor(osFolderId: widget.osFolderId, osLabel: osLabel);
        final firstError = pendingItems.where((e) => (e.lastError ?? '').trim().isNotEmpty).map((e) => e.lastError!.trim()).cast<String?>().firstWhere((e) => e != null && e.isNotEmpty, orElse: () => null);
        if (left == 0) {
          if (showSnack) _snack('Mídia enviada com sucesso.');
        } else {
          _log('[MEDIA] mídia pendente após tentativa. erro=${firstError ?? '(sem detalhe)'}');
          if (showSnack) _snack('Mídia salva na Outbox (pendente). ${firstError == null ? '' : 'Motivo: $firstError'}');
        }
      } else {
        if (showSnack) _snack('Mídia salva na Outbox.');
      }
    } catch (e) {
      // Se falhar antes de enfileirar, pelo menos não deixa temporário sujo.
      try {
        if (processedFile != null && await processedFile.exists()) {
          await processedFile.delete();
        }
      } catch (_) {}
      if (showSnack) _snack('Erro ao salvar/enfileirar mídia: $e');
    } finally {
      if (manageUploading) _endUpload();
    }
  }

  // ===============================
  // SELEÇÃO
  // ===============================
  void _enterSelectMode(String id) {
    if (id.trim().isEmpty) return;
    setState(() {
      _selectMode = true;
      _selected.add(id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  void _selectAllFiltered() {
    final ids = _filteredFiles.map((e) => e['id'].toString()).toSet();
    setState(() {
      _selectMode = true;
      _selected
        ..clear()
        ..addAll(ids);
    });
  }

  List<Map<String, dynamic>> get _selectedFiles {
    final set = _selected;
    return _files.where((f) => set.contains(f['id'].toString())).toList();
  }

  // ===============================
  // FILTROS/ORDENAÇÃO
  // ===============================
  bool _matchSearch(Map<String, dynamic> f) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;

    final path = (f['storage_path'] ?? '').toString();
    final name = p.basename(path).toLowerCase();

    final tag = (f['tag'] ?? '').toString().toLowerCase();
    final obs = (f['obs'] ?? '').toString().toLowerCase();
    final quick = (f['quick_tag'] ?? '').toString().toLowerCase();
    final fase = (f['fase'] ?? '').toString().toLowerCase();

    return name.contains(q) || tag.contains(q) || obs.contains(q) || quick.contains(q) || fase.contains(q);
  }

  DateTime? _createdAtOf(Map<String, dynamic> f) {
    final raw = f['created_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  List<Map<String, dynamic>> get _filteredFiles {
    List<Map<String, dynamic>> list;
    if (_filter == _MediaFilter.all) {
      list = List<Map<String, dynamic>>.from(_files);
    } else if (_filter == _MediaFilter.images) {
      list = _files.where((e) => e['file_type'] == 'image').toList();
    } else {
      list = _files.where((e) => e['file_type'] == 'video').toList();
    }

    // período
    if (_period != _MediaPeriod.all) {
      final now = DateTime.now();
      DateTime start;
      if (_period == _MediaPeriod.today) {
        start = DateTime(now.year, now.month, now.day);
      } else if (_period == _MediaPeriod.d7) {
        start = now.subtract(const Duration(days: 7));
      } else {
        start = now.subtract(const Duration(days: 30));
      }

      list = list.where((f) {
        final dt = _createdAtOf(f);
        if (dt == null) return false;
        return dt.toLocal().isAfter(start);
      }).toList();
    }

    // busca
    if (_search.trim().isNotEmpty) {
      list = list.where(_matchSearch).toList();
    }

    // sort
    list.sort((a, b) {
      final da = _createdAtOf(a);
      final db = _createdAtOf(b);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;

      final cmp = da.compareTo(db);
      return _sort == _MediaSort.newest ? -cmp : cmp;
    });

    // capa primeiro
    if (_coverFirst) {
      final cover = list.where((e) => e['is_cover'] == true).toList();
      final rest = list.where((e) => e['is_cover'] != true).toList();
      return [...cover, ...rest];
    }

    return list;
  }

  // ===============================
  // GALERIA
  // ===============================
  Future<void> _openGalleryAt(Map<String, dynamic> f, List<Map<String, dynamic>> currentList) async {
    final id = f['id'].toString();
    final start = max(0, currentList.indexWhere((e) => e['id'].toString() == id));
    final coverPath = (_osInfo?['cover_path'] ?? '').toString();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaGalleryPage(
          osFolderId: widget.osFolderId,
          files: currentList,
          initialIndex: start,
          currentCoverPath: coverPath.isEmpty ? null : coverPath,
        ),
      ),
    );
    await _loadOsInfoAndFiles();
  }

  // ===============================
  // EXCLUIR / CAPA / SHARE / PDF / LINK / OS
  // ===============================

  Future<void> _recalculateCoverAfterDelete() async {
    final list = await SupabaseManager.client
        .from('media_files')
        .select('id, file_type, storage_path, is_cover, created_at')
        .eq('os_folder_id', widget.osFolderId)
        .order('created_at', ascending: true);

    final files = List<Map<String, dynamic>>.from(list);

    if (files.isEmpty) {
      await SupabaseManager.client.from('os_folders').update({'cover_path': null}).eq('id', widget.osFolderId);
      return;
    }

    Map<String, dynamic>? newCover;
    try {
      newCover = files.firstWhere((e) => e['is_cover'] == true);
    } catch (_) {
      newCover = null;
    }

    if (newCover == null) {
      final imgs = files.where((e) => e['file_type'] == 'image').toList();
      newCover = imgs.isNotEmpty ? imgs.first : files.first;

      await SupabaseManager.client.from('media_files').update({'is_cover': false}).eq('os_folder_id', widget.osFolderId);
      await SupabaseManager.client.from('media_files').update({'is_cover': true}).eq('id', newCover['id']);
    }

    await SupabaseManager.client.from('os_folders').update({'cover_path': newCover['storage_path']}).eq('id', widget.osFolderId);
  }

  Future<void> _deleteMedia(String id, String storagePath, bool isCover) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Arquivar arquivo'),
        content: const Text('Arquivar este arquivo? O registro será preservado para auditoria.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true) return;

    _beginUpload();
    try {
      await SupabaseManager.client.rpc(
        'app_archive_media_file',
        params: {
          'p_media_id': id,
          'p_reason': 'Arquivado pelo app',
        },
      );

      if (isCover || storagePath == _osInfo?['cover_path']) {
        await _recalculateCoverAfterDelete();
      }

      await _loadOsInfoAndFiles();
    } catch (e) {
      _snack('Erro ao excluir arquivo: $e');
    } finally {
      _endUpload();
    }
  }

  Future<void> _setCover(String id, String storagePath) async {
    if (_busy) return;

    _beginUpload();
    try {
      final client = SupabaseManager.client;

      await client.rpc(
        'app_set_media_cover',
        params: {
          'p_os_folder_id': widget.osFolderId,
          'p_media_id': id,
        },
      );

      await _loadOsInfoAndFiles();
      _snack('Capa atualizada.');
    } catch (e) {
      _snack('Erro ao definir capa: $e');
    } finally {
      _endUpload();
    }
  }

  Future<void> _deleteSelected() async {
    final sel = _selectedFiles;
    if (sel.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Excluir ${sel.length} item(s)'),
        content: const Text('Arquivar os itens selecionados? Os registros serão preservados para auditoria.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true) return;

    _beginUpload();
    try {
      final paths = sel.map((e) => (e['storage_path'] ?? '').toString()).where((s) => s.isNotEmpty).toList();
      final ids = sel.map((e) => e['id'].toString()).toList();

      for (final id in ids) {
        await SupabaseManager.client.rpc(
          'app_archive_media_file',
          params: {
            'p_media_id': id,
            'p_reason': 'Arquivado em lote pelo app',
          },
        );
      }

      final coverPath = (_osInfo?['cover_path'] ?? '').toString();
      if (coverPath.isNotEmpty && paths.contains(coverPath)) {
        await _recalculateCoverAfterDelete();
      }

      _exitSelectMode();
      await _loadOsInfoAndFiles();
      _snack('Itens arquivados.');
    } catch (e) {
      _snack('Erro ao excluir seleção: $e');
    } finally {
      _endUpload();
    }
  }

  Future<void> _setCoverFromSelection() async {
    final sel = _selectedFiles;
    if (sel.length != 1) {
      _snack('Selecione apenas 1 imagem para definir como capa.');
      return;
    }
    final f = sel.first;
    if (f['file_type'] != 'image') {
      _snack('A capa deve ser uma imagem.');
      return;
    }

    final id = f['id'].toString();
    final path = (f['storage_path'] ?? '').toString();
    if (path.isEmpty) return;

    await _setCover(id, path);
    _exitSelectMode();
  }

  Future<void> _shareMedia({required String storagePath}) async {
    try {
      final url = await SupabaseManager.client.storage.from('smi_midias').createSignedUrl(storagePath, 3600);
      await Share.share(url);
    } catch (e) {
      _snack('Erro ao compartilhar: $e');
    }
  }

  Future<void> _shareSelected() async {
    final sel = _selectedFiles;
    if (sel.isEmpty) return;

    _beginUpload();
    try {
      final buffer = StringBuffer();
      buffer.writeln('Links (OS ${_osInfo?['ano']}/${_osInfo?['os_code']}):');
      buffer.writeln('');

      for (final f in sel) {
        final path = (f['storage_path'] ?? '').toString();
        if (path.isEmpty) continue;
        final url = await SupabaseManager.client.storage.from('smi_midias').createSignedUrl(path, 3600);
        buffer.writeln('- ${p.basename(path)}');
        buffer.writeln(url);
      }

      await Share.share(buffer.toString());
      _snack('Links compartilhados.');
    } catch (e) {
      _snack('Erro ao compartilhar seleção: $e');
    } finally {
      _endUpload();
    }
  }

  Future<void> _shareOs() async {
    if (_files.isEmpty) return;

    _beginUpload();
    try {
      final buffer = StringBuffer();
      final ano = _osInfo?['ano'];
      final osCode = _osInfo?['os_code'];

      buffer.writeln('Arquivos da OS $ano/$osCode:');
      buffer.writeln('');

      for (final f in _files) {
        final path = (f['storage_path'] ?? '').toString();
        if (path.isEmpty) continue;

        final url = await SupabaseManager.client.storage.from('smi_midias').createSignedUrl(path, 3600);
        final isImage = f['file_type'] == 'image';
        final tipoMidia = isImage ? 'Imagem' : 'Vídeo';

        buffer.writeln('- $tipoMidia: ${p.basename(path)}');
        buffer.writeln(url);
      }

      await Share.share(buffer.toString());
    } catch (e) {
      _snack('Erro ao compartilhar OS: $e');
    } finally {
      _endUpload();
    }
  }

  Future<void> _saveOsNotes() async {
    final novoStatus   = (_osInfo?['status']   ?? 'aberta').toString();
    final novoExecucao = (_osInfo?['execucao']  ?? 'pendente').toString();

    // situacao_equipamento só faz sentido quando em execução
    final novaSituacao = novoExecucao == 'em_execucao' ? _situacaoEquipamento : null;

    try {
      final updated = await SupabaseManager.client
          .from('os_folders')
          .update({
            'status':               novoStatus,
            'execucao':             novoExecucao,
            'situacao_equipamento': novaSituacao,
          })
          .eq('id', widget.osFolderId)
          .select('id, status, execucao, situacao_equipamento');

      final rows = (updated as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (rows.isEmpty) {
        _snack('Atenção: nenhuma linha foi atualizada. Verifique as permissões (RLS) no Supabase.');
        return;
      }

      if (mounted) {
        setState(() {
          _osInfo?['status']               = rows.first['status'];
          _osInfo?['execucao']             = rows.first['execucao'];
          _osInfo?['situacao_equipamento'] = rows.first['situacao_equipamento'];
          _situacaoEquipamento = (rows.first['situacao_equipamento'] ?? '').toString().trim().isEmpty
              ? null
              : rows.first['situacao_equipamento'].toString().trim();
        });
      }

      _snack('Salvo com sucesso.');
    } catch (e) {
      _snack('Erro ao salvar: $e');
    }
  }

  String _genToken([int length = 32]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _createOrCopyPublicLink() async {
    try {
      final result = await SupabaseManager.client.rpc(
        'app_create_public_os_link',
        params: {
          'p_os_folder_id': widget.osFolderId,
          'p_expires_at': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
          'p_created_by': (_osInfo?['tecnico_nome'] ?? '').toString(),
        },
      );

      Map<String, dynamic> row;
      if (result is List && result.isNotEmpty) {
        row = Map<String, dynamic>.from(result.first as Map);
      } else if (result is Map) {
        row = Map<String, dynamic>.from(result);
      } else {
        throw Exception('RPC app_create_public_os_link não retornou link.');
      }

      final url = (row['url'] ?? '').toString();
      if (url.isEmpty) throw Exception('Link público vazio.');

      await Clipboard.setData(ClipboardData(text: url));
      _snack('Link público copiado.');
    } catch (e) {
      _snack('Erro ao criar/copiar link público: $e');
    }
  }

  Future<void> _deleteOs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Arquivar OS'),
        content: const Text(
          'Isso irá excluir a pasta da OS e TODOS os arquivos de mídia associados.\n'
              'Esta ação é irreversível. Deseja continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Arquivar OS')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deletingOs = true);

    try {
      await SupabaseManager.client.rpc(
        'app_archive_os_folder',
        params: {
          'p_os_folder_id': widget.osFolderId,
          'p_reason': 'OS arquivada pelo app',
        },
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingOs = false);
      _snack('Erro ao arquivar OS: $e');
    }
  }

  void _openHorasPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OsFolderApontamentosPage(
          osFolderId: widget.osFolderId,
          titleLabel: _osInfo == null ? null : 'OS ${_osInfo!['ano']}/${_osInfo!['os_code']}',
        ),
      ),
    );
  }

  void _toggleView() {
    setState(() {
      _viewMode = _viewMode == _MediaViewMode.grid ? _MediaViewMode.list : _MediaViewMode.grid;
    });
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Câmera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImageFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeria (múltiplas)'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImagesFromGallery(multiple: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showVideoSourceSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Vídeo da câmera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo(useCamera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Vídeo da galeria'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo(useCamera: false);
              },
            ),
          ],
        ),
      ),
    );
  }



  void _showAddMediaSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Foto (câmera)'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImageFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.perm_media_outlined),
              title: const Text('Fotos/Vídeos (galeria - lote até 150)'),
              subtitle: const Text('Mais estável para grandes quantidades.'),
              onTap: () {
                Navigator.pop(ctx);
                _pickMediaBatchFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Somente fotos (galeria - múltiplas)'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImagesFromGallery(multiple: true);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Vídeo (câmera)'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo(useCamera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Vídeo (galeria)'),
              onTap: () {
                Navigator.pop(ctx);
                _pickVideo(useCamera: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasAnyActiveFilter => false;

  void _clearFilters() {
    setState(() {
      _filter = _MediaFilter.all;
      _period = _MediaPeriod.all;
      _sort = _MediaSort.newest;
      _coverFirst = true;
      _search = '';
      _searchCtrl.text = '';
    });
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var tmpFilter = _filter;
        var tmpPeriod = _period;
        var tmpSort = _sort;
        var tmpCoverFirst = _coverFirst;

        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filtros', style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 12),

                    Text('Tipo de mídia', style: Theme.of(ctx).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SegmentedButton<_MediaFilter>(
                      segments: const [
                        ButtonSegment(value: _MediaFilter.all, label: Text('Tudo')),
                        ButtonSegment(value: _MediaFilter.images, label: Text('Imagens')),
                        ButtonSegment(value: _MediaFilter.videos, label: Text('Vídeos')),
                      ],
                      selected: {tmpFilter},
                      onSelectionChanged: (s) => setSheet(() => tmpFilter = s.first),
                    ),

                    const SizedBox(height: 14),
                    Text('Período', style: Theme.of(ctx).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SegmentedButton<_MediaPeriod>(
                      segments: const [
                        ButtonSegment(value: _MediaPeriod.all, label: Text('Tudo')),
                        ButtonSegment(value: _MediaPeriod.today, label: Text('Hoje')),
                        ButtonSegment(value: _MediaPeriod.d7, label: Text('7d')),
                        ButtonSegment(value: _MediaPeriod.d30, label: Text('30d')),
                      ],
                      selected: {tmpPeriod},
                      onSelectionChanged: (s) => setSheet(() => tmpPeriod = s.first),
                    ),

                    const SizedBox(height: 14),
                    Text('Ordenação', style: Theme.of(ctx).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SegmentedButton<_MediaSort>(
                      segments: const [
                        ButtonSegment(value: _MediaSort.newest, label: Text('Mais recente')),
                        ButtonSegment(value: _MediaSort.oldest, label: Text('Mais antigo')),
                      ],
                      selected: {tmpSort},
                      onSelectionChanged: (s) => setSheet(() => tmpSort = s.first),
                    ),

                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: tmpCoverFirst,
                      onChanged: (v) => setSheet(() => tmpCoverFirst = v),
                      title: const Text('Capa primeiro'),
                    ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            setSheet(() {
                              tmpFilter = _MediaFilter.all;
                              tmpPeriod = _MediaPeriod.all;
                              tmpSort = _MediaSort.newest;
                              tmpCoverFirst = true;
                            });
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Limpar'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _filter = tmpFilter;
                              _period = tmpPeriod;
                              _sort = tmpSort;
                              _coverFirst = tmpCoverFirst;
                            });
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Aplicar'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _activeFilterChips() {
    return const <Widget>[];
  }

  Widget _chip({required String label, required VoidCallback onClear}) {
    return InputChip(
      label: Text(label),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close, size: 18),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  String _normalizeStatusDetalhe(String? raw) {
    var s = (raw ?? '').trim().toLowerCase();
    s = s
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ');
    s = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).join(' ');

    if (s == 'encerrado' ||
        s == 'encerrada' ||
        s == 'fechado' ||
        s == 'fechada' ||
        s == 'closed' ||
        s == 'excluido' ||
        s == 'excluida' ||
        s == 'deletado' ||
        s == 'deletada' ||
        s == 'deleted' ||
        s == 'cancelado' ||
        s == 'cancelada' ||
        s == 'exc') {
      return 'encerrada';
    }
    return 'aberta';
  }

  String _normalizeExecucaoDetalhe(String? raw) {
    var s = (raw ?? '').trim().toLowerCase();
    s = s
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ');
    s = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).join(' ');
    if (s == 'encerrada' ||
        s == 'encerrado' ||
        s == 'fechada' ||
        s == 'fechado' ||
        s == 'closed' ||
        s == 'excluida' ||
        s == 'excluido' ||
        s == 'deletada' ||
        s == 'deletado' ||
        s == 'deleted' ||
        s == 'cancelada' ||
        s == 'cancelado' ||
        s == 'exc') {
      return 'encerrada';
    }
    if (s == 'em execucao' || s == 'execucao' || s == 'executando' || s == 'em andamento') return 'em_execucao';
    if (s == 'finalizada' || s == 'finalizado' || s == 'concluida' || s == 'concluido') return 'finalizada';
    return 'pendente';
  }

  String _estadoOperacionalDetalhe() {
    final status = _normalizeStatusDetalhe(_osInfo?['status']?.toString());
    if (status == 'encerrada') return 'encerrada';
    return _normalizeExecucaoDetalhe(_osInfo?['execucao']?.toString());
  }

  String _estadoOperacionalLabel(String key) {
    switch (key) {
      case 'pendente':
        return 'Pendente';
      case 'em_execucao':
        return 'Em execução';
      case 'finalizada':
        return 'Finalizada';
      case 'encerrada':
        return 'Encerrada';
      default:
        return key;
    }
  }


  void _openDetailsSheet() {
    // garante raw carregado (se ainda não veio)
    if (_osRaw == null) {
      _loadOsRawFromServer();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final kb = MediaQuery.of(ctx).viewInsets.bottom;

        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.82,
            minChildSize: 0.35,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return StatefulBuilder(
                builder: (context, setSheet) {
                  final st = _normalizeStatusDetalhe(_osInfo?['status']?.toString());
                  final ex = _normalizeExecucaoDetalhe(_osInfo?['execucao']?.toString());
                  final estado = _estadoOperacionalDetalhe();

                  return ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + kb),
                    children: [
                      Text(
                        'Detalhes da OS',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.cloud_outlined, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Dados do servidor',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: 'Recarregar',
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                      await _loadOsRawFromServer();
                                      if (!mounted) return;
                                      _snack('Dados atualizados.');
                                      setSheet(() {});
                                    },
                                    icon: const Icon(Icons.refresh),
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              _detailRow('Cliente', _clienteNome() ?? _osRaw?['cliente']?.toString()),
                              _detailRow('Departamento', _osRaw?['departamento']?.toString()),
                              _detailRow('Serviço solicitado', _servicoSolicitadoFromRaw()),
                              _detailRow('Data abertura', _osRaw?['dataabertura']?.toString()),
                              _detailRow('Status da OS', st == 'encerrada' ? 'Encerrada' : 'Aberta'),
                              _detailRow('Execução da OS', _estadoOperacionalLabel(ex)),
                              _detailRow('Estado no app', _estadoOperacionalLabel(estado)),
                              _detailRow('Equipamento', _extractNested(_osRaw, 'equipamento', 'descricao')),
                              _detailRow('Máquina', _extractNested(_osRaw, 'maquina', 'descricao')),
                              _detailRow('Alarme', _extractNested(_osRaw, 'alarme', 'descricao')),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Técnico responsável (obrigatório para mídia)
                      Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: const Icon(Icons.engineering_outlined),
                          title: const Text('Técnico responsável'),
                          subtitle: Text(
                            _hasTecnicoResponsavel
                                ? (_osInfo?['tecnico_nome'] ?? '').toString()
                                : 'Selecione para liberar fotos e vídeos',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy
                              ? null
                              : () async {
                            final picked = await _pickTecnicoBottomSheet();
                            if (picked == null) return;
                            try {
                              await _setTecnicoResponsavel(picked);
                              if (mounted) _snack('Técnico responsável atualizado.');
                              setSheet(() {});
                            } catch (e) {
                              _snack('Erro ao salvar técnico: $e');
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      Text('Status da OS', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      // Mapeamento de estado operacional → (p_status, p_execucao)
                      // A RPC app_set_os_status recebe os dois parâmetros separados.
                      // 'encerrada' usa p_status='encerrada'; os demais usam p_status='aberta'
                      // e variam p_execucao para refletir o progresso real da OS.
                      DropdownButtonFormField<String>(
                        value: _estadoOperacionalDetalhe(),
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'pendente',
                            child: Text('Pendente'),
                          ),
                          DropdownMenuItem(
                            value: 'em_execucao',
                            child: Text('Em execução'),
                          ),
                          DropdownMenuItem(
                            value: 'finalizada',
                            child: Text('Finalizada'),
                          ),
                          DropdownMenuItem(
                            value: 'encerrada',
                            child: Text('Encerrada'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (v) {
                          if (v == null) return;

                          // Converte o estado selecionado nos dois campos do banco
                          final String novoStatus   = v == 'encerrada' ? 'encerrada' : 'aberta';
                          final String novoExecucao = v; // pendente | em_execucao | finalizada | encerrada

                          // Atualiza apenas o estado local — a persistência ocorre ao clicar em Salvar
                          setSheet(() {
                            _osInfo!['status']   = novoStatus;
                            _osInfo!['execucao'] = novoExecucao;
                          });
                          if (mounted) setState(() {
                            _osInfo!['status']   = novoStatus;
                            _osInfo!['execucao'] = novoExecucao;
                          });
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_normalizeExecucaoDetalhe(_osInfo?['execucao']?.toString()) == 'em_execucao') ...[
                        Text('Situação do equipamento', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _situacaoEquipamento,
                          isExpanded: true,
                          hint: const Text('Selecione a situação'),
                          items: const [
                            DropdownMenuItem(
                              value: 'em_analise',
                              child: Text('Equipamento em análise'),
                            ),
                            DropdownMenuItem(
                              value: 'aguardando_pecas',
                              child: Text('Equipamento aguardando peças'),
                            ),
                            DropdownMenuItem(
                              value: 'aguardando_orcamento',
                              child: Text('Equipamento aguardando orçamento'),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) {
                            setSheet(() => _situacaoEquipamento = v);
                            if (mounted) setState(() => _situacaoEquipamento = v);
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.save),
                              label: const Text('Salvar'),
                              onPressed: () async {
                                await _saveOsNotes();
                                if (!mounted) return;
                                Navigator.pop(context);
                                // Recarrega os dados da OS para refletir o novo status na tela
                                await _loadOsInfoAndFiles();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showMediaActions(Map<String, dynamic> f) async {
    final id = f['id'].toString();
    final isImage = f['file_type'] == 'image';
    final isCover = f['is_cover'] == true;
    final path = (f['storage_path'] ?? '').toString();

    if (path.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(isImage ? Icons.open_in_new : Icons.play_arrow),
              title: const Text('Abrir'),
              onTap: () {
                Navigator.pop(ctx);
                _openGalleryAt(f, _filteredFiles);
              },
            ),
            if (isImage)
              ListTile(
                leading: const Icon(Icons.star),
                title: Text(isCover ? 'Já é capa' : 'Definir como capa'),
                enabled: !_busy && !isCover,
                onTap: (!_busy && !isCover)
                    ? () async {
                  Navigator.pop(ctx);
                  await _setCover(id, path);
                }
                    : null,
              ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Compartilhar link'),
              enabled: !_busy,
              onTap: _busy
                  ? null
                  : () async {
                Navigator.pop(ctx);
                await _shareMedia(storagePath: path);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('Excluir'),
              enabled: !_busy,
              onTap: _busy
                  ? null
                  : () async {
                Navigator.pop(ctx);
                await _deleteMedia(id, path, isCover);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbSmall(Map<String, dynamic> f, {double size = 52}) {
    final cs = Theme.of(context).colorScheme;
    final isImage = f['file_type'] == 'image';
    final path = (f['storage_path'] ?? '').toString();

    if (!isImage || path.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Icon(Icons.videocam, color: cs.onSurfaceVariant),
      );
    }

    return FutureBuilder<String?>(
      future: _signedUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
              ),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: cs.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _gridThumbFill(Map<String, dynamic> f) {
    final cs = Theme.of(context).colorScheme;
    final isImage = f['file_type'] == 'image';
    final path = (f['storage_path'] ?? '').toString();

    if (!isImage || path.isEmpty) {
      return Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.videocam, size: 40, color: cs.onSurfaceVariant),
      );
    }

    return FutureBuilder<String?>(
      future: _signedUrl(path),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return Container(
            color: cs.surfaceContainerHighest,
            alignment: Alignment.center,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            ),
          );
        }

        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: cs.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
          ),
        );
      },
    );
  }

  Widget _selectionOverlay(bool selected) {
    if (!selected) return const SizedBox.shrink();
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.topRight,
        padding: const EdgeInsets.all(10),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Icon(Icons.check, color: Colors.white, size: 16),
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> files) {
    if (files.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('Nenhuma mídia.')),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: files.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final f = files[i];
        final id = f['id'].toString();
        final path = (f['storage_path'] ?? '').toString();
        final isCover = f['is_cover'] == true;
        final selected = _selected.contains(id);

        return ListTile(
          leading: Stack(
            children: [
              _thumbSmall(f),
              if (_selectMode && selected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 14),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              Expanded(child: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (isCover) const Icon(Icons.star, color: Colors.amber, size: 18),
            ],
          ),
          onTap: () {
            if (_selectMode) {
              _toggleSelected(id);
            } else {
              _openGalleryAt(f, files);
            }
          },
          onLongPress: () {
            if (!_selectMode) _enterSelectMode(id);
          },
          trailing: _selectMode
              ? Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
          )
              : IconButton(
            tooltip: 'Ações',
            onPressed: _busy ? null : () => _showMediaActions(f),
            icon: Icon(Icons.more_horiz, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        );
      },
    );
  }

  Widget _buildGrid(List<Map<String, dynamic>> files) {
    if (files.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('Nenhuma mídia.')),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cross = w >= 980 ? 6 : (w >= 740 ? 5 : (w >= 520 ? 4 : 3));

        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemCount: files.length,
          itemBuilder: (context, i) {
            final f = files[i];
            final id = f['id'].toString();
            final isCover = f['is_cover'] == true;
            final path = (f['storage_path'] ?? '').toString();
            final selected = _selected.contains(id);

            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (_selectMode) {
                  _toggleSelected(id);
                } else {
                  _openGalleryAt(f, files);
                }
              },
              onLongPress: () {
                if (!_selectMode) _enterSelectMode(id);
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _gridThumbFill(f),
                    ),
                  ),
                  if (_selectMode) _selectionOverlay(selected),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(
                      children: [
                        if (!_selectMode)
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: _busy ? null : () => _showMediaActions(f),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Icon(Icons.more_vert, color: Colors.white, size: 16),
                            ),
                          ),
                        if (isCover) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Icon(Icons.star, color: Colors.amber, size: 16),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        p.basename(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===============================
  // PENDÊNCIAS (INDICADOR + BANNER)
  // ===============================
  Widget _pendingAction() {
    return ValueListenableBuilder<int>(
      valueListenable: OutboxService.I.pendingCount,
      builder: (context, count, _) {
        return IconButton(
          tooltip: count > 0 ? 'Outbox ($count)' : 'Outbox',
          onPressed: _busy
              ? null
              : () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OutboxPage(osFolderId: widget.osFolderId, osLabel: _currentOsLabel()),
              ),
            );
            await _loadOsInfoAndFiles();
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.cloud_upload_outlined),
              if (count > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _pendingBanner() {
    return ValueListenableBuilder<int>(
      valueListenable: OutboxService.I.pendingCount,
      builder: (context, count, _) {
        if (count <= 0) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, color: Colors.red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Existem $count mídia(s) pendente(s) de envio.',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OutboxPage(osFolderId: widget.osFolderId, osLabel: _currentOsLabel()),
                    ),
                  );
                  await _loadOsInfoAndFiles();
                },
                child: const Text('Ver'),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _appBarActionsNormal(List<Map<String, dynamic>> filtered) => [
    _pendingAction(),IconButton(
      icon: Icon(_viewMode == _MediaViewMode.grid ? Icons.view_list : Icons.grid_view),
      tooltip: _viewMode == _MediaViewMode.grid ? 'Ver em lista' : 'Ver em grade',
      onPressed: _toggleView,
    ),
    IconButton(
      icon: const Icon(Icons.checklist_rounded),
      tooltip: 'Checklist da OS',
      onPressed: _busy
          ? null
          : () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OsChecklistPage(
                    osFolderId: widget.osFolderId,
                    osLabel: _currentOsLabel(),
                    ano: (_osInfo?['ano'] ?? '').toString(),
                    osCode: (_osInfo?['os_code'] ?? '').toString(),
                  ),
                ),
              );
              await _loadOsInfoAndFiles();
            },
    ),
    IconButton(
      icon: const Icon(Icons.timer_outlined),
      tooltip: 'Apontamento de horas',
      onPressed: _busy ? null : _openHorasPage,
    ),
    IconButton(
      icon: const Icon(Icons.info_outline),
      tooltip: 'Detalhes',
      onPressed: _busy ? null : _openDetailsSheet,
    ),
    IconButton(
      icon: const Icon(Icons.picture_as_pdf),
      tooltip: 'Exportar PDF',
      onPressed: filtered.isEmpty || _busy
          ? null
          : () async {
        setState(() => _generatingPdf = true);
        try {
          await OsPdfExport.exportOsToPdf(
            context: context,
            osInfo: _osInfo!,
            mediaFiles: _files,
          );
        } finally {
          if (mounted) setState(() => _generatingPdf = false);
        }
      },
    ),
    IconButton(
      icon: const Icon(Icons.share),
      tooltip: 'Compartilhar OS',
      onPressed: filtered.isEmpty || _busy ? null : _shareOs,
    ),
    IconButton(
      icon: const Icon(Icons.link),
      tooltip: 'Link público',
      onPressed: _busy ? null : _createOrCopyPublicLink,
    ),
    IconButton(
      icon: const Icon(Icons.delete_forever),
      tooltip: 'Arquivar OS',
      onPressed: _deletingOs ? null : _deleteOs,
    ),
  ];

  List<Widget> _appBarActionsSelect() => [
    IconButton(
      icon: const Icon(Icons.select_all),
      tooltip: 'Selecionar tudo (filtro atual)',
      onPressed: _busy ? null : _selectAllFiltered,
    ),
    IconButton(
      icon: const Icon(Icons.star),
      tooltip: 'Definir capa (1 imagem)',
      onPressed: _busy ? null : _setCoverFromSelection,
    ),
    IconButton(
      icon: const Icon(Icons.share),
      tooltip: 'Compartilhar links',
      onPressed: _busy ? null : _shareSelected,
    ),
    IconButton(
      icon: const Icon(Icons.delete),
      tooltip: 'Excluir selecionados',
      onPressed: _busy ? null : _deleteSelected,
    ),
    IconButton(
      icon: const Icon(Icons.close),
      tooltip: 'Sair da seleção',
      onPressed: _busy ? null : _exitSelectMode,
    ),
  ];

  // ===============================
  // BUILD
  // ===============================
  @override
  Widget build(BuildContext context) {
    if (_loadingInfo || _osInfo == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ano = (_osInfo!['ano'] ?? '').toString();
    final osCode = (_osInfo!['os_code'] ?? '').toString();
    final tipoCode = (_osInfo!['tipo'] ?? '').toString();
    final setor = (_osInfo!['setor'] ?? '').toString();

    final tipoLabel = _tipoLabel(tipoCode);
    final subtitle = setor.trim().isEmpty ? tipoLabel : '$tipoLabel · $setor';

    final filtered = _filteredFiles;

    final chips = _activeFilterChips();
    final showChips = chips.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: _selectMode
            ? Text('${_selected.length} selecionado(s)')
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('OS $ano/$osCode', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: _selectMode ? _appBarActionsSelect() : _appBarActionsNormal(filtered),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(showChips || _hasAnyActiveFilter ? 96 : 72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Buscar mídia (nome, tag, observação...)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.trim().isEmpty
                        ? null
                        : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.close),
                      onPressed: _busy
                          ? null
                          : () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    ),
                    isDense: true,
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (showChips)
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ...chips.map((c) => Padding(padding: const EdgeInsets.only(right: 8), child: c)),
                              if (_hasAnyActiveFilter)
                                TextButton.icon(
                                  onPressed: _busy ? null : _clearFilters,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Limpar'),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _hasAnyActiveFilter
                              ? TextButton.icon(
                            onPressed: _busy ? null : _clearFilters,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Limpar filtros'),
                          )
                              : Text(
                            'Mostrando ${filtered.length} item(ns)',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      _selectMode ? '${_selected.length}' : '${filtered.length}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_busy) ...[
            LinearProgressIndicator(
              minHeight: 2,
              value: _batchQueueing && _batchQueueTotal > 0 ? (_batchQueueDone / _batchQueueTotal).clamp(0.0, 1.0) : null,
            ),
            if (_batchQueueing)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                child: Text(
                  'Preparando mídias: $_batchQueueDone/$_batchQueueTotal',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              )
            else if (_generatingPdf)
              const Padding(
                padding: EdgeInsets.only(top: 4.0, bottom: 4.0),
                child: Text('Gerando PDF, aguarde...', style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
          ],
          _pendingBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reloadPage,
              child: _viewMode == _MediaViewMode.grid ? _buildGrid(filtered) : _buildList(filtered),
            ),
          ),
        ],
      ),
      floatingActionButton: (!_selectMode && !_busy)
          ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (filtered.isNotEmpty)
            FloatingActionButton.small(
              heroTag: 'fab_select',
              onPressed: () => _enterSelectMode(filtered.first['id'].toString()),
              child: const Icon(Icons.checklist),
            ),
          if (filtered.isNotEmpty) const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'fab_add',
            onPressed: _showAddMediaSheet,
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Adicionar'),
          ),
        ],
      )
          : null,
    );
  }
}
