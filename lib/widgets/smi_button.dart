// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/widgets/smi_button.dart
import 'package:flutter/material.dart';

class SmiButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;

  // extras (não quebram uso antigo)
  final bool fullWidth;
  final bool loading;
  final bool dense;

  const SmiButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = true,
    this.fullWidth = true,
    this.loading = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final effectiveOnPressed = (loading) ? null : onPressed;

    final spinner = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        valueColor: AlwaysStoppedAnimation<Color>(
          primary ? cs.onPrimary : cs.primary,
        ),
      ),
    );

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading) ...[
          spinner,
          const SizedBox(width: 10),
        ] else if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(
        Size(fullWidth ? double.infinity : 0, dense ? 44 : 52),
      ),
      padding: WidgetStateProperty.all(
        EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 10 : 14),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    return primary
        ? FilledButton(
      onPressed: effectiveOnPressed,
      style: style,
      child: content,
    )
        : OutlinedButton(
      onPressed: effectiveOnPressed,
      style: style,
      child: content,
    );
  }
}
