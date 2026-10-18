import 'package:flutter/material.dart';

import '../services/commercial_pricing_service.dart';

/// Remise individuelle administrée par le Super Admin uniquement.
/// Aucun code promo public, aucun changement des grilles tarifaires.
class SuperAdminCustomerDiscountPanel extends StatefulWidget {
  const SuperAdminCustomerDiscountPanel({
    super.key,
    required this.sessionToken,
  });

  final String sessionToken;

  @override
  State<SuperAdminCustomerDiscountPanel> createState() =>
      _SuperAdminCustomerDiscountPanelState();
}

class _SuperAdminCustomerDiscountPanelState
    extends State<SuperAdminCustomerDiscountPanel> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);

  final _uid = TextEditingController();
  String _market = 'ADVERTISER_RADIUS';
  int _percent = 0;
  bool _loaded = false;
  bool _busy = false;
  String? _notice;
  String? _error;

  late final CommercialPricingService _service =
      CommercialPricingService(widget.sessionToken);

  @override
  void dispose() {
    _uid.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid.text.trim();
    if (uid.isEmpty) {
      setState(() => _error = 'Identifiant Firebase du client requis.');
      return;
    }
    setState(() {
      _busy = true;
      _loaded = false;
      _error = null;
      _notice = null;
    });
    try {
      final percent =
          await _service.customerDiscount(market: _market, uid: uid);
      if (!mounted) return;
      setState(() {
        _percent = percent;
        _loaded = true;
        _notice = 'Remise client actuelle : $percent %.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Lecture impossible : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_loaded) return;
    final uid = _uid.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('CONFIRMER LA REMISE CLIENT'),
        content: Text(
          'Accorder $_percent % à ce client pour '
          '${_market == 'ADMIN' ? 'SPHOT ADMIN' : 'SPHOT PUBLICITAIRE'} ? '
          'Cette remise affectera ses nouveaux aperçus de devis, '
          'pas les factures historiques.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ANNULER'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('CONFIRMER'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final percent = await _service.setCustomerDiscount(
        market: _market,
        uid: uid,
        percent: _percent,
      );
      if (!mounted) return;
      setState(() {
        _percent = percent;
        _notice = 'Remise enregistrée : $percent %.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Enregistrement impossible : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const Text(
          'RISTOURNE INDIVIDUELLE',
          style: TextStyle(
            color: _blue,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Une remise en pourcentage, par client et par parcours. '
          'Les tarifs publiés et les anciennes factures ne sont pas modifiés.',
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'ADVERTISER_RADIUS',
              label: Text('PUBLICITAIRE'),
            ),
            ButtonSegment(value: 'ADMIN', label: Text('ADMIN')),
          ],
          selected: {_market},
          onSelectionChanged: _busy
              ? null
              : (value) => setState(() {
                    _market = value.first;
                    _loaded = false;
                    _percent = 0;
                    _notice = null;
                    _error = null;
                  }),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _uid,
          onChanged: (_) {
            if (_loaded) setState(() => _loaded = false);
          },
          decoration: const InputDecoration(
            labelText: 'Identifiant Firebase UID du client',
            helperText: 'L’identifiant du dossier client, pas son email.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : _load,
          child: const Text('CHARGER LA REMISE ACTUELLE'),
        ),
        if (_loaded) ...[
          const SizedBox(height: 20),
          Text(
            'REMISE : $_percent %',
            style: const TextStyle(
              color: _blue,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Slider(
            value: _percent.toDouble(),
            min: 0,
            max: 90,
            divisions: 90,
            label: '$_percent %',
            onChanged: _busy
                ? null
                : (value) => setState(() => _percent = value.round()),
          ),
          const Wrap(
            children: [],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final value in [0, 5, 10, 15, 20, 25, 30])
                OutlinedButton(
                  onPressed:
                      _busy ? null : () => setState(() => _percent = value),
                  child: Text('$value %'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('APPLIQUER AU CLIENT'),
          ),
        ],
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _notice!,
              style: const TextStyle(color: _blue),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: _red),
            ),
          ),
      ],
    );
  }
}
