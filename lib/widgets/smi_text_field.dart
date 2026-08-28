// ignore_for_file: deprecated_member_use, prefer_const_constructors, prefer_const_declarations, unused_element, dead_null_aware_expression, use_rethrow_when_possible, dead_code, use_build_context_synchronously, unnecessary_non_null_assertion, unnecessary_cast, unnecessary_import, depend_on_referenced_packages, no_leading_underscores_for_local_identifiers
// lib/widgets/smi_text_field.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SmiTextField extends StatelessWidget {
  final TextEditingController controller;

  final String label;
  final String? hint;

  final bool obscureText;
  final TextInputType? keyboardType;

  final Widget? prefixIcon;
  final Widget? suffixIcon;

  final bool enabled;
  final bool readOnly;

  final int? maxLines;
  final int minLines;

  final TextInputAction? textInputAction;
  final FocusNode? focusNode;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;

  /// Mostra botão de limpar quando tiver texto (útil em busca/campos longos)
  final bool showClearButton;

  const SmiTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines = 1,
    this.textInputAction,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.inputFormatters,
    this.autofillHints,
    this.showClearButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bool multiline = (maxLines ?? 1) > 1;

    Widget? finalSuffix = suffixIcon;

    if (showClearButton) {
      finalSuffix = ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, __) {
          final hasText = value.text.trim().isNotEmpty;
          if (!hasText) return suffixIcon ?? const SizedBox.shrink();

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (suffixIcon != null) suffixIcon!,
              IconButton(
                tooltip: 'Limpar',
                onPressed: enabled && !readOnly
                    ? () {
                  controller.clear();
                  onChanged?.call('');
                  FocusScope.of(context).unfocus();
                }
                    : null,
                icon: const Icon(Icons.clear),
              ),
            ],
          );
        },
      );
    }

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction ?? (multiline ? TextInputAction.newline : TextInputAction.next),
      minLines: multiline ? minLines : 1,
      maxLines: multiline ? maxLines : 1,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        suffixIcon: finalSuffix,
        isDense: true,
        filled: true,
        fillColor: enabled ? cs.surface : cs.surfaceContainerHighest.withOpacity(0.6),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

        // Respeita seu inputDecorationTheme, mas garante fallback
        border: const OutlineInputBorder(),
      ),
    );
  }
}
