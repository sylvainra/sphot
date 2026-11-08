import 'package:bathing_spots_app/map/public_legal_gate.dart';
import 'package:bathing_spots_app/services/public_legal_acceptance_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<PublicLegalDocument> _documents({
  int cguRevision = 1,
  int privacyRevision = 1,
  int rgpdRevision = 1,
}) {
  PublicLegalDocument document(String id, String title, int revision) {
    return PublicLegalDocument(
      id: id,
      title: title,
      version: '1.0',
      revision: revision,
      chapters: const [
        PublicLegalChapter(
          title: 'Article de démonstration',
          content: 'Texte juridique de test.',
          order: 1,
        ),
      ],
    );
  }

  return [
    document('cgu', 'Conditions Générales d’Utilisation', cguRevision),
    document('privacyPolicy', 'Politique de confidentialité', privacyRevision),
    document('rgpdNotice', 'Notice RGPD', rgpdRevision),
  ];
}

Widget _testApp(List<PublicLegalDocument> documents) {
  return MaterialApp(
    home: PublicLegalGate(
      loadDocuments: () async => documents,
      child: const Scaffold(
        body: Center(child: Text('CARTE SPHOT DE TEST')),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('les notices communes historiques sont reconnues comme actives', () {
    const legacy = <String, dynamic>{'version': '1.0', 'revision': 1};
    expect(PublicLegalDocument.isEligibleLiveDocument('privacyPolicy', legacy),
        isTrue);
    expect(PublicLegalDocument.isEligibleLiveDocument('rgpdNotice', legacy),
        isTrue);
    expect(PublicLegalDocument.isEligibleLiveDocument('cgu', legacy), isFalse);
    expect(
      PublicLegalDocument.isEligibleLiveDocument(
        'cgu',
        {'published': true, 'testOnly': false},
      ),
      isTrue,
    );
    expect(
      PublicLegalDocument.isEligibleLiveDocument(
        'privacyPolicy',
        {'published': false},
      ),
      isFalse,
    );
    expect(
      PublicLegalDocument.isEligibleLiveDocument(
        'rgpdNotice',
        {'testOnly': true},
      ),
      isFalse,
    );
  });

  testWidgets('première visite : textes accessibles et case obligatoire',
      (tester) async {
    await tester.pumpWidget(_testApp(_documents()));
    await tester.pumpAndSettle();

    expect(find.text('BIENVENUE SUR SPHOT'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    final continueButton =
        find.widgetWithText(FilledButton, 'ACCEPTER ET CONTINUER');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

    await tester.tap(find.text('CGU — Grand public'));
    await tester.pumpAndSettle();
    expect(find.text('Article de démonstration'), findsOneWidget);
    expect(find.text('Version 1.0 — révision 1'), findsOneWidget);
    await tester.tap(find.text('FERMER'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(find.text('BIENVENUE SUR SPHOT'), findsNothing);
    expect(find.text('CARTE SPHOT DE TEST'), findsOneWidget);
  });

  testWidgets('visite suivante : accès direct à la carte', (tester) async {
    await const PublicLegalAcceptanceService().accept(
      const PublicLegalVersions(
        cgu: '1.0:r1',
        privacyPolicy: '1.0:r1',
        rgpdNotice: '1.0:r1',
      ),
    );

    await tester.pumpWidget(_testApp(_documents()));
    await tester.pumpAndSettle();

    expect(find.text('BIENVENUE SUR SPHOT'), findsNothing);
    expect(find.text('CARTE SPHOT DE TEST'), findsOneWidget);
  });

  testWidgets('nouvelle notice RGPD : information sans nouvelle case',
      (tester) async {
    await const PublicLegalAcceptanceService().accept(
      const PublicLegalVersions(
        cgu: '1.0:r1',
        privacyPolicy: '1.0:r1',
        rgpdNotice: '1.0:r1',
      ),
    );

    await tester.pumpWidget(_testApp(_documents(rgpdRevision: 2)));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.text('J’AI COMPRIS'));
    await tester.pumpAndSettle();
    expect(find.text('BIENVENUE SUR SPHOT'), findsNothing);
  });

  testWidgets('nouvelle CGU : nouvelle acceptation nécessaire', (tester) async {
    await const PublicLegalAcceptanceService().accept(
      const PublicLegalVersions(
        cgu: '1.0:r1',
        privacyPolicy: '1.0:r1',
        rgpdNotice: '1.0:r1',
      ),
    );

    await tester.pumpWidget(_testApp(_documents(cguRevision: 2)));
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsOneWidget);
    final continueButton =
        find.widgetWithText(FilledButton, 'ACCEPTER ET CONTINUER');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
  });

  testWidgets('écran mobile étroit : fenêtre défilable et bouton accessible',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp(_documents()));
    await tester.pumpAndSettle();

    expect(find.text('BIENVENUE SUR SPHOT'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    final continueButton =
        find.widgetWithText(FilledButton, 'ACCEPTER ET CONTINUER');
    await tester.ensureVisible(continueButton);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('CARTE SPHOT DE TEST'), findsOneWidget);
  });
}
