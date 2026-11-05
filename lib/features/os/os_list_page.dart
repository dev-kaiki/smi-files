// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/os/os_list_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sml_files/core/supabase/supabase_manager.dart';

import '../../utils/os_backup.dart';
import '../../utils/setor_access.dart';
import 'os_folder_apontamentos_page.dart';
import 'os_media_page.dart';

class OsListPage extends StatefulWidget {
  const OsListPage({
    super.key,
    required this.tecnicoId,
    required this.tecnicoNome,
    required this.setor,
  });

  final int tecnicoId;
  final String tecnicoNome;
  final String setor;

  @override
  State<OsListPage> createState() => _OsListPageState();
}

class _OsListPageState extends State<OsListPage> {
  // Busca texto livre (topo da tela)
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ✅ controla o suffixIcon (X) de forma confiável
  bool _hasSearchText = false;

  // Filtros avançados (em memória)
  String? _statusFiltro; // pendente / em_execucao / finalizada / encerrada
  String? _tipoFiltro; // reforma / assistencia / servicos
  String? _setorFiltro; // filtro dentro dos setores visíveis para o usuário
  String? _anoFiltroText;
  String? _clienteFiltroId;
  String? _clienteFiltroNome;
  String? _tecnicoFiltroId;
  String? _tecnicoFiltroNome;

  // Campo "Ano" no filtro (controller fixo para não resetar)
  final TextEditingController _anoFiltroCtrl = TextEditingController();

  // Busca de cliente dentro do filtro
  final TextEditingController _clienteFiltroCtrl = TextEditingController();
  Timer? _clienteDebounce;
  bool _loadingClientesFiltro = false;
  List<Map<String, dynamic>> _clientesFiltroResultados = [];

  // Busca de técnico dentro do filtro
  final TextEditingController _tecnicoFiltroCtrl = TextEditingController();
  Timer? _tecnicoDebounce;
  bool _loadingTecnicosFiltro = false;
  List<Map<String, dynamic>> _tecnicosFiltroResultados = [];

  bool _isLoading = false; // carregando lista de OS
  bool _isBackingUp = false; // fazendo backup geral

  List<Map<String, dynamic>> _todasOs = [];
  List<Map<String, dynamic>> _osFiltradas = [];

  // ==========================
  // CACHE de URLs assinadas (capa)
  // ==========================
  final Map<String, Future<String>> _coverUrlFuture = {};
  final Map<String, String> _coverUrlCache = {};

  Future<String?> _getCoverSignedUrl(String? storagePath) async {
    final path = (storagePath ?? '').trim();
    if (path.isEmpty) return null;

    final cached = _coverUrlCache[path];
    if (cached != null && cached.isNotEmpty) return cached;

    final fut = _coverUrlFuture.putIfAbsent(path, () async {
      final url = await SupabaseManager.client.storage.from('smi_midias').createSignedUrl(path, 3600);
      _coverUrlCache[path] = url;
      return url;
    });

    return fut;
  }

  Widget _buildCoverOrIcon(String? coverPath, Color tipoColor) {
    final cs = Theme.of(context).colorScheme;

    if (coverPath == null || coverPath.trim().isEmpty) {
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: tipoColor.withOpacity(0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tipoColor.withOpacity(0.35)),
        ),
        child: Icon(Icons.folder, color: tipoColor, size: 22),
      );
    }

    return FutureBuilder<String?>(
      future: _getCoverSignedUrl(coverPath),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null || url.isEmpty) {
          return Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant, size: 20),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: cs.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant, size: 18),
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: cs.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress.expectedTotalBytes == null
                          ? null
                          : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  String get _userSetor => normalizeSetor(widget.setor);
  Set<String> get _visibleSetores => visibleSetoresFor(widget.setor);

  @override
  void initState() {
    super.initState();

    // ✅ listener pra atualizar o (X) do campo de busca corretamente
    _hasSearchText = _searchController.text.trim().isNotEmpty;
    _searchController.addListener(_syncSearchSuffixUi);

    _carregarOs();
  }

  void _syncSearchSuffixUi() {
    final has = _searchController.text.trim().isNotEmpty;
    if (has != _hasSearchText) {
      if (!mounted) return;
      setState(() => _hasSearchText = has);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _clienteDebounce?.cancel();
    _tecnicoDebounce?.cancel();

    _searchController.removeListener(_syncSearchSuffixUi);
    _searchController.dispose();

    _anoFiltroCtrl.dispose();
    _clienteFiltroCtrl.dispose();
    _tecnicoFiltroCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ==========================
  // CARREGAR OS DO SUPABASE
  // ==========================

  Future<void> _carregarOs() async {
    setState(() => _isLoading = true);

    try {
      dynamic resp;

      try {
        resp = await SupabaseManager.client
            .from('os_folders')
            .select('''
            id,
            ano,
            os_code,
            os_principal_code,
            is_sub,
            empresa_code,
            tipo,
            status,
            execucao,
            setor,
            client_id,
            tecnico_id,
            tecnico_nome,
            cover_path,
            storage_prefix,
            created_at,
            clientes ( razao_social )
          ''')
            .order('created_at', ascending: false);
      } catch (e) {
        final msg = e.toString().toLowerCase();
        final isMissingColumn = msg.contains('42703') ||
            msg.contains('does not exist') ||
            msg.contains('empresa_code') ||
            msg.contains('is_sub') ||
            msg.contains('os_principal_code') ||
            msg.contains('storage_prefix');

        if (!isMissingColumn) rethrow;

        // Fallback para schema antigo
        resp = await SupabaseManager.client
            .from('os_folders')
            .select('''
            id,
            ano,
            os_code,
            tipo,
            status,
            execucao,
            setor,
            client_id,
            tecnico_id,
            tecnico_nome,
            cover_path,
            storage_prefix,
            created_at,
            clientes ( razao_social )
          ''')
            .order('created_at', ascending: false);
      }

      var lista = (resp as List).cast<Map<String, dynamic>>();

      // VISIBILIDADE POR SETOR
      lista = lista.where((os) {
        return canUserSeeOs(
          userSetor: _userSetor,
          osSetor: os['setor']?.toString(),
        );
      }).toList();

      // Filtros avançados (em memória)
      if (_setorFiltro != null && _setorFiltro!.isNotEmpty) {
        final f = normalizeSetor(_setorFiltro);
        lista = lista.where((os) {
          final osSetor = normalizeSetor(os['setor']?.toString());
          return osSetor == f;
        }).toList();
      }

      // Status
      if (_statusFiltro != null && _statusFiltro!.isNotEmpty) {
        final f = _statusFiltro!.toLowerCase().trim();
        lista = lista.where((os) {
          final st = _estadoOperacionalKey(os);
          return st == f;
        }).toList();
      }

      // Tipo (preferindo empresa_code quando existir)
      if (_tipoFiltro != null && _tipoFiltro!.isNotEmpty) {
        final f = _tipoFiltro!.toLowerCase().trim();
        lista = lista.where((os) => _tipoKeyFromRow(os) == f).toList();
      }

      // Ano
      if (_anoFiltroText != null && _anoFiltroText!.trim().isNotEmpty) {
        final f = _anoFiltroText!.trim();
        lista = lista.where((os) {
          final ano = (os['ano'] ?? '').toString().trim();
          return ano == f;
        }).toList();
      }

      // Cliente
      if (_clienteFiltroId != null && _clienteFiltroId!.isNotEmpty) {
        final f = _clienteFiltroId!;
        lista = lista.where((os) {
          final cid = (os['client_id'] ?? '').toString();
          return cid == f;
        }).toList();
      }

      // Técnico responsável
      if (_tecnicoFiltroId != null && _tecnicoFiltroId!.isNotEmpty) {
        final f = _tecnicoFiltroId!;
        lista = lista.where((os) {
          final tid = (os['tecnico_id'] ?? '').toString();
          return tid == f;
        }).toList();
      }

      // ✅ Ordenação padrão (profissional): Abertas -> Em andamento -> Aguardando cliente -> Finalizadas
      _sortOsDefault(lista);

      _todasOs = lista;
      _aplicarFiltroTextoLivre(_searchController.text, setStateNow: true);
    } catch (e) {
      debugPrint('Erro ao carregar OS: $e');
      _snack('Erro ao carregar OS: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reloadPage() async {
    FocusScope.of(context).unfocus();
    await _carregarOs();
  }

  // ==========================
  // FILTRO TEXTO LIVRE (com debounce)
  // ==========================

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _aplicarFiltroTextoLivre(v, setStateNow: true);
    });
  }

  void _aplicarFiltroTextoLivre(String query, {bool setStateNow = false}) {
    final q = query.trim().toLowerCase();

    final filtered = (q.isEmpty)
        ? List<Map<String, dynamic>>.from(_todasOs)
        : _todasOs.where((os) {
      final cliente = _safeClienteNome(os).toLowerCase();
      final tipoKey = _tipoKeyFromRow(os);
      final emp = _empresaCodeFromAny(os['empresa_code']);
      final principal = _principalCodeFromRow(os);
      final sub = _isSubFromRow(os) ? 'sub-os' : 'os-principal';

      final texto =
      '$cliente ${os['ano']} ${os['os_code']} $principal $sub $tipoKey $emp ${os['status']} ${os['execucao']} ${os['setor']} ${(os['tecnico_nome'] ?? '').toString()}'
          .toLowerCase();

      return texto.contains(q);
    }).toList();

    if (setStateNow) {
      setState(() => _osFiltradas = filtered);
    } else {
      _osFiltradas = filtered;
    }
  }

  // ==========================
  // BUSCA CLIENTES (FILTRO)
  // ==========================

  void _onClienteFiltroChanged(String v, StateSetter setSheet) {
    _clienteDebounce?.cancel();
    _clienteDebounce = Timer(const Duration(milliseconds: 250), () {
      _buscarClientesFiltro(v, setSheet);
    });
  }

  Future<void> _buscarClientesFiltro(String query, StateSetter setSheet) async {
    _loadingClientesFiltro = true;
    _clientesFiltroResultados = [];
    setSheet(() {});

    try {
      dynamic resp;

      if (query.trim().isEmpty) {
        resp = await SupabaseManager.client
            .from('clientes')
            .select('id, razao_social, codigo')
            .order('razao_social')
            .limit(100);
      } else {
        resp = await SupabaseManager.client
            .from('clientes')
            .select('id, razao_social, codigo')
            .ilike('razao_social', '%$query%')
            .order('razao_social')
            .limit(20);
      }

      _clientesFiltroResultados = (resp as List).cast<Map<String, dynamic>>();
      _loadingClientesFiltro = false;
      if (mounted) setSheet(() {});
    } catch (e) {
      debugPrint('Erro ao buscar clientes (filtro): $e');
      _loadingClientesFiltro = false;
      if (mounted) {
        _snack('Erro ao buscar clientes: $e');
        setSheet(() {});
      }
    }
  }

  void _selecionarClienteFiltro(Map<String, dynamic> cliente, StateSetter setSheet) {
    _clienteFiltroId = cliente['id'].toString();
    _clienteFiltroNome = cliente['razao_social']?.toString() ?? '';
    _clienteFiltroCtrl.text = _clienteFiltroNome!;
    _clientesFiltroResultados = [];
    setSheet(() {});
  }

  void _limparFiltroCliente({StateSetter? setSheet}) {
    _clienteFiltroId = null;
    _clienteFiltroNome = null;
    _clienteFiltroCtrl.clear();
    _clientesFiltroResultados = [];
    setSheet?.call(() {});
  }

  // ==========================
  // BUSCA TÉCNICOS (FILTRO)
  // ==========================

  void _onTecnicoFiltroChanged(String v, StateSetter setSheet) {
    _tecnicoDebounce?.cancel();
    _tecnicoDebounce = Timer(const Duration(milliseconds: 250), () {
      _buscarTecnicosFiltro(v, setSheet);
    });
  }

  Future<void> _buscarTecnicosFiltro(String query, StateSetter setSheet) async {
    _loadingTecnicosFiltro = true;
    _tecnicosFiltroResultados = [];
    setSheet(() {});

    try {
      dynamic resp;

      if (query.trim().isEmpty) {
        resp = await SupabaseManager.client
            .from('tecnicos')
            .select('id, nome, codigo, setor')
            .order('nome')
            .limit(50);
      } else {
        resp = await SupabaseManager.client
            .from('tecnicos')
            .select('id, nome, codigo, setor')
            .ilike('nome', '%$query%')
            .order('nome')
            .limit(20);
      }

      _tecnicosFiltroResultados = (resp as List).cast<Map<String, dynamic>>();
      _loadingTecnicosFiltro = false;
      if (mounted) setSheet(() {});
    } catch (e) {
      debugPrint('Erro ao buscar técnicos (filtro): $e');
      _loadingTecnicosFiltro = false;
      if (mounted) {
        _snack('Erro ao buscar técnicos: $e');
        setSheet(() {});
      }
    }
  }

  void _selecionarTecnicoFiltro(Map<String, dynamic> tecnico, StateSetter setSheet) {
    _tecnicoFiltroId = tecnico['id'].toString();
    _tecnicoFiltroNome = tecnico['nome']?.toString() ?? '';
    _tecnicoFiltroCtrl.text = _tecnicoFiltroNome!;
    _tecnicosFiltroResultados = [];
    setSheet(() {});
  }

  void _limparFiltroTecnico({StateSetter? setSheet}) {
    _tecnicoFiltroId = null;
    _tecnicoFiltroNome = null;
    _tecnicoFiltroCtrl.clear();
    _tecnicosFiltroResultados = [];
    setSheet?.call(() {});
  }

  // ==========================
  // ORDENACAO / SECOES
  // ==========================

  int _statusRank(Map<String, dynamic> os) {
    final s = _estadoOperacionalKey(os);
    if (s == 'pendente') return 0;
    if (s == 'em_execucao') return 1;
    if (s == 'finalizada') return 2;
    if (s == 'encerrada') return 3;
    return 50;
  }

  DateTime _createdAt(Map<String, dynamic> os) {
    final iso = os['created_at']?.toString();
    return DateTime.tryParse(iso ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _sortOsDefault(List<Map<String, dynamic>> lista) {
    lista.sort((a, b) {
      final ra = _statusRank(a);
      final rb = _statusRank(b);
      if (ra != rb) return ra.compareTo(rb);

      final da = _createdAt(a);
      final db = _createdAt(b);
      return db.compareTo(da);
    });
  }

  String _normalizeStatusKey(String? raw) {
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
        s == 'encerradas' ||
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
    if (s == 'aberto' || s == 'aberta' || s == 'abertas' || s == 'em aberto' || s == 'open') return 'aberta';
    return s.isEmpty ? 'aberta' : s;
  }

  String _normalizeExecucaoKey(String? raw) {
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
    if (s == 'em execucao' || s == 'execucao' || s == 'executando' || s == 'em andamento' || s == 'andamento') return 'em_execucao';
    if (s == 'finalizada' || s == 'finalizado' || s == 'concluida' || s == 'concluido') return 'finalizada';
    return 'pendente';
  }

  String _estadoOperacionalKey(Map<String, dynamic> os) {
    final status = _normalizeStatusKey(os['status']?.toString());
    if (status == 'encerrada') return 'encerrada';
    return _normalizeExecucaoKey(os['execucao']?.toString());
  }

  String _sectionTitle(String key) {
    switch (key) {
      case 'pendente':
        return 'Pendentes';
      case 'em_execucao':
        return 'Em execução';
      case 'finalizada':
        return 'Finalizadas';
      case 'encerrada':
        return 'Encerradas';
      default:
        return 'Outros';
    }
  }

  // ==========================
  // CORES E TAGS
  // ==========================


  // ==========================
  // NORMALIZAÇÃO (empresa/tipo) + OS principal/sub
  // ==========================

  String _empresaCodeFromAny(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return '';
    if (s == '1' || s == '01' || s == '001') return '001';
    if (s == '2' || s == '02' || s == '002') return '002';
    if (s == '3' || s == '03' || s == '003') return '003';
    return s;
  }

  String _tipoKeyFromAny(dynamic v) {
    final raw = (v ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final emp = _empresaCodeFromAny(raw);
    if (emp == '001') return 'servicos';
    if (emp == '002') return 'assistencia';
    if (emp == '003') return 'reforma';

    final t = raw.toLowerCase();
    if (t.contains('serv')) return 'servicos';
    if (t.contains('assist')) return 'assistencia';
    if (t.contains('reform')) return 'reforma';
    return t;
  }

  // Deriva empresa/tipo pelo storage_prefix (mais confiável para mídia),
  // porque ele costuma carregar "OS001/OS002/OS003" ou o diretório (servicos/assistencia/reforma).
  String _empresaCodeFromStoragePrefix(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return '';
    final low = s.toLowerCase();

    // Ex.: "...OS0010002024..." ou ".../os001/..."
    final m = RegExp(r'os0*(001|002|003)', caseSensitive: false).firstMatch(low);
    if (m != null) return (m.group(1) ?? '').trim();

    // Ex.: ".../servicos/...", ".../assistencia/...", ".../reforma/..."
    if (low.contains('servic')) return '001';
    if (low.contains('assist')) return '002';
    if (low.contains('reform')) return '003';

    return '';
  }

  String _tipoKeyFromStoragePrefix(dynamic v) {
    final emp = _empresaCodeFromStoragePrefix(v);
    if (emp.isEmpty) return '';
    return _tipoKeyFromAny(emp);
  }



  String _tipoKeyFromRow(Map<String, dynamic> os) {
    // Fonte de verdade: empresa_code vindo da reconciliação do backend.
    final emp = _empresaCodeFromAny(os['empresa_code']);
    if (emp.isNotEmpty) return _tipoKeyFromAny(emp);

    // Legado: algumas bases antigas ainda persistem o enum em `tipo`.
    final fromTipo = _tipoKeyFromAny(os['tipo']);
    if (fromTipo.isNotEmpty) return fromTipo;

    // Último recurso: storage_prefix. Não pode ter prioridade, porque
    // um prefixo antigo/errado faz a OS aparecer no tipo incorreto.
    final fromPrefix = _tipoKeyFromStoragePrefix(os['storage_prefix']);
    if (fromPrefix.isNotEmpty) return fromPrefix;

    return '';
  }

  bool _isSubFromRow(Map<String, dynamic> os) {
    final v = os['is_sub'];
    if (v is bool) return v;

    final code = (os['os_code'] ?? '').toString().trim();
    if (code.contains('/')) {
      final seq = code.split('/').last.padLeft(3, '0');
      return seq != '000';
    }
    return false;
  }

  String _principalCodeFromRow(Map<String, dynamic> os) {
    final v = (os['os_principal_code'] ?? '').toString().trim();
    if (v.isNotEmpty) return v;

    final code = (os['os_code'] ?? '').toString().trim();
    if (!code.contains('/')) return '${code.padLeft(4, '0')}/000';

    final nro = code.split('/').first.padLeft(4, '0');
    return '$nro/000';
  }

  Color _tipoColor(String? tipoOrKey) {
    final t = _tipoKeyFromAny(tipoOrKey);
    if (t == 'reforma') return const Color(0xFFF37A05);
    if (t == 'assistencia') return const Color(0xFF8C06F8);
    if (t == 'servicos') return const Color(0xFF00BFA5);
    return const Color(0xFF9E9E9E);
  }

  Color _statusColor(String? statusOrKey) {
    final s = (statusOrKey ?? '').toLowerCase();
    if (s == 'pendente') return const Color(0xFFFFA000);
    if (s == 'em_execucao') return const Color(0xFF0D47A1);
    if (s == 'finalizada') return const Color(0xFF00C853);
    if (s == 'encerrada') return const Color(0xFF616161);
    return const Color(0xFF9E9E9E);
  }

  String _statusLabel(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'pendente':
        return 'Pendente';
      case 'em_execucao':
        return 'Em execução';
      case 'finalizada':
        return 'Finalizada';
      case 'encerrada':
      case 'encerrado':
        return 'Encerrada';
      case 'aberta':
      case 'aberto':
        return 'Aberta';
      default:
        return status?.toString() ?? '-';
    }
  }

  String _tipoLabel(String? tipoOrKey) {
    final t = _tipoKeyFromAny(tipoOrKey);
    switch (t) {
      case 'reforma':
        return 'Reforma';
      case 'assistencia':
        return 'Assistência';
      case 'servicos':
        return 'Serviços';
      default:
        final raw = (tipoOrKey ?? '').toString();
        return raw.isEmpty ? '-' : raw;
    }
  }

  Widget _buildStatusTag(String? status) {
    if (status == null || status.isEmpty) return const SizedBox.shrink();

    final color = _statusColor(_normalizeStatusKey(status));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  // ==========================
  // HELPERS
  // ==========================

  String _safeClienteNome(Map<String, dynamic> os) {
    final embedded = os['clientes'];
    if (embedded is Map) {
      return (embedded['razao_social'] ?? '').toString();
    }
    if (embedded is List && embedded.isNotEmpty) {
      final first = embedded.first;
      if (first is Map) return (first['razao_social'] ?? '').toString();
    }
    return '';
  }

  String _fmtCreatedAt(Map<String, dynamic> os) {
    final createdAtIso = os['created_at']?.toString();
    if (createdAtIso == null || createdAtIso.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAtIso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return createdAtIso;
    }
  }

  String _osTitleLabel(Map<String, dynamic> os) {
    final ano = os['ano']?.toString() ?? '';
    final osCode = os['os_code']?.toString() ?? '';
    return 'OS $ano/$osCode';
  }

  // ==========================
  // ITEM DE LISTA (profissional)
  // ==========================

  Widget _buildOsCard(Map<String, dynamic> os) {
    final cs = Theme.of(context).colorScheme;

    final id = os['id'].toString();
    final ano = os['ano']?.toString() ?? '';
    final osCode = os['os_code']?.toString() ?? '';
    final status = _estadoOperacionalKey(os);
    final setor = os['setor']?.toString() ?? '';
    final tecnicoNome = os['tecnico_nome']?.toString() ?? '';
    final cliente = _safeClienteNome(os);
    final createdStr = _fmtCreatedAt(os);
    final coverPath = os['cover_path']?.toString();

    final empresaCode = _empresaCodeFromAny(os['empresa_code']);
    final tipoKey = _tipoKeyFromRow(os);
    final isSub = _isSubFromRow(os);
    final principalCode = _principalCodeFromRow(os);
    final osRoleLabel = isSub ? 'Sub-OS • $principalCode' : 'OS Principal';

    final tipoColor = _tipoColor(tipoKey);

    void openMidias() {
      Navigator.push(context, MaterialPageRoute(builder: (_) => OsMediaPage(osFolderId: id)));
    }

    void openHoras() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OsFolderApontamentosPage(
            osFolderId: id,
            titleLabel: _osTitleLabel(os),
          ),
        ),
      );
    }

    Future<void> copyOs() async {
      await Clipboard.setData(ClipboardData(text: 'OS $ano/$osCode'));
      _snack('Copiado: OS $ano/$osCode');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: openMidias,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Capa (thumb) ou ícone
                _buildCoverOrIcon(coverPath, tipoColor),
                const SizedBox(width: 12),
// Conteúdo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Linha 1: título + status tag
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'OS $ano/$osCode',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusTag(status),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Cliente
                      if (cliente.trim().isNotEmpty)
                        Text(
                          cliente,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),

                      const SizedBox(height: 6),

                      // Meta
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _miniPill(icon: Icons.build, label: _tipoLabel(tipoKey), color: tipoColor),
                          if (empresaCode.isNotEmpty)
                            _miniPill(icon: Icons.business, label: 'Empresa $empresaCode', color: tipoColor),
                          _miniPill(
                            icon: isSub ? Icons.call_split : Icons.star,
                            label: osRoleLabel,
                            color: cs.onSurfaceVariant,
                          ),
                          _miniPill(icon: Icons.apartment, label: setor, color: cs.onSurfaceVariant),
                          if (tecnicoNome.trim().isNotEmpty)
                            _miniPill(icon: Icons.engineering, label: tecnicoNome, color: cs.onSurfaceVariant),
                        ],
                      ),

                      if (createdStr.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Criada em: $createdStr',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Menu de ações
                PopupMenuButton<String>(
                  tooltip: 'Ações',
                  onSelected: (v) {
                    switch (v) {
                      case 'open':
                        openMidias();
                        break;
                      case 'hours':
                        openHoras();
                        break;
                      case 'copy':
                        copyOs();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'open', child: Text('Abrir mídias')),
                    PopupMenuItem(value: 'hours', child: Text('Apontamento de horas')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'copy', child: Text('Copiar OS')),
                  ],
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniPill({required IconData icon, required String label, required Color color}) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  // ==========================
  // SEÇÕES
  // ==========================

  Widget _buildSectionHeader(String key, int count) {
    final color = _statusColor(key);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _sectionTitle(key),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withOpacity(0.45)),
              ),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionedOsList() {
    final ordem = <String>['pendente', 'em_execucao', 'finalizada', 'encerrada', 'outros'];
    final Map<String, List<Map<String, dynamic>>> grupos = {for (final k in ordem) k: <Map<String, dynamic>>[]};

    for (final os in _osFiltradas) {
      final key = _estadoOperacionalKey(os);
      (grupos[key] ?? grupos['outros']!).add(os);
    }

    // Mantém a ordenação por status + data dentro de cada seção
    for (final k in ordem) {
      _sortOsDefault(grupos[k]!);
    }

    final children = <Widget>[];

    for (final k in ordem) {
      final list = grupos[k]!;
      if (list.isEmpty) continue;

      children.add(_buildSectionHeader(k, list.length));
      for (final os in list) {
        children.add(_buildOsCard(os));
      }
    }

    if (children.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('Nenhuma OS encontrada.', style: TextStyle(color: Colors.black54))),
        ],
      );
    }

    children.add(const SizedBox(height: 12));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }

  // ==========================
  // CHIPS DE FILTROS ATIVOS
  // ==========================

  bool get _hasAnyAdvancedFilter =>
      (_setorFiltro?.isNotEmpty ?? false) ||
          (_statusFiltro?.isNotEmpty ?? false) ||
          (_tipoFiltro?.isNotEmpty ?? false) ||
          (_anoFiltroText?.isNotEmpty ?? false) ||
          (_clienteFiltroId?.isNotEmpty ?? false) ||
          (_tecnicoFiltroId?.isNotEmpty ?? false);

  void _clearAllAdvancedFilters() {
    setState(() {
      _statusFiltro = null;
      _tipoFiltro = null;
      _setorFiltro = null;
      _anoFiltroText = null;
      _anoFiltroCtrl.clear();

      _clienteFiltroId = null;
      _clienteFiltroNome = null;
      _clienteFiltroCtrl.clear();
      _clientesFiltroResultados = [];

      _tecnicoFiltroId = null;
      _tecnicoFiltroNome = null;
      _tecnicoFiltroCtrl.clear();
      _tecnicosFiltroResultados = [];
    });
    _carregarOs();
  }

  Widget _buildActiveFilterChips() {
    final chips = <Widget>[];

    if (_hasAnyAdvancedFilter) {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.clear_all, size: 18),
          label: const Text('Limpar filtros'),
          onPressed: _clearAllAdvancedFilters,
        ),
      );
    }

    if (_setorFiltro?.isNotEmpty ?? false) {
      chips.add(
        FilterChip(
          label: Text('Setor: $_setorFiltro'),
          onSelected: (_) {
            setState(() => _setorFiltro = null);
            _carregarOs();
          },
        ),
      );
    }

    if (_statusFiltro?.isNotEmpty ?? false) {
      chips.add(
        FilterChip(
          label: Text('Status: ${_statusLabel(_statusFiltro)}'),
          onSelected: (_) {
            setState(() => _statusFiltro = null);
            _carregarOs();
          },
        ),
      );
    }

    if (_tipoFiltro?.isNotEmpty ?? false) {
      chips.add(
        FilterChip(
          label: Text('Tipo: ${_tipoLabel(_tipoFiltro)}'),
          onSelected: (_) {
            setState(() => _tipoFiltro = null);
            _carregarOs();
          },
        ),
      );
    }

    if (_anoFiltroText?.isNotEmpty ?? false) {
      chips.add(
        FilterChip(
          label: Text('Ano: $_anoFiltroText'),
          onSelected: (_) {
            setState(() {
              _anoFiltroText = null;
              _anoFiltroCtrl.clear();
            });
            _carregarOs();
          },
        ),
      );
    }

    if (_clienteFiltroNome?.isNotEmpty ?? false) {
      chips.add(
        FilterChip(
          label: Text('Cliente: $_clienteFiltroNome'),
          onSelected: (_) {
            setState(() => _limparFiltroCliente());
            _carregarOs();
          },
        ),
      );
    }

    if (_tecnicoFiltroNome?.isNotEmpty ?? false) {
      chips.add(
        FilterChip(
          label: Text('Técnico: $_tecnicoFiltroNome'),
          onSelected: (_) {
            setState(() => _limparFiltroTecnico());
            _carregarOs();
          },
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips
              .map((c) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: c,
          ))
              .toList(),
        ),
      ),
    );
  }

  // ==========================
  // FILTRO AVANÇADO (BOTTOM SHEET)
  // ==========================

  void _abrirFiltroAvancado() {
    // preenche controls com o estado atual (pra não abrir “em branco”)
    _anoFiltroCtrl.text = _anoFiltroText ?? '';
    _clienteFiltroCtrl.text = _clienteFiltroNome ?? '';
    _tecnicoFiltroCtrl.text = _tecnicoFiltroNome ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 8,
            ),
            child: StatefulBuilder(
              builder: (context, setSheet) {
                return SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filtros avançados',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _statusFiltro = null;
                                _tipoFiltro = null;
                                _setorFiltro = null;
                                _anoFiltroText = null;
                                _anoFiltroCtrl.clear();
                                _clienteFiltroId = null;
                                _clienteFiltroNome = null;
                                _clienteFiltroCtrl.clear();
                                _clientesFiltroResultados = [];
                                _tecnicoFiltroId = null;
                                _tecnicoFiltroNome = null;
                                _tecnicoFiltroCtrl.clear();
                                _tecnicosFiltroResultados = [];
                              });
                              setSheet(() {});
                            },
                            child: const Text('Limpar tudo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Setor (somente dentro do que o usuário pode ver)
                      if (_visibleSetores.length > 1) ...[
                        const Text('Setor', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Todos'),
                              selected: _setorFiltro == null,
                              onSelected: (_) {
                                setState(() => _setorFiltro = null);
                                setSheet(() {});
                              },
                            ),
                            ..._visibleSetores.map((setorKey) {
                              return ChoiceChip(
                                label: Text(setorLabel(setorKey)),
                                selected: _setorFiltro == setorKey,
                                onSelected: (_) {
                                  setState(() => _setorFiltro = setorKey);
                                  setSheet(() {});
                                },
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Status
                      const Text('Estado da OS', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Todos'),
                            selected: _statusFiltro == null,
                            onSelected: (_) {
                              setState(() => _statusFiltro = null);
                              setSheet(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Pendente'),
                            selected: _statusFiltro == 'pendente',
                            onSelected: (_) {
                              setState(() => _statusFiltro = 'pendente');
                              setSheet(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Em execução'),
                            selected: _statusFiltro == 'em_execucao',
                            onSelected: (_) {
                              setState(() => _statusFiltro = 'em_execucao');
                              setSheet(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Finalizada'),
                            selected: _statusFiltro == 'finalizada',
                            onSelected: (_) {
                              setState(() => _statusFiltro = 'finalizada');
                              setSheet(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Encerrada'),
                            selected: _statusFiltro == 'encerrada',
                            onSelected: (_) {
                              setState(() => _statusFiltro = 'encerrada');
                              setSheet(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Tipo de OS
                      const Text('Tipo de OS', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Todos'),
                            selected: _tipoFiltro == null,
                            onSelected: (_) {
                              setState(() => _tipoFiltro = null);
                              setSheet(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Reforma'),
                            selected: _tipoFiltro == 'reforma',
                            onSelected: (_) {
                              setState(() => _tipoFiltro = 'reforma');
                              setSheet(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Assistência'),
                            selected: _tipoFiltro == 'assistencia',
                            onSelected: (_) {
                              setState(() => _tipoFiltro = 'assistencia');
                              setSheet(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('Serviços'),
                            selected: _tipoFiltro == 'servicos',
                            onSelected: (_) {
                              setState(() => _tipoFiltro = 'servicos');
                              setSheet(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Ano
                      const Text('Ano (digite o ano desejado)', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _anoFiltroCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Ex: 2025',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          _anoFiltroText = v.trim();
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 16),

                      // Cliente
                      const Text('Cliente', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _clienteFiltroCtrl,
                        decoration: InputDecoration(
                          hintText: 'Buscar cliente',
                          prefixIcon: const Icon(Icons.business),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_clienteFiltroId != null)
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Limpar cliente',
                                  onPressed: () => _limparFiltroCliente(setSheet: setSheet),
                                ),
                              IconButton(
                                icon: const Icon(Icons.search),
                                tooltip: 'Buscar',
                                onPressed: () => _buscarClientesFiltro(_clienteFiltroCtrl.text, setSheet),
                              ),
                            ],
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          _clienteFiltroId = null;
                          _clienteFiltroNome = null;
                          _onClienteFiltroChanged(v, setSheet);
                        },
                      ),
                      if (_loadingClientesFiltro) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                      if (_clientesFiltroResultados.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _clientesFiltroResultados.length,
                            itemBuilder: (context, index) {
                              final c = _clientesFiltroResultados[index];
                              final nome = c['razao_social']?.toString() ?? 'Sem nome';
                              final codigo = c['codigo']?.toString();
                              return ListTile(
                                dense: true,
                                title: Text(nome),
                                subtitle: codigo != null ? Text('Código: $codigo') : null,
                                onTap: () => _selecionarClienteFiltro(c, setSheet),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Técnico responsável
                      const Text('Técnico responsável', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _tecnicoFiltroCtrl,
                        decoration: InputDecoration(
                          hintText: 'Buscar técnico',
                          prefixIcon: const Icon(Icons.engineering),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_tecnicoFiltroId != null)
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Limpar técnico',
                                  onPressed: () => _limparFiltroTecnico(setSheet: setSheet),
                                ),
                              IconButton(
                                icon: const Icon(Icons.search),
                                tooltip: 'Buscar',
                                onPressed: () => _buscarTecnicosFiltro(_tecnicoFiltroCtrl.text, setSheet),
                              ),
                            ],
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          _tecnicoFiltroId = null;
                          _tecnicoFiltroNome = null;
                          _onTecnicoFiltroChanged(v, setSheet);
                        },
                      ),
                      if (_loadingTecnicosFiltro) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                      ],
                      if (_tecnicosFiltroResultados.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _tecnicosFiltroResultados.length,
                            itemBuilder: (context, index) {
                              final t = _tecnicosFiltroResultados[index];
                              final nome = t['nome']?.toString() ?? 'Sem nome';
                              final codigo = t['codigo']?.toString();
                              final setor = t['setor']?.toString();
                              return ListTile(
                                dense: true,
                                title: Text(nome),
                                subtitle: Text([
                                  if (codigo != null) 'Cód: $codigo',
                                  if (setor != null) 'Setor: $setor',
                                ].join(' · ')),
                                onTap: () => _selecionarTecnicoFiltro(t, setSheet),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.close),
                              label: const Text('Fechar'),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.check),
                              label: const Text('Aplicar filtros'),
                              onPressed: () async {
                                Navigator.pop(context);
                                await _carregarOs();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ==========================
  // BUILD
  // ==========================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF3),
      appBar: AppBar(
        backgroundColor: const Color(0xFF333333),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text('Explorar OS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        actions: [
          // 🔹 Backup geral
          IconButton(
            icon: _isBackingUp
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : const Icon(Icons.download, color: Colors.white),
            tooltip: 'Backup de todas as pastas',
            onPressed: (_isLoading || _isBackingUp)
                ? null
                : () async {
              setState(() => _isBackingUp = true);
              try {
                await OsBackup.backupAllOs(context);
                if (!mounted) return;
                _snack('Backup concluído.');
                await _carregarOs();
              } catch (e) {
                debugPrint('Erro no backup geral: $e');
                _snack('Erro no backup: $e');
              } finally {
                if (mounted) setState(() => _isBackingUp = false);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            tooltip: 'Filtros',
            onPressed: _abrirFiltroAvancado,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Recarregar',
            onPressed: _reloadPage,
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de busca texto livre
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por cliente, ano, código, tipo ou técnico',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (!_hasSearchText)
                    ? null
                    : IconButton(
                  tooltip: 'Limpar',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _searchController.clear();
                    _aplicarFiltroTextoLivre('', setStateNow: true);
                    FocusScope.of(context).unfocus();
                  },
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onSearchChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
          ),

          // Chips de filtros ativos
          _buildActiveFilterChips(),

          if (_isLoading) const LinearProgressIndicator(minHeight: 2),

          Expanded(
            child: RefreshIndicator(
              color: cs.primary,
              onRefresh: _reloadPage,
              child: _buildSectionedOsList(),
            ),
          ),
        ],
      ),
    );
  }
}
