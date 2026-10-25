import 'package:flutter/material.dart';

import '../services/odoo_local_order_service.dart';
import '../../shared/web_colors.dart';

/// Test local Odoo uniquement : facture liée à la commande SPHOT existante.
/// Aucun paiement, email, déploiement Firebase ou activation de campagne.
class AdvertiserOdooLocalInvoiceSection extends StatefulWidget {
  const AdvertiserOdooLocalInvoiceSection({
    super.key,
    required this.requestId,
    this.readOnly = false,
  });

  final String requestId;
  final bool readOnly;

  @override
  State<AdvertiserOdooLocalInvoiceSection> createState() =>
      _AdvertiserOdooLocalInvoiceSectionState();
}

class _AdvertiserOdooLocalInvoiceSectionState
    extends State<AdvertiserOdooLocalInvoiceSection> {
  final _service = const OdooLocalOrderService();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _invoice;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!OdooLocalOrderService.enabled) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.invoiceStatus(widget.requestId);
      if (!mounted) return;
      setState(() {
        _order = status['order'] is Map
            ? Map<String, dynamic>.from(status['order'] as Map)
            : null;
        _invoice = status['invoice'] is Map
            ? Map<String, dynamic>.from(status['invoice'] as Map)
            : null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createInvoice() async {
    if (_order == null || _submitting || _invoice != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FACTURE ODOO — TEST LOCAL'),
        content: const Text(
          'Odoo va créer et valider une facture de TEST liée à la commande '
          'SPHOT déjà confirmée. Aucun email, aucun paiement bancaire '
          'et aucune campagne active ne seront déclenchés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CRÉER LA FACTURE TEST'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _service.createInvoice(widget.requestId);
      if (!mounted) return;
      setState(() {
        _order = Map<String, dynamic>.from(result['order'] as Map);
        _invoice = Map<String, dynamic>.from(result['invoice'] as Map);
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _euro(dynamic cents) {
    final value = cents is num ? cents / 100 : 0;
    return '${value.toStringAsFixed(2)} €';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD97706)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'FACTURATION ODOO — ENVIRONNEMENT LOCAL DE TEST',
            style: TextStyle(color: WebColors.blue, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text('Facture liée à la commande SPHOT. '
              'Aucun paiement réel ni activation publicitaire.'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_order == null)
            const Text('La commande Odoo doit être confirmée '
                'dans DEVIS & COMMANDE avant la facturation.'),
          if (_order != null) ...[
            const SizedBox(height: 10),
            Text('COMMANDE ODOO : ${_order!['odooOrderName']}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            if (_invoice == null && !widget.readOnly && !_loading) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _createInvoice,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.receipt_long_outlined),
                label: Text(_submitting
                    ? 'FACTURATION EN COURS…'
                    : 'CRÉER LA FACTURE TEST DANS ODOO'),
              ),
            ],
          ],
          if (_invoice != null) ...[
            const SizedBox(height: 10),
            Text('FACTURE ODOO : ${_invoice!['odooInvoiceName']}',
                style: const TextStyle(color: WebColors.blue,
                    fontWeight: FontWeight.w900)),
            Text('STATUT : ${_invoice!['state']}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('MONTANT HT : ${_euro(_invoice!['amountUntaxedCents'])}'),
            Text('TVA ODOO : ${_euro(_invoice!['amountTaxCents'])}'),
            Text('TOTAL TTC : ${_euro(_invoice!['amountTotalCents'])}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text('PAIEMENT : ${_invoice!['paymentState']}'),
            const Text('Campagne non activée.'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: WebColors.red,
                fontWeight: FontWeight.w800)),
          ],
          TextButton.icon(
            onPressed: _submitting ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('ACTUALISER LE STATUT ODOO'),
          ),
        ],
      ),
    );
  }
}
