// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// os_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'os_models.dart';
import 'os_repository.dart';

class OsListPage extends StatefulWidget {
  const OsListPage({super.key});

  @override
  State<OsListPage> createState() => _OsListPageState();
}

class _OsListPageState extends State<OsListPage> {
  final _repo = OsRepository();

  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _hasSearchText = false;

  bool _includeDeleted = true;
  bool _loading = true;
  String? _error;
  List<OsModel> _items = const [];

  @override
  void initState() {
    super.initState();

    _hasSearchText = _searchCtrl.text.trim().isNotEmpty;
    _searchCtrl.addListener(_syncSearchSuffixUi);

    _load();
  }

  void _syncSearchSuffixUi() {
    final has = _searchCtrl.text.trim().isNotEmpty;
    if (has != _hasSearchText) {
      if (!mounted) return;
      setState(() => _hasSearchText = has);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_syncSearchSuffixUi);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _repo.listarOs(
        search: _searchCtrl.text,
        incluirExcluidas: _includeDeleted,
      );
      if (mounted) setState(() => _items = res);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ordens de Serviço'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    onSubmitted: (_) {
                      FocusScope.of(context).unfocus();
                      _load();
                    },
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Buscar por cliente, OS ou arquivo...',
                      suffixIcon: !_hasSearchText
                          ? null
                          : IconButton(
                        tooltip: 'Limpar',
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    _load();
                  },
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SwitchListTile.adaptive(
              value: _includeDeleted,
              onChanged: (v) {
                setState(() => _includeDeleted = v);
                _load();
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar OS excluídas'),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: TextStyle(color: cs.error),
                    ),
                  ),
                ],
              )
                  : _items.isEmpty
                  ? ListView(
                children: const [
                  SizedBox(height: 60),
                  Center(child: Text('Nenhuma OS encontrada.')),
                ],
              )
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final os = _items[i];
                  return _OsCard(
                    os: os,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OsDetailPage(osId: os.id),
                        ),
                      );
                      _load();
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OsCard extends StatelessWidget {
  final OsModel os;
  final VoidCallback onTap;

  const _OsCard({required this.os, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('dd/MM/yyyy');

    final titulo = 'OS ${os.nroos}/${os.seqos} — ${os.cliente ?? '-'}';
    final subtitulo = [
      if (os.departamento != null && os.departamento!.trim().isNotEmpty) os.departamento!,
      if (os.dataAbertura != null) df.format(os.dataAbertura!),
      if (os.arquivoNome != null && os.arquivoNome!.trim().isNotEmpty) os.arquivoNome!,
    ].join(' • ');

    final disabled = os.deleted;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: disabled ? null : onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: disabled ? cs.surfaceContainerHighest : cs.primaryContainer,
                child: Icon(
                  disabled ? Icons.block : Icons.folder_open,
                  color: disabled ? cs.onSurfaceVariant : cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: disabled ? 0.6 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              titulo,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(status: os.statusArquivo, deleted: os.deleted),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitulo.isEmpty ? '-' : subtitulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      if (os.deleted) ...[
                        const SizedBox(height: 8),
                        Text(
                          'OS marcada como EXCLUÍDA',
                          style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status; // inc|alt|exc
  final bool deleted;

  const _StatusChip({required this.status, required this.deleted});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = status.toLowerCase().trim();

    String label;
    IconData icon;
    Color bg;
    Color fg;

    if (deleted || s == 'exc') {
      label = 'EXC';
      icon = Icons.delete_forever;
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
    } else if (s == 'alt') {
      label = 'ALT';
      icon = Icons.edit;
      bg = cs.tertiaryContainer;
      fg = cs.onTertiaryContainer;
    } else {
      label = 'INC';
      icon = Icons.add_circle;
      bg = cs.primaryContainer;
      fg = cs.onPrimaryContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class OsDetailPage extends StatefulWidget {
  final String osId;
  const OsDetailPage({super.key, required this.osId});

  @override
  State<OsDetailPage> createState() => _OsDetailPageState();
}

class _OsDetailPageState extends State<OsDetailPage> {
  final _repo = OsRepository();
  OsModel? _os;
  List<OsApontamento> _apont = const [];
  bool _loading = true;
  String? _error;

  final _servExecCtrl = TextEditingController();
  bool _savingServico = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _servExecCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final os = await _repo.obterOsPorId(widget.osId);
      final ap = await _repo.listarApontamentos(widget.osId);
      _os = os;
      _apont = ap;
      _servExecCtrl.text = os.servicoExecutado ?? '';
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _totalHoras() {
    double sum = 0;
    for (final a in _apont) {
      if (a.horas != null) sum += a.horas!;
    }
    return sum;
  }

  Future<void> _saveServicoExecutado() async {
    final os = _os;
    if (os == null) return;

    setState(() => _savingServico = true);
    try {
      await _repo.atualizarServicoExecutado(
        osId: os.id,
        servicoExecutado: _servExecCtrl.text.trim().isEmpty ? null : _servExecCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Serviço executado salvo.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingServico = false);
    }
  }

  Future<void> _addOrEditApontamento({OsApontamento? edit}) async {
    final os = _os;
    if (os == null) return;

    final res = await showDialog<_ApontamentoFormResult>(
      context: context,
      builder: (_) => _ApontamentoDialog(initial: edit),
    );

    if (res == null) return;

    try {
      if (edit == null) {
        await _repo.criarApontamento(
          osId: os.id,
          data: res.data,
          inicioHHmmss: res.inicio,
          fimHHmmss: res.fim,
          horas: res.horas,
          descricao: res.descricao,
          tecnico: res.tecnico,
        );
      } else {
        await _repo.atualizarApontamento(
          id: edit.id,
          data: res.data,
          inicioHHmmss: res.inicio,
          fimHHmmss: res.fim,
          horas: res.horas,
          descricao: res.descricao,
          tecnico: res.tecnico,
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _deleteApontamento(OsApontamento a) async {
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

    try {
      await _repo.excluirApontamento(a.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes da OS'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: (_os != null && !_os!.deleted)
          ? FloatingActionButton.extended(
        onPressed: () => _addOrEditApontamento(),
        icon: const Icon(Icons.add),
        label: const Text('Apontamento de horas'),
      )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(_error!, style: TextStyle(color: cs.error)),
        ),
      )
          : _os == null
          ? const Center(child: Text('OS não encontrada.'))
          : _buildContent(context, df),
    );
  }

  Widget _buildContent(BuildContext context, DateFormat df) {
    final cs = Theme.of(context).colorScheme;
    final os = _os!;
    final total = _totalHoras();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'OS ${os.nroos}/${os.seqos}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            _StatusChip(status: os.statusArquivo, deleted: os.deleted),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          os.cliente ?? '-',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        if (os.deleted) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Esta OS está marcada como EXCLUÍDA (exc).',
              style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w800),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Informações',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Departamento', os.departamento ?? '-'),
              _kv('Data abertura', os.dataAbertura != null ? df.format(os.dataAbertura!) : '-'),
              _kv('Arquivo', os.arquivoNome ?? '-'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Serviço solicitado',
          child: Text(
            (os.servicoSolicitado == null || os.servicoSolicitado!.trim().isEmpty) ? '-' : os.servicoSolicitado!,
            style: const TextStyle(height: 1.3),
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Serviço executado',
          trailing: os.deleted
              ? null
              : (_savingServico
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
            tooltip: 'Salvar',
            onPressed: _saveServicoExecutado,
            icon: const Icon(Icons.save),
          )),
          child: TextField(
            controller: _servExecCtrl,
            enabled: !os.deleted,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: 'Descreva o que foi feito (serviço executado)...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (!os.deleted)
          FilledButton.icon(
            onPressed: () => _addOrEditApontamento(),
            icon: const Icon(Icons.access_time),
            label: const Text('Apontamento de horas'),
          ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Apontamentos',
          trailing: Chip(
            label: Text('Total: ${total.toStringAsFixed(2)} h'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: _apont.isEmpty
              ? Text('Nenhum apontamento ainda.', style: TextStyle(color: cs.onSurfaceVariant))
              : Column(
            children: _apont
                .map((a) => _ApontTile(
              a: a,
              onEdit: os.deleted ? null : () => _addOrEditApontamento(edit: a),
              onDelete: os.deleted ? null : () => _deleteApontamento(a),
            ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(width: 8),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ApontTile extends StatelessWidget {
  final OsApontamento a;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ApontTile({required this.a, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat('dd/MM/yyyy');

    String fmtTime(TimeOfDay? t) {
      if (t == null) return '--:--';
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    final horas = a.horas?.toStringAsFixed(2) ?? '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${df.format(a.data)} • ${fmtTime(a.inicio)} - ${fmtTime(a.fim)} • $horas h',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Editar',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit),
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Excluir',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          if (a.descricao != null && a.descricao!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(a.descricao!, style: const TextStyle(height: 1.3)),
          ],
          if (a.tecnico != null && a.tecnico!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Técnico: ${a.tecnico!}', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _ApontamentoFormResult {
  final DateTime data;
  final String? inicio; // HH:MM:SS
  final String? fim; // HH:MM:SS
  final double? horas;
  final String? descricao;
  final String? tecnico;

  _ApontamentoFormResult({
    required this.data,
    required this.inicio,
    required this.fim,
    required this.horas,
    required this.descricao,
    required this.tecnico,
  });
}

class _ApontamentoDialog extends StatefulWidget {
  final OsApontamento? initial;
  const _ApontamentoDialog({this.initial});

  @override
  State<_ApontamentoDialog> createState() => _ApontamentoDialogState();
}

class _ApontamentoDialogState extends State<_ApontamentoDialog> {
  DateTime _data = DateTime.now();
  TimeOfDay? _inicio;
  TimeOfDay? _fim;

  bool _modoManual = false;
  final _horasCtrl = TextEditingController();

  final _descCtrl = TextEditingController();
  final _tecCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _data = i.data;
      _inicio = i.inicio;
      _fim = i.fim;
      _descCtrl.text = i.descricao ?? '';
      _tecCtrl.text = i.tecnico ?? '';
      if (i.horas != null) _horasCtrl.text = i.horas!.toStringAsFixed(2);
    } else {
      // default: tenta usar email do usuário
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) _tecCtrl.text = email;
    }

    // se não tem horários, já sugere manual
    if (_inicio == null || _fim == null) {
      _modoManual = true;
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _tecCtrl.dispose();
    _horasCtrl.dispose();
    super.dispose();
  }

  double? _calcHorasAuto() {
    if (_inicio == null || _fim == null) return null;
    final a = _inicio!.hour * 60 + _inicio!.minute;
    final b = _fim!.hour * 60 + _fim!.minute;
    var diff = b - a;

    // ✅ permite virar o dia (ex: 22:00 -> 01:00)
    if (diff <= 0) diff += 24 * 60;

    if (diff <= 0) return null;
    return (diff / 60.0);
  }

  double? _parseHorasManual() {
    final s = _horasCtrl.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    final v = double.tryParse(s);
    if (v == null || v <= 0) return null;
    return v;
  }

  String? _toHHmmss(TimeOfDay? t) {
    if (t == null) return null;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    final horasAuto = _calcHorasAuto();
    final horasManual = _parseHorasManual();
    final horasFinal = _modoManual ? horasManual : horasAuto;

    return AlertDialog(
      title: Text(widget.initial == null ? 'Novo apontamento' : 'Editar apontamento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data'),
              subtitle: Text(df.format(_data)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _data,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _data = picked);
              },
            ),

            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Automático'),
                    selected: !_modoManual,
                    onSelected: (_) => setState(() => _modoManual = false),
                  ),
                  ChoiceChip(
                    label: const Text('Manual'),
                    selected: _modoManual,
                    onSelected: (_) => setState(() => _modoManual = true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Horários (sempre disponíveis, mesmo no manual)
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Início'),
                    subtitle: Text(_inicio == null
                        ? '--:--'
                        : '${_inicio!.hour.toString().padLeft(2, '0')}:${_inicio!.minute.toString().padLeft(2, '0')}'),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: _inicio ?? TimeOfDay.now());
                      if (t != null) setState(() => _inicio = t);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fim'),
                    subtitle: Text(_fim == null
                        ? '--:--'
                        : '${_fim!.hour.toString().padLeft(2, '0')}:${_fim!.minute.toString().padLeft(2, '0')}'),
                    trailing: const Icon(Icons.schedule),
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: _fim ?? TimeOfDay.now());
                      if (t != null) setState(() => _fim = t);
                    },
                  ),
                ),
              ],
            ),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                !_modoManual
                    ? (horasAuto == null ? 'Horas: -' : 'Horas calculadas: ${horasAuto.toStringAsFixed(2)} h')
                    : (horasManual == null ? 'Horas (manual): -' : 'Horas (manual): ${horasManual.toStringAsFixed(2)} h'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),

            if (_modoManual) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _horasCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Horas (ex: 1,5)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],

            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Descrição do serviço no período',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tecCtrl,
              decoration: const InputDecoration(
                labelText: 'Técnico (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            // ✅ validação mínima:
            // - se automático, precisa ter horasAuto (depende de início/fim)
            // - se manual, precisa ter horasManual
            if ((!_modoManual && horasAuto == null) || (_modoManual && horasManual == null)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Informe horários válidos ou horas manuais.')),
              );
              return;
            }

            final result = _ApontamentoFormResult(
              data: _data,
              inicio: _toHHmmss(_inicio),
              fim: _toHHmmss(_fim),
              horas: horasFinal,
              descricao: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
              tecnico: _tecCtrl.text.trim().isEmpty ? null : _tecCtrl.text.trim(),
            );
            Navigator.pop(context, result);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
