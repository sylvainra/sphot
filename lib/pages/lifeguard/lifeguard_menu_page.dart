import 'package:flutter/material.dart';

import 'lifeguard_actions_page.dart';
import 'placeholder_page.dart';
import 'terrestrial_weather_page.dart';
import 'marine_weather_page.dart';

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 52,
                    fit: BoxFit.contain,
                  ),

                  Text(
                    'RENSEIGNEMENTS SAUVETEURS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: profileColor,
                      letterSpacing: 0.6,
                    ),
                  ),

                  const SizedBox(height: 14),

                  Container(
                    height:
                        MediaQuery.of(context).size.height * 0.69,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.black,
                        width: 2.5,
                      ),
                    ),
                    child: GridView.count(
                      physics:
                          const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.02,
                      children: [
                        _MenuSquare(
                          title: 'ACTIONS RAPIDES',
                          icon: Icons.warning_amber_rounded,
                          color: const Color(0xFFD50000),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    LifeguardActionsPage(
                                  profileColor: profileColor,
                                ),
                              ),
                            );
                          },
                        ),

                        _MenuSquare(
                          title: 'MÉTÉO TERRESTRE',
                          icon: Icons.wb_sunny_rounded,
                          color: const Color(0xFF8D6E63),
                          iconColor:
                              const Color(0xFFFBC02D),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    TerrestrialWeatherPage(
                                  profileColor: profileColor,
                                ),
                              ),
                            );
                          },
                        ),

                        _MenuSquare(
                          title: 'MÉTÉO MARINE',
                          icon: Icons.waves_rounded,
                          color: const Color(0xFF1E88E5),
                          onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MarineWeatherPage(
        profileColor: profileColor,
      ),
    ),
  );
},
                        ),

                        _MenuSquare(
                          title: 'EMPLOI DU TEMPS',
                          icon:
                              Icons.calendar_month_rounded,
                          color: const Color(0xFF43A047),
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
                          color: const Color(0xFF8E24AA),
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
                          color: const Color(0xFF546E7A),
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

                  const SizedBox(height: 12),

                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black,
                          width: 2.5,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.black,
                          size: 24,
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

  const _MenuSquare({
  required this.title,
  required this.icon,
  required this.color,
  required this.onTap,
  this.iconColor,
});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: color,
            width: 2.3,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: iconColor ?? color,
                size: 36,
              ),

              const SizedBox(height: 10),

              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}