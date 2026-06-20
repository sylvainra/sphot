import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'web/shared/web_placeholder_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SphotWebSauveteurApp());
}

class SphotWebSauveteurApp extends StatelessWidget {
  const SphotWebSauveteurApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPHOT Sauveteur Web',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const WebPlaceholderPage(
        title: 'Portail Web Sauveteur SPHOT',
        subtitle: 'Interface sauveteur connectée au même Firebase / Firestore.',
      ),
    );
  }
}