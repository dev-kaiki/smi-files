// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/checklist/checklist_template_page.dart
//
// Editor de template de checklist (ADMIN).
// Sem Auth: o controle de acesso é feito pela tela anterior (readOnly).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_manager.dart';
import '../../widgets/smi_page_shell.dart';

class ChecklistTemplatePage extends StatefulWidget {
  final String? templateId;
  final bool readOnly;

  const ChecklistTemplatePage({
    super.key,
    this.templateId,
    this.readOnly = false,
  });

  @override
  State<ChecklistTemplatePage> createState() => _ChecklistTemplatePageState();
}

class _ChecklistTemplatePageState extends State<ChecklistTemplatePage> {
  final SupabaseClient _db = SupabaseManager.client;

  final _nomeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _ativo = true;
  bool _loading = true;
  bool _saving = false;

  String? _templateId;
  List<TextEditingController> _itemCtrls = [];

  bool get _readOnly => widget.readOnly;

  @override
  void initState() {
    super.initState();
    _templateId = widget.templateId;
    _load();
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _itemCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    try {
      if (_templateId == null) {
        // novo template
        _itemCtrls = [TextEditingController()];
        setState(() => _loading = false);
        return;
      }

      final tpl = await _db
          .from('files_checklist_templates')
          .select()
          .eq('id', _templateId!)
          .limit(1);

      final tplList = (tpl as List).cast<Map<String, dynamic>>();
      if (tplList.isEmpty) {
        setState(() => _loading = false);
        _snack('Template não encontrado.');
        return;
      }

      final t = tplList.first;
      _nomeCtrl.text = (t['nome'] ?? '').toString();
      _descCtrl.text = (t['descricao'] ?? '').toString();
      _ativo = (t['ativo'] ?? true) == true;

      final itemsRes = await _db
          .from('files_checklist_template_items')
          .select()
          .eq('template_id', _templateId!)
          .order('ordem', ascending: true);

      final items = (itemsRes as List).cast<Map<String, dynamic>>();
      for (final c in _itemCtrls) {
        c.dispose();
      }
      _itemCtrls = items.isEmpty
          ? [TextEditingController()]
          : items
          .map((e) => TextEditingController(text: (e['label'] ?? '').toString()))
          .toList();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Erro ao carregar: $e');
    }
  }

  void _addItem() {
    setState(() {
      _itemCtrls.add(TextEditingController());
    });
  }

  void _removeItem(int i) {
    if (_itemCtrls.length <= 1) return;
    final c = _itemCtrls.removeAt(i);
    c.dispose();
    setState(() {});
  }

  void _moveItemUp(int i) {
    if (i <= 0) return;
    final a = _itemCtrls[i - 1];
    _itemCtrls[i - 1] = _itemCtrls[i];
    _itemCtrls[i] = a;
    setState(() {});
  }

  void _moveItemDown(int i) {
    if (i >= _itemCtrls.length - 1) return;
    final a = _itemCtrls[i + 1];
    _itemCtrls[i + 1] = _itemCtrls[i];
    _itemCtrls[i] = a;
    setState(() {});
  }

  Future<void> _save() async {
    if (_readOnly) return;

    final nome = _nomeCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    final labels = _itemCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (nome.isEmpty) {
      _snack('Informe um nome para o checklist.');
      return;
    }
    if (labels.isEmpty) {
      _snack('Adicione pelo menos 1 item.');
      return;
    }

    setState(() => _saving = true);

    try {
      final now = DateTime.now().toUtc().toIso8601String();

      if (_templateId == null) {
        final inserted = await _db
            .from('files_checklist_templates')
            .insert({
          'nome': nome,
          'descricao': desc.isEmpty ? null : desc,
          'ativo': _ativo,
          'updated_at': now,
        })
            .select('id')
            .single();

        _templateId = (inserted['id'] ?? '').toString();
      } else {
        await _db
            .from('files_checklist_templates')
            .update({
          'nome': nome,
          'descricao': desc.isEmpty ? null : desc,
          'ativo': _ativo,
          'updated_at': now,
        })
            .eq('id', _templateId!);
      }

      // sincroniza itens (simples e confiável)
      await _db.from('files_checklist_template_items').delete().eq('template_id', _templateId!);

      final payload = <Map<String, dynamic>>[];
      for (var i = 0; i < labels.length; i++) {
        payload.add({
          'template_id': _templateId,
          'ordem': i + 1,
          'label': labels[i],
        });
      }
      await _db.from('files_checklist_template_items').insert(payload);

      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Salvo com sucesso.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Erro ao salvar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_templateId == null ? 'Novo checklist' : 'Editar checklist'),
        actions: [
          if (!_readOnly)
            IconButton(
              tooltip: 'Salvar',
              icon: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              onPressed: _saving ? null : _save,
            ),
        ],
      ),
      body: SmiPageShell(
        title: _templateId == null ? 'Criar template' : 'Template',
        icon: Icons.checklist_rounded,
        subtitle: _readOnly ? 'Visualização apenas.' : 'Edite o nome e os itens.',
        chips: [
          Chip(
            avatar: Icon(_ativo ? Icons.check_circle_outline : Icons.pause_circle_outline, size: 18),
            label: Text(_ativo ? 'Ativo' : 'Inativo'),
          ),
          if (_readOnly)
            Chip(
              avatar: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Somente leitura'),
            ),
        ],
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
            : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nomeCtrl,
              enabled: !_readOnly && !_saving,
              decoration: const InputDecoration(
                labelText: 'Nome do checklist',
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              enabled: !_readOnly && !_saving,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 12),

            SwitchListTile(
              value: _ativo,
              onChanged: _readOnly || _saving ? null : (v) => setState(() => _ativo = v),
              title: const Text('Template ativo'),
              subtitle: const Text('Somente templates ativos aparecem na escolha da OS.'),
            ),

            const SizedBox(height: 12),
            Text('Itens', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),

            ...List.generate(_itemCtrls.length, (i) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      Text('#${i + 1}', style: TextStyle(color: cs.onSurfaceVariant)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _itemCtrls[i],
                          enabled: !_readOnly && !_saving,
                          decoration: const InputDecoration(
                            hintText: 'Ex.: Lavar drive',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Subir',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: _readOnly || _saving || i == 0 ? null : () => _moveItemUp(i),
                      ),
                      IconButton(
                        tooltip: 'Descer',
                        icon: const Icon(Icons.arrow_downward),
                        onPressed: _readOnly || _saving || i == _itemCtrls.length - 1 ? null : () => _moveItemDown(i),
                      ),
                      IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _readOnly || _saving || _itemCtrls.length <= 1 ? null : () => _removeItem(i),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 8),

            if (!_readOnly)
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Adicionar item'),
                onPressed: _saving ? null : _addItem,
              ),

            const SizedBox(height: 12),

            if (!_readOnly)
              FilledButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Salvar'),
                onPressed: _saving ? null : _save,
              ),
          ],
        ),
      ),
    );
  }
}
