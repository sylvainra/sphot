import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bathing_spots_app/web/super_admin/widgets/sphot_dropdown_visuals.dart';
import 'package:bathing_spots_app/web/super_admin/widgets/super_admin_annual_financial_export_card.dart';

void main() {
  testWidgets('Le menu Exercice utilise une liste SPHOT avec sélection',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 500,
          child: SuperAdminAnnualFinancialExportCard(),
        ),
      ),
    ));

    final current = DateTime.now().year;
    expect(find.text(current.toString()), findsOneWidget);

    await tester.tap(find.text(current.toString()));
    await tester.pumpAndSettle();

    expect(find.text((current - 1).toString()), findsOneWidget);
    expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);

    // Le popup doit être joint au bas du sélecteur, et non flottant sous lui.
    final fieldRect = tester.getRect(find.byType(InputDecorator));
    final popupFinder = find.byWidgetPredicate((widget) =>
        widget is Container &&
        widget.decoration == SphotDropdownVisuals.popupDecoration);
    expect(popupFinder, findsOneWidget);
    final popupRect = tester.getRect(popupFinder);
    expect(popupRect.top, lessThan(fieldRect.bottom));
    expect(popupRect.width, closeTo(fieldRect.width, 1.5));
    expect(fieldRect.width, greaterThan(240));

    await tester.tap(find.text((current - 1).toString()));
    await tester.pumpAndSettle();

    expect(find.text((current - 1).toString()), findsOneWidget);
    expect(find.byIcon(Icons.check_box_rounded), findsNothing);
  });
}
