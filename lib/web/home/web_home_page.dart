import 'package:flutter/material.dart';

import '../shared/web_colors.dart';

import '../auth/web_proconnect_login_page.dart';

class WebHomePage extends StatelessWidget {
  const WebHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),

          Container(
            color: Colors.white.withOpacity(0.65),
          ),

          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 72,
                  child: Center(
                    child: Image.asset(
                      'data/icons/title.png',
                      height: 68,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                const Spacer(),

                Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    _PortalCard(
      title: 'ESPACE SAUVETEUR',
      icon: Icons.groups,
      color: WebColors.red,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const WebProConnectLoginPage(
              mode: 'sauveteur',
            ),
          ),
        );
      },
    ),

    const SizedBox(width: 32),

    _PortalCard(
      title: 'ESPACE ADMIN',
      icon: Icons.admin_panel_settings,
      color: WebColors.blue,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const WebProConnectLoginPage(
              mode: 'admin',
            ),
          ),
        );
      },
    ),
  ],
),

                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PortalCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 280,
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: color,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 64,
                color: color,
              ),

              const SizedBox(height: 24),

              Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}