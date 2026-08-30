import 'package:bathing_spots_app/web/shared/text_input_formatters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forceUpperCase met toute la valeur en majuscules', () {
    expect(forceUpperCase('La Tranche-sur-Mer'), 'LA TRANCHE-SUR-MER');
  });

  test('capitalizeFirstLetter conserve le reste de la valeur', () {
    expect(capitalizeFirstLetter('sylvain'), 'Sylvain');
    expect(capitalizeFirstLetter(' commercial'), ' Commercial');
  });

  test('UpperCaseTextInputFormatter conserve la position du curseur', () {
    const formatter = UpperCaseTextInputFormatter();
    final value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: 'rabreau',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );

    expect(value.text, 'RABREAU');
    expect(value.selection.baseOffset, 3);
  });

  test('FirstLetterUpperCaseTextInputFormatter normalise la saisie', () {
    const formatter = FirstLetterUpperCaseTextInputFormatter();
    final value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: 'commercial',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );

    expect(value.text, 'Commercial');
  });
}
