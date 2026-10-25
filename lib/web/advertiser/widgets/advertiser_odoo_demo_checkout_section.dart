import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/web_colors.dart';
import '../services/odoo_local_order_service.dart';

/// Deuxième achat strictement local : portail Odoo et prestataire Démo natif.
/// Aucune information bancaire n'est saisie ici, aucun accès Firebase modifié.
class AdvertiserOdooDemoCheckoutSection extends StatefulWidget {
  const AdvertiserOdooDemoCheckoutSection({
    super.key,
    required this.requestId,
  });

  final String requestId;

  @override
  State<AdvertiserOdooDemoCheckoutSection> createState() =>
      _AdvertiserOdooDemoCheckoutSectionState();
}

class _AdvertiserOdooDemoCheckoutSectionState
    extends State<AdvertiserOdooDemoCheckoutSection> {
  final _service = const OdooLocalOrderService();
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _invoice;
  List<Map<String, dynamic>> _transactions = [];
  Uri? _portalLink;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  String _euro(Object? cents) {
    final value = cents is num ? cents / 100 : 0;
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Future<void> _refresh() async {
    if (_submitting) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.demoStatus(widget.requestId);
      if (!mounted) return;
      setState(() {
        _order = status['order'] is Map
            ? Map<String, dynamic>.from(status['order'] as Map) : null;
        _invoice = status['invoice'] is Map
            ? Map<String, dynamic>.from(status['invoice'] as Map) : null;
        _transactions = status['transactions'] is List
            ? (status['transactions'] as List)
                .whereType<Map>()
                .map((tx) => Map<String, dynamic>.from(tx))
                .toList() : [];
        // A previously generated link must never be reused after refresh.
        _portalLink = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString()
            .replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('CONFIRMER LE TEST'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() operation) async {
    if (_loading || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString()
            .replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (mounted && _error == null) await _refresh();
  }

  Future<void> _newOrder() async {
    if (!await _confirm('DEUXIÈME ACHAT ODOO — TEST',
        'Créer une nouvelle commande Odoo liée au même compte BLUE SURF '
        'SCHOOL, avec le tarif enregistré pour la première commande ? '
        'S00001 et FAC/2026/00001 resteront inchangées. '
        'Aucune facture et aucun paiement ne seront créés à cette étape.')) {
      return;
    }
    if (mounted) await _act(() => _service.demoConfirm(widget.requestId));
  }

  Future<void> _newInvoice() async {
    if (!await _confirm('NOUVELLE FACTURE ODOO — DÉMO',
        'Odoo va créer et valider UNE facture non réglée pour la '
        'deuxième commande de test. Aucun email, aucun encaissement '
        'et aucune campagne active ne seront déclenchés.')) {
      return;
    }
    if (mounted) await _act(() => _service.demoInvoice(widget.requestId));
  }

  Future<void> _preparePayment() async {
    if (_loading || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final url = await _service.demoCheckout(widget.requestId);
      if (mounted) setState(() => _portalLink = url);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString()
            .replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openPayment() async {
    final url = _portalLink;
    if (url == null) return;
    try {
      final opened = await launchUrl(url, webOnlyWindowName: '_blank');
      if (!opened && mounted) {
        setState(() => _error = 'Impossible d’ouvrir le portail Odoo local.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Le portail Odoo local ne s’ouvre pas.');
      }
    }
  }

  String _transactionLabel(Map<String, dynamic> tx) =>
      switch (tx['state']) {
        'done' => 'TRANSACTION DÉMO CONFIRMÉE — AUCUN DÉBIT',
        'pending' => 'TRANSACTION DÉMO EN ATTENTE',
        'authorized' => 'TRANSACTION DÉMO AUTORISÉE EN TEST',
        'error' => 'TRANSACTION DÉMO REFUSÉE',
        'cancel' => 'TRANSACTION DÉMO ANNULÉE',
        _ => 'TRANSACTION DÉMO : ${tx['state'] ?? 'inconnue'}',
      };

  @override
  Widget build(BuildContext context) {
    final latestTransaction = _transactions.isEmpty ? null : _transactions.first;
    final paid = _invoice != null &&
        ['paid', 'in_payment'].contains(_invoice!['paymentState']);
    final blocked = latestTransaction != null &&
        ['done', 'pending', 'authorized'].contains(latestTransaction['state']);
    final canPay = _invoice?['state'] == 'posted' &&
        _invoice?['paymentState'] == 'not_paid' && !blocked;

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B82F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ACHAT N° 2 — PAIEMENT DÉMO NATIF ODOO',
              style: TextStyle(color: WebColors.blue,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Même annonceur BLUE SURF SCHOOL. Nouvelle commande '
              'et nouvelle facture de TEST indépendantes du premier achat. '
              'Aucun paiement réel et aucune activation publicitaire.'),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_order == null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submitting ? null : _newOrder,
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('CRÉER LA DEUXIÈME COMMANDE DE TEST'),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text('COMMANDE : ${_order!['odooOrderName']}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text('STATUT : ${_order!['odooState']}'),
            Text('MONTANT HT : ${_euro(_order!['odooUntaxedCents'])}'),
            Text('TOTAL TTC : ${_euro(_order!['odooTotalCents'])}'),
            if (_invoice == null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _newInvoice,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('CRÉER LA FACTURE DÉMO DANS ODOO'),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Text('FACTURE : ${_invoice!['odooInvoiceName']}',
                  style: const TextStyle(color: WebColors.blue,
                      fontWeight: FontWeight.w900)),
              Text('TOTAL TTC : ${_euro(_invoice!['amountTotalCents'])}'),
              Text('PAIEMENT ODOO : ${_invoice!['paymentState']}'),
              if (latestTransaction != null) ...[
                const SizedBox(height: 8),
                Text(_transactionLabel(latestTransaction),
                    style: const TextStyle(color: WebColors.blue,
                        fontWeight: FontWeight.w900)),
                Text('Référence de test : '
                    '${latestTransaction['reference'] ?? '—'}'),
              ],
              if (paid)
                const Text('Odoo signale un règlement. Aucun nouveau '
                    'paiement ne doit être lancé sur cette facture.'),
              if (canPay) ...[
                const SizedBox(height: 12),
                if (_portalLink == null)
                  FilledButton.icon(
                    onPressed: _submitting ? null : _preparePayment,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('PRÉPARER LE PORTAIL PAIEMENT ODOO'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _openPayment,
                    icon: const Icon(Icons.payment_outlined),
                    label: const Text('OUVRIR LE PAIEMENT DÉMO ODOO'),
                  ),
                const SizedBox(height: 6),
                const Text('La nouvelle fenêtre Odoo doit proposer '
                    'le moyen Démo. Sélectionne le résultat souhaité '
                    'dans Odoo, puis reviens ici et actualise.',
                    style: TextStyle(fontSize: 12)),
              ],
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: WebColors.red,
                fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _submitting ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('ACTUALISER LA TRANSACTION ODOO DÉMO'),
          ),
          const Text('Ce test ne prouve aucun encaissement réel. '
              'La campagne reste inactive.',
              textAlign: TextAlign.center,
              style: TextStyle(color: WebColors.red, fontSize: 12)),
        ],
      ),
    );
  }
}
