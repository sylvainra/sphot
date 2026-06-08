import 'package:flutter/material.dart';

class AdminEspacePage extends StatelessWidget {
  const AdminEspacePage({super.key});

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

                  const SizedBox(height: 2),

                  SizedBox(
                    height: 474,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
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
                          _MenuSquare(
                            title: 'SPHOTS\nCOMMUNE',
                            icon: Icons.map_rounded,
                            color: adminColor,
                            height: 110,
                            onTap: () {
                              // Prochaine étape :
                              // Navigator vers AdminEspaceSphotsPage
                            },
                          ),

                          const SizedBox(height: 10),

                          Expanded(
                            child: GridView.count(
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.15,
                              children: [
                                _MenuSquare(
                                  title: 'MODÈLE\nEXCEL',
                                  icon: Icons.download_rounded,
                                  color: const Color(0xFF16A34A),
                                  onTap: () {
                                    // Prochaine étape :
                                    // génération / partage du modèle Excel
                                  },
                                ),

                                _MenuSquare(
                                  title: 'IMPORT\nEXCEL',
                                  icon: Icons.upload_file_rounded,
                                  color: const Color(0xFFF97316),
                                  onTap: () {
                                    // Prochaine étape :
                                    // import du fichier Excel rempli
                                  },
                                ),

                                _MenuSquare(
                                  title: 'GÉNÉRER\nCSV',
                                  icon: Icons.table_chart_rounded,
                                  color: const Color(0xFFEF4444),
                                  onTap: () {
                                    // Prochaine étape :
                                    // conversion Excel vers CSV
                                  },
                                ),

                                _MenuSquare(
                                  title: 'PRÉVISUALISER\nDONNÉES',
                                  icon: Icons.visibility_rounded,
                                  color: const Color(0xFF546E7A),
                                  onTap: () {
                                    // Prochaine étape :
                                    // contrôle des SPHOTS avant validation
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 4),

                          _MenuSquare(
                            title: 'VALIDATION BASE SPHOTS POUR MAP / SAUVETEURS',
                            icon: Icons.verified_rounded,
                            color: const Color(0xFF8E24AA),
                            height: 82,
                            onTap: () {
                              // Prochaine étape :
                              // validation finale du CSV comme source commune
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  Transform.translate(
                    offset: const Offset(0, 9),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Container(
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
                        child: const Center(
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.black,
                            size: 22,
                          ),
                        ),
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

class _MenuSquare extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Color? iconColor;
  final double? height;

  const _MenuSquare({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.iconColor,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: color,
            width: 2.1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: iconColor ?? color,
                size: 34,
              ),

              const SizedBox(height: 7),

              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}