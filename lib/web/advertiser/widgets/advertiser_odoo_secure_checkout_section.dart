import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/web_colors.dart';
import '../services/odoo_local_order_service.dart';

/// Nouveau parcours Odoo anti-doublons : base locale NEUTRALISÉE uniquement.
/// Aucune validation Super Admin supplémentaire, écriture Firebase ou
/// activation de campagne. Le paiement est exclusivement Stripe Sandbox.
class AdvertiserOdooSecureCheckoutSection extends StatefulWidget {
  const AdvertiserOdooSecureCheckoutSection({
    super.key,
    required this.requestId,
    this.readOnly = false,
  });

  final String requestId;
  final bool readOnly;

  @override
  State<AdvertiserOdooSecureCheckoutSection> createState() =>
      _AdvertiserOdooSecureCheckoutSectionState();
}

class _AdvertiserOdooSecureCheckoutSectionState
    extends State<AdvertiserOdooSecureCheckoutSection> {
  final _service = const OdooLocalOrderService();
  bool _loading = true;
  bool _busy = false;
  bool _refreshing = false;
  bool _paymentConfirmed = false;
  String? _error;
  String? _stripeWarning;
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _invoice;
  List<Map<String, dynamic>> _transactions = [];
  Uri? _portalLink;
  Timer? _pollTimer;
  int _pollCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _euros(Object? cents) {
    final amount = cents is num ? cents / 100 : 0;
    return '${amount.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_busy || _refreshing) return;
    _refreshing = true;
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final status = await _service.secureCheckoutStatus(widget.requestId);
      final rawOrder = status['order'];
      final rawInvoice = status['invoice'];
      final order = rawOrder is Map
          ? Map<String, dynamic>.from(rawOrder) : null;
      final invoice = rawInvoice is Map
          ? Map<String, dynamic>.from(rawInvoice) : null;
      var transactions = <Map<String, dynamic>>[];
      var confirmed = false;
      String? stripeWarning;
      if (invoice != null) {
        try {
          final payment = await _service.secureCheckoutStripeStatus(
              widget.requestId);
          confirmed = payment['paymentConfirmed'] == true;
          final raw = payment['transactions'];
          if (raw is List) {
            transactions = raw.whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item)).toList();
          }
        } catch (error) {
          stripeWarning = 'Lecture Stripe Sandbox indisponible : '
              '${error.toString().replaceFirst('Bad state: ', '')}';
        }
      }
      if (!mounted) return;
      setState(() {
        _order = order;
        _invoice = invoice;
        _transactions = transactions;
        _paymentConfirmed = confirmed;
        _stripeWarning = stripeWarning;
        _error = null;
      });
      if (confirmed) _pollTimer?.cancel();
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

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
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

  Future<void> _createInvoice() async {
    if (_busy || _invoice != null || _order == null || widget.readOnly) return;
    if (!await _confirm('FACTURE UNIQUE — ODOO TEST',
        'Le module Odoo va confirmer la commande existante et établir '
        'une seule facture dans la base neutralisée. Aucun règlement, '
        'email ni activation publicitaire ne sera effectué.')) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.secureCheckoutInvoice(widget.requestId);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString()
            .replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _error == null) await _refresh();
  }

  Future<void> _prepareStripe() async {
    if (_busy || widget.readOnly || _invoice == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await _service.secureCheckoutStripePortal(widget.requestId);
      if (mounted) setState(() => _portalLink = url);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString()
            .replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openStripe() async {
    final url = _portalLink;
    if (url == null || _busy || widget.readOnly) return;
    bool opened;
    try {
      opened = await launchUrl(url, webOnlyWindowName: '_blank');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Le portail Odoo local ne s’ouvre pas.');
      }
      return;
    }
    if (!mounted) return;
    if (!opened) {
      setState(() => _error = 'Le portail Odoo local ne s’ouvre pas.');
      return;
    }
    // Un retour navigateur n'est jamais une preuve de paiement.
    _pollTimer?.cancel();
    _pollCount = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _pollCount++;
      if (!mounted || _paymentConfirmed || _pollCount >= 60) {
        timer.cancel();
      } else {
        unawaited(_refresh(silent: true));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final latest = _transactions.isEmpty ? null : _transactions.first;
    final transactionBlocked = _transactions.any((transaction) =>
        ['done', 'pending', 'authorized'].contains(transaction['state']));
    final canPay = !widget.readOnly && _invoice?['state'] == 'posted' &&
        _invoice?['paymentState'] == 'not_paid' &&
        _invoice?['odooPaymentRecorded'] != true &&
        !transactionBlocked && !_paymentConfirmed && _stripeWarning == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF059669)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ODOO 20 — FACTURATION SÉCURISÉE / TEST',
              style: TextStyle(color: WebColors.blue,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Base neutralisée uniquement. Paiement Stripe SANDBOX '
              'avec carte fictive. Aucune écriture Firebase, aucun débit réel '
              'et aucune activation publicitaire.'),
          const SizedBox(height: 8),
          const Text('Avant le paiement Stripe, le prestataire Démo '
              'doit être non publié dans Odoo.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_order == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Confirmez d’abord la commande dans '
                  'DEVIS & COMMANDE.'),
            )
          else ...[
            const SizedBox(height: 12),
            Text('COMMANDE : ${_order!['odooOrderName']}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text('HT : ${_euros(_order!['odooUntaxedCents'])}'),
            Text('TTC Odoo : ${_euros(_order!['odooTotalCents'])}'),
            if (_invoice == null && !widget.readOnly) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _createInvoice,
                icon: const Icon(Icons.receipt_long_outlined),
                label: Text(_busy ? 'FACTURATION EN COURS…' :
                    'CONFIRMER ET CRÉER LA FACTURE UNIQUE'),
              ),
            ],
          ],
          if (_invoice != null) ...[
            const SizedBox(height: 12),
            Text('FACTURE : ${_invoice!['odooInvoiceName']}',
                style: const TextStyle(color: WebColors.blue,
                    fontWeight: FontWeight.w900)),
            Text('STATUT : ${_invoice!['state']}'),
            Text('TOTAL TTC : ${_euros(_invoice!['amountTotalCents'])}'),
            Text('PAIEMENT : ${_invoice!['paymentState']}'),
            if (latest != null)
              Text('TRANSACTION STRIPE : ${latest['state'] ?? 'inconnue'}'),
            if (_paymentConfirmed)
              const Text('PAIEMENT STRIPE SANDBOX VÉRIFIÉ PAR ODOO',
                  style: TextStyle(color: Color(0xFF047857),
                      fontWeight: FontWeight.w900)),
            if (_invoice!['paymentState'] == 'paid' && !_paymentConfirmed)
              const Text('Facture déclarée payée, mais preuve Stripe '
                  'complète non confirmée : aucune activation autorisée.'),
            if (canPay) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null :
                    (_portalLink == null ? _prepareStripe : _openStripe),
                icon: const Icon(Icons.payment_outlined),
                label: Text(_portalLink == null
                    ? 'PRÉPARER LE PAIEMENT STRIPE SANDBOX'
                    : 'OUVRIR LE PORTAIL ODOO — STRIPE TEST'),
              ),
            ],
          ],
          if (_stripeWarning != null) ...[
            const SizedBox(height: 10),
            Text(_stripeWarning!,
                style: const TextStyle(color: WebColors.red)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: WebColors.red,
                fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : () => _refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('ACTUALISER LE STATUT ODOO'),
          ),
          const Text('CAMPAGNE NON ACTIVÉE — ENVIRONNEMENT DE TEST',
              textAlign: TextAlign.center,
              style: TextStyle(color: WebColors.red,
                  fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
