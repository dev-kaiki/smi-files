// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/home/home_page.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../os/new_os_folder_page.dart';
import '../os/os_list_page.dart';
import '../os/os_media_page.dart';
import '../checklist/checklist_config_page.dart';
import '../debug/supabase_diagnostics_page.dart';
import '../../utils/setor_access.dart';
import '../../widgets/smi_button.dart';
import '../../widgets/smi_page_shell.dart';
import '../../utils/smi_routes.dart';

class HomePage extends StatelessWidget {
  final int tecnicoId;
  final String tecnicoNome;
  final String setor;

  const HomePage({
    super.key,
    required this.tecnicoId,
    required this.tecnicoNome,
    required this.setor,
  });

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sair da conta?'),
        content: const Text('Deseja realmente sair deste usuário?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sair')),
        ],
      ),
    );

    if (ok != true) return;

    final prefs = await SharedPreferences.getInstance();

    // limpa apenas o que usamos para login/remember-me
    await prefs.remove('remember_me');
    await prefs.remove('tecnico_id');
    await prefs.remove('tecnico_nome');
    await prefs.remove('tecnico_setor');
    await prefs.remove('tecnico_codigo');
    await prefs.remove('current_tecnico_id');
    await prefs.remove('current_tecnico_nome');
    await prefs.remove('current_tecnico_setor');
    await prefs.remove('current_tecnico_codigo');

    // volta para a tela de login
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, SmiRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAdmin = isAdministrativo(setor);

    return Scaffold(
      backgroundColor: cs.surfaceVariant.withOpacity(0.35),
      appBar: AppBar(
        title: const Text('SMI Arquivos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair da conta',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: SmiPageShell(
        title: 'Olá, $tecnicoNome',
        icon: Icons.home_filled,
        subtitle: 'Gerencie as pastas de OS e mídias dos clientes.',
        chips: [
          Chip(
            avatar: const Icon(Icons.engineering, size: 18),
            label: Text('Técnico #$tecnicoId'),
          ),
          Chip(
            avatar: const Icon(Icons.apartment, size: 18),
            label: Text(setorLabel(setor)),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ações rápidas
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.bolt, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ações rápidas', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(
                          'Criar nova OS ou explorar as OS já existentes.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Criar nova pasta de OS -> depois de criar, entra direto na OS
            SmiButton(
              label: 'Criar nova pasta de OS',
              icon: Icons.create_new_folder,
              onPressed: () async {
                final newOsId = await Navigator.push<String?>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NewOsFolderPage(
                      tecnicoId: tecnicoId,
                      tecnicoNome: tecnicoNome,
                      setor: setor,
                    ),
                  ),
                );

                if (newOsId != null && context.mounted) {
                  // assim que a pasta é criada, já abre dentro dela (tela de mídias da OS)
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OsMediaPage(osFolderId: newOsId),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),

            // Explorar OS existentes
            OutlinedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Explorar OS existentes'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OsListPage(
                      tecnicoId: tecnicoId,
                      tecnicoNome: tecnicoNome,
                      setor: setor,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.checklist_rounded, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Checklists', style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(
                              isAdmin
                                  ? 'Cadastre e mantenha os tipos de checklist usados nas OS.'
                                  : 'Os checklists ficam disponíveis dentro de cada OS. O cadastro de tipos é restrito ao administrativo.',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.rule_folder_outlined),
                    label: const Text('Abrir checklists'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChecklistConfigPage(
                            tecnicoId: tecnicoId,
                            setor: setor,
                          ),
                        ),
                      );
                    },
                  ),
                  if (!isAdmin) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Somente o setor Administrativo pode adicionar, editar ou excluir tipos de checklist.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // V9.4 FIX: oculto em release para evitar que técnicos criem
            // registros de teste em produção. Visível apenas em debug/profile.
            if (!kReleaseMode) ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud_done_outlined),
                label: const Text('Teste do Supabase'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SupabaseDiagnosticsPage()),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],

            // Ajuda / dicas
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dica: após criar uma OS, você já será levado para anexar mídias e preencher informações.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
