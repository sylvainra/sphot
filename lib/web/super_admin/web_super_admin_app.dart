import 'package:flutter/material.dart';

import '../shared/web_layout.dart';
import '../shared/web_menu_item.dart';

import 'pages/super_admin_admin_requests_page.dart';
import 'pages/super_admin_ads_page.dart';
import 'pages/super_admin_dashboard_finances_page.dart';
import 'pages/super_admin_dashboard_page.dart';
import 'pages/super_admin_sphots_page.dart';
import 'pages/super_admin_subscriptions_page.dart';

class WebSuperAdminApp extends StatelessWidget {
  const WebSuperAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WebLayout(
      title: 'SPHOT ADMIN',
      menuItems: [
        WebMenuItem(
          title: 'Finances',
          icon: Icons.dashboard_outlined,
          page: SuperAdminDashboardFinancesPage(),
        ),
        WebMenuItem(
          title: 'Carte Monde',
          icon: Icons.public,
          page: SuperAdminDashboardPage(),
        ),
        WebMenuItem(
          title: 'SPHOTS',
          icon: Icons.place_outlined,
          page: SuperAdminSphotsPage(),
        ),
        WebMenuItem(
          title: 'Demandes Admin',
          icon: Icons.request_page_outlined,
          page: SuperAdminAdminRequestsPage(),
        ),
        WebMenuItem(
          title: 'Abonnements',
          icon: Icons.subscriptions_outlined,
          page: SuperAdminSubscriptionsPage(),
        ),
        WebMenuItem(
          title: 'Ads',
          icon: Icons.campaign_outlined,
          page: SuperAdminAdsPage(),
        ),
      ],
    );
  }
}