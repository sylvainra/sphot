import 'package:flutter/material.dart';

import '../services/sphot_odoo_billing_status_service.dart';

/// Consultation Odoo : ne confirme aucune commande et n'active aucun droit.
class SphotOdooBillingStatusCard extends StatefulWidget {
  const SphotOdooBillingStatusCard({
    super.key,
    required this.market,
    required this.requestId,
  });

  final String market;
  final String requestId;

  @override
  State<SphotOdooBillingStatusCard> createState() =>
      _SphotOdooBillingStatusCardState();
}

class _SphotOdooBillingStatusCardState
    extends State<SphotOdooBillingStatusCard> {
  static const _blue = Color(0xFF1E3A8A);
  final _service = const SphotOdooBillingStatusService();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _status;

  String _amount(int cents) {
    final euros = cents / 100;
    return '${euros.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await _service.read(
        market: widget.market,
        requestId: widget.requestId,
      );
      if (mounted) setState(() => _status = status);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message.toString()
            : 'Consultation impossible.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ne crée aucun appel vers un point d'entrée non publié ou non configuré.
    if (!SphotOdooBillingStatusService.configured) {
      return const SizedBox.shrink();
    }
    final status = _status;
    final state = status?['status'];
    final amountTotal = status?['amountTotalCents'];
    final residual = status?['amountResidualCents'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: _blue.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('COMMANDES ET FACTURES ODOO',
            style: TextStyle(fontWeight: FontWeight.w900, color: _blue,
                fontSize: 12)),
          const SizedBox(height: 8),
          if (state == null)
            const Text('Consultez le statut de votre dossier de facturation.'),
          if (state == 'not_linked')
            const Text('Aucune commande commerciale Odoo liée à ce dossier.'),
          if (state == 'order_pending')
            const Text('Commande en cours de rapprochement dans Odoo.'),
          if (state == 'order_found' || state == 'invoice_found') ...[
            Text('Commande : ${status?['orderNumber'] ?? '—'}'),
            if (state == 'invoice_found') ...[
              Text('Facture : ${status?['invoiceNumber'] ?? '—'}'),
              Text('État : ${status?['invoiceState'] ?? '—'}'),
              Text('Règlement : ${status?['paymentState'] ?? '—'}'),
              if (amountTotal is int)
                Text('Montant TTC : ${_amount(amountTotal)}'),
              if (residual is int)
                Text('Solde restant : ${_amount(residual)}'),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _busy ? null : _refresh,
            icon: _busy
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('ACTUALISER LES FACTURES'),
          ),
          const Text('Consultation uniquement : un statut Odoo ne vaut pas '
            'activation d’abonnement ni de campagne.',
            style: TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }
}
