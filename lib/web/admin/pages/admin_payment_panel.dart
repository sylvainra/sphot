import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../widgets/adaptive_asset_image.dart';

import '../../../services/published_commercial_quote_service.dart';
import '../services/admin_station_pricing_preview.dart';

/// Aperçu de tarification SPHOT ADMIN : aucun règlement, aucune écriture.
/// La création des devis contractuels sera raccordée séparément.
class AdminPaymentPanel extends StatefulWidget {
  const AdminPaymentPanel({
    super.key,
    required this.adminUid,
    required this.availableRescueStationIds,
    required this.onClose,
    this.rescueStationNames = const <String, String>{},
  });

  final String adminUid;
  final Map<String, String> rescueStationNames;
  final List<String> availableRescueStationIds;
  final VoidCallback onClose;

  @override
  State<AdminPaymentPanel> createState() => _AdminPaymentPanelState();
}

class _AdminPaymentPanelState extends State<AdminPaymentPanel> {
  static const _blue = Color(0xFF1E3A8A);
  static const _muted = Color(0xFF64748B);
  static const _border = Color(0xFFD5DFEC);
  static const _canvas = Color(0xFFF5F7FA);

  final Map<int, Future<PublishedCommercialQuote>> _quoteFutures = {};
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _subscriptionStream;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _subscriptionStream = FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(widget.adminUid.trim())
        .snapshots();
  }

  @override
  void didUpdateWidget(covariant AdminPaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adminUid != widget.adminUid) {
      _quoteFutures.clear();
      _subscribe();
    }
  }

  String _money(num amount) => NumberFormat.currency(
        locale: 'fr_FR',
        symbol: '€',
        decimalDigits: 2,
      ).format(amount);

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  Widget _sectionHeading(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 19, color: _blue),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: _blue,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _notice(String message) => _card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: _blue, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _publishedAdminQuotePreview() {
    final uid = widget.adminUid.trim();
    if (uid.isEmpty) {
      return _notice('Administrateur non identifié : estimation impossible.');
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _subscriptionStream,
      builder: (context, subscriptionSnapshot) {
        if (subscriptionSnapshot.hasError) {
          return _notice(
            'Impossible de consulter le dossier de cette collectivité. '
            'Aucun montant ne peut être confirmé.',
          );
        }
        if (!subscriptionSnapshot.hasData) {
          return _card(
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final data =
            subscriptionSnapshot.data?.data() ?? const <String, dynamic>{};
        final preview = AdminStationPricingPreview.resolve(
          availableSpotIds: widget.availableRescueStationIds,
          subscription: data,
        );
        if (preview.availableCount == 0) {
          return _notice(
            'Aucun poste de secours référencé pour cette collectivité. '
            'La simulation tarifaire est indisponible.',
          );
        }
        if (preview.unmatchedSavedCount > 0) {
          return _notice(
            'La sélection enregistrée contient '
            '${preview.unmatchedSavedCount} poste(s) introuvable(s) dans '
            'le territoire. Actualisez la sélection dans '
            'ABONNEMENT → OFFRE ET DEVIS.',
          );
        }
        final stations = preview.quotedCount;
        if (stations <= 0) {
          return _notice(
            'Aucun poste de secours sélectionné : estimation indisponible.',
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
              return _notice(
                'La grille tarifaire publiée est temporairement '
                'indisponible. Aucun montant n’est affiché.',
              );
            }
            final quote = quoteSnapshot.data;
            if (quote == null) {
              return _card(
                child: const Center(child: CircularProgressIndicator()),
              );
            }

            final rawLines = quote.details['lines'];
            final lines = rawLines is List ? rawLines : const [];
            final saved = preview.hasSavedSelection;
            final rawSelected = data['selectedRescueStationIds'];
            final selectedIds = rawSelected is Iterable
                ? rawSelected.whereType<String>().toSet()
                : <String>{};
            final stationNames = widget.availableRescueStationIds
                .where((id) => !saved || selectedIds.contains(id))
                .map((id) {
                  final name = widget.rescueStationNames[id]?.trim() ?? '';
                  return name.isEmpty ? id : name;
                })
                .toList()
              ..sort((first, second) => first.compareTo(second));

            return _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Postes de Secours sollicités',
                    style: TextStyle(
                      color: _blue, fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  for (final name in stationNames)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Color(0xFF334155), fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Grille tarifaire utilisée',
                    style: TextStyle(
                      color: _blue, fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    quote.pricingReference,
                    style: const TextStyle(
                      color: Color(0xFF334155), fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Divider(height: 27),
                  const Text(
                    'TARIFICATION',
                    style: TextStyle(
                      color: _blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 11),
                  for (final line in lines)
                    if (line is Map &&
                        line['count'] is num &&
                        (line['count'] as num) > 0 &&
                        line['unitExclTax'] is num &&
                        line['amountExclTax'] is num)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _tierLine(line),
                      ),
                  const Divider(height: 23, color: _border),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'TOTAL ANNUEL HT',
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      Text(
                        _money(quote.amountExclTax),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Avant TVA et fiscalité applicable. Aucun devis contractuel '
                    'ni montant à payer confirmé.',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 11,
                      height: 1.35,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _tierLine(Map<dynamic, dynamic> line) {
    final tier = line['tier'];
    final label = switch (tier) {
      1 => '1er Poste de Secours',
      2 => 'De 2 à 4 Postes de Secours',
      3 => 'De 5 à 9 Postes de Secours',
      4 => 'À partir du 10e Poste de Secours',
      _ => 'Tranche',
    };
    final count = (line['count'] as num).toInt();
    final unit = line['unitExclTax'] as num;
    final amount = line['amountExclTax'] as num;

    // Conserver les montants calculés par la grille commerciale publiée.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.none,
                  ),
                ),
                if (tier != 1) ...[
                  const SizedBox(height: 3),
                  Text(
                    '$count × ${_money(unit)}',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _money(amount),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _blue,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethod({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _canvas,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: _blue, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        const Icon(Icons.lock_outline_rounded, color: _muted, size: 19),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: _blue.withOpacity(0.45), width: 1.5),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    Transform.translate(
                      offset: const Offset(-12, 0),
                      child: Transform.scale(
                        scale: 1.5,
                        alignment: Alignment.center,
                        child: AdaptiveAssetImage(
                          'data/icons/fire_red_icon.svg',
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'PAIEMENT',
                        style: TextStyle(
                          color: _blue,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: _blue.withOpacity(0.20)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _publishedAdminQuotePreview(),
                    const SizedBox(height: 14),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeading(
                            'MODE DE RÈGLEMENT',
                            Icons.account_balance_wallet_outlined,
                          ),
                          const SizedBox(height: 16),
                          _paymentMethod(
                            icon: Icons.credit_card_outlined,
                            title: 'CARTE BANCAIRE',
                            detail: 'Paiement sécurisé en ligne '
                                'indisponible pendant cette phase de test.',
                          ),
                          const Divider(height: 27),
                          _paymentMethod(
                            icon: Icons.receipt_long_outlined,
                            title: 'FACTURATION / COMMANDE PUBLIQUE',
                            detail: 'Circuit administratif et Chorus Pro '
                                'à raccorder après validation du devis.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _notice(
                      'ÉTAPE DE TEST — Aucun paiement réel et aucune '
                      'écriture commerciale. Le devis devra être confirmé '
                      'avec les données de facturation et la fiscalité '
                      'applicable. L’essai gratuit et l’activation '
                      'de l’abonnement restent des étapes distinctes.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
