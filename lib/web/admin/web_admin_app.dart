import 'package:flutter/material.dart';

import '../shared/web_layout.dart';
import '../shared/web_menu_item.dart';

import 'pages/dashboard_page.dart';
import 'pages/sphots_page.dart';
import 'pages/users_page.dart';

class WebAdminApp extends StatelessWidget {
  const WebAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WebLayout(
      title: 'SPHOT ADMIN',
      menuItems: const [
        WebMenuItem(
          title: 'Dashboard',
          icon: Icons.dashboard_outlined,
          page: DashboardPage(),
        ),
        WebMenuItem(
          title: 'SPHOTS',
          icon: Icons.place_outlined,
          page: SphotsPage(),
        ),
        WebMenuItem(
          title: 'Utilisateurs',
          icon: Icons.people_outline,
          page: UsersPage(),
        ),
      ],
    );
  }
}