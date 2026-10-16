import 'package:flutter/material.dart';

import '../../../services/published_commercial_quote_service.dart';

/// Présentation du dossier commercial ENREGISTRÉ, sans création de devis.
/// Aucun document officiel, numéro DV, email ou écriture Firestore.
void showAdminQuoteDraftPreview({
  required BuildContext context,
  required Map<String, dynamic> data,
}) {
  String str(dynamic value) => value?.toString().trim() ?? '';
  String money(num value) =>
      value.toStringAsFixed(2).replaceAll('.', ',') + ' €';

  final rawIds = data['selectedRescueStationIds'];
  final selectedIds = rawIds is Iterable
      ? rawIds.whereType<String>().where((id) => id.trim().isNotEmpty).toSet()
      : <String>{};
  final storedStations = data['selectedRescueStations'];
  final stationNames = <String, String>{};
  if (storedStations is Iterable) {
    for (final entry in storedStations) {
      if (entry is! Map) continue;
      final id = str(entry['spotDocumentId']);
      if (!selectedIds.contains(id)) continue;
      final publicId = str(entry['idSphot']);
      final name = str(entry['name']);
      stationNames[id] = [publicId, name]
          .where((part) => part.isNotEmpty)
          .join(' — ');
    }
  }
  final names = selectedIds
      .map((id) => stationNames[id]?.isNotEmpty == true
          ? stationNames[id]!
          : 'Poste à identifier : ' + id)
      .toList()..sort();
  final reference = str(data['administrativeReference']);
  final buyer = str(data['billingOrganisation']);
  final siret = str(data['billingSiret']);
  final address = [
    str(data['billingAddress']),
    [
      str(data['billingPostalCode']),
      str(data['billingCity']),
    ].where((part) => part.isNotEmpty).join(' '),
    str(data['billingCountry']),
  ].where((part) => part.isNotEmpty).join(', ');
  final email = str(data['billingContactEmail']);

  // Même grille publiée que l'écran OFFRE. Pas de montant client réutilisé.
  // Un appel distinct à chaque ouverture évite un ancien prix mis en cache.
  final future = selectedIds.isEmpty
      ? null
      : const PublishedCommercialQuoteService()
          .admin(numberOfRescueStations: selectedIds.length);

  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPHOT — APERÇU DU DEVIS',
            style: TextStyle(
              color: Color(0xFFDC2626),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'BROUILLON NON CONTRACTUEL — AUCUN DEVIS ÉMIS',
            style: TextStyle(
              color: Color(0xFFF59E0B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 590,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                reference.isEmpty
                    ? 'Référence administrative non renseignée'
                    : 'Dossier administratif : ' + reference,
                style: const TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'ÉMETTEUR',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                'SPHOT — immatriculation et situation fiscale à finaliser.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
              ),
              const Divider(height: 26),
              const Text(
                'ORGANISME PAYEUR (INFORMATIONS DÉCLARÉES)',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              SelectableText(
                [
                  buyer.isEmpty ? 'Organisme non renseigné' : buyer,
                  if (siret.isNotEmpty) 'SIRET : ' + siret,
                  if (address.isNotEmpty) address,
                  if (email.isNotEmpty) 'Contact : ' + email,
                ].join('\n'),
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
              const Divider(height: 26),
              const Text(
                'POSTES DE SECOURS ENREGISTRÉS',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              for (final name in names)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ' + name,
                      style: const TextStyle(fontSize: 12)),
                ),
              if (names.isEmpty)
                const Text(
                  'Aucun poste enregistré.',
                  style: TextStyle(color: Color(0xFFDC2626)),
                ),
              const Divider(height: 26),
              if (future != null)
                FutureBuilder<PublishedCommercialQuote>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text(
                        'Tarif publié indisponible. Aucun montant ne peut '
                        'être affiché pour cet aperçu.',
                        style: TextStyle(color: Color(0xFFDC2626)),
                      );
                    }
                    final quote = snapshot.data;
                    if (quote == null) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(15),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final rawLines = quote.details['lines'];
                    final lines = rawLines is List ? rawLines : const [];
                    if (lines.isEmpty) {
                      return const Text(
                        'Le détail du tarif publié est indisponible.',
                        style: TextStyle(color: Color(0xFFDC2626)),
                      );
                    }
                    const tiers = [
                      '1er poste',
                      'Du 2e au 4e poste',
                      'Du 5e au 9e poste',
                      'À partir du 10e poste',
                    ];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'TARIFICATION — ' + quote.pricingReference,
                          style: const TextStyle(
                            color: Color(0xFF1E3A8A),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final entry in lines)
                          if (entry is Map &&
                              entry['tier'] is num &&
                              entry['count'] is num &&
                              (entry['count'] as num) > 0 &&
                              entry['unitExclTax'] is num &&
                              entry['amountExclTax'] is num)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                (entry['tier'] as num).toInt() >= 1 &&
                                        (entry['tier'] as num).toInt() <= 4
                                    ? tiers[(entry['tier'] as num).toInt() - 1] +
                                        ' : ' + str(entry['count']) +
                                        ' × ' + money(entry['unitExclTax'] as num) +
                                        ' = ' + money(entry['amountExclTax'] as num)
                                    : 'Tranche : ' +
                                        money(entry['amountExclTax'] as num),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        const Divider(height: 22),
                        Text(
                          'TOTAL ANNUEL ESTIMATIF HT : ' +
                              money(quote.amountExclTax),
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'TVA et montant TTC : non déterminés. '
                          'Aucun montant à payer n’est confirmé.',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 16),
              const Text(
                'Cet aperçu utilise les informations enregistrées du dossier '
                'et la grille de prix publiée. Les identités, les postes et '
                'la fiscalité ne sont pas certifiés ici. '
                'Il n’a ni numéro de devis, ni date d’émission, ni valeur '
                'contractuelle. Aucun PDF officiel n’est généré ou envoyé.',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('FERMER'),
        ),
      ],
    ),
  );
}
