import 'package:flutter/material.dart';

import 'admin_creation_sauveteur_page.dart';
import 'admin_gestion_sauveteur_page.dart';

class AdminEspaceSauveteurPage extends StatelessWidget {
  final String ville;

  const AdminEspaceSauveteurPage({
    super.key,
    this.ville = 'VILLE_NON_RENSEIGNEE',
  });

  @override
  Widget build(BuildContext context) {
    const Color bleuRef = Color(0xFF1E3A8A);
    const Color rougeRef = Color(0xFFDC2626);

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
                    'ESPACE SAUVETEUR(S)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: rougeRef,
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
                          color: bleuRef,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: _SauveteurMenuButton(
                              title: '+ CRÉER\nUN SAUVETEUR',
                              subtitle:
                                  'Créer une nouvelle fiche sauveteur',
                              icon: Icons.person_add_alt_1_rounded,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AdminCreationSauveteurPage(),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 12),

                          Expanded(
                            child: _SauveteurMenuButton(
                              title: 'GÉRER\nLE(S) SAUVETEUR(S) CRÉÉ(S)',
                              subtitle:
                                  'Voir, modifier ou supprimer\nle(s) sauveteur(s) existant(s)',
                              icon: Icons.manage_accounts_rounded,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AdminGestionSauveteurPage(
                                      ville: ville,
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
                        color: bleuRef,
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
                        color: bleuRef,
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

class _SauveteurMenuButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SauveteurMenuButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color bleuRef = Color(0xFF1E3A8A);
    const Color rougeRef = Color(0xFFDC2626);

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
            color: bleuRef,
            width: 2.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: rougeRef,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: bleuRef,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 3,
              style: const TextStyle(
                color: bleuRef,
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