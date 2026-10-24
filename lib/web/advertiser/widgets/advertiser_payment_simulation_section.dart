import 'package:flutter/material.dart';

import '../../shared/web_colors.dart';
import '../services/odoo_simulation_service.dart';

/// Démonstration locale du parcours commercial, jamais un moyen de paiement.
class AdvertiserPaymentSimulationSection extends StatefulWidget {
  const AdvertiserPaymentSimulationSection({
    super.key,
    required this.territory,
    required this.offer,
    required this.duration,
    required this.planningComplete,
    required this.publishedPricingReference,
    required this.publishedPayableExclTaxCents,
  });

  final String? territory;
  final String? offer;
  final String? duration;
  final bool planningComplete;
  final String? publishedPricingReference;
  final int publishedPayableExclTaxCents;

  @override
  State<AdvertiserPaymentSimulationSection> createState() =>
      _AdvertiserPaymentSimulationSectionState();
}

class _AdvertiserPaymentSimulationSectionState
    extends State<AdvertiserPaymentSimulationSection> {
  static const OdooSimulationService _service = OdooSimulationService();
  static int _sessionCounter = 0;

  late String _sessionKey = _newSessionKey();
  OdooSimulationResult? _result;
  int _attemptCount = 0;
  bool _loading = false;
  String? _error;

  static String _newSessionKey() {
    _sessionCounter++;
    return 'UI${DateTime.now().microsecondsSinceEpoch}$_sessionCounter';
  }

  bool get _canSimulate =>
      widget.territory != null &&
      widget.offer != null &&
      widget.duration != null &&
      widget.planningComplete;

  Map<String, dynamic> _object(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Map<String, dynamic> get _simulation =>
      _result?.simulation ?? <String, dynamic>{};

  Map<String, dynamic> get _order => _object(_simulation['order']);
  Map<String, dynamic> get _invoice => _object(_simulation['invoice']);

  String _euro(Object? value) {
    final cents = value is num ? value.toInt() : 0;
    final sign = cents < 0 ? '-' : '';
    final absolute = cents.abs();
    return '$sign${absolute ~/ 100},'
        '${(absolute % 100).toString().padLeft(2, '0')} €';
  }

  String get _zoneLabel => switch (widget.territory) {
    'radius_5km' => '5 km',
    'radius_15km' => '15 km',
    'radius_50km' => '50 km',
    'radius_150km' => '150 km',
    'radius_300km' => '300 km',
    'country' => 'PAYS ENTIER',
    _ => 'À définir',
  };

  String get _offerLabel => switch (widget.offer) {
    'map' => 'CARTE SPHOT',
    'premium' => 'FICHES SPHOT',
    'pack' => 'PACK VISIBILITÉ TOTALE',
    _ => 'À définir',
  };

  String get _paymentLabel => switch (
      _simulation['simulatedPaymentStatus']) {
    'simulated_success' =>
      'PAIEMENT RÉUSSI EN SIMULATION — AUCUN ENCAISSEMENT',
    'simulated_failure' => 'PAIEMENT REFUSÉ EN SIMULATION — RETENTATIVE POSSIBLE',
    'simulated_pending' => 'PAIEMENT EN ATTENTE EN SIMULATION',
    _ => 'AUCUN PAIEMENT SIMULÉ',
  };

  Future<void> _perform(String action, {String? outcome}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final attemptKey = outcome == null
          ? null
          : 'ATTEMPT-${_sessionKey}-${++_attemptCount}';
      final next = await _service.perform(
        action: action,
        sessionKey: _sessionKey,
        territory: widget.territory,
        offer: widget.offer,
        duration: widget.duration,
        outcome: outcome,
        attemptKey: attemptKey,
      );
      if (!mounted) return;
      setState(() => _result = next);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('FormatException: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reset() {
    if (_loading) return;
    setState(() {
      _sessionKey = _newSessionKey();
      _attemptCount = 0;
      _result = null;
      _error = null;
    });
  }

  Widget _stepButton(String label, VoidCallback action) {
    return ElevatedButton(
      onPressed: _loading ? null : action,
      style: ElevatedButton.styleFrom(
        backgroundColor: WebColors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF4B5F97)),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: WebColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!OdooSimulationService.enabled) return const SizedBox.shrink();

    final orderStatus = _order['status'];
    final invoiceStatus = _invoice['status'];
    final paymentStatus = _simulation['simulatedPaymentStatus'];
    final canPay = invoiceStatus == 'simulated_posted' &&
        (paymentStatus == 'not_started' ||
            paymentStatus == 'simulated_failure');
    final amountsDiffer = _result != null &&
        widget.publishedPricingReference != null &&
        (widget.publishedPricingReference !=
                _simulation['pricingReference'] ||
            widget.publishedPayableExclTaxCents !=
                _simulation['untaxedCents']);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD97706), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.science_outlined, color: Color(0xFF92400E)),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'SIMULATION ODOO — AUCUN PAIEMENT RÉEL',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Parcours de démonstration : commande, facture et résultat de '
            'paiement fictifs. Tarifs de référence V1, remise fictive 0 %, '
            'TVA illustrative 20 %. Aucune donnée n’est envoyée à Odoo, '
            'Stripe ou Firestore. La campagne reste inactive.',
            style: TextStyle(color: Color(0xFF78350F), height: 1.4),
          ),
          const SizedBox(height: 12),
          _line('Zone choisie', _zoneLabel),
          _line('Visibilité choisie', _offerLabel),
          _line('Durée choisie', widget.duration ?? 'À définir'),
          if (!_canSimulate) ...[
            const SizedBox(height: 12),
            const Text(
              'Pour essayer ce parcours, définissez la zone, la diffusion '
              'et validez la planification dans les étapes précédentes.',
              style: TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (_result == null && _canSimulate) ...[
            const SizedBox(height: 12),
            _stepButton(
              '1. CRÉER LA COMMANDE FICTIVE',
              () => _perform('create'),
            ),
          ],
          if (_result != null) ...[
            const Divider(height: 28),
            _line('Référence SPHOT fictive',
                '${_simulation['sphotReference'] ?? '—'}'),
            _line('Commande fictive', '${_order['reference'] ?? '—'}'),
            _line('Facture fictive', '${_invoice['reference'] ?? '—'}'),
            _line('Montant HT simulé', _euro(_simulation['untaxedCents'])),
            _line('TVA simulée (20 %)', _euro(_simulation['simulatedTaxCents'])),
            _line('Total TTC simulé', _euro(_simulation['simulatedTotalCents'])),
            _line('Solde simulé', _euro(_simulation['simulatedAmountDueCents'])),
            if (amountsDiffer) ...[
              const SizedBox(height: 9),
              const Text(
                'Attention : ce tarif de démonstration diffère du devis '
                'indicatif SPHOT affiché. Il ne le remplace pas et ne '
                'constitue pas une commande réelle.',
                style: TextStyle(
                  color: WebColors.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _paymentLabel,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            if (orderStatus == 'simulated_draft')
              _stepButton('2. CONFIRMER LA COMMANDE FICTIVE',
                  () => _perform('confirm_order')),
            if (orderStatus == 'simulated_confirmed' && _invoice.isEmpty)
              _stepButton('3. CRÉER LA FACTURE FICTIVE',
                  () => _perform('invoice_draft')),
            if (invoiceStatus == 'simulated_draft')
              _stepButton('4. CONFIRMER LA FACTURE FICTIVE',
                  () => _perform('confirm_invoice')),
            if (canPay) ...[
              const Text(
                '5. CHOISIR LE RÉSULTAT DU PAIEMENT FICTIF',
                style: TextStyle(
                  color: WebColors.blue,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _stepButton('SIMULER RÉUSSITE',
                      () => _perform('payment', outcome: 'success')),
                  _stepButton('SIMULER REFUS',
                      () => _perform('payment', outcome: 'failure')),
                  _stepButton('SIMULER ATTENTE',
                      () => _perform('payment', outcome: 'pending')),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _loading ? null : _reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('RECOMMENCER UNE NOUVELLE SIMULATION'),
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_result != null)
              TextButton.icon(
                onPressed: _loading ? null : () => _perform('status'),
                icon: const Icon(Icons.refresh),
                label: const Text('ACTUALISER LA SIMULATION LOCALE'),
              ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Le résultat « réussi » ne prouve aucun règlement et '
            'ne déclenche aucune diffusion publicitaire.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF78350F),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
