// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/os/new_os_folder_page.dart
//
// Regras (SMI_FILES):
// - tipo (servicos/assistencia/reforma) é derivado de public.os.empresa: 001/002/003
// - setor é derivado de public.os.departamento (JSON), convertido para setor_enum via função SQL setor_from_departamento(dep)
// - usuário não escolhe mais tipo/setor nesta tela (fica automático pelo servidor)
// - o código da OS é normalizado (ex.: 19/0 -> 0019/000) para evitar duplicidade

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sml_files/core/supabase/supabase_manager.dart';

class NewOsFolderPage extends StatefulWidget {
  const NewOsFolderPage({
    super.key,
    required this.tecnicoId,
    required this.tecnicoNome,
    required this.setor,
  });

  final int tecnicoId;
  final String tecnicoNome;
  final String setor;

  @override
  State<NewOsFolderPage> createState() => _NewOsFolderPageState();
}

class _NewOsFolderPageState extends State<NewOsFolderPage> {
  // UI
  static const _bgDark = Color(0xFF4F5454);
  static const _cardBg = Color(0xFFF5FAF3);
  static const _green = Color(0xFF00C853);

  final _formKey = GlobalKey<FormState>();

  // Focus
  final _clienteFocus = FocusNode();
  final _tecFocus = FocusNode();
  final _anoFocus = FocusNode();
  final _osFocus = FocusNode();

  // Cliente
  final TextEditingController _clienteController = TextEditingController();
  String? _clienteIdSelecionado;
  bool _isCarregandoClientes = false;
  List<Map<String, dynamic>> _clientesEncontrados = [];
  Timer? _debounceCliente;
  int _clienteReqToken = 0;

  // Técnico responsável
  final TextEditingController _tecnicoRespController = TextEditingController();
  String? _tecnicoRespIdSelecionado;
  bool _isCarregandoTecnicos = false;
  List<Map<String, dynamic>> _tecnicosEncontrados = [];
  Timer? _debounceTecnico;
  int _tecnicoReqToken = 0;

  // Dados da OS
  final TextEditingController _anoController = TextEditingController();
  final TextEditingController _codigoOsController = TextEditingController();

  // Resolução automática (servidor)
  bool _isCarregandoOs = false;
  String? _osResolvedKey; // "ANO|OS_CODE_NORMALIZADO"
  Map<String, dynamic>? _osServerRow;
  String? _empresaCode; // 001/002/003
  String? _departamentoRaw; // texto vindo do JSON (public.os.departamento)
  String? _departamentoSlug; // sugestão (para enum)
  String? _tipoAuto; // servicos/assistencia/reforma
  String? _setorAuto; // setor_enum
  String? _osServerError;

  bool _criando = false;

  @override
  void initState() {
    super.initState();
    _anoController.text = DateTime.now().year.toString();

    // Técnico responsável: começa vazio (obrigatório escolher)
    _tecnicoRespIdSelecionado = null;
    _tecnicoRespController.clear();

    // Sugestões iniciais
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buscarClientes('');
      _buscarTecnicos('');
    });
  }

  @override
  void dispose() {
    _debounceCliente?.cancel();
    _debounceTecnico?.cancel();

    _clienteFocus.dispose();
    _tecFocus.dispose();
    _anoFocus.dispose();
    _osFocus.dispose();

    _clienteController.dispose();
    _tecnicoRespController.dispose();
    _anoController.dispose();
    _codigoOsController.dispose();
    super.dispose();
  }

  void _unfocus() => FocusScope.of(context).unfocus();

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ================================
  // Helpers: OS server
  // ================================

  String? _tipoFromEmpresa(String empresa) {
    final e = empresa.trim();
    switch (e) {
      case '001':
        return 'servicos';
      case '002':
        return 'assistencia';
      case '003':
        return 'reforma';
      default:
        return null;
    }
  }

  String _displayTipo(String? tipo) {
    switch ((tipo ?? '').trim()) {
      case 'servicos':
        return 'Serviços';
      case 'assistencia':
        return 'Assistência';
      case 'reforma':
        return 'Reforma';
      default:
        return '—';
    }
  }

  String _slugify(String input) {
    var s = input.trim().toLowerCase();

    // remoção simples de acentos mais comuns (ok para PT-BR)
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }

    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    return s;
  }

  List<String>? _parseOsCode(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final parts = s.split('/');
    if (parts.length < 2) return null;

    String onlyDigits(String x) => x.replaceAll(RegExp(r'\D'), '');
    final nroD = onlyDigits(parts[0]);
    final seqD = onlyDigits(parts[1]);

    if (nroD.isEmpty || seqD.isEmpty) return null;

    final nroPad = nroD.padLeft(4, '0');
    final seqPad = seqD.padLeft(3, '0');
    return [nroPad, seqPad];
  }

  String _normalizedOsCodeOrEmpty() {
    final parsed = _parseOsCode(_codigoOsController.text);
    if (parsed == null) return _codigoOsController.text.trim();
    return '${parsed[0]}/${parsed[1]}';
  }

  String _currentOsKey() => '${_anoController.text.trim()}|${_normalizedOsCodeOrEmpty()}';

  Future<void> _buscarOsServidor({bool silent = false}) async {
    final ano = _anoController.text.trim();
    final parsed = _parseOsCode(_codigoOsController.text);
    if (ano.isEmpty || parsed == null) {
      setState(() {
        _osServerRow = null;
        _empresaCode = null;
        _departamentoRaw = null;
        _departamentoSlug = null;
        _tipoAuto = null;
        _setorAuto = null;
        _osResolvedKey = null;
        _osServerError = 'Informe Ano e Código da OS (ex.: 0019/000).';
      });
      if (!silent) _snack('Informe Ano e Código da OS (ex.: 0019/000).');
      return;
    }

    final nroPad = parsed[0];
    final seqPad = parsed[1];
    final osCodeNorm = '$nroPad/$seqPad';

    // padroniza no input para evitar duplicidade
    if (_codigoOsController.text.trim() != osCodeNorm) {
      _codigoOsController.text = osCodeNorm;
    }

    setState(() {
      _isCarregandoOs = true;
      _osServerError = null;
      _osServerRow = null;
      _empresaCode = null;
      _departamentoRaw = null;
      _departamentoSlug = null;
      _tipoAuto = null;
      _setorAuto = null;
      _osResolvedKey = null;
    });

    try {
      // 1) Busca a OS oficial pela RPC do banco.
      // Não consulta public.os diretamente porque pode existir mesma numeração
      // em empresas diferentes. A RPC aplica a regra oficial do Supabase.
      dynamic row;
      try {
        final rpc = await SupabaseManager.client.rpc(
          'app_find_os_for_folder',
          params: {
            'p_anomovto': int.tryParse(ano),
            'p_nroos': nroPad,
            'p_seqos': seqPad,
          },
        );
        if (rpc is List && rpc.isNotEmpty) {
          row = rpc.first;
        } else if (rpc is Map) {
          row = rpc;
        }
      } catch (_) {
        row = null;
      }

      // fallback legado: somente se a RPC não existir em banco antigo
      if (row == null) {
        row = await SupabaseManager.client
            .from('os')
            .select('id, empresa, filial, anomovto, nroos, seqos, departamento, cliente, deleted, status_arquivo')
            .eq('anomovto', ano)
            .eq('nroos', nroPad)
            .eq('seqos', seqPad)
            .maybeSingle();
      }

      if (!mounted) return;

      if (row == null) {
        setState(() {
          _osServerError = 'OS não encontrada no servidor para $ano / $nroPad/$seqPad.';
        });
        if (!silent) _snack('OS não encontrada no servidor.');
        return;
      }

      final map = Map<String, dynamic>.from(row as Map);
      final emp = (map['empresa'] ?? '').toString().trim();
      final dep = (map['departamento'] ?? '').toString().trim();

      final tipo = _tipoFromEmpresa(emp);
      if (tipo == null) {
        setState(() {
          _osServerRow = map;
          _empresaCode = emp;
          _departamentoRaw = dep.isEmpty ? null : dep;
          _departamentoSlug = dep.isEmpty ? null : _slugify(dep);
          _tipoAuto = null;
          _setorAuto = null;
          _osServerError = 'Código empresa inválido para tipo (empresa=$emp). Esperado: 001/002/003.';
        });
        if (!silent) _snack('Empresa inválida (esperado 001/002/003).');
        return;
      }

      if (dep.isEmpty) {
        setState(() {
          _osServerRow = map;
          _empresaCode = emp;
          _departamentoRaw = null;
          _departamentoSlug = null;
          _tipoAuto = tipo;
          _setorAuto = null;
          _osServerError = 'A OS encontrada não possui "departamento" no servidor.';
        });
        if (!silent) _snack('A OS não possui "departamento" no servidor.');
        return;
      }

      final depSlug = _slugify(dep);

      // 2) Converte departamento -> setor_enum via função SQL
      dynamic setorRpc;
      try {
        setorRpc = await SupabaseManager.client.rpc('setor_from_departamento', params: {'dep': dep});
      } catch (_) {
        try {
          setorRpc = await SupabaseManager.client.rpc('setor_from_departamento', params: {'departamento_in': dep});
        } catch (_) {
          setorRpc = null;
        }
      }

      final setorAuto = (setorRpc == null) ? '' : setorRpc.toString().trim();
      if (setorAuto.isEmpty || setorAuto == 'null') {
        setState(() {
          _osServerRow = map;
          _empresaCode = emp;
          _departamentoRaw = dep;
          _departamentoSlug = depSlug;
          _tipoAuto = tipo;
          _setorAuto = null;
          _osServerError =
          'Departamento "$dep" ainda não está cadastrado no setor_enum.\n'
              'Slug sugerido: "$depSlug".';
        });
        if (!silent) _snack('Departamento não cadastrado no setor_enum.');
        return;
      }

      setState(() {
        _osServerRow = map;
        _empresaCode = emp;
        _departamentoRaw = dep;
        _departamentoSlug = depSlug;
        _tipoAuto = tipo;
        _setorAuto = setorAuto;
        _osServerError = null;
        _osResolvedKey = _currentOsKey();
      });

      if (!silent) _snack('Tipo/Setor carregados do servidor.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _osServerError = 'Erro ao buscar OS no servidor: $e';
      });
      if (!silent) _snack('Erro ao buscar OS no servidor.');
    } finally {
      if (mounted) setState(() => _isCarregandoOs = false);
    }
  }

  // ================================
  // BUSCA CLIENTES (DEBOUNCE)
  // ================================

  void _onClienteChanged(String value) {
    if (_clienteIdSelecionado != null) {
      setState(() => _clienteIdSelecionado = null);
    }
    _debounceCliente?.cancel();
    _debounceCliente = Timer(const Duration(milliseconds: 280), () {
      _buscarClientes(value);
    });
  }

  Future<void> _buscarClientes(String query) async {
    final token = ++_clienteReqToken;
    if (mounted) setState(() => _isCarregandoClientes = true);

    try {
      final q = query.trim();
      dynamic resp;
      if (q.isEmpty) {
        resp = await SupabaseManager.client
            .from('clientes')
            .select('id, razao_social, codigo')
            .order('razao_social')
            .limit(40);
      } else {
        resp = await SupabaseManager.client
            .from('clientes')
            .select('id, razao_social, codigo')
            .ilike('razao_social', '%$q%')
            .order('razao_social')
            .limit(25);
      }

      if (!mounted || token != _clienteReqToken) return;

      setState(() {
        _clientesEncontrados = (resp as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) _snack('Erro ao buscar clientes: $e');
    } finally {
      if (mounted && token == _clienteReqToken) {
        setState(() => _isCarregandoClientes = false);
      }
    }
  }

  void _selecionarCliente(Map<String, dynamic> cliente) {
    setState(() {
      _clienteIdSelecionado = cliente['id']?.toString();
      _clienteController.text = cliente['razao_social']?.toString() ?? '';
      _clientesEncontrados = [];
    });
    _tecFocus.requestFocus();
  }

  void _limparCliente() {
    setState(() {
      _clienteIdSelecionado = null;
      _clienteController.clear();
      _clientesEncontrados = [];
    });
    _clienteFocus.requestFocus();
    _buscarClientes('');
  }

  // ================================
  // BUSCA TÉCNICOS (DEBOUNCE)
  // ================================

  void _onTecnicoChanged(String value) {
    if (_tecnicoRespIdSelecionado != null) {
      setState(() => _tecnicoRespIdSelecionado = null);
    }
    _debounceTecnico?.cancel();
    _debounceTecnico = Timer(const Duration(milliseconds: 280), () {
      _buscarTecnicos(value);
    });
  }

  Future<void> _buscarTecnicos(String query) async {
    final token = ++_tecnicoReqToken;
    if (mounted) setState(() => _isCarregandoTecnicos = true);

    try {
      final q = query.trim();

      dynamic resp;
      if (q.isEmpty) {
        resp = await SupabaseManager.client
            .from('tecnicos')
            .select('id, nome, codigo, setor')
            .order('nome')
            .limit(35);
      } else {
        resp = await SupabaseManager.client
            .from('tecnicos')
            .select('id, nome, codigo, setor')
            .ilike('nome', '%$q%')
            .order('nome')
            .limit(25);
      }

      if (!mounted || token != _tecnicoReqToken) return;

      setState(() {
        _tecnicosEncontrados = (resp as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) _snack('Erro ao buscar técnicos: $e');
    } finally {
      if (mounted && token == _tecnicoReqToken) {
        setState(() => _isCarregandoTecnicos = false);
      }
    }
  }

  void _selecionarTecnico(Map<String, dynamic> tecnico) {
    setState(() {
      _tecnicoRespIdSelecionado = tecnico['id']?.toString();
      _tecnicoRespController.text = tecnico['nome']?.toString() ?? '';
      _tecnicosEncontrados = [];
    });
    _anoFocus.requestFocus();
  }

  void _limparTecnico() {
    setState(() {
      _tecnicoRespIdSelecionado = null;
      _tecnicoRespController.clear();
      _tecnicosEncontrados = [];
    });
    _tecFocus.requestFocus();
    _buscarTecnicos('');
  }

  // ================================
  // CRIAR OS (os_folders)
  // ================================

  Future<void> _criarOs() async {
    if (_criando) return;

    _unfocus();

    if (!_formKey.currentState!.validate()) return;

    if (_clienteIdSelecionado == null) {
      _snack('Selecione um cliente para continuar.');
      return;
    }

    if (_tecnicoRespIdSelecionado == null || _tecnicoRespController.text.trim().isEmpty) {
      _snack('Selecione o técnico responsável.');
      return;
    }

    final anoTxt = _anoController.text.trim();
    final anoInt = int.tryParse(anoTxt);
    if (anoInt == null || anoInt < 2000 || anoInt > 2100) {
      _snack('Ano inválido.');
      return;
    }

    final parsed = _parseOsCode(_codigoOsController.text);
    if (parsed == null) {
      _snack('Informe o código da OS no formato 0019/000.');
      return;
    }

    final osCodeNorm = '${parsed[0]}/${parsed[1]}';
    if (_codigoOsController.text.trim() != osCodeNorm) {
      _codigoOsController.text = osCodeNorm;
    }

    // garante que tipo/setor foram resolvidos
    if (_osResolvedKey != _currentOsKey() || _tipoAuto == null || _setorAuto == null) {
      await _buscarOsServidor(silent: true);
    }

    if (_tipoAuto == null || _setorAuto == null) {
      _snack(_osServerError ?? 'Não foi possível determinar Tipo/Setor pelo servidor.');
      return;
    }

    setState(() => _criando = true);

    try {
      final rpcResult = await SupabaseManager.client.rpc(
        'app_open_os_folder',
        params: {
          'p_anomovto': anoInt,
          'p_nroos': parsed[0],
          'p_seqos': parsed[1],
          'p_client_id': int.tryParse(_clienteIdSelecionado!),
          'p_tecnico_id': int.tryParse(_tecnicoRespIdSelecionado!),
          'p_tecnico_nome': _tecnicoRespController.text.trim(),
        },
      );

      Map<String, dynamic> folder;
      if (rpcResult is List && rpcResult.isNotEmpty) {
        folder = Map<String, dynamic>.from(rpcResult.first as Map);
      } else if (rpcResult is Map) {
        folder = Map<String, dynamic>.from(rpcResult);
      } else {
        throw Exception('RPC app_open_os_folder não retornou a pasta criada.');
      }

      final newOsId = folder['id'].toString();

      if (!mounted) return;

      _snack('Pasta de OS criada com sucesso!');
      Navigator.pop(context, newOsId);
    } catch (e) {
      if (!mounted) return;
      _snack('Erro ao abrir/criar pasta da OS: $e');
    } finally {
      if (mounted) setState(() => _criando = false);
    }
  }

  // ================================
  // UI HELPERS
  // ================================

  Widget _suggestionsBox({
    required List<Map<String, dynamic>> items,
    required bool loading,
    required Widget Function(Map<String, dynamic>) tileBuilder,
  }) {
    if (loading) {
      return Column(
        children: const [
          SizedBox(height: 8),
          LinearProgressIndicator(minHeight: 3),
        ],
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => tileBuilder(items[index]),
          ),
        ),
      ),
    );
  }

  Widget _serverResolveCard(ThemeData theme) {
    final ok = _osResolvedKey == _currentOsKey() &&
        _tipoAuto != null &&
        _setorAuto != null &&
        _osServerError == null;

    final titleStyle = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: Colors.black54);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ok ? Colors.green.withOpacity(0.35) : Colors.black12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.verified_rounded : Icons.cloud_sync, color: ok ? Colors.green : Colors.black54),
              const SizedBox(width: 8),
              Expanded(child: Text('Tipo/Setor automáticos (servidor)', style: titleStyle)),
              TextButton.icon(
                onPressed: (_criando || _isCarregandoOs) ? null : () => _buscarOsServidor(),
                icon: _isCarregandoOs
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Buscar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_osServerError != null) ...[
            Text(_osServerError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
            if (_departamentoRaw != null && _departamentoSlug != null) ...[
              const SizedBox(height: 6),
              Text('Departamento: $_departamentoRaw', style: labelStyle),
              Text('Slug sugerido: $_departamentoSlug', style: labelStyle),
            ],
          ] else if (_osServerRow == null) ...[
            Text('Clique em Buscar para puxar Tipo/Setor pelo Ano + Código da OS.', style: labelStyle),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tipo (empresa=$_empresaCode)', style: labelStyle),
                      const SizedBox(height: 2),
                      Text(_displayTipo(_tipoAuto), style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Setor (dep=$_departamentoRaw)', style: labelStyle),
                      const SizedBox(height: 2),
                      Text(_setorAuto ?? '—', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if ((_osServerRow?['cliente'] ?? '').toString().trim().isNotEmpty)
              Text('Cliente (servidor): ${_osServerRow!['cliente']}', style: labelStyle),
          ],
        ],
      ),
    );
  }

  // ================================
  // BUILD
  // ================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _cardBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: Colors.black87,
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text('Nova pasta de OS', style: TextStyle(color: Colors.black87)),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _unfocus,
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final kb = MediaQuery.of(ctx).viewInsets.bottom;
              return SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + kb),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 650),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // HEADER
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                                    child: const Icon(Icons.folder_open, color: Colors.white, size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Criar nova OS',
                                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Cliente + Técnico + OS (Ano/Código). Tipo/Setor são automáticos pelo servidor.',
                                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            Chip(
                                              avatar: const Icon(Icons.person, size: 18, color: Colors.white),
                                              label: Text(widget.tecnicoNome, style: const TextStyle(color: Colors.white)),
                                              backgroundColor: _green,
                                            ),
                                            Chip(
                                              avatar: const Icon(Icons.badge, size: 18, color: Colors.white),
                                              label: Text('Setor usuário: ${widget.setor}', style: const TextStyle(color: Colors.white)),
                                              backgroundColor: _green,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 16),

                              // ========== CLIENTE ==========
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Cliente',
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  if (_clienteIdSelecionado != null)
                                    Chip(
                                      avatar: const Icon(Icons.check_circle, size: 18, color: Colors.white),
                                      label: const Text('Selecionado', style: TextStyle(color: Colors.white)),
                                      backgroundColor: _green,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              TextFormField(
                                controller: _clienteController,
                                focusNode: _clienteFocus,
                                enabled: !_criando,
                                decoration: InputDecoration(
                                  hintText: 'Buscar cliente',
                                  prefixIcon: const Icon(Icons.business),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_clienteController.text.isNotEmpty)
                                        IconButton(
                                          tooltip: 'Limpar',
                                          onPressed: _criando ? null : _limparCliente,
                                          icon: const Icon(Icons.clear),
                                        ),
                                      IconButton(
                                        tooltip: 'Buscar',
                                        onPressed: _criando ? null : () => _buscarClientes(_clienteController.text),
                                        icon: const Icon(Icons.search),
                                      ),
                                    ],
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onChanged: _onClienteChanged,
                                validator: (v) {
                                  if ((v ?? '').trim().isEmpty || _clienteIdSelecionado == null) {
                                    return 'Selecione um cliente';
                                  }
                                  return null;
                                },
                              ),

                              _suggestionsBox(
                                items: _clientesEncontrados,
                                loading: _isCarregandoClientes,
                                tileBuilder: (c) {
                                  final nome = c['razao_social']?.toString() ?? 'Sem nome';
                                  final codigo = c['codigo']?.toString();
                                  return ListTile(
                                    dense: true,
                                    title: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: (codigo == null || codigo.isEmpty) ? null : Text('Cód: $codigo'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: _criando ? null : () => _selecionarCliente(c),
                                  );
                                },
                              ),

                              const SizedBox(height: 24),

                              // ========== TÉCNICO RESPONSÁVEL ==========
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Técnico responsável',
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  if (_tecnicoRespIdSelecionado != null)
                                    Chip(
                                      avatar: const Icon(Icons.check_circle, size: 18, color: Colors.white),
                                      label: const Text('Selecionado', style: TextStyle(color: Colors.white)),
                                      backgroundColor: _green,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              TextFormField(
                                controller: _tecnicoRespController,
                                focusNode: _tecFocus,
                                enabled: !_criando,
                                decoration: InputDecoration(
                                  hintText: 'Buscar técnico responsável',
                                  prefixIcon: const Icon(Icons.engineering),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_tecnicoRespController.text.isNotEmpty)
                                        IconButton(
                                          tooltip: 'Limpar',
                                          onPressed: _criando ? null : _limparTecnico,
                                          icon: const Icon(Icons.clear),
                                        ),
                                      IconButton(
                                        tooltip: 'Buscar',
                                        onPressed: _criando ? null : () => _buscarTecnicos(_tecnicoRespController.text),
                                        icon: const Icon(Icons.search),
                                      ),
                                    ],
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onChanged: _onTecnicoChanged,
                                validator: (v) {
                                  if ((v ?? '').trim().isEmpty || _tecnicoRespIdSelecionado == null) {
                                    return 'Selecione o técnico responsável';
                                  }
                                  return null;
                                },
                              ),

                              _suggestionsBox(
                                items: _tecnicosEncontrados,
                                loading: _isCarregandoTecnicos,
                                tileBuilder: (t) {
                                  final nome = t['nome']?.toString() ?? 'Sem nome';
                                  final codigo = t['codigo']?.toString();
                                  final setor = t['setor']?.toString();
                                  final sub = [
                                    if (codigo != null) 'Cód: $codigo',
                                    if (setor != null) 'Setor: $setor',
                                  ].join(' · ');

                                  return ListTile(
                                    dense: true,
                                    title: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: sub.isEmpty ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: _criando ? null : () => _selecionarTecnico(t),
                                  );
                                },
                              ),

                              const SizedBox(height: 24),

                              // ========== DADOS DA OS ==========
                              Text(
                                'Dados da OS',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),

                              _serverResolveCard(theme),
                              const SizedBox(height: 12),

                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _anoController,
                                      focusNode: _anoFocus,
                                      enabled: !_criando,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(4),
                                      ],
                                      textInputAction: TextInputAction.next,
                                      onFieldSubmitted: (_) => _osFocus.requestFocus(),
                                      decoration: InputDecoration(
                                        labelText: 'Ano',
                                        prefixIcon: const Icon(Icons.calendar_today),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onChanged: (_) {
                                        if (_osResolvedKey != null) setState(() => _osResolvedKey = null);
                                      },
                                      validator: (v) {
                                        final s = (v ?? '').trim();
                                        if (s.isEmpty) return 'Informe o ano';
                                        final n = int.tryParse(s);
                                        if (n == null || n < 2000 || n > 2100) return 'Ano inválido';
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: _codigoOsController,
                                      focusNode: _osFocus,
                                      enabled: !_criando,
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) async {
                                        await _buscarOsServidor(silent: true);
                                      },
                                      decoration: InputDecoration(
                                        labelText: 'Código da OS',
                                        hintText: 'Ex: 0019/000',
                                        prefixIcon: const Icon(Icons.confirmation_number),
                                        suffixIcon: IconButton(
                                          tooltip: 'Buscar no servidor',
                                          onPressed: (_criando || _isCarregandoOs) ? null : () => _buscarOsServidor(),
                                          icon: const Icon(Icons.cloud_download),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onChanged: (_) {
                                        if (_osResolvedKey != null) setState(() => _osResolvedKey = null);
                                      },
                                      validator: (v) {
                                        final s = (v ?? '').trim();
                                        if (s.isEmpty) return 'Informe o código';
                                        if (_parseOsCode(s) == null) return 'Formato inválido (ex.: 0019/000)';
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                    elevation: 0,
                                  ),
                                  icon: _criando
                                      ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                      : const Icon(Icons.check_circle),
                                  label: Text(
                                    _criando ? 'Criando...' : 'Criar OS',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                  ),
                                  onPressed: _criando ? null : _criarOs,
                                ),
                              ),

                              const SizedBox(height: 10),

                              Text(
                                'Ao criar, você será direcionado para adicionar mídias e preencher informações.',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
