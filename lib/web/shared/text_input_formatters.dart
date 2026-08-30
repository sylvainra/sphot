import 'dart:math' as math;

import 'package:flutter/services.dart';

String forceUpperCase(String value) => value.toUpperCase();

String capitalizeFirstLetter(String value) {
  final firstLetterIndex = value.indexOf(RegExp(r'\S'));
  if (firstLetterIndex < 0) return value;

  return value.replaceRange(
    firstLetterIndex,
    firstLetterIndex + 1,
    value[firstLetterIndex].toUpperCase(),
  );
}

class UpperCaseTextInputFormatter extends TextInputFormatter {
  const UpperCaseTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _withFormattedText(newValue, forceUpperCase(newValue.text));
  }
}

class FirstLetterUpperCaseTextInputFormatter extends TextInputFormatter {
  const FirstLetterUpperCaseTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return _withFormattedText(newValue, capitalizeFirstLetter(newValue.text));
  }
}

TextEditingValue _withFormattedText(
  TextEditingValue value,
  String formattedText,
) {
  if (formattedText == value.text) return value;

  final baseOffset = math.min(value.selection.baseOffset, formattedText.length);
  final extentOffset = math.min(
    value.selection.extentOffset,
    formattedText.length,
  );

  return TextEditingValue(
    text: formattedText,
    selection: value.selection.copyWith(
      baseOffset: baseOffset,
      extentOffset: extentOffset,
    ),
    composing: TextRange.empty,
  );
}
