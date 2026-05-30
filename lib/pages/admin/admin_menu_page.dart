import 'package:flutter/material.dart';

import 'admin_sphots_commune_page.dart';

class AdminMenuPage extends StatelessWidget {
  const AdminMenuPage({super.key});

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
                      color: adminColor,
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
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          _AdminButton(
                            title: 'SPHOTS',
subtitle: 'Créer, voir, copier, modifier, supprimer\nles SPHOTS',
imageAsset: 'data/icons/fire_blue_icon.png',
topSpacing: 2,
                            color: adminColor,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AdminSphotsCommunePage(),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 14),

                          _AdminButton(
                            title: 'IMPORTER LES SPHOTS',
subtitle: 'Importer les SPHOTS créés\nci-dessus une fois renseignés',
                            icon: Icons.upload_file_rounded,
                            color: const Color(0xFFF97316),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Import CSV bientôt disponible',
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 14),

                          _AdminButton(
                            title: 'CONTRÔLER ET VALIDER',
                            subtitle: 'Vérifier les données saisies\navant publication',
                            icon: Icons.fact_check_rounded,
                            color: const Color(0xFF16A34A),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Contrôle des données bientôt disponible',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black,
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
                        color: Colors.black,
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
  this.topSpacing = 10,
});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: color,
              width: 2.2,
            ),
          ),
          child: Column(
  mainAxisAlignment: MainAxisAlignment.start,
  children: [
              if (imageAsset != null)
  Image.asset(
    imageAsset!,
    height: 60,
    fit: BoxFit.contain,
  )
else
  Icon(
    icon,
    color: color,
    size: 42,
  ),

              SizedBox(height: topSpacing),

              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),

              const SizedBox(height: 5),

              Text(
  subtitle,
  textAlign: TextAlign.center,
  maxLines: 3,
  overflow: TextOverflow.visible,
  style: const TextStyle(
    color: Colors.black,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.50,
  ),
),
            ],
          ),
        ),
      ),
    );
  }
}