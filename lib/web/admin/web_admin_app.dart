import 'package:flutter/material.dart';

import '../shared/web_layout.dart';
import '../shared/web_menu_item.dart';

import 'pages/dashboard_page.dart';
import 'pages/dashboard_super_admin_page.dart';
import 'pages/sphots_page.dart';
import 'pages/users_page.dart';
import 'pages/admin_requests_page.dart';
import 'pages/subscriptions_page.dart';
import 'pages/web_ads_page.dart';

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
          title: 'Carte Monde',
          icon: Icons.public,
          page: DashboardSuperAdminPage(),
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
        WebMenuItem(
          title: 'Demandes Admin',
          icon: Icons.request_page_outlined,
          page: AdminRequestsPage(),
        ),
        WebMenuItem(
          title: 'Abonnements',
          icon: Icons.subscriptions_outlined,
          page: SubscriptionsPage(),
        ),
        WebMenuItem(
          title: 'Ads',
          icon: Icons.campaign_outlined,
          page: WebAdsPage(),
        ),
      ],
    );
  }
}