import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'map/map_page.dart';
import 'pages/advertiser_access_page.dart';
import 'services/advertiser_auth_service.dart';
import 'services/web_pending_auth_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final pendingAuth = WebPendingAuthStorage.getPendingAuth();

  if (pendingAuth == 'advertiser') {
    WebPendingAuthStorage.clearPendingAuth();

    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AdvertiserAccessPage(),
    ));

    return;
  }

  runApp(const SphotApp());
}

class SphotApp extends StatelessWidget {
  const SphotApp({super.key});

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
      home: const MapPage(),
    );
  }
}