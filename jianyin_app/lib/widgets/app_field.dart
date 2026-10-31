import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.minLength,
    this.maxLength,
    this.onSubmitted,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int? minLength;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: enabled ? null : AppTokens.fgMuted,
              ),
        ),
        const SizedBox(height: AppTokens.space2),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          enabled: enabled,
          onSubmitted: onSubmitted,
          maxLength: maxLength,
          inputFormatters: keyboardType == TextInputType.phone
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: enabled ? null : AppTokens.fgMuted,
              ),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space4,
              vertical: 12,
            ),
            filled: !enabled,
            fillColor: enabled ? null : AppTokens.muted,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusField),
              borderSide: const BorderSide(color: AppTokens.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusField),
              borderSide: const BorderSide(color: AppTokens.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusField),
              borderSide: const BorderSide(color: AppTokens.teal),
            ),
          ),
        ),
      ],
    );
  }
}
