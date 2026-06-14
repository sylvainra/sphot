import 'package:flutter/material.dart';

import 'admin_attribution_sphot_page.dart';
import 'admin_periodes_surveillance_page.dart';
import 'admin_profile_button.dart';

class AdminEspaceSurveillancePage extends StatelessWidget {
  final String territoireId;

  const AdminEspaceSurveillancePage({
    super.key,
    required this.territoireId,
  });

  @override
  Widget build(BuildContext context) {
    const Color pageColor = Color(0xFF1E3A8A);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  SizedBox(
  height: 56,
  width: double.infinity,
  child: Stack(
    alignment: Alignment.center,
    children: [
      Image.asset(
        'data/icons/title.png',
        height: 56,
        fit: BoxFit.contain,
      ),
      const Positioned(
        right: 0,
        child: AdminProfileButton(),
      ),
    ],
  ),
),

                  const Text(
                    'ESPACE SURVEILLANCE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFEF4444),
                      letterSpacing: 0.6,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: pageColor,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: _SurveillanceBand(
                              title: 'PÉRIODE(S) DE SURVEILLANCE',
                              subtitle:
                                  'Créer le(s) période(s) avec dates et horaires',
                              icon: Icons.calendar_month_rounded,
                              color: pageColor,
                              onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdminPeriodesSurveillancePage(
  territoireId: territoireId,
),
    ),
  );
},
                            ),
                          ),

                          const SizedBox(height: 14),

                          Expanded(
                            child: _SurveillanceBand(
                              title: 'ATTRIBUTION À/AUX SPHOT(S)',
                              subtitle:
                                  'Attribuer le(s) période(s) créée(s) à/aux SPHOT(S)',
                              icon: Icons.location_on_rounded,
                              color: const Color(0xFF1E3A8A),
                              onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdminAttributionSphotsPage(
  territoireId: territoireId,
),
    ),
  );
},
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Container(
  width: 40,
  height: 40,
  decoration: BoxDecoration(
    color: Colors.transparent,
    shape: BoxShape.circle,
    border: Border.all(
      color: pageColor,
      width: 2,
    ),
  ),
  child: IconButton(
    onPressed: () {
      Navigator.of(context).pop();
    },
    padding: EdgeInsets.zero,
    icon: const Icon(
      Icons.arrow_back_ios_new_rounded,
      color: pageColor,
      size: 22,
    ),
  ),
),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurveillanceBand extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SurveillanceBand({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: color,
            width: 2.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Color(0xFFEF4444),
              size: 54,
            ),

            const SizedBox(height: 12),

            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 0.95,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 3,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}