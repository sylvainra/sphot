import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/published_commercial_quote_service.dart';

/// Étape de paiement ADMIN : aperçu ergonomique uniquement.
/// Aucun numéro de carte n'est collecté et aucune transaction n'est lancée.
/// Le raccordement au devis et au prestataire de paiement sera réalisé
/// après validation des règles de facturation internationale.
class AdminPaymentPanel extends StatefulWidget {
  const AdminPaymentPanel({
    super.key,
    required this.adminUid,
    required this.onClose,
  });

  final String adminUid;
  final VoidCallback onClose;

  @override
  State<AdminPaymentPanel> createState() => _AdminPaymentPanelState();
}

class _AdminPaymentPanelState extends State<AdminPaymentPanel> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  String _method = 'card';
  final Map<int, Future<PublishedCommercialQuote>> _quoteFutures = {};


  /// Apercu des prix PUBLIES uniquement : aucune ecriture commerciale.
  Widget _publishedAdminQuotePreview() {
    final uid = widget.adminUid.trim();
    if (uid.isEmpty) {
      return const Text(
        'Identifiant Admin indisponible : estimation impossible.',
        style: TextStyle(color: _red, fontSize: 12),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(uid)
          .snapshots(),
      builder: (context, subscriptionSnapshot) {
        if (subscriptionSnapshot.hasError) {
          return const Text(
            'La sélection des postes de secours est inaccessible.',
            style: TextStyle(color: _red, fontSize: 12),
          );
        }
        if (!subscriptionSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = subscriptionSnapshot.data?.data() ??
            const <String, dynamic>{};
        final value = data['numberOfRescueStations'];
        final stations = value is num ? value.toInt() : 0;
        if (stations <= 0) {
          return const Text(
            'Sélectionnez et enregistrez vos postes de secours dans '
            'l’étape ABONNEMENT pour afficher le nouveau devis indicatif.',
            style: TextStyle(color: _red, fontSize: 12),
          );
        }
        final future = _quoteFutures.putIfAbsent(
          stations,
          () => const PublishedCommercialQuoteService()
              .admin(numberOfRescueStations: stations),
        );
        return FutureBuilder<PublishedCommercialQuote>(
          future: future,
          builder: (context, quoteSnapshot) {
            if (quoteSnapshot.hasError) {
              return Text(
                'Devis indicatif indisponible : ${quoteSnapshot.error}',
                style: const TextStyle(color: _red, fontSize: 12),
              );
            }
            final quote = quoteSnapshot.data;
            if (quote == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final lines = quote.details['lines'] is List
                ? quote.details['lines'] as List
                : const [];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'APERÇU DES TARIFS PUBLIÉS · ${quote.pricingReference}',
                    style: const TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$stations poste${stations > 1 ? "s" : ""} de secours',
                    style: const TextStyle(
                      color: _blue, fontSize: 12, fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final line in lines)
                    if (line is Map && (line['count'] as num?) != null &&
                        (line['count'] as num) > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Tranche ${line["tier"]} · ${line["count"]} × '
                          '${line["unitExclTax"]} € = '
                          '${line["amountExclTax"]} € HT',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  const Divider(),
                  Text(
                    'TOTAL INDICATIF : ${quote.amountExclTax} € HT / an',
                    style: const TextStyle(
                      color: _red, fontWeight: FontWeight.w900, fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Lecture de la version publiée. Aucun devis contractuel '
                    'ni montant à payer n’est encore confirmé. TVA et '
                    'conditions de facturation seront vérifiées séparément.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _methodTile({
    required String value,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final selected = _method == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _method = value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected ? _blue.withOpacity(0.06) : Colors.white,
            border: Border.all(
              color: selected ? _blue : const Color(0xFFCED9E8),
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: _blue, size: 27),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? _red : _blue,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 540,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        border: Border(left: BorderSide(color: _blue.withOpacity(0.25), width: 1.5)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
              child: Row(
                children: [
                  const Icon(Icons.credit_card, color: _blue, size: 27),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'PAIEMENT SPHOT ADMIN',
                      style: TextStyle(
                        color: _blue, fontSize: 19, fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, color: _blue),
                    tooltip: 'Fermer le paiement',
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E7),
                        border: Border.all(color: const Color(0xFFEDC974)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'ÉTAPE DE TEST — Aucun paiement réel et aucune écriture Firebase.',
                        style: TextStyle(
                          color: Color(0xFF775B13),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '1. OFFRE ET DEVIS',
                      style: TextStyle(color: _blue, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'L’abonnement annuel et les postes de secours concernés '
                      'sont sélectionnés dans l’étape ABONNEMENT. '
                      'Le paiement utilisera le montant exact du devis confirmé, '
                      'calculé avec les tarifs dégressifs publiés et la fiscalité '
                      'applicable au pays de facturation.',
                      style: TextStyle(
                        fontSize: 13, height: 1.45, color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _publishedAdminQuotePreview(),
                    const SizedBox(height: 12),
                    const Text(
                      'Montant à payer : en attente du devis confirmé',
                      style: TextStyle(
                        color: _red, fontSize: 13, fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Divider(height: 28),
                    const Text(
                      '2. MODE DE PAIEMENT',
                      style: TextStyle(color: _blue, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    _methodTile(
                      value: 'card',
                      icon: Icons.credit_card,
                      title: 'CARTE BANCAIRE',
                      description:
                          'Paiement en ligne sécurisé. Stripe Checkout est '
                          'le prestataire envisagé, avec prise en charge '
                          'des devises et pays éligibles.',
                    ),
                    const SizedBox(height: 10),
                    _methodTile(
                      value: 'invoice',
                      icon: Icons.receipt_long,
                      title: 'FACTURATION / COMMANDE PUBLIQUE',
                      description:
                          'Conservation du circuit administratif de facturation '
                          'et de paiement applicable à l’organisme.',
                    ),
                    const Divider(height: 28),
                    const Text(
                      '3. VALIDATION ET ACTIVATION',
                      style: TextStyle(color: _blue, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Le règlement par carte devra être confirmé côté serveur '
                      'avant toute activation payante. Les huit jours d’essai, '
                      'les dates d’abonnement et les conditions de renouvellement '
                      'restent distincts de cette étape de paiement.',
                      style: TextStyle(
                        fontSize: 13, height: 1.45, color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.lock_outline),
                      label: Text(
                        _method == 'card'
                            ? 'PAIEMENT CB — EN ATTENTE DU RACCORDEMENT'
                            : 'FACTURATION — EN ATTENTE DU RACCORDEMENT',
                        textAlign: TextAlign.center,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Ce bouton restera désactivé pendant la phase d’essai '
                      'de l’interface. Aucune donnée bancaire n’est saisie ici.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
