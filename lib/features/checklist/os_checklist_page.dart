// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/checklist/os_checklist_page.dart
//
// Checklist por OS do SMI_FILES (1 checklist por os_folder_id).
// Compatível com chamadas antigas que passam osLabel/ano/osCode (opcionais).
// Sem Supabase Auth: grava técnico em cada item (tecnico_id + tecnico_nome).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_manager.dart';

class OsChecklistPage extends StatefulWidget {
  final String osFolderId;

  /// Opcionais (mantidos para compatibilidade com sua chamada atual no OsMediaPage)
  final String? osLabel;
  final String? ano;
  final String? osCode;

  const OsChecklistPage({
    super.key,
    required this.osFolderId,
    this.osLabel,
    this.ano,
    this.osCode,
  });

  @override
  State<OsChecklistPage> createState() => _OsChecklistPageState();
}

class _OsChecklistPageState extends State<OsChecklistPage> {
  final SupabaseClient _db = SupabaseManager.client;

  bool _loading = true;
  bool _creating = false;
  String? _error;

  // dados
  Map<String, dynamic>? _osFolder; // para título OS
  Map<String, dynamic>? _osChecklist; // files_checklist_execucoes row
  List<Map<String, dynamic>> _items = const [];
  String _currentLogin = '';
  String _currentNome = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadCurrentOperator();

      // Carrega dados básicos da OS pra título (se não vieram por parâmetro)
      try {
        final osRes = await _db
            .from('os_folders')
            .select('id, ano, os_code')
            .eq('id', widget.osFolderId)
            .limit(1);

        final osList = (osRes as List).cast<Map<String, dynamic>>();
        _osFolder = osList.isEmpty ? null : osList.first;
      } catch (_) {
        _osFolder = null;
      }

      // Carrega checklist (1 por OS)
      final ckRes = await _db
          .from('files_checklist_execucoes')
          .select('id, os_folder_id, template_id, template_nome_snapshot, created_at, updated_at')
          .eq('os_folder_id', widget.osFolderId)
          .limit(1);

      final ckList = (ckRes as List).cast<Map<String, dynamic>>();
      _osChecklist = ckList.isEmpty ? null : ckList.first;

      // Carrega itens se existir checklist
      if (_osChecklist != null) {
        final itemsRes = await _db
            .from('files_checklist_execucao_itens')
            .select('*')
            .eq('execucao_id', _osChecklist!['id'])
            .order('ordem', ascending: true);

        _items = (itemsRes as List).cast<Map<String, dynamic>>();
      } else {
        _items = const [];
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }


  Future<void> _loadCurrentOperator() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final codigo = (prefs.getString('current_tecnico_codigo') ?? '').trim();
      final nome = (prefs.getString('current_tecnico_nome') ?? '').trim();
      if (codigo.isNotEmpty || nome.isNotEmpty) {
        _currentLogin = codigo;
        _currentNome = nome;
        return;
      }

      final tecnicoId = prefs.getInt('current_tecnico_id') ?? prefs.getInt('tecnico_id');
      if (tecnicoId == null) return;

      final res = await _db
          .from('tecnicos')
          .select('codigo, nome')
          .eq('id', tecnicoId)
          .limit(1);

      final list = (res as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return;
      _currentLogin = (list.first['codigo'] ?? '').toString().trim();
      _currentNome = (list.first['nome'] ?? '').toString().trim();
    } catch (_) {
      // fallback silencioso
    }
  }

  Future<void> _updateChecklistItemWithAudit({
    required String itemId,
    required bool checked,
    int? tecnicoId,
    String? tecnicoNome,
    String? checkedAt,
  }) async {
    final basePayload = <String, dynamic>{
      'checked': checked,
      'tecnico_id': tecnicoId,
      'tecnico_nome': tecnicoNome,
      'checked_at': checkedAt,
    };

    if (!checked) {
      try {
        await _db.from('files_checklist_execucao_itens').update({
          ...basePayload,
          'marcado_por_login': null,
          'marcado_por_nome': null,
        }).eq('id', itemId);
        return;
      } catch (_) {}

      await _db.from('files_checklist_execucao_itens').update(basePayload).eq('id', itemId);
      return;
    }

    final login = _currentLogin.trim();
    final nome = _currentNome.trim();

    if (login.isNotEmpty || nome.isNotEmpty) {
      try {
        await _db.from('files_checklist_execucao_itens').update({
          ...basePayload,
          'marcado_por_login': login.isEmpty ? null : login,
          'marcado_por_nome': nome.isEmpty ? null : nome,
        }).eq('id', itemId);
        return;
      } catch (_) {}
    }

    await _db.from('files_checklist_execucao_itens').update(basePayload).eq('id', itemId);
  }

  String _checkedByLabel(Map<String, dynamic> item) {
    final login = (item['marcado_por_login'] ?? '').toString().trim();
    final nome = (item['marcado_por_nome'] ?? '').toString().trim();
    if (login.isNotEmpty) return login;
    if (nome.isNotEmpty) return nome;
    return '';
  }

  String _osTitle() {
    final ano = (widget.ano ?? _osFolder?['ano'] ?? '').toString().trim();
    final osCode = (widget.osCode ?? _osFolder?['os_code'] ?? '').toString().trim();
    if (ano.isNotEmpty && osCode.isNotEmpty) return 'OS $ano/$osCode';
    final label = (widget.osLabel ?? '').toString().trim();
    if (label.isNotEmpty) return 'OS $label';
    return 'Checklist';
  }

  // ==========================
  // Templates
  // ==========================

  Future<Map<String, dynamic>?> _pickTemplate() async {
    final res = await _db
        .from('files_checklist_templates')
        .select('id, nome, descricao, ativo')
        .eq('ativo', true)
        .order('nome', ascending: true);

    final templates = (res as List).cast<Map<String, dynamic>>();

    if (!mounted) return null;

    if (templates.isEmpty) {
      _snack('Nenhum template ativo cadastrado.');
      return null;
    }

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: templates.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final t = templates[i];
            final nome = (t['nome'] ?? '').toString();
            final desc = (t['descricao'] ?? '').toString();
            return ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: Text(nome.isEmpty ? '(sem nome)' : nome),
              subtitle: desc.trim().isEmpty ? null : Text(desc),
              onTap: () => Navigator.pop(context, t),
            );
          },
        ),
      ),
    );
  }

  Future<void> _createChecklistFromTemplate() async {
    if (_creating) return;
    if (_osChecklist != null) return;

    final t = await _pickTemplate();
    if (t == null) return;

    setState(() => _creating = true);

    try {
      final templateId = t['id'].toString();
      final templateNome = (t['nome'] ?? '').toString();

      // cria instância do checklist
      final inserted = await _db
          .from('files_checklist_execucoes')
          .insert({
        'os_folder_id': widget.osFolderId,
        'template_id': templateId,
        'template_nome_snapshot': templateNome,
      })
          .select('id, os_folder_id, template_id, template_nome_snapshot, created_at, updated_at')
          .single();

      final checklistRow = Map<String, dynamic>.from(inserted);

      // busca itens do template
      final itemsRes = await _db
          .from('files_checklist_template_items')
          .select('id, template_id, label, ordem')
          .eq('template_id', templateId)
          .order('ordem', ascending: true);

      final tplItems = (itemsRes as List).cast<Map<String, dynamic>>();

      if (tplItems.isEmpty) {
        // não deixa checklist vazio
        await _db.from('files_checklist_execucoes').delete().eq('id', checklistRow['id']);
        throw Exception('Template não possui itens.');
      }

      // cria os itens da OS (snapshot do label)
      final payload = tplItems.map((it) {
        return {
          'execucao_id': checklistRow['id'],
          'template_item_id': it['id'],
          'label_snapshot': (it['label'] ?? '').toString(),
          'ordem': (it['ordem'] is num) ? (it['ordem'] as num).toInt() : 0,
          'checked': false,
          'tecnico_id': null,
          'tecnico_nome': null,
          'checked_at': null,
        };
      }).toList();

      await _db.from('files_checklist_execucao_itens').insert(payload);

      // se existir coluna files_checklist_execucao_id em os_folders, atualiza (não quebra se não existir)
      try {
        await _db.from('os_folders').update({'files_checklist_execucao_id': checklistRow['id']}).eq('id', widget.osFolderId);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _osChecklist = checklistRow;
      });

      await _load();
      _snack('Checklist adicionada.');
    } catch (e) {
      _snack('Erro ao criar checklist: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  // ==========================
  // Técnico picker
  // ==========================

  Future<List<Map<String, dynamic>>> _fetchTecnicos(String query) async {
    final q = query.trim();

    dynamic base = _db.from('tecnicos').select('id, codigo, nome, ativo');
    try {
      base = base.eq('ativo', true);
    } catch (_) {}

    if (q.isEmpty) {
      final r = await base.order('nome', ascending: true).limit(200);
      return (r as List).cast<Map<String, dynamic>>();
    }

    // Sem OR: faz 2 buscas e junta
    final a = await base.ilike('nome', '%$q%').order('nome', ascending: true).limit(200);

    dynamic base2 = _db.from('tecnicos').select('id, codigo, nome, ativo');
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

  Future<void> _setItemChecked({
    required Map<String, dynamic> item,
    required bool checked,
  }) async {
    final id = item['id'].toString();

    // marcar: exige técnico
    if (checked) {
      final t = await _pickTecnicoBottomSheet();
      if (t == null) return;

      final tecnicoId = (t['id'] as num?)?.toInt();
      final tecnicoNome = (t['nome'] ?? '').toString().trim();
      if (tecnicoId == null || tecnicoNome.isEmpty) return;

      final now = DateTime.now().toUtc().toIso8601String();

      await _updateChecklistItemWithAudit(
        itemId: id,
        checked: true,
        tecnicoId: tecnicoId,
        tecnicoNome: tecnicoNome,
        checkedAt: now,
      );
    } else {
      // desmarcar: limpa técnico
      await _updateChecklistItemWithAudit(
        itemId: id,
        checked: false,
        tecnicoId: null,
        tecnicoNome: null,
        checkedAt: null,
      );
    }

    await _load();
  }

  Future<void> _changeTecnico(Map<String, dynamic> item) async {
    final id = item['id'].toString();
    final t = await _pickTecnicoBottomSheet();
    if (t == null) return;

    final tecnicoId = (t['id'] as num?)?.toInt();
    final tecnicoNome = (t['nome'] ?? '').toString().trim();
    if (tecnicoId == null || tecnicoNome.isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();

    await _updateChecklistItemWithAudit(
      itemId: id,
      checked: true,
      tecnicoId: tecnicoId,
      tecnicoNome: tecnicoNome,
      checkedAt: now,
    );

    await _load();
    _snack('Técnico atualizado.');
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_osTitle()),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorBox(message: _error!, onRetry: _load)
          : Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: _osChecklist == null
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: const Text(
                'Esta OS ainda não possui checklist.\n\n'
                    'Toque em "Adicionar checklist" e escolha um tipo.',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(_creating ? 'Criando...' : 'Adicionar checklist'),
              onPressed: _creating ? null : _createChecklistFromTemplate,
            ),
            const SizedBox(height: 12),
            const Text(
              'Observação: cada OS pode ter apenas 1 checklist.',
              textAlign: TextAlign.center,
            ),
          ],
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: Text((_osChecklist?['template_nome_snapshot'] ?? 'Checklist').toString()),
                subtitle: Text('Itens: ${_items.length}'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('Nenhum item.'))
                  : ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final it = _items[i];
                  final label = (it['label_snapshot'] ?? '').toString();
                  final checked = (it['checked'] ?? false) == true;
                  final tecnico = (it['tecnico_nome'] ?? '').toString().trim();
                  final when = _fmtDate((it['checked_at'] ?? '').toString());
                  final checkedBy = _checkedByLabel(it);

                  return ListTile(
                    leading: Checkbox(
                      value: checked,
                      onChanged: _creating
                          ? null
                          : (v) async {
                        if (v == null) return;
                        await _setItemChecked(item: it, checked: v);
                      },
                    ),
                    title: Text(label.isEmpty ? '(sem descrição)' : label),
                    subtitle: checked
                        ? Text(
                            'Técnico: ${tecnico.isEmpty ? '—' : tecnico}'
                            '${checkedBy.isEmpty ? '' : ' • Lançado por: $checkedBy'}'
                            '${when.isEmpty ? '' : ' • $when'}',
                          )
                        : const Text('Não feito'),
                    trailing: checked
                        ? IconButton(
                      tooltip: 'Alterar técnico',
                      icon: const Icon(Icons.engineering_outlined),
                      onPressed: _creating ? null : () => _changeTecnico(it),
                    )
                        : null,
                    onTap: _creating
                        ? null
                        : () async {
                      await _setItemChecked(item: it, checked: !checked);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.error.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Erro', style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: cs.onErrorContainer)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// Bottom sheet para selecionar técnico
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
