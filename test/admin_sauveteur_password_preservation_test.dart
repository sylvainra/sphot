import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String section(String source, String first, String next) {
  final start = source.indexOf(first);
  final end = source.indexOf(next, start >= 0 ? start : 0);
  expect(start, greaterThanOrEqualTo(0));
  expect(end, greaterThan(start));
  return source.substring(start, end);
}

void main() {
  final admin = File(
    'lib/web/admin/pages/admin_dashboard_page.dart',
  ).readAsStringSync();

  test('Modification sauveteur : mot de passe conserve', () {
    final save = section(
      admin,
      'Future<void> _saveSauveteur() async {',
      'bool _looksLikeDirectPhotoUrl(',
    );
    expect(save.contains('_regenerateSauveteurPassword'), isFalse);
    expect(save.contains('await _syncSauveteurAccountContext('), isTrue);
    expect(save.contains('await _sendSauveteurCredentialsEmail();'), isTrue);
    expect(
      RegExp(
        r'if \(!isEditing\) \{\s*try \{\s*'
        r'await _sendSauveteurCredentialsEmail\(\);',
      ).hasMatch(save),
      isTrue,
    );
    expect(save.contains("'resetPassword':"), isFalse);
    expect(
      admin.contains('Future<bool> _regenerateSauveteurPassword()'),
      isFalse,
    );
  });

  test('Creation : identifiants provisoires et email inchanges', () {
    final save = section(
      admin,
      'Future<void> _saveSauveteur() async {',
      'bool _looksLikeDirectPhotoUrl(',
    );
    final newAccount = section(
      save,
      'if (!isEditing) {',
      'final sauveteurRef =',
    );
    expect(newAccount.contains("'login': _sauveteurGeneratedLogin"), isTrue);
    expect(
      newAccount.contains("'temporaryPassword': _sauveteurGeneratedPassword"),
      isTrue,
    );
    expect(newAccount.contains("'mustChangePassword': true"), isTrue);
    expect(
      save.contains("'periodesSurveillance': data['periodesSurveillance']"),
      isTrue,
    );
    expect(save.contains("'postesAffectes': data['postesAffectes']"), isTrue);
  });

  test('Synchronisation du profil sans reinitialisation des acces', () {
    final sync = section(
      admin,
      'Future<void> _syncSauveteurAccountContext(',
      'Future<bool> _generateSauveteurAccess()',
    );
    expect(sync.contains("'temporaryPassword':"), isFalse);
    expect(sync.contains("'resetPassword':"), isFalse);
    expect(
      sync.contains("'postesAffectes': _sauveteurPostes.toList()"),
      isTrue,
    );
    expect(
      sync.contains("'periodesSurveillance': _sauveteurPeriodesSurveillance"),
      isTrue,
    );
  });

  test('Edition : aucun ancien mot de passe provisoire reutilise', () {
    final edit = section(
      admin,
      'void _openSauveteurForEditing(',
      'Future<void> _deleteSauveteur(',
    );
    expect(edit.contains("_sauveteurGeneratedPassword = '';"), isTrue);
    expect(edit.contains("data['temporaryPassword']"), isFalse);
    expect(edit.contains('_sauveteurGeneratedLogin ='), isTrue);
  });

  test('Recuperation explicite du mot de passe toujours disponible', () {
    final login = File('lib/map/profil_login_page.dart').readAsStringSync();
    expect(login.contains('MOT DE PASSE OUBLIÉ ?'), isTrue);
    expect(login.contains('PasswordRecoveryRequestPage('), isTrue);
    final server = File('functions/index.js').readAsStringSync();
    final upsert = section(
      server,
      'exports.upsertSauveteurAccount = onRequest(',
      'exports.changeSauveteurPassword = onRequest(',
    );
    expect(upsert.contains('data.resetPassword === true'), isTrue);
    expect(upsert.contains('if (temporaryPassword &&'), isTrue);
  });
}
