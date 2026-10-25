import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/web_colors.dart';
import '../services/odoo_local_order_service.dart';

/// Troisième achat local, réservé au prestataire Stripe SANDBOX d'Odoo.
/// Le navigateur ne déclare jamais lui-même un paiement réussi.
/// Aucune campagne ou donnée Firebase n'est modifiée.
class AdvertiserOdooStripeTestSection extends StatefulWidget {
  const AdvertiserOdooStripeTestSection({
    super.key,
    required this.requestId,
  });

  final String requestId;

  @override
  State<AdvertiserOdooStripeTestSection> createState() =>
      _AdvertiserOdooStripeTestSectionState();
}

class _AdvertiserOdooStripeTestSectionState
    extends State<AdvertiserOdooStripeTestSection> {
  final _service = const OdooLocalOrderService();
  bool _loading = true;
  bool _submitting = false;
  bool _refreshing = false;
  bool _paymentConfirmed = false;
  String? _error;
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _invoice;
  List<Map<String, dynamic>> _transactions = [];
  Uri? _portalLink;
  Timer? _pollTimer;
  int _pollAttempts = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _euro(Object? cents) {
    final value = cents is num ? cents / 100 : 0;
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_submitting || _refreshing) return;
    _refreshing = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final status = await _service.stripeTestStatus(widget.requestId);
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
        _paymentConfirmed = status['paymentConfirmed'] == true;
        // The private invoice link is valid only for the current checkout.
        _portalLink = null;
        _error = null;
      });
      if (_paymentConfirmed) _pollTimer?.cancel();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString()
            .replaceFirst('Bad state: ', ''));
      }
    } finally {
      _refreshing = false;
      if (mounted && !silent) setState(() => _loading = false);
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
    if (!await _confirm('TROISIÈME ACHAT ODOO — STRIPE TEST',
        'Créer une nouvelle commande de test pour BLUE SURF SCHOOL, '
        'avec le prix Odoo historique ? Les commandes et factures '
        'précédentes seront conservées. Aucun paiement et aucune '
        'campagne active à cette étape.')) return;
    if (mounted) await _act(() => _service.stripeTestConfirm(widget.requestId));
  }

  Future<void> _newInvoice() async {
    if (!await _confirm('FACTURE ODOO — STRIPE TEST',
        'Odoo créera et validera une facture distincte, non réglée. '
        'Aucun paiement, email ni activation publicitaire.')) return;
    if (mounted) await _act(() => _service.stripeTestInvoice(widget.requestId));
  }

  Future<void> _preparePayment() async {
    if (_loading || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final url = await _service.stripeTestCheckout(widget.requestId);
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
      if (!opened) {
        if (mounted) setState(() => _error = 'Portail Odoo indisponible.');
        return;
      }
      // Odoo receives Stripe's webhook. SPHOT only polls Odoo's verified
      // transaction state; no secret or Stripe webhook is sent to Flutter.
      _pollTimer?.cancel();
      _pollAttempts = 0;
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        _pollAttempts++;
        if (!mounted || _paymentConfirmed || _pollAttempts >= 60) {
          timer.cancel();
        } else {
          unawaited(_refresh(silent: true));
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Le portail Odoo local ne s’ouvre pas.');
      }
    }
  }

  String _transactionLabel(Map<String, dynamic> tx) =>
      switch (tx['state']) {
        'done' => 'TRANSACTION STRIPE REÇUE — VÉRIFICATION ODOO',
        'pending' => 'TRANSACTION STRIPE TEST EN ATTENTE',
        'authorized' => 'TRANSACTION STRIPE TEST AUTORISÉE',
        'error' => 'TRANSACTION STRIPE TEST REFUSÉE',
        'cancel' => 'TRANSACTION STRIPE TEST ANNULÉE',
        _ => 'TRANSACTION STRIPE TEST : ${tx['state'] ?? 'inconnue'}',
      };

  @override
  Widget build(BuildContext context) {
    final latest = _transactions.isEmpty ? null : _transactions.first;
    final blocked = _transactions.any((tx) =>
        ['done', 'pending', 'authorized'].contains(tx['state']));
    final canPay = _invoice?['state'] == 'posted' &&
        _invoice?['paymentState'] == 'not_paid' &&
        _invoice?['odooPaymentRecorded'] != true && !blocked;

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF059669)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ACHAT N° 3 — PAIEMENT STRIPE TEST',
              style: TextStyle(color: WebColors.blue,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Stripe SANDBOX via Odoo local. Cartes fictives '
              'uniquement. Aucun débit bancaire réel, aucune campagne active.'),
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
              label: const Text('CRÉER LA TROISIÈME COMMANDE DE TEST'),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text('COMMANDE : ${_order!['odooOrderName']}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text('MONTANT HT : ${_euro(_order!['odooUntaxedCents'])}'),
            Text('TOTAL TTC : ${_euro(_order!['odooTotalCents'])}'),
            if (_invoice == null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _newInvoice,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('CRÉER LA FACTURE STRIPE TEST'),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Text('FACTURE : ${_invoice!['odooInvoiceName']}',
                  style: const TextStyle(color: WebColors.blue,
                      fontWeight: FontWeight.w900)),
              Text('TOTAL TTC : ${_euro(_invoice!['amountTotalCents'])}'),
              Text('PAIEMENT ODOO : ${_invoice!['paymentState']}'),
              if (latest != null) ...[
                const SizedBox(height: 8),
                Text(_paymentConfirmed
                    ? 'TRANSACTION STRIPE TEST CONFIRMÉE — AUCUN DÉBIT'
                    : _transactionLabel(latest),
                    style: const TextStyle(color: WebColors.blue,
                        fontWeight: FontWeight.w900)),
                Text('Référence de test : ${latest['reference'] ?? '—'}'),
              ],
              if (_invoice!['paymentState'] == 'paid' && !_paymentConfirmed)
                const Text('Odoo indique une facture payée, mais la preuve '
                    'Stripe TEST complète n’est pas encore confirmée.'),
              if (canPay) ...[
                const SizedBox(height: 12),
                if (_portalLink == null)
                  FilledButton.icon(
                    onPressed: _submitting ? null : _preparePayment,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('PRÉPARER LE PAIEMENT STRIPE TEST'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _openPayment,
                    icon: const Icon(Icons.payment_outlined),
                    label: const Text('OUVRIR LE PORTAIL ODOO — STRIPE TEST'),
                  ),
                const SizedBox(height: 6),
                const Text('Dans Odoo, utiliser uniquement une carte fictive '
                    'Stripe. Le statut sera actualisé automatiquement '
                    'après le retour ici.',
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
            onPressed: _submitting ? null : () => _refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('ACTUALISER LA TRANSACTION STRIPE TEST'),
          ),
          const Text('ACTIVATION PUBLICITAIRE INTERDITE — TEST UNIQUEMENT',
              textAlign: TextAlign.center,
              style: TextStyle(color: WebColors.red, fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
