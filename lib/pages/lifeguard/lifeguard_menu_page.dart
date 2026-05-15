import 'package:flutter/material.dart';

import 'lifeguard_actions_page.dart';
import 'placeholder_page.dart';

import 'terrestrial_weather_page.dart';

class LifeguardMenuPage extends StatelessWidget {
  final Color profileColor;

  const LifeguardMenuPage({
    super.key,
    required this.profileColor,
  });

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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),

                  Text(
                    'RENSEIGNEMENTS SAUVETEURS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: profileColor,
                      letterSpacing: 0.6,
                    ),
                  ),

                  const SizedBox(height: 22),

                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      children: [
                        _MenuSquare(
  title: 'ACTIONS RAPIDES',
  icon: Icons.warning_amber_rounded,
  color: const Color(0xFFFFD600),
  backgroundColor: const Color(0xFFD50000),
  textColor: Colors.white,
  iconColor: Colors.white,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LifeguardActionsPage(
                                  profileColor: profileColor,
                                ),
                              ),
                            );
                          },
                        ),

                       _MenuSquare(
  title: 'MÉTÉO TERRESTRE',
  icon: Icons.wb_sunny_rounded,
  color: const Color(0xFF5D4037),
  backgroundColor: const Color(0xFF8D6E63),
  textColor: Colors.white,
  iconColor: Colors.white,
                          onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TerrestrialWeatherPage(
        profileColor: profileColor,
      ),
    ),
  );
},
                        ),

                        _MenuSquare(
  title: 'MÉTÉO MARINE',
  icon: Icons.waves_rounded,
  color: const Color(0xFF1565C0),
  backgroundColor: const Color(0xFF1E88E5),
  textColor: Colors.white,
  iconColor: Colors.white,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlaceholderPage(
                                  title: 'MÉTÉO MARINE',
                                  profileColor: profileColor,
                                ),
                              ),
                            );
                          },
                        ),

                       _MenuSquare(
  title: 'EMPLOI DU TEMPS',
  icon: Icons.calendar_month_rounded,
  color: const Color(0xFF2E7D32),
  backgroundColor: const Color(0xFF43A047),
  textColor: Colors.white,
  iconColor: Colors.white,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlaceholderPage(
                                  title: 'EMPLOI DU TEMPS',
                                  profileColor: profileColor,
                                ),
                              ),
                            );
                          },
                        ),

                       _MenuSquare(
  title: 'MAIN COURANTE',
  icon: Icons.menu_book_rounded,
  color: const Color(0xFF6A1B9A),
  backgroundColor: const Color(0xFF8E24AA),
  textColor: Colors.white,
  iconColor: Colors.white,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlaceholderPage(
                                  title: 'MAIN COURANTE',
                                  profileColor: profileColor,
                                ),
                              ),
                            );
                          },
                        ),

                        _MenuSquare(
  title: 'STATS',
  icon: Icons.bar_chart_rounded,
  color: const Color(0xFF37474F),
  backgroundColor: const Color(0xFF546E7A),
  textColor: Colors.white,
  iconColor: Colors.white,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlaceholderPage(
                                  title: 'STATS',
                                  profileColor: profileColor,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
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
final Color? backgroundColor;
final Color? textColor;
final Color? iconColor;
  final VoidCallback onTap;

  const _MenuSquare({
  required this.title,
  required this.icon,
  required this.color,
  required this.onTap,
  this.backgroundColor,
  this.textColor,
  this.iconColor,
});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.white.withOpacity(0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
  color: color,
  width: 2.5,
),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: iconColor ?? color,
                size: 42,
              ),

              const SizedBox(height: 14),

              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor ?? color,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}