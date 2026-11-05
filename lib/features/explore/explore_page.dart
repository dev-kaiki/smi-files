// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/features/explore/explore_page.dart

import 'package:flutter/material.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorar'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.explore, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Explorar OS / Clientes',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Em desenvolvimento — em breve você poderá buscar e filtrar OS e clientes.',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            _SoonTile(
              icon: Icons.filter_alt,
              title: 'Filtros avançados',
              subtitle: 'Buscar por status, setor, período, técnico e cliente.',
            ),
            const SizedBox(height: 10),
            _SoonTile(
              icon: Icons.manage_search,
              title: 'Busca rápida',
              subtitle: 'Pesquisar por OS, sequência, arquivo e palavras-chave.',
            ),
            const SizedBox(height: 10),
            _SoonTile(
              icon: Icons.folder_shared,
              title: 'Atalhos por cliente',
              subtitle: 'Ver OS agrupadas e acessos rápidos por cliente.',
            ),

            const SizedBox(height: 18),

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
                      'Dica: enquanto isso, use “Ordens de Serviço” no menu principal para localizar OS rapidamente.',
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

class _SoonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SoonTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: cs.onSecondaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.lock_clock, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}
