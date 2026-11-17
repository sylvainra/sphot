import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Le portail ADMIN impose les CGU publiées avant le dashboard', () {
    final dashboard = File('lib/web/admin/pages/admin_dashboard_page.dart')
        .readAsStringSync();
    expect(
      dashboard.contains("import '../../shared/professional_legal_gate.dart';"),
      isTrue,
    );
    expect(
      RegExp(
        r'Widget build\(BuildContext context\)\s*=>\s*'
        r'ProfessionalLegalGate\(\s*'
        r'audience:\s*ProfessionalLegalAudience\.admin,\s*'
        r'child:\s*_buildDashboardContent\(context\),\s*\);',
      ).hasMatch(dashboard),
      isTrue,
    );
    expect(dashboard.contains('ProfessionalLegalAudience.advertiser'), isFalse);
  });

  test('La réacceptation ADMIN ne modifie pas le portail PUBLICITAIRE', () {
    final advertiser =
        File('lib/web/advertiser/pages/advertiser_dashboard_page.dart')
            .readAsStringSync();
    expect(
      advertiser.contains('ProfessionalLegalAudience.advertiser'),
      isTrue,
    );
    expect(advertiser.contains('if (!widget.approvedAccess) return dashboard;'),
        isTrue);
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
