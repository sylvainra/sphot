import 'package:flutter/material.dart';

import 'super_admin_admin_pricing_table.dart';
import 'super_admin_advertiser_pricing_table.dart';

/// Super Admin pricing test shell. All pricing actions are local simulations.
/// Other pricing/devis/renewal services remain unchanged.
class SuperAdminPricingPanel extends StatefulWidget {
  const SuperAdminPricingPanel({
    super.key,
    required this.onClose,
    this.selectedTab = 0,
    this.onTabChanged,
  });

  final VoidCallback onClose;
  final int selectedTab;
  final ValueChanged<int>? onTabChanged;

  @override
  State<SuperAdminPricingPanel> createState() => _SuperAdminPricingPanelState();
}

class _SuperAdminPricingPanelState extends State<SuperAdminPricingPanel> {
  static const _blue = Color(0xFF1E3A8A);
  static const _red = Color(0xFFDC2626);
  int _localTab = 0;

  int get _tab => widget.onTabChanged == null ? _localTab : widget.selectedTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.onTabChanged == null ? 560 : null,
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
                  children: const [
                    SuperAdminAdminPricingTable(),
                    SuperAdminAdvertiserPricingTable(),
                  ],
                ),
              ),
            ),
          ],
        ),
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
