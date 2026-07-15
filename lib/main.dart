import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'map/map_page.dart';
import 'pages/advertiser_access_page.dart';
import 'pages/admin/admin_trial_request_page.dart';
import 'services/advertiser_auth_service.dart';
import 'services/web_pending_auth_storage.dart';
import 'web/admin/web_admin_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

print('Uri.base = ${Uri.base}');
print('fragment = ${Uri.base.fragment}');

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

  runApp(const SphotApp());
}

class SphotApp extends StatelessWidget {
  const SphotApp({super.key});

  Route<dynamic> _generateRoute(RouteSettings settings) {
    final routeName = settings.name ?? '/';
    final uri = Uri.parse(routeName);

    if (uri.path == '/web-admin') {
  final requestId =
      uri.queryParameters['requestId']?.trim() ?? '';

  if (requestId.isNotEmpty) {
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => const WebAdminApp(),
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