import 'package:flutter/material.dart';

import '../../shared/web_colors.dart';

/// Prévisualisations strictement locales pour le parcours publicitaire.
///
/// Aucune saisie CB, aucune requête réseau, aucun paiement Odoo, aucune
/// écriture Firestore et aucune activation de campagne ne sont possibles ici.
/// La véritable simulation Odoo avec le prestataire Démo est un test distinct.
class AdvertiserOdooLocalCardPreview extends StatefulWidget {
  const AdvertiserOdooLocalCardPreview({
    super.key,
    required this.requestId,
    required this.order,
    required this.invoice,
  });

  final String requestId;
  final Map<String, dynamic> order;
  final Map<String, dynamic> invoice;

  @override
  State<AdvertiserOdooLocalCardPreview> createState() =>
      _AdvertiserOdooLocalCardPreviewState();
}

class _AdvertiserOdooLocalCardPreviewState
    extends State<AdvertiserOdooLocalCardPreview> {
  // Une maquette n'écrit rien sur disque. Le résultat reste visible après
  // navigation entre rubriques tant que l'application Web reste ouverte.
  static final Map<String, String> _demoOutcomes = <String, String>{};

  String get _testKey =>
      '${widget.requestId}:${widget.invoice['odooInvoiceId']}';

  String? get _outcome => _demoOutcomes[_testKey];

  String _euros(Object? cents) {
    final value = cents is num ? cents / 100 : 0;
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  bool get _confirmedOrder =>
      widget.order['odooState'] == 'sale' &&
      widget.order['odooOrderId'] is int;

  bool get _validInvoice =>
      widget.invoice['state'] == 'posted' &&
      widget.invoice['odooInvoiceId'] is int &&
      widget.invoice['amountTotalCents'] is int &&
      widget.invoice['amountTotalCents'] > 0 &&
      widget.invoice['amountTotalCents'] ==
          widget.order['odooTotalCents'];

  bool get _accountingPayment =>
      widget.invoice['paymentState'] == 'paid' &&
      widget.invoice['odooPaymentRecorded'] == true &&
      widget.invoice['amountResidualCents'] == 0;

  String get _outcomeLabel => switch (_outcome) {
        'success' => 'CB FICTIVE ACCEPTÉE À L’ÉCRAN',
        'failure' => 'CB FICTIVE REFUSÉE À L’ÉCRAN',
        'pending' => 'CB FICTIVE EN ATTENTE À L’ÉCRAN',
        _ => 'AUCUN ESSAI CB VISUEL',
      };

  Color get _outcomeColor => switch (_outcome) {
        'success' => const Color(0xFF166534),
        'failure' => WebColors.red,
        'pending' => const Color(0xFF92400E),
        _ => WebColors.blue,
      };

  Widget _check(String label, bool ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ok ? Icons.check_circle_outline : Icons.highlight_off,
                color: ok ? const Color(0xFF166534) : WebColors.red,
                size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
          ],
        ),
      );

  Future<void> _showActivationPreview() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ACTIVATION — CONTRÔLE VISUEL TEST'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Commande ${widget.order['odooOrderName'] ?? '—'} · '
                  'Facture ${widget.invoice['odooInvoiceName'] ?? '—'}'),
              const SizedBox(height: 10),
              _check('Commande confirmée dans Odoo', _confirmedOrder),
              _check('Facture validée et montants concordants', _validInvoice),
              _check('Facture soldée en comptabilité Odoo TEST',
                  _accountingPayment),
              _check('Preuve authentifiée d’un paiement CB réel', false),
              _check('Autorisation de publication SPHOT', false),
              const SizedBox(height: 12),
              const Text(
                'La planification et le visuel publicitaire devront aussi '
                'être contrôlés avant une future diffusion.',
              ),
              const SizedBox(height: 10),
              const Text(
                'CONCLUSION : activation réelle BLOQUÉE. Le règlement '
                'manuel et la CB fictive ne constituent pas une preuve '
                'bancaire. Aucune campagne n’est publiée.',
                style: TextStyle(color: WebColors.red,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('FERMER'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCardDemo() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('PAIEMENT CB — SIMULATION VISUELLE'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    Color(0xFF102A5F), Color(0xFF1D4ED8),
                  ]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('SPHOT · CARTE FICTIVE',
                            style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w900)),
                        Icon(Icons.credit_card, color: Colors.white),
                      ],
                    ),
                    SizedBox(height: 26),
                    Text('••••  ••••  ••••  TEST',
                        style: TextStyle(color: Colors.white,
                            fontSize: 19, fontWeight: FontWeight.bold)),
                    SizedBox(height: 18),
                    Text('AUCUNE DONNÉE BANCAIRE À SAISIR',
                        style: TextStyle(color: Colors.white70,
                            fontSize: 11, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Facture ${widget.invoice['odooInvoiceName'] ?? '—'}'),
              Text('Total : '
                  '${_euros(widget.invoice['amountTotalCents'])}',
                  style: const TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 18)),
              const SizedBox(height: 10),
              if (_accountingPayment)
                const Text(
                  'Cette facture est déjà soldée par un règlement manuel '
                  'dans Odoo TEST. Les choix ci-dessous ne créeront PAS '
                  'un deuxième paiement.',
                  style: TextStyle(color: Color(0xFF92400E),
                      fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 10),
              const Text(
                'Choisis le résultat que tu veux observer. '
                'Il s’agit seulement d’une maquette interactive : '
                'aucune transaction CB ou Odoo n’est créée.',
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'success'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('SIMULER CB ACCEPTÉE'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'failure'),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('SIMULER CB REFUSÉE'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, 'pending'),
                icon: const Icon(Icons.hourglass_empty),
                label: const Text('SIMULER CB EN ATTENTE'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ANNULER'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    setState(() => _demoOutcomes[_testKey] = choice);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('DERNIERS TESTS VISUELS — SANS PAIEMENT RÉEL',
              style: TextStyle(color: WebColors.blue,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('La facture Odoo existante n’est jamais modifiée.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _showCardDemo,
            icon: const Icon(Icons.credit_card_outlined),
            label: const Text('VOIR LA SIMULATION DE PAIEMENT CB'),
          ),
          const SizedBox(height: 8),
          Text(_outcomeLabel,
              style: TextStyle(color: _outcomeColor,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showActivationPreview,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('PRÉVISUALISER L’ACTIVATION (TEST)'),
          ),
          const SizedBox(height: 5),
          const Text('Activation réelle toujours interdite.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: WebColors.red)),
        ],
      ),
    );
  }
}
