import 'package:flutter/services.dart';

/// Strips redundant leading zeros from numeric input so a field that shows the
/// placeholder "0" doesn't turn into "05" when the user starts typing. Keeps a
/// single leading zero only when it is followed by a decimal point ("0.5") or
/// when the value is exactly "0". Empty input is left untouched so hint text can
/// show through.
///
/// Do NOT use this on PIN / passcode fields — leading zeros are significant
/// there (e.g. a PIN of "0123").
class NoLeadingZeroFormatter extends TextInputFormatter {
  const NoLeadingZeroFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    // Remove leading zeros that are immediately followed by another digit,
    // so "007" -> "7" and "05" -> "5", but "0", "0.5" and "0.75" are preserved.
    final stripped = text.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (stripped == text) return newValue;

    final removed = text.length - stripped.length;
    final offset =
        (newValue.selection.baseOffset - removed).clamp(0, stripped.length);
    return TextEditingValue(
      text: stripped,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Convenience list combining the leading-zero strip with a digit/decimal
/// filter for money and quantity fields.
const List<TextInputFormatter> decimalNumberFormatters = [
  NoLeadingZeroFormatter(),
];
