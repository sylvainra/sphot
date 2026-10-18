import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/commercial_customer_discount_service.dart';
import 'sphot_dropdown_visuals.dart';

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
  final GlobalKey _marketFieldKey = GlobalKey();
  OverlayEntry? _marketOverlay;
  bool _marketMenuOpen = false;
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _marketOverlay?.remove();
    _marketOverlay?.dispose();
    _marketOverlay = null;
    _uidController.dispose();
    _percentController.dispose();
    super.dispose();
  }

  void _closeMarketMenu() {
    _marketOverlay?.remove();
    _marketOverlay?.dispose();
    _marketOverlay = null;
    if (mounted && _marketMenuOpen) {
      setState(() => _marketMenuOpen = false);
    }
  }

  Widget _marketOption(String value, String label) {
    final selected = _market == value;
    return InkWell(
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      onTap: () {
        _closeMarketMenu();
        if (!mounted) return;
        setState(() {
          _market = value;
          _message = null;
          _error = null;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: selected ? _red : _blue,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? _red : _blue,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleMarketMenu() {
    if (_busy) return;
    if (_marketOverlay != null) {
      _closeMarketMenu();
      return;
    }

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject();
    final target = _marketFieldKey.currentContext?.findRenderObject();
    if (overlayBox is! RenderBox || target is! RenderBox) return;
    final position = target.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final size = target.size;

    _marketOverlay = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMarketMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: position.dx,
            top: position.dy + size.height -
                SphotDropdownVisuals.popupOverlap,
            width: size.width,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: SphotDropdownVisuals.popupDecoration,
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.only(
                  top: SphotDropdownVisuals.popupContentInset,
                  bottom: 5,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _marketOption('ADVERTISER_RADIUS', 'SPHOT Publicitaire'),
                    Divider(
                      height: 1,
                      color: _blue.withValues(alpha: 0.12),
                    ),
                    _marketOption('ADMIN', 'SPHOT Admin'),
                  ],
                ),
              ),
            ),
          ),
          ...SphotDropdownVisuals.joinedFieldEdges(position, size),
        ],
      ),
    );
    overlay.insert(_marketOverlay!);
    setState(() => _marketMenuOpen = true);
  }

  Widget _marketField() {
    return MouseRegion(
      cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        key: _marketFieldKey,
        onTap: _busy ? null : _toggleMarketMenu,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Type de client',
            labelStyle: const TextStyle(color: _blue),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            enabledBorder: SphotDropdownVisuals.inputBorder(),
            border: SphotDropdownVisuals.inputBorder(),
            focusedBorder: SphotDropdownVisuals.inputBorder(width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _market == 'ADMIN' ? 'SPHOT Admin' : 'SPHOT Publicitaire',
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                _marketMenuOpen
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: _red,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
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
            _marketField(),
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
