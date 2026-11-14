import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Identification : profil SAUVETEUR refusé sur Web avant mot de passe', () {
    final source = File('lib/map/profil_login_page.dart').readAsStringSync();
    final identity = source.substring(
      source.indexOf('Future<void> _continueWithIdentifier()'),
      source.indexOf('Future<Map<String, dynamic>?> _tryLogin('),
    );
    expect(identity.contains("accountTypes.contains('SAUVETEUR')"), isTrue);
    expect(identity.contains('if (kIsWeb &&'), isTrue);
    expect(identity.contains('_step = 0;'), isTrue);
    expect(identity.contains('_passwordController.clear();'), isTrue);
    expect(identity.contains('SPHOT SAUVETEUR est réservé'), isTrue);
  });

  test('Identification : profils professionnels et Super Admin Web uniquement', () {
    final source = File('lib/map/profil_login_page.dart').readAsStringSync();
    final identity = source.substring(
      source.indexOf('Future<void> _continueWithIdentifier()'),
      source.indexOf('Future<Map<String, dynamic>?> _tryLogin('),
    );
    expect(identity.contains("accountTypes.contains('SUPER_ADMIN')"), isTrue);
    expect(identity.contains("accountTypes.contains('ADMIN')"), isTrue);
    expect(identity.contains("accountTypes.contains('ANNONCEUR')"), isTrue);
    expect(identity.contains('if (!kIsWeb &&'), isTrue);
    expect(identity.contains('réservé au site Web'), isTrue);
  });
}
