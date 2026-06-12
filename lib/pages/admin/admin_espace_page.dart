import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_espace_sphot_page.dart';
import 'admin_espace_sauveteur_page.dart';
import 'admin_espace_surveillance_page.dart';

class AdminEspacePage extends StatefulWidget {
  const AdminEspacePage({super.key});

  @override
  State<AdminEspacePage> createState() => _AdminEspacePageState();
}

class _AdminEspacePageState extends State<AdminEspacePage> {
  String ville = 'VILLE_NON_RENSEIGNEE';
  String territoireId = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadAdmin();
  }

  Future<void> _loadAdmin() async {
  try {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
      return;
    }

    final adminDoc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get()
        .timeout(const Duration(seconds: 8));

    if (!adminDoc.exists) {
      if (!mounted) return;
      setState(() {
        loading = false;
        ville = 'ADMIN_NON_TROUVÉ';
        territoireId = '';
      });
      return;
    }

    final adminData = adminDoc.data() ?? {};
    final loadedTerritoireId =
        (adminData['territoireId'] ?? '').toString();

    String loadedVille = 'VILLE_NON_RENSEIGNEE';

    if (loadedTerritoireId.isNotEmpty) {
      final territoireDoc = await FirebaseFirestore.instance
          .collection('territoires')
          .doc(loadedTerritoireId)
          .get()
          .timeout(const Duration(seconds: 8));

      if (territoireDoc.exists) {
        final territoireData = territoireDoc.data() ?? {};
        loadedVille =
            (territoireData['ville'] ?? 'VILLE_NON_RENSEIGNEE').toString();
      }
    }

    if (!mounted) return;

    setState(() {
      territoireId = loadedTerritoireId;
      ville = loadedVille;
      loading = false;
    });
  } catch (error) {
    if (!mounted) return;

    setState(() {
      loading = false;
      ville = 'ERREUR_FIREBASE';
      territoireId = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Erreur chargement admin : $error'),
        duration: const Duration(seconds: 6),
      ),
    );
  }
}

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
                    'ESPACE ADMIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFDC2626),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (loading)
                    const Expanded(
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: adminColor,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: _AdminButton(
                                title: 'SPHOT(S)',
                                subtitle:
                                    'Créer, voir, copier, modifier, supprimer\nle(s) SPHOT(S)',
                                imageAsset: 'data/icons/fire_red_icon.png',
                                topSpacing: 2,
                                color: adminColor,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AdminEspaceSphotPage(
                                        territoireId: territoireId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _AdminButton(
                                title: 'DATES/HEURES DE SURVEILLANCE',
                                subtitle:
                                    'Renseigner les périodes et heures\nde surveillance pour chaque SPHOT',
                                icon: Icons.calendar_month_rounded,
                                color: const Color(0xFFDC2626),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AdminEspaceSurveillancePage(
  territoireId: territoireId,
)
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _AdminButton(
                                title: 'SAUVETEUR(S)',
                                subtitle:
                                    'Créer, modifier et gérer le(s) sauveteur(s)\naffecté(s) au(x) SPHOT(S)',
                                icon: Icons.groups_rounded,
                                color: const Color(0xFFDC2626),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AdminEspaceSauveteurPage(
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
                        color: adminColor,
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      onPressed: () {
                        FirebaseAuth.instance.signOut();
                        Navigator.of(context).pop();
                      },
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: adminColor,
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
                color: const Color(0xFFDC2626),
                size: 48,
              ),
            const SizedBox(height: 8),
            const SizedBox(height: 0),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: Color(0xFF1E3A8A),
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 0.95,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                color: Color(0xFF1E3A8A),
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