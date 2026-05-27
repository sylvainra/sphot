import 'package:flutter/material.dart';

import 'lifeguard_actions_page.dart';
import 'placeholder_page.dart';
import 'terrestrial_weather_page.dart';
import 'marine_weather_page.dart';

import 'person_search_page.dart';

import 'ephemeride_dicton_page.dart';

import 'schedule_page.dart';

class LifeguardMenuPage extends StatelessWidget {
  final Color profileColor;

final String userRole;

  const LifeguardMenuPage({
  super.key,
  required this.profileColor,
  required this.userRole,
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
                            title: 'ACTIONS RAPIDES',
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFFD50000),
                            height: 82,
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

                          const SizedBox(height: 10),

                          Expanded(
                            child: GridView.count(
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.74,
                              children: [
                                _MenuSquare(
                                  title: 'MÉTÉO TERRESTRE',
                                  icon: Icons.wb_sunny_rounded,
                                  color: const Color(0xFF8D6E63),
                                  iconColor: const Color(0xFFFBC02D),
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
  title: 'ÉPHÉMÉRIDE\nDICTON',
  icon: Icons.auto_awesome_rounded,
  color: const Color(0xFFF9A825),
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EphemerideDictonPage(
  profileColor: profileColor,
),
      ),
    );
  },
),

                                _MenuSquare(
  title: 'RECHERCHE DE PERSONNE',
  icon: Icons.person_search_rounded,
  color: const Color(0xFF00897B),
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonSearchPage(
          profileColor: profileColor,
        ),
      ),
    );
  },
),

_MenuSquare(
  title: 'EMPLOI DU TEMPS',
  icon: Icons.calendar_month_rounded,
  color: const Color(0xFF43A047),
  onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SchedulePage(
  profileColor: const Color(0xFF43A047),
  userRole: userRole,
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

                          const SizedBox(height: 4),

                          _MenuSquare(
                            title: 'MAIN COURANTE',
                            icon: Icons.menu_book_rounded,
                            color: const Color(0xFF8E24AA),
                            height: 82,
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