import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/commercial_customer_discount_service.dart';

/// Remise nominative simple. Aucun code public à distribuer.
class SuperAdminCustomerDiscountsDialog extends StatefulWidget {
  const SuperAdminCustomerDiscountsDialog({
    super.key,
    required this.sessionToken,
  });

  final String sessionToken;

  @override
  State<SuperAdminCustomerDiscountsDialog> createState() =>
      _SuperAdminCustomerDiscountsDialogState();
}

class _SuperAdminCustomerDiscountsDialogState
    extends State<SuperAdminCustomerDiscountsDialog> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  final _uidController = TextEditingController();
  final _percentController = TextEditingController(text: '0');
  String _market = 'ADVERTISER_RADIUS';
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _uidController.dispose();
    _percentController.dispose();
    super.dispose();
  }

  Future<void> _perform({required bool save}) async {
    if (_busy) return;
    final uid = _uidController.text.trim();
    if (!RegExp(r'^[a-zA-Z0-9_-]{6,128}$').hasMatch(uid)) {
      setState(() => _error = 'Saisissez l’UID Firebase du client.');
      return;
    }
    final percent = int.tryParse(_percentController.text.trim());
    if (save && (percent == null || percent < 0 || percent > 90)) {
      setState(() => _error = 'Remise entière de 0 à 90 % requise.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      final service = CommercialCustomerDiscountService(widget.sessionToken);
      final value = save
          ? await service.saveDiscount(
              market: _market,
              customerUid: uid,
              percent: percent!,
            )
          : await service.getDiscount(market: _market, customerUid: uid);
      if (!mounted) return;
      setState(() {
        _percentController.text = '$value';
        _message = save
            ? value == 0
                ? 'Remise supprimée pour ce client.'
                : 'Remise de $value % attribuée à ce client.'
            : 'Remise actuellement enregistrée : $value %.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Opération impossible : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'REMISE COMMERCIALE PAR CLIENT',
        style: TextStyle(color: _blue, fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Le Super Admin peut attribuer un pourcentage au client. '
              'La remise s’applique aux futurs devis publiés, '
              'sans changer la grille tarifaire ni les factures passées.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _market,
              decoration: const InputDecoration(
                labelText: 'Type de client',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'ADVERTISER_RADIUS',
                  child: Text('SPHOT Publicitaire'),
                ),
                DropdownMenuItem(
                  value: 'ADMIN',
                  child: Text('SPHOT Admin'),
                ),
              ],
              onChanged: _busy ? null : (value) {
                if (value != null) {
                  setState(() {
                    _market = value;
                    _message = null;
                    _error = null;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _uidController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Identifiant Firebase (UID) du client',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _percentController,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Remise en pourcentage',
                helperText: 'Exemples : 5, 10, 15. Mettre 0 pour retirer.',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: _red)),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_message!, style: const TextStyle(color: _blue)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('FERMER'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _perform(save: false),
          child: const Text('CONSULTER'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _perform(save: true),
          child: const Text('ENREGISTRER'),
        ),
      ],
    );
  }
}
