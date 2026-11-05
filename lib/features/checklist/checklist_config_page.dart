// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/checklist/checklist_config_page.dart
//
// FIX: Admin = (setor contém "admin") OR (tecnicos.is_admin == true).
// Antes: se is_admin existia e vinha false, derrubava admin do setor.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_manager.dart';
import '../../widgets/smi_page_shell.dart';
import '../../utils/setor_access.dart';
import 'checklist_template_page.dart';

class ChecklistConfigPage extends StatefulWidget {
  final int tecnicoId;
  final String setor;

  const ChecklistConfigPage({
    super.key,
    required this.tecnicoId,
    required this.setor,
  });

  @override
  State<ChecklistConfigPage> createState() => _ChecklistConfigPageState();
}

class _ChecklistConfigPageState extends State<ChecklistConfigPage> {
  final SupabaseClient _db = SupabaseManager.client;

  bool _loading = true;
  bool _checkingAdmin = true;
  String? _error;

  bool _admin = false;

  List<Map<String, dynamic>> _templates = const [];
  final Map<String, int> _itemCountByTemplateId = {};

  @override
  void initState() {
    super.initState();
    _admin = _adminBySetor(widget.setor);
    _checkAdmin().then((_) => _load());
  }

  bool _adminBySetor(String s) => isAdministrativo(s);

  Future<void> _checkAdmin() async {
    bool isAdmin = _adminBySetor(widget.setor);

    try {
      final res = await _db
          .from('tecnicos')
          .select('is_admin,setor')
          .eq('id', widget.tecnicoId)
          .limit(1);

      final list = (res as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty) {
        final row = list.first;
        final dbSetor = (row['setor'] ?? '').toString();
        final dbIsAdmin = row['is_admin'] == true;
        isAdmin = isAdmin || _adminBySetor(dbSetor) || dbIsAdmin;
      }
    } catch (_) {
      // mantém fallback
    }

    if (!mounted) return;
    setState(() {
      _admin = isAdmin;
      _checkingAdmin = false;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _db
          .from('files_checklist_templates')
          .select()
          .order('updated_at', ascending: false);

      final templates = (res as List).cast<Map<String, dynamic>>();

      _itemCountByTemplateId.clear();
      if (templates.isNotEmpty) {
        final ids = templates.map((e) => e['id'].toString()).toList();
        final itemsRes = await _db
            .from('files_checklist_template_items')
            .select('id,template_id')
            .inFilter('template_id', ids);

        final items = (itemsRes as List).cast<Map<String, dynamic>>();
        for (final it in items) {
          final tid = it['template_id']?.toString() ?? '';
          if (tid.isEmpty) continue;
          _itemCountByTemplateId[tid] = (_itemCountByTemplateId[tid] ?? 0) + 1;
        }
      }

      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openTemplateEditor({String? templateId}) async {
    final ok = await Navigator.push<bool?>(
      context,
      MaterialPageRoute(
        builder: (_) => ChecklistTemplatePage(
          templateId: templateId,
          readOnly: !_admin,
        ),
      ),
    );

    if (ok == true) {
      await _load();
    }
  }

  Future<void> _deleteTemplate(String templateId, String nome) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir checklist?'),
        content: Text('Isso remove o template "$nome" e seus itens.\n\nDeseja continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _db.from('files_checklist_templates').delete().eq('id', templateId);
      _snack('Checklist excluída.');
      await _load();
    } catch (e) {
      _snack('Erro ao excluir: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar checklists'),
        actions: [
          if (_checkingAdmin)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SmiPageShell(
        title: 'Tipos de checklist',
        icon: Icons.checklist_rounded,
        subtitle: _admin ? 'Crie e edite os templates de checklist.' : 'Você não é ADMIN. Visualização apenas.',
        chips: [
          Chip(
            avatar: Icon(_admin ? Icons.verified_user : Icons.lock_outline, size: 18),
            label: Text(_admin ? 'ADMIN' : 'Somente leitura'),
            backgroundColor: _admin ? cs.primaryContainer : cs.surfaceContainerHighest,
          ),
        ],
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
            : _error != null
            ? _ErrorBox(message: _error!, onRetry: _load)
            : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_templates.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Nenhum template cadastrado ainda.\nCrie o primeiro para usar nas OS.',
                ),
              )
            else
              ..._templates.map((t) {
                final id = t['id']?.toString() ?? '';
                final nome = (t['nome'] ?? '').toString();
                final desc = (t['descricao'] ?? '').toString();
                final ativo = (t['ativo'] ?? true) == true;
                final count = _itemCountByTemplateId[id] ?? 0;

                return Card(
                  child: ListTile(
                    leading: Icon(Icons.checklist_rounded, color: ativo ? cs.primary : cs.onSurfaceVariant),
                    title: Text(nome.isEmpty ? '(sem nome)' : nome),
                    subtitle: Text(
                      '${desc.isEmpty ? 'Sem descrição' : desc}\nItens: $count • ${ativo ? 'Ativo' : 'Inativo'}',
                    ),
                    isThreeLine: true,
                    onTap: () => _openTemplateEditor(templateId: id),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: _admin ? 'Editar' : 'Visualizar',
                          icon: Icon(_admin ? Icons.edit : Icons.visibility),
                          onPressed: () => _openTemplateEditor(templateId: id),
                        ),
                        if (_admin)
                          IconButton(
                            tooltip: 'Excluir',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteTemplate(id, nome),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 12),
            if (_admin)
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Criar novo template'),
                onPressed: () => _openTemplateEditor(),
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
          Text('Erro ao carregar', style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: cs.onErrorContainer)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
