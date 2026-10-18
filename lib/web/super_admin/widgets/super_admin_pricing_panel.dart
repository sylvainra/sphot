import 'package:flutter/material.dart';

import 'super_admin_admin_pricing_table.dart';
import 'super_admin_advertiser_pricing_table.dart';
import 'super_admin_advertiser_radius_pricing_table.dart';

/// Shell des catalogues tarifaires Firestore ADMIN et ANNONCEUR.
/// Aucun prix de devis, abonnement ou renouvellement existant n'est modifie.
class SuperAdminPricingPanel extends StatefulWidget {
  const SuperAdminPricingPanel({
    super.key,
    required this.onClose,
    this.selectedTab = 0,
    this.pricingSessionToken = '',
    this.onTabChanged,
  });

  final VoidCallback onClose;
  final int selectedTab;
  final String pricingSessionToken;
  final ValueChanged<int>? onTabChanged;

  @override
  State<SuperAdminPricingPanel> createState() => _SuperAdminPricingPanelState();
}

class _SuperAdminPricingPanelState extends State<SuperAdminPricingPanel> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  int _localTab = 0;
  bool _radiusCatalog = true;

  int get _tab => widget.onTabChanged == null ? _localTab : widget.selectedTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      // ADMIN reste un volet latéral de 560 px à côté de la carte.
      // ANNONCEUR prend l'espace central via Expanded dans le dashboard.
      // Sans cette largeur, le Row parent donne des contraintes horizontales
      // non bornées aux widgets Expanded du volet et bloque le rendu Flutter.
      width: _tab == 0 ? 560 : null,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        border: Border(
          left: BorderSide(color: _blue.withOpacity(0.25), width: 1.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
              color: Colors.white,
              child: Row(
                children: [
                  const Icon(Icons.euro_rounded, color: _blue, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'GRILLES TARIFAIRES',
                      style: TextStyle(
                        color: _blue,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded, color: _blue),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Expanded(child: _tabButton('ADMIN', 0)),
                  const SizedBox(width: 10),
                  Expanded(child: _tabButton('ANNONCEUR', 1)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: IndexedStack(
                  index: _tab,
                  children: [
                    SuperAdminAdminPricingTable(sessionToken: widget.pricingSessionToken),
                    Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _catalogButton(
                                '6 RAYONS · 108 PRIX',
                                true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _catalogButton(
                                'HISTORIQUE · 90 PRIX',
                                false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: _radiusCatalog
                              ? SuperAdminAdvertiserRadiusPricingTable(
                                  sessionToken: widget.pricingSessionToken,
                                )
                              : SuperAdminAdvertiserPricingTable(
                                  sessionToken: widget.pricingSessionToken,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogButton(String label, bool isRadius) {
    final selected = _radiusCatalog == isRadius;
    return OutlinedButton(
      onPressed: () => setState(() => _radiusCatalog = isRadius),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? _red : _blue,
        backgroundColor: selected ? _red.withOpacity(0.08) : Colors.white,
        side: BorderSide(color: selected ? _red : _blue),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _tab == index;
    return OutlinedButton(
      onPressed: () {
        if (widget.onTabChanged != null) {
          widget.onTabChanged!(index);
        } else {
          setState(() => _localTab = index);
        }
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? _red.withOpacity(0.08) : Colors.white,
        foregroundColor: selected ? _red : _blue,
        side: BorderSide(color: selected ? _red : _blue, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 13),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}
