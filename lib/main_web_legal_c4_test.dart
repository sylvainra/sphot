import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'web/super_admin/widgets/super_admin_legal_test_corpus_editor.dart';

/// Point d'entrée indépendant pour l'aperçu local du corpus juridique C4 TEST.
/// Ne charge ni le routeur SPHOT, ni ses fonctions ou parcours de production.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SuperAdminLegalTestCorpusEditor.testFlag ||
      !SuperAdminLegalTestCorpusEditor.previewOnly) {
    throw StateError('APERÇU C4 TEST REFUSÉ : deux drapeaux TEST obligatoires.');
  }

  const options = FirebaseOptions(
    apiKey: 'AIzaSyBubkTUDpRJBpMQ19VNnOEfFoNeTpnveUU',
    appId: '1:46473700026:web:5e266ebd72801b28311883',
    messagingSenderId: '46473700026',
    projectId: 'sphot-c4-test-20261029',
    authDomain: 'sphot-c4-test-20261029.firebaseapp.com',
    storageBucket: 'sphot-c4-test-20261029.firebasestorage.app',
  );

  final app = await Firebase.initializeApp(options: options);
  if (app.options.projectId != SuperAdminLegalTestCorpusEditor.testProjectId) {
    throw StateError('APERÇU REFUSÉ : projet Firebase différent de C4 TEST.');
  }

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'SPHOT — Corpus juridique C4 TEST',
    home: Scaffold(
      appBar: _LegalTestHeader(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 900),
              child: SuperAdminLegalTestCorpusEditor(),
            ),
          ),
        ),
      ),
    ),
  ));
}

class _LegalTestHeader extends StatelessWidget implements PreferredSizeWidget {
  const _LegalTestHeader();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
        title: const Text('SPHOT · Documents juridiques C4 TEST'),
        backgroundColor: const Color(0xFF16317C),
        foregroundColor: Colors.white,
      );
}
