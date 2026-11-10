import 'dart:async';

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
  String cguContent = 'Texte juridique de test.',
}) {
  PublicLegalDocument document(String id, String title, int revision) {
    return PublicLegalDocument(
      id: id,
      title: title,
      version: '1.0',
      revision: revision,
      chapters: [
        PublicLegalChapter(
          title: 'Article de démonstration',
          content: id == 'cgu' ? cguContent : 'Texte juridique de test.',
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

Widget _testApp(
  List<PublicLegalDocument> documents, {
  Future<List<PublicLegalDocument>> Function()? loadDocuments,
}) {
  return MaterialApp(
    home: PublicLegalGate(
      loadDocuments: loadDocuments ?? () async => documents,
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

  test('les versions historiques des notices sont compatibles sans révision', () {
    final privacy = PublicLegalDocument.resolveVersion(
      'privacyPolicy',
      {'version': '2.4'},
    );
    expect(privacy.version, '2.4');
    expect(privacy.revision, -1);

    final rgpd = PublicLegalDocument.resolveVersion(
      'rgpdNotice',
      {},
      globalVersion: '2.5',
    );
    expect(rgpd.version, '2.5');
    expect(rgpd.revision, -1);

    expect(
      () => PublicLegalDocument.resolveVersion(
        'cgu',
        {'version': '2.5'},
        globalVersion: '2.5',
      ),
      throwsStateError,
    );
    expect(
      () => PublicLegalDocument.resolveVersion('privacyPolicy', {}),
      throwsStateError,
    );
    expect(
      PublicLegalDocument.resolveVersion('cgu', {'version': '2.5', 'revision': 3}),
      (version: '2.5', revision: 3),
    );
  });

  testWidgets('une notice historique affiche sa version sans fausse révision',
      (tester) async {
    await tester.pumpWidget(_testApp(_documents(privacyRevision: -1)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Politique de confidentialité'));
    await tester.pumpAndSettle();

    expect(find.text('Version 1.0 — édition historique'), findsOneWidget);
    await tester.tap(find.text('FERMER'));
    await tester.pumpAndSettle();
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

    await tester.tap(find.text('CGU'));
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

  testWidgets('les CGU affichent le gras Markdown sans perdre la sélection',
      (tester) async {
    await tester.pumpWidget(_testApp(
      _documents(cguContent: 'Texte **juridique** de test.'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CGU'));
    await tester.pumpAndSettle();

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(selectable.textSpan?.toPlainText(), 'Texte juridique de test.');

    final spans = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is! TextSpan) return;
      spans.add(span);
      for (final child in span.children ?? <InlineSpan>[]) {
        collect(child);
      }
    }
    collect(selectable.textSpan!);
    expect(
      spans.any((span) =>
          span.text == 'juridique' &&
          span.style?.fontWeight == FontWeight.w700),
      isTrue,
    );
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

  testWidgets('rafraîchissement accepté : aucun volet de chargement fugace',
      (tester) async {
    await const PublicLegalAcceptanceService().accept(
      const PublicLegalVersions(
        cgu: '1.0:r1',
        privacyPolicy: '1.0:r1',
        rgpdNotice: '1.0:r1',
      ),
    );

    final pending = Completer<List<PublicLegalDocument>>();
    await tester.pumpWidget(
      _testApp(_documents(), loadDocuments: () => pending.future),
    );
    await tester.pump();

    expect(find.text('BIENVENUE SUR SPHOT'), findsNothing);
    expect(
      find.text('Vérification des documents juridiques publiés…'),
      findsNothing,
    );
    expect(find.byKey(const Key('public-legal-access-barrier')), findsOneWidget);
    expect(find.text('CARTE SPHOT DE TEST'), findsOneWidget);

    pending.complete(_documents());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('public-legal-access-barrier')), findsNothing);
    expect(find.text('BIENVENUE SUR SPHOT'), findsNothing);
  });

  testWidgets('les CGU révisées réapparaissent après vérification silencieuse',
      (tester) async {
    await const PublicLegalAcceptanceService().accept(
      const PublicLegalVersions(
        cgu: '1.0:r1',
        privacyPolicy: '1.0:r1',
        rgpdNotice: '1.0:r1',
      ),
    );

    final pending = Completer<List<PublicLegalDocument>>();
    await tester.pumpWidget(
      _testApp(_documents(), loadDocuments: () => pending.future),
    );
    await tester.pump();
    expect(find.text('BIENVENUE SUR SPHOT'), findsNothing);

    pending.complete(_documents(cguRevision: 2));
    await tester.pumpAndSettle();
    expect(find.text('BIENVENUE SUR SPHOT'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
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
