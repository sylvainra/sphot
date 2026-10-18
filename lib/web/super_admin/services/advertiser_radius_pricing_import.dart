/// Saisie groupée du catalogue SPHOT PUBLICITAIRE.
/// 6 zones × 3 offres × 6 durées = 108 montants HT en euros.
class AdvertiserRadiusPricingImport {
  const AdvertiserRadiusPricingImport._();

  static const zones = [
    '5 km', '15 km', '50 km', '150 km', '300 km', 'PAYS ENTIER',
  ];
  static const offers = [
    'CARTE SPHOT', 'FICHES SPHOT', 'PACK TOTAL',
  ];
  static const durations = [
    '1 semaine', '2 semaines', '1 mois',
    '2 mois', '6 mois', '1 an',
  ];

  static const header =
      'Zone;Offre;1 semaine;2 semaines;1 mois;2 mois;6 mois;1 an';

  /// Modèle volontairement VIDE : aucun prix historique n'est réemployé
  /// ou attribué automatiquement aux nouveaux rayons.
  static String get blankTemplate => [
    header,
    for (final zone in zones)
      for (final offer in offers) '$zone;$offer;;;;;;',
  ].join('\n');

  /// Chaque ligne est identifiée par une zone et une offre.
  /// Import total et atomique : refuse les valeurs manquantes, doublons,
  /// prix non entiers ou catégories inconnues.
  static Map<String, int> parse(String input) {
    final lines = input.replaceAll('\r\n', '\n').trim().split('\n');
    if (lines.isEmpty || lines.first.trim() != header) {
      throw const FormatException(
        'En-tête attendu : Zone;Offre;1 semaine;2 semaines;'
        '1 mois;2 mois;6 mois;1 an',
      );
    }
    final result = <String, int>{};
    final seenRows = <String>{};
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(';').map((cell) => cell.trim()).toList();
      if (parts.length != 8) {
        throw const FormatException(
          'Chaque ligne doit contenir une zone, une offre et 6 tarifs HT.',
        );
      }
      final zone = zones.indexOf(parts[0]);
      final offer = offers.indexOf(parts[1]);
      if (zone == -1 || offer == -1) {
        throw FormatException(
          'Zone ou offre inconnue : ${parts[0]} / ${parts[1]}',
        );
      }
      final rowId = '$zone:$offer';
      if (!seenRows.add(rowId)) {
        throw FormatException('Ligne présente plusieurs fois : $rowId');
      }
      for (var duration = 0; duration < durations.length; duration++) {
        final cell = parts[duration + 2];
        if (!RegExp(r'^[0-9]+$').hasMatch(cell)) {
          throw FormatException(
            'Tarif HT invalide : ${parts[0]}, ${parts[1]}, '
            '${durations[duration]}',
          );
        }
        final amount = int.tryParse(cell);
        if (amount == null || amount < 1 || amount > 10000000) {
          throw FormatException(
            'Le tarif HT doit être compris entre 1 et 10 000 000 €.',
          );
        }
        result['$zone:$offer:$duration'] = amount;
      }
    }
    if (seenRows.length != zones.length * offers.length ||
        result.length != 108) {
      throw FormatException(
        'Grille incomplète : ${result.length} / 108 tarifs. '
        'Aucun prix n’a été importé.',
      );
    }
    return Map<String, int>.unmodifiable(result);
  }

  /// Export du brouillon courant pour reprise dans un tableur.
  /// Une grille partiellement renseignée reste exportable, mais pas
  /// importable ni publiable.
  static String export(Map<String, String> values) => [
    header,
    for (var z = 0; z < zones.length; z++)
      for (var o = 0; o < offers.length; o++)
        [
          zones[z],
          offers[o],
          for (var d = 0; d < durations.length; d++)
            values['$z:$o:$d'] ?? '',
        ].join(';'),
  ].join('\n');
}
