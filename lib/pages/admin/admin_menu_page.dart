import 'package:flutter/material.dart';

import 'admin_sphots_commune_page.dart';

import 'admin_sauveteur_page.dart';

import 'admin_dates_surveillance_page.dart';

class AdminMenuPage extends StatelessWidget {
  final String ville;

  const AdminMenuPage({
    super.key,
    this.ville = 'VILLE_NON_RENSEIGNEE',
  });

  @override
  Widget build(BuildContext context) {
    const Color adminColor = Color(0xFF1E3A8A);

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
                  Image.asset(
                    'data/icons/title.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),

                  const Text(
                    'ESPACE ADMIN MAIRIE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFF0000),
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
    color: Color(0xFF1E3A8A),
    width: 2,
  ),
),
                      child: Column(
                        children: [
                          Expanded(
  child: _AdminButton(
    title: 'SPHOTS',
    subtitle:
        'Créer, voir, copier, modifier, supprimer\nles SPHOTS',
    imageAsset: 'data/icons/fire_red_icon.png',
    topSpacing: 2,
    color: const Color(0xFF1E3A8A),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AdminSphotsCommunePage(),
        ),
      );
    },
  ),
),

const SizedBox(height: 12),

                          const SizedBox(height: 12),

Expanded(
  child: _AdminButton(
    title: 'DATES/HEURES DE SURVEILLANCE',
    subtitle:
        'Renseigner les périodes et heures\nde surveillance pour chaque SPHOT',
    icon: Icons.calendar_month_rounded,
    color: const Color(0xFFFF0000),
    onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdminDatesSurveillancePage(
        ville: ville,
      ),
    ),
  );
},
  ),
),

const SizedBox(height: 12),

Expanded(
  child: _AdminButton(
    title: 'SAUVETEURS',
    subtitle:
        'Créer, modifier et gérer\nles sauveteurs affectés aux SPHOTS',
    icon: Icons.groups_rounded,
    color: const Color(0xFFFF0000),
    onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const AdminSauveteurPage(),
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
  color: const Color(0xFF1E3A8A),
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
  color: Color(0xFF1E3A8A),
  size: 18,
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

class _AdminButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final String? imageAsset;
  final Color color;
  final VoidCallback onTap;
  final double topSpacing;

  const _AdminButton({
    required this.title,
    required this.subtitle,
    this.icon,
    this.imageAsset,
    required this.color,
    required this.onTap,
    this.topSpacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 1, 8, 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0xFF1E3A8A),
            width: 2.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (imageAsset != null)
              Image.asset(
                imageAsset!,
                height: 42,
                fit: BoxFit.contain,
              )
            else
              Icon(
                icon,
                color: const Color(0xFFFF0000),
                size: 48,
              ),

            const SizedBox(height: 8),

            Text(
  title,
  textAlign: TextAlign.center,
  maxLines: 2,
  style: TextStyle(
    color: Color(0xFF1E3A8A),
    fontSize: 16,
    fontWeight: FontWeight.w900,
    height: 0.95,
  ),
),

            SizedBox(
  height: 10,
),

            Text(
  subtitle,
  textAlign: TextAlign.center,
  maxLines: 3,
  overflow: TextOverflow.visible,
  style: TextStyle(
    color: const Color(0xFF1E3A8A),
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.3,
  ),
),
          ],
        ),
      ),
    );
  }
}