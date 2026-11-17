import 'dart:io';

import 'package:bathing_spots_app/web/shared/admin_legal_overlay.dart';
import 'package:flutter/material.dart';
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
        r'child:\s*_buildDashboardContent\(context\),\s*'
        r'lockedDashboard:\s*_buildAdminLegalBackdrop\(\),\s*\);',
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

  test('Le panneau CGU ADMIN conserve les 14 articles et le consentement', () {
    final gate = File('lib/web/shared/professional_legal_gate.dart')
        .readAsStringSync();
    expect(gate.contains("if (widget.documentId == 'adminCgu')"), isTrue);
    expect(gate.contains('AdminLegalOverlay('), isTrue);
    expect(gate.contains('...widget.chapters.map((chapter)'), isTrue);
    expect(gate.contains('SphotLegalArticleMarkdown('), isTrue);
    expect(gate.contains("'action': 'accept'"), isTrue);
    expect(gate.contains("'versionId': widget.versionId"), isTrue);
    expect(gate.contains('_required = false;'), isTrue);
    // La branche annonceur et son affichage historique restent inchangés.
    expect(gate.contains("backgroundColor: const Color(0xFFF3F6FA)"),
        isTrue);
  });

  test('L’écran ADMIN cible automatiquement les corrections sans '
      'masquer les CGU complètes', () {
    final gate = File('lib/web/shared/professional_legal_gate.dart')
        .readAsStringSync();
    expect(gate.contains("result['adminChanges']"), isTrue);
    expect(gate.contains('...changes.map(_adminChangedArticle)'), isTrue);
    expect(gate.contains('SphotLegalArticleMarkdown(markdown: after)'),
        isTrue);
    expect(gate.contains('Consulter l’ancienne rédaction'), isTrue);
    expect(gate.contains('CONSULTER LES'), isTrue);
    expect(gate.contains('if (full)'), isTrue);
    expect(gate.contains('...widget.chapters.map((chapter)'), isTrue);
    expect(gate.contains('j’accepte l’intégralité des CGU SPHOT ADMIN'),
        isTrue);
  });

  test('Le volet de modifications reste compact sur la carte Admin', () {
    final overlay = File('lib/web/shared/admin_legal_overlay.dart')
        .readAsStringSync();
    expect(overlay.contains('Alignment.centerRight'), isTrue);
    expect(overlay.contains('maxWidth: 620'), isTrue);
    expect(overlay.contains('AbsorbPointer('), isTrue);
    expect(overlay.contains('ExcludeFocus('), isTrue);
    expect(overlay.contains('ExcludeSemantics('), isTrue);
    expect(overlay.contains('dismissible: false'), isTrue);
    final dashboard = File('lib/web/admin/pages/admin_dashboard_page.dart')
        .readAsStringSync();
    expect(dashboard.contains('_buildDashboardContent(context)'), isTrue);
  });

  testWidgets('La carte et les cinq étapes Admin restent visibles '
      'mais non interactives avant acceptation', (tester) async {
    var backgroundClicks = 0;
    var panelClicks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: AdminLegalOverlay(
          dashboard: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: TextButton(
                onPressed: () => backgroundClicks++,
                child: const Text('CARTE ET CINQ ETAPES ADMIN'),
              ),
            ),
          ),
          fullHeight: false,
          panel: Center(
            child: FilledButton(
              onPressed: () => panelClicks++,
              child: const Text('ACCEPTER LES CGU'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('CARTE ET CINQ ETAPES ADMIN'), findsOneWidget);
    expect(find.text('ACCEPTER LES CGU'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AdminLegalOverlay),
        matching: find.byType(ModalBarrier),
      ),
      findsOneWidget,
    );
    expect(find.byType(ExcludeFocus), findsOneWidget);
    expect(find.byType(PopScope), findsOneWidget);

    await tester.tap(
      find.text('CARTE ET CINQ ETAPES ADMIN'),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(backgroundClicks, 0);
    expect(panelClicks, 0);

    await tester.tap(find.text('ACCEPTER LES CGU'));
    await tester.pump();
    expect(panelClicks, 1);
  });

  test('La carte réelle et les étapes Admin restent visibles '
      'sans flux Firestore pendant le verrou CGU', () {
    final dashboard = File('lib/web/admin/pages/admin_dashboard_page.dart')
        .readAsStringSync();
    final gate = File('lib/web/shared/professional_legal_gate.dart')
        .readAsStringSync();

    expect(dashboard.contains('Widget _buildAdminLegalBackdrop()'), isTrue);
    final backdropStart =
        dashboard.indexOf('Widget _buildAdminLegalBackdrop()');
    final backdropEnd = dashboard.indexOf(
        'Widget _buildDashboardContent(BuildContext context)', backdropStart);
    final backdrop = dashboard.substring(backdropStart, backdropEnd);
    expect(backdrop.contains('_buildRightPanel('), isTrue);
    expect(backdrop.contains('FlutterMap('), isTrue);
    expect(backdrop.contains('TileLayer('), isTrue);
    expect(backdrop.contains('lockedDashboard: _buildAdminLegalBackdrop()'),
        isTrue);
    // Vrais composants du dashboard, pas une maquette en texte.
    for (final step in <String>[
      'CRÉER UN SPHOT',
      'CRÉER UNE PÉRIODE',
      'CRÉER UN SAUVETEUR',
      'ESPACE SPHOT ADMIN',
      'ESSAI GRATUIT 8 JOURS',
    ]) {
      expect(dashboard.contains(step), isTrue);
    }
    expect(gate.contains('dashboard: widget.lockedDashboard ?? widget.child'),
        isTrue);
    expect(gate.contains('if (!_loading && _error == null && !_required) '
        'return widget.child;'), isTrue);
    expect(gate.contains('widget.audience == ProfessionalLegalAudience.admin'),
        isTrue);
    expect(gate.contains('lockedDashboard: widget.audience == '
        'ProfessionalLegalAudience.admin'), isTrue);
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
