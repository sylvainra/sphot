import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'web/super_admin/widgets/super_admin_legal_test_corpus_editor.dart';

/// Entrée C4 indépendante et authentifiée pour l'enregistrement des brouillons.
/// Ne charge aucun routeur, compte ni document de la production SPHOT.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const importMode = bool.fromEnvironment(
    'SPHOT_LEGAL_C4_IMPORT_MODE', defaultValue: false);
  if (!SuperAdminLegalTestCorpusEditor.testFlag ||
      SuperAdminLegalTestCorpusEditor.previewOnly || !importMode) {
    throw StateError('ÉDITION C4 REFUSÉE : mode TEST et mode IMPORT '
        'obligatoires ; aperçu seul interdit pour les écritures.');
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
  if (app.options.projectId !=
      SuperAdminLegalTestCorpusEditor.testProjectId) {
    throw StateError('ÉDITION C4 REFUSÉE : projet Firebase non autorisé.');
  }

  runApp(const _C4LegalImportApp());
}

class _C4LegalImportApp extends StatelessWidget {
  const _C4LegalImportApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SPHOT — Brouillons juridiques C4',
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF16317C),
            foregroundColor: Colors.white,
            title: const Text('SPHOT · Documents juridiques — C4 BROUILLONS'),
          ),
          body: const _C4AuthGate(),
        ),
      );
}

class _C4AuthGate extends StatelessWidget {
  const _C4AuthGate();

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Connexion Firebase indisponible.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final user = snapshot.data;
          return user == null
              ? const _C4LoginForm()
              : _C4AuthorizedEditor(key: ValueKey(user.uid), user: user);
        },
      );
}

class _C4AuthorizedEditor extends StatefulWidget {
  const _C4AuthorizedEditor({super.key, required this.user});

  final User user;

  @override
  State<_C4AuthorizedEditor> createState() => _C4AuthorizedEditorState();
}

class _C4AuthorizedEditorState extends State<_C4AuthorizedEditor> {
  late final Future<bool> _authorization;

  @override
  void initState() {
    super.initState();
    _authorization = _readAuthorization();
  }

  Future<bool> _readAuthorization() async {
    final reference = FirebaseFirestore.instance
        .collection('legalC4Editors').doc(widget.user.uid);
    final snapshot = await reference.get();
    final data = snapshot.data() ?? <String, dynamic>{};
    return data['active'] == true && data['role'] == 'legal_editor';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _authorization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data != true) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 42,
                        color: Color(0xFFB91C1C)),
                    const SizedBox(height: 12),
                    const Text('Accès refusé : autorisation spécifique '
                        'aux brouillons juridiques C4 nécessaire.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('SE DÉCONNECTER'),
                    ),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        const Expanded(
                          child: Text('ENVIRONNEMENT C4 — BROUILLONS '
                              'UNIQUEMENT, AUCUNE PUBLICATION',
                              style: TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w800)),
                        ),
                        TextButton.icon(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          icon: const Icon(Icons.logout),
                          label: const Text('DÉCONNEXION'),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      const SuperAdminLegalTestCorpusEditor(),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class _C4LoginForm extends StatefulWidget {
  const _C4LoginForm();

  @override
  State<_C4LoginForm> createState() => _C4LoginFormState();
}

class _C4LoginFormState extends State<_C4LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Identifiant et mot de passe obligatoires.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: _password.text);
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() =>
          _error = 'Connexion au projet C4 refusée (${error.code}).');
    } catch (_) {
      if (mounted) setState(() => _error = 'Connexion au projet C4 impossible.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('CONNEXION SUPER ADMIN — C4 TEST',
                      style: TextStyle(fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF16317C))),
                  const SizedBox(height: 10),
                  const Text('Utilise exclusivement un compte déjà habilité '
                      'dans le projet Firebase C4. Aucun compte ne sera créé.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        labelText: 'Email du compte C4',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(
                        labelText: 'Mot de passe C4',
                        border: OutlineInputBorder()),
                  ),
                  if (_error != null) Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: Color(0xFFB91C1C))),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: Text(_busy ? 'CONNEXION…' : 'SE CONNECTER'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
