import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'web_colors.dart';

import '../home/web_home_page.dart';

class WebTopBar extends StatelessWidget {
  const WebTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final displayName = user?.displayName?.isNotEmpty == true
        ? user!.displayName!
        : user?.email ?? 'Utilisateur';

    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Image.asset(
              'data/icons/title.png',
              height: 42,
              fit: BoxFit.contain,
            ),
          ),

          Positioned(
            right: 24,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: WebColors.blue.withOpacity(0.1),
                  child: const Icon(
                    Icons.person,
                    color: WebColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 24),
                IconButton(
                  tooltip: 'Déconnexion',
                  onPressed: () async {
  await FirebaseAuth.instance.signOut();

  if (!context.mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => const WebHomePage(),
    ),
    (route) => false,
  );
},
                  icon: const Icon(
                    Icons.logout,
                    color: WebColors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}