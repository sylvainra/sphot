import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/web/admin/services/admin_cgv_live_service.dart';
import 'package:bathing_spots_app/web/admin/widgets/admin_cgv_acceptance_section.dart';

AdminCgvLiveDocument _document(int revision) => AdminCgvLiveDocument(
  version: '1.1',
  revision: revision,
  chapters: List.generate(13, (index) => AdminCgvLiveChapter(
    title: 'Article ${index + 1}',
    content: 'Texte complet de l’article ${index + 1}',
    order: index + 1,
  )),
);

void main() {
  testWidgets('lecture obligatoire puis case non précochée', (tester) async {
    final controller = StreamController<AdminCgvLiveDocument>();
    addTearDown(controller.close);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 380,
            child: AdminCgvAcceptanceSection(documentStream: controller.stream),
          ),
        ),
      ),
    ));

    controller.add(_document(2));
    await tester.pumpAndSettle();
    var checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile));
    expect(checkbox.value, false);
    expect(checkbox.onChanged, isNull);

    await tester.tap(find.text('CONSULTER LES 13 ARTICLES'));
    await tester.pumpAndSettle();
    expect(find.text('Article 1'), findsOneWidget);
    expect(find.textContaining('Version 1.1 · Révision 2'), findsWidgets);
    await tester.tap(find.text('FERMER'));
    await tester.pumpAndSettle();

    checkbox = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(checkbox.onChanged, isNotNull);
    expect(checkbox.value, false);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    checkbox = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(checkbox.value, true);

    // Une version nouvellement publiée n'hérite jamais de l'accord précédent.
    controller.add(_document(3));
    await tester.pumpAndSettle();
    checkbox = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(checkbox.value, false);
    expect(checkbox.onChanged, isNull);
  });

  testWidgets('erreur de publication : aucune case proposée', (tester) async {
    final controller = StreamController<AdminCgvLiveDocument>();
    addTearDown(controller.close);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AdminCgvAcceptanceSection(documentStream: controller.stream),
      ),
    ));
    controller.addError(StateError('Non publié'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.textContaining('Aucune acceptation'), findsOneWidget);
  });
}
