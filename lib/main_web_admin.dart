import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'main.dart' show SphotApp;

/// Point d'entree Web ADMIN.
/// Reutilise le routeur SPHOT principal au lieu du formulaire
/// d'inscription historique avec des donnees ProConnect fictives.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // La connexion professionnelle est l'accueil par defaut pour ce point
  // d'entree. Les liens /#/super-admin et autres routes existantes restent
  // disponibles via le routeur commun.
  final fragment = Uri.base.fragment.trim();
  final initialRoute = fragment.isEmpty
      ? '/professional-login'
      : (fragment.startsWith('/') ? fragment : '/$fragment');

  runApp(SphotApp(initialRoute: initialRoute));
}
