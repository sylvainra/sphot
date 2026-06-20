import 'package:flutter/material.dart';

class AdminRequestPendingPage extends StatelessWidget {
  const AdminRequestPendingPage({super.key});

  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
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
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: adminColor,
                    width: 2,
                  ),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hourglass_top_rounded,
                      color: redColor,
                      size: 54,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'DEMANDE EN COURS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: redColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Votre demande d’accès au portail Admin SPHOT a bien été transmise.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: adminColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Elle sera vérifiée avant activation de votre accès.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: adminColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}