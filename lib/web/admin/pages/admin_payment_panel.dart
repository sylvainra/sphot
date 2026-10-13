import 'package:flutter/material.dart';

/// Étape de paiement ADMIN : aperçu ergonomique uniquement.
/// Aucun numéro de carte n'est collecté et aucune transaction n'est lancée.
/// Le raccordement au devis et au prestataire de paiement sera réalisé
/// après validation des règles de facturation internationale.
class AdminPaymentPanel extends StatefulWidget {
  const AdminPaymentPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<AdminPaymentPanel> createState() => _AdminPaymentPanelState();
}

class _AdminPaymentPanelState extends State<AdminPaymentPanel> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  String _method = 'card';

  Widget _methodTile({
    required String value,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final selected = _method == value;
    return InkWell(
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
