import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'pages/professional/professional_login_page.dart';
import 'web/admin/web_admin_registration_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SphotWebAdminApp());
}

class SphotWebAdminApp extends StatelessWidget {
  const SphotWebAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPHOT Admin Web',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.orange,
      ),
      routes: {
        '/professional-login': (context) =>
            const ProfessionalLoginPage(),
      },
      home: const WebAdminRegistrationPage(
        proConnectUid: 'test-admin',
        proConnectEmail: 'admin@sphot.app',
        proConnectNom: 'DUPONT',
        proConnectPrenom: 'Jean',
        proConnectOrganisation: 'Mairie de Nice',
        proConnectSiret: '12345678901234',
        proConnectSiren: '123456789',
      ),
    );
  }
}