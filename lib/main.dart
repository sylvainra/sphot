import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'map/map_page.dart';
import 'pages/advertiser_access_page.dart';
import 'pages/admin/admin_trial_request_page.dart';
import 'pages/professional/professional_login_page.dart';
import 'web/admin/pages/admin_dashboard_page.dart';
import 'services/web_pending_auth_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final pendingAuth = WebPendingAuthStorage.getPendingAuth();

  if (pendingAuth == 'advertiser') {
    WebPendingAuthStorage.clearPendingAuth();

    runApp(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AdvertiserAccessPage(),
      ),
    );

    return;
  }

  /*
   * Avec une adresse comme :
   *
   * https://sphot.app/#/professional-login
   *
   * Uri.base.fragment contient :
   *
   * /professional-login
   */
  final fragment = Uri.base.fragment.trim();

  final initialRoute = fragment.isEmpty
      ? '/'
      : fragment.startsWith('/')
          ? fragment
          : '/$fragment';

  runApp(
    SphotApp(
      initialRoute: initialRoute,
    ),
  );
}

class SphotApp extends StatelessWidget {
  final String initialRoute;

  const SphotApp({
    super.key,
    required this.initialRoute,
  });

  Route<dynamic> _generateRoute(RouteSettings settings) {
    String routeName = settings.name?.trim() ?? '/';

    /*
     * Sécurité supplémentaire :
     * certains navigateurs peuvent transmettre "/" à Flutter alors que
     * la véritable route se trouve encore dans le fragment de l'URL.
     */
    if (routeName == '/' && Uri.base.fragment.trim().isNotEmpty) {
      final fragment = Uri.base.fragment.trim();

      routeName = fragment.startsWith('/')
          ? fragment
          : '/$fragment';
    }

    final uri = Uri.parse(routeName);

    if (uri.path == '/professional-login') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const ProfessionalLoginPage(),
      );
    }

    if (uri.path == '/web-admin') {
      final requestId =
          uri.queryParameters['requestId']?.trim() ?? '';

      if (requestId.isNotEmpty) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminDashboardPage(),
        );
      }
    }

    if (uri.path == '/admin-request-correction') {
      final requestId =
          uri.queryParameters['requestId']?.trim() ?? '';

      if (requestId.isNotEmpty) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => AdminTrialRequestPage(
            correctionRequestId: requestId,
          ),
        );
      }
    }

    return MaterialPageRoute(
      settings: settings,
      builder: (_) => const MapPage(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SPHOT',
      initialRoute: initialRoute,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
      ],
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      onGenerateRoute: _generateRoute,
    );
  }
}