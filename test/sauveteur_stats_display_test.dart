import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/pages/sauveteur/sauveteur_stats_page.dart')
        .readAsStringSync();
  });

  test('Les trois compteurs restent distincts de la rubrique FAITS', () {
    final start = source.indexOf('Widget _dayCard(_DailyStats stats)');
    final end = source.indexOf('Future<Uint8List> _buildPdf()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final card = source.substring(start, end);
    expect(card, contains('stats.facts.entries.where((entry)'));
    expect(card, contains("type != 'incident'"));
    expect(card, contains("type != 'intervention'"));
    expect(card, contains("type != 'personne recherchée'"));
    expect(card, contains('else if (factEntries.isNotEmpty)'));
    expect(card, contains('_eventRow(stats.summary)'));
    expect(card, contains('stats.rescueQualifications.isNotEmpty'));
  });

  test('Compteurs lisibles et adaptés aux téléphones étroits', () {
    final start = source.indexOf('Widget _eventCount({');
    final end = source.indexOf('Widget _eventRow(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final counter = source.substring(start, end);
    expect(counter, contains('fontSize: 16'));
    expect(counter, contains('fontSize: 10.5'));
    expect(counter, contains('crossAxisAlignment: CrossAxisAlignment.stretch'));
    expect(counter, contains('FittedBox('));
    expect(counter, contains('BoxFit.scaleDown'));
  });

  test('Navigation rapide vers les bilans et export conservé', () {
    expect(source, contains('Scrollable.ensureVisible('));
    expect(source, contains('_monthlySummaryKey.currentContext'));
    expect(source, contains("'VOIR LES BILANS'"));
    expect(source, contains('key: _monthlySummaryKey'));
    expect(source, contains("title: 'BILAN MENSUEL'"));
    expect(source, contains("title: 'BILAN SAISONNIER '"));
    expect(source, contains("'PARTAGER'"));
  });

  test('Pas de navigation vers un mois futur', () {
    expect(source, contains('bool get _canGoToNextMonth'));
    expect(
      source,
      contains('if (target.isAfter(DateTime(now.year, now.month))) return;'),
    );
    expect(source, contains('onPressed: _canGoToNextMonth ?'));
  });

  test('Les bilans et le PDF conservent les recherches distinctes', () {
    expect(source, contains('final searches = <String>{};'));
    expect(source, contains('searches.add(caseId.isNotEmpty'));
    expect(source, contains('Bilan de saison '));
    expect(source, contains('Recherches distinctes : '));
    expect(source, contains('Autres faits : aucun'));
  });
}
