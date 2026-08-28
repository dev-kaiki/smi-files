// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/widgets/smi_page_shell.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';

class SmiPageShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget>? chips;
  final Widget child;

  /// Extras (não quebram seu uso atual)
  final double maxWidth;
  final Color? backgroundColor;
  final Widget? headerTrailing;
  final bool showDivider;

  const SmiPageShell({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.chips,
    this.maxWidth = 640,
    this.backgroundColor,
    this.headerTrailing,
    this.showDivider = true,
  });

  EdgeInsets _responsivePadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return const EdgeInsets.all(12);
    if (w < 600) return const EdgeInsets.all(16);
    return const EdgeInsets.all(20);
  }

  EdgeInsets _cardInnerPadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return const EdgeInsets.all(14);
    if (w < 600) return const EdgeInsets.all(18);
    return const EdgeInsets.all(20);
  }

  double _avatarSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 40;
    return 44;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    final basePadding = _responsivePadding(context);
    final cardPadding = _cardInnerPadding(context);
    final avatarSize = _avatarSize(context);

    return SafeArea(
      child: Container(
        color: backgroundColor ?? theme.scaffoldBackgroundColor,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(ctx).unfocus(),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: EdgeInsets.fromLTRB(
                  basePadding.left,
                  basePadding.top,
                  basePadding.right,
                  basePadding.bottom + math.max(0, viewInsetsBottom),
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxWidth),
                        child: Card(
                          elevation: 3,
                          color: cs.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: cardPadding,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Header
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Semantics(
                                      label: 'Ícone da página',
                                      child: Container(
                                        width: avatarSize,
                                        height: avatarSize,
                                        decoration: BoxDecoration(
                                          color: cs.primaryContainer,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: cs.outlineVariant),
                                        ),
                                        child: Icon(
                                          icon,
                                          color: cs.onPrimaryContainer,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleLarge?.copyWith(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              subtitle!,
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (headerTrailing != null) ...[
                                      const SizedBox(width: 10),
                                      headerTrailing!,
                                    ],
                                  ],
                                ),

                                // Chips
                                if (chips != null && chips!.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: chips!,
                                    ),
                                  ),
                                ],

                                // Divider
                                if (showDivider) ...[
                                  const SizedBox(height: 16),
                                  Divider(color: cs.outlineVariant),
                                  const SizedBox(height: 12),
                                ] else ...[
                                  const SizedBox(height: 14),
                                ],

                                // Body
                                child,
                              ],
                            ),
                          ),
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
    );
  }
}
