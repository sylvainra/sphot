import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('La connexion ADMIN ne force pas la validation des CGU', () {
    final dashboard = File('lib/web/admin/pages/admin_dashboard_page.dart')
        .readAsStringSync();
    expect(dashboard.contains('ProfessionalLegalGate('), isFalse);
    expect(dashboard.contains('_buildDashboardContent(context)'), isTrue);
  });

  test('La demande d’accès garde les CGU ADMIN versionnées', () {
    final registration =
        File('lib/web/admin/pages/admin_trial_request_page.dart')
            .readAsStringSync();
    expect(registration.contains("loadLegalDoc('adminCgu')"), isTrue);
    expect(registration.contains("'acceptedDocuments':"), isTrue);
    expect(registration.contains("'documentVersions':"), isTrue);
  });

  test('La phase commerciale conserve la section CGV ADMIN', () {
    final subscription =
        File('lib/web/admin/pages/admin_subscription_panel.dart')
            .readAsStringSync();
    expect(subscription.contains('AdminCgvAcceptanceSection()'), isTrue);
    expect(subscription.contains("'CONFIRMER MA COMMANDE'"), isTrue);
  });

  test('La fonction de preuve professionnelle reste disponible', () {
    final endpoint = File('functions-legal/index.js').readAsStringSync();
    expect(endpoint.contains('exports.acceptSphotProfessionalLegal'), isTrue);
  });
}
