import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../pages/sauveteur/change_password_page.dart';
import '../pages/sauveteur/sauveteur_legal_acceptance_page.dart';
import '../pages/sauveteur/sauveteur_menu_page.dart';
import '../web/admin/pages/admin_change_password_page.dart';
import '../web/admin/pages/admin_dashboard_page.dart';
import '../web/advertiser/pages/advertiser_change_password_page.dart';
import '../web/advertiser/pages/advertiser_dashboard_page.dart';
import '../web/shared/sphot_access_page.dart';

enum _LoginAudience {
  admin,
  advertiser,
}

class ProfilLoginPage extends StatefulWidget {
  const ProfilLoginPage({super.key});

  @override
  State<ProfilLoginPage> createState() => _ProfilLoginPageState();
}

class _ProfilLoginPageState extends State<ProfilLoginPage>
    with WidgetsBindingObserver {
  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _red = Color(0xFFDC2626);

  static const String _functionsBaseUrl =
      'https://us-central1-sphot-ab80b.cloudfunctions.net';

  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _identifierFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isEditing = false;
  bool _showPassword = false;
  bool _isResolvingIdentity = false;
  bool _isLoggingIn = false;
  int _step = 0;

  String? _errorMessage;
  List<String> _accountTypes = const [];
  _LoginAudience? _selectedAudience;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    final bottomInset =
        WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;

    if (bottomInset == 0 && _isEditing) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        FocusScope.of(context).unfocus();
        setState(() => _isEditing = false);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _identifierController.dispose();
    _passwordController.dispose();
    _identifierFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _activateEditingMode() {
    if (_isEditing) return;
    setState(() => _isEditing = true);
  }

  void _closeKeyboard() {
    FocusScope.of(context).unfocus();
    if (_isEditing) {
      setState(() => _isEditing = false);
    }
  }

  Future<void> _goBack() async {
    FocusScope.of(context).unfocus();

    if (_step == 1) {
      setState(() {
        _step = 0;
        _passwordController.clear();
        _accountTypes = const [];
        _selectedAudience = null;
        _errorMessage = null;
      });
      return;
    }

    final navigator = Navigator.of(context);
    final popped = await navigator.maybePop();

    if (!popped && mounted) {
      navigator.pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  bool get _hasAdmin => _accountTypes.contains('ADMIN');
  bool get _hasAdvertiser => _accountTypes.contains('ANNONCEUR');
  bool get _hasSauveteur => _accountTypes.contains('SAUVETEUR');
  bool get _hasProfessionalAccount => _hasAdmin || _hasAdvertiser;

  Future<void> _continueWithIdentifier() async {
    if (_isResolvingIdentity || _isLoggingIn) return;

    final identifier = _identifierController.text.trim().toLowerCase();

    FocusScope.of(context).unfocus();

    if (identifier.isEmpty) {
      setState(() {
        _errorMessage =
            'Saisissez votre identifiant ou votre adresse e-mail.';
      });
      return;
    }

    setState(() {
      _isResolvingIdentity = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_functionsBaseUrl/resolveLoginIdentity'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'login': identifier}),
      );

      if (response.statusCode == 404) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Identifiant inconnu.';
        });
        return;
      }

      if (response.statusCode != 200) {
        throw StateError(
          'Service de résolution indisponible (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        throw const FormatException('Réponse de connexion invalide.');
      }

      final accountTypes = decoded['accountTypes'] is List
          ? (decoded['accountTypes'] as List)
              .map((value) => value.toString().toUpperCase())
              .toSet()
              .toList()
          : <String>[];

      if (accountTypes.isEmpty) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Identifiant inconnu.';
        });
        return;
      }

      _LoginAudience? audience;
      if (accountTypes.contains('ADMIN') &&
          !accountTypes.contains('ANNONCEUR')) {
        audience = _LoginAudience.admin;
      } else if (accountTypes.contains('ANNONCEUR') &&
          !accountTypes.contains('ADMIN')) {
        audience = _LoginAudience.advertiser;
      }

      if (!mounted) return;

      setState(() {
        _accountTypes = accountTypes;
        _selectedAudience = audience;
        _step = 1;
        _errorMessage = null;
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        _passwordFocusNode.requestFocus();
      });
    } catch (error, stackTrace) {
      debugPrint('Résolution identifiant SPHOT impossible : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Connexion momentanément indisponible. Réessayez dans quelques instants.';
      });
    } finally {
      if (mounted) {
        setState(() => _isResolvingIdentity = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _tryLogin({
    required String endpoint,
    required String login,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/$endpoint'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'login': login,
        'password': password,
      }),
    );

    if (response.statusCode == 401) {
      return null;
    }

    if (response.statusCode != 200) {
      throw StateError(
        'Service $endpoint indisponible (HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      return null;
    }

    return decoded;
  }

  Future<void> _login() async {
    if (_isLoggingIn || _isResolvingIdentity) return;

    final login = _identifierController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    FocusScope.of(context).unfocus();

    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Saisissez votre mot de passe.';
      });
      return;
    }

    if (_hasAdmin &&
        _hasAdvertiser &&
        _selectedAudience == null) {
      setState(() {
        _errorMessage =
            'Sélectionnez SPHOT ADMIN ou SPHOT PUBLICITAIRE.';
      });
      return;
    }

    setState(() {
      _isLoggingIn = true;
      _errorMessage = null;
    });

    try {
      Map<String, dynamic>? decoded;

      if (_hasProfessionalAccount) {
        switch (_selectedAudience) {
          case _LoginAudience.admin:
            decoded = await _tryLogin(
              endpoint: 'loginAdmin',
              login: login,
              password: password,
            );
            break;
          case _LoginAudience.advertiser:
            decoded = await _tryLogin(
              endpoint: 'loginAdvertiser',
              login: login,
              password: password,
            );
            break;
          case null:
            break;
        }

        /*
         * Un Super Admin peut être enregistré dans le circuit sauveteur.
         * S'il possède aussi une adresse utilisée côté professionnel,
         * on conserve la reconnaissance historique sans lui imposer
         * une page de connexion dédiée.
         */
        if (decoded == null && _hasSauveteur) {
          final potentialSuperAdmin = await _tryLogin(
            endpoint: 'loginSauveteur',
            login: login,
            password: password,
          );

          if (potentialSuperAdmin != null &&
              (potentialSuperAdmin['userRole'] ?? '')
                      .toString()
                      .toUpperCase() ==
                  'SUPER_ADMIN') {
            decoded = potentialSuperAdmin;
          }
        }
      } else if (_hasSauveteur) {
        decoded = await _tryLogin(
          endpoint: 'loginSauveteur',
          login: login,
          password: password,
        );
      }

      if (decoded == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Mot de passe incorrect.';
        });
        return;
      }

      final userRole =
          (decoded['userRole'] ?? '').toString().toUpperCase();

      if (userRole == 'SUPER_ADMIN') {
        await _openSuperAdmin(decoded);
        return;
      }

      if (userRole == 'ANNONCEUR') {
        await _openAdvertiser(decoded);
        return;
      }

      if (_selectedAudience == _LoginAudience.admin || userRole == 'ADMIN') {
        await _openAdmin(decoded);
        return;
      }

      await _openSauveteur(decoded);
    } catch (error, stackTrace) {
      debugPrint('Erreur de connexion SPHOT : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Connexion impossible. Vérifiez votre connexion internet et réessayez.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  Future<void> _openSauveteur(Map<String, dynamic> result) async {
    final login = _identifierController.text.trim().toLowerCase();
    final userRole = (result['userRole'] ?? 'SAUVETEUR').toString();
    final territoireId = (result['territoireId'] ?? '').toString();
    final mustChangePassword = result['mustChangePassword'] == true;
    final sphotMode = (result['sphotMode'] ?? 'OFF').toString().toUpperCase();
    final sphotModeReason =
        (result['sphotModeReason'] ?? 'administration_diffusion_off')
            .toString();
    final sauveteurSessionToken =
        (result['sauveteurSessionToken'] ?? '').toString();
    final canManageRestrictedOperationalData =
        result['canManageRestrictedOperationalData'] == true;
    final legalAcceptanceRequired =
        result['legalAcceptanceRequired'] == true;
    final postesAffectes = result['postesAffectes'] is List
        ? (result['postesAffectes'] as List)
            .map((value) => value.toString())
            .where((value) => value.trim().isNotEmpty)
            .toList()
        : <String>[];

    final modernSauveteurBackend =
        result.containsKey('sphotMode') &&
        result.containsKey('sphotModeReason') &&
        result.containsKey('legalAcceptanceRequired') &&
        sauveteurSessionToken.trim().isNotEmpty;

    if (userRole.toUpperCase() != 'SUPER_ADMIN' &&
        !modernSauveteurBackend) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Le service SPHOT SAUVETEUR n’est pas à jour. '
            'Les Cloud Functions doivent être redéployées avant de poursuivre.';
      });
      return;
    }

    if (!mounted) return;

    if (mustChangePassword) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChangePasswordPage(
            login: login,
            territoireId: territoireId,
            userRole: userRole,
            sphotMode: sphotMode,
            sphotModeReason: sphotModeReason,
            sauveteurSessionToken: sauveteurSessionToken,
            postesAffectes: postesAffectes,
            canManageRestrictedOperationalData:
                canManageRestrictedOperationalData,
          ),
        ),
      );
      return;
    }

    if (legalAcceptanceRequired) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SauveteurLegalAcceptancePage(
            login: login,
            territoireId: territoireId,
            userRole: userRole,
            sphotMode: sphotMode,
            sphotModeReason: sphotModeReason,
            sauveteurSessionToken: sauveteurSessionToken,
            postesAffectes: postesAffectes,
            canManageRestrictedOperationalData:
                canManageRestrictedOperationalData,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SauveteurMenuPage(
          profileColor: const Color(0xFFFF0000),
          userRole: userRole,
          territoireId: territoireId,
          login: login,
          sphotMode: sphotMode,
          sphotModeReason: sphotModeReason,
          sauveteurSessionToken: sauveteurSessionToken,
          postesAffectes: postesAffectes,
          canManageRestrictedOperationalData:
              canManageRestrictedOperationalData,
        ),
      ),
    );
  }

  Future<void> _openAdmin(Map<String, dynamic> decoded) async {
    final login = _identifierController.text.trim().toLowerCase();
    final mustChangePassword = decoded['mustChangePassword'] == true;
    final userRole = (decoded['userRole'] ?? 'ADMIN').toString();
    final adminUid = (decoded['adminUid'] ?? '').toString();
    final territoireId = (decoded['territoireId'] ?? '').toString();
    final civilite = (decoded['civilite'] ?? '').toString();
    final prenom = (decoded['prenom'] ?? '').toString();
    final nom = (decoded['nom'] ?? '').toString();
    final mainCouranteToken =
        (decoded['mainCouranteToken'] ?? '').toString();

    if (!mounted) return;

    if (mustChangePassword) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AdminChangePasswordPage(
            login: login,
            adminUid: adminUid,
            territoireId: territoireId,
            userRole: userRole,
            civilite: civilite,
            prenom: prenom,
            nom: nom,
            mainCouranteToken: mainCouranteToken,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdminDashboardPage(
          adminUid: adminUid,
          territoireId: territoireId,
          mainCouranteToken: mainCouranteToken,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _openAdvertiser(Map<String, dynamic> decoded) async {
    final login = _identifierController.text.trim().toLowerCase();
    final advertiserRequestId =
        (decoded['advertiserRequestId'] ?? '').toString();
    final firebaseToken = (decoded['firebaseToken'] ?? '').toString();
    final mustChangePassword = decoded['mustChangePassword'] == true;
    final prenom = (decoded['prenom'] ?? '').toString();
    final nom = (decoded['nom'] ?? '').toString();

    if (advertiserRequestId.isEmpty || firebaseToken.isEmpty) {
      throw StateError('Session Firebase annonceur absente.');
    }

    final credential = await FirebaseAuth.instance.signInWithCustomToken(
      firebaseToken,
    );

    if (!mounted) return;

    if (mustChangePassword) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AdvertiserChangePasswordPage(
            login: login,
            advertiserRequestId: advertiserRequestId,
            firstName: prenom,
            lastName: nom,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdvertiserDashboardPage(
          user: credential.user,
          advertiserRequestId: advertiserRequestId,
          approvedAccess: true,
          onSignOut: FirebaseAuth.instance.signOut,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _openSuperAdmin(Map<String, dynamic> decoded) async {
    final token = (decoded['webSessionToken'] ?? '').toString().trim();

    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'La session Super Admin n’a pas pu être créée.';
      });
      return;
    }

    if (!mounted) return;

    final route = Uri(
      path: '/super-admin',
      queryParameters: {'token': token},
    ).toString();

    Navigator.of(context).pushNamedAndRemoveUntil(
      route,
      (route) => false,
    );
  }

  Future<void> _showLegalDocument({
    required String documentId,
    required String title,
  }) async {
    FocusScope.of(context).unfocus();

    try {
      final metadataSnapshot = await FirebaseFirestore.instance
          .collection('legalDocuments')
          .doc('metadata')
          .get();

      final metadata = metadataSnapshot.data() ?? {};
      final version = (metadata['legalVersion'] ??
              metadata['version'] ??
              metadata['activeVersion'] ??
              '1.0')
          .toString();

      final documentSnapshot = await FirebaseFirestore.instance
          .collection('legalDocuments')
          .doc(documentId)
          .get();

      final chaptersSnapshot = await FirebaseFirestore.instance
          .collection('legalDocuments')
          .doc(documentId)
          .collection('chapters')
          .orderBy(FieldPath.documentId)
          .get();

      if (!mounted) return;

      final document = documentSnapshot.data() ?? {};
      final chapters =
          chaptersSnapshot.docs.map((chapter) => chapter.data()).toList();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            title,
            style: const TextStyle(
              color: _blue,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Version : $version',
                    style: const TextStyle(
                      color: _red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if ((document['title'] ?? '').toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      document['title'].toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                  ...chapters.map((chapter) {
                    final chapterTitle =
                        (chapter['title'] ?? chapter['titre'] ?? '').toString();
                    final chapterContent =
                        (chapter['content'] ?? chapter['texte'] ?? '').toString();

                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (chapterTitle.trim().isNotEmpty)
                            Text(
                              chapterTitle,
                              style: const TextStyle(
                                color: _blue,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          if (chapterContent.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              chapterContent,
                              style: const TextStyle(
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'FERMER',
                style: TextStyle(
                  color: _red,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Lecture du document juridique impossible : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Impossible d’ouvrir ce document juridique pour le moment.';
      });
    }
  }

  Future<void> _openProfessionalCreation() async {
    final choice = await showDialog<_LoginAudience>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'CRÉER UN ACCÈS PROFESSIONNEL',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _blue,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Choisissez l’espace professionnel que vous souhaitez créer.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            Center(
              child: SizedBox(
                width: 190,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext)
                      .pop(_LoginAudience.admin),
                  child: const Text(
                    'SPHOT ADMIN',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: 190,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext)
                      .pop(_LoginAudience.advertiser),
                  child: const Text(
                    'SPHOT PUBLICITAIRE',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == _LoginAudience.admin) {
      Navigator.of(context).pushNamed('/admin-request');
      return;
    }

    Navigator.of(context).pushNamed('/advertiser');
  }

  InputDecoration _inputDecoration({
    required String hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: _blue,
        fontWeight: FontWeight.w700,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withOpacity(0.14),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _blue, width: 1.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _blue, width: 1.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _red, width: 2.2),
      ),
    );
  }

  Widget _errorArea() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _errorMessage == null
          ? const SizedBox(height: 8)
          : Padding(
              key: ValueKey(_errorMessage),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _red,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
    );
  }

  Widget _buildLegalNotice() {
    const linkStyle = TextStyle(
      color: _blue,
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
    );

    return Column(
      children: [
        const Text(
          'En continuant, vous reconnaissez avoir pris connaissance des documents juridiques SPHOT :',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12.5,
            height: 1.35,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 2,
          runSpacing: 0,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _showLegalDocument(
                documentId: 'cgu',
                title: 'Conditions Générales d’Utilisation',
              ),
              child: const Text(
                'Conditions Générales d’Utilisation',
                style: linkStyle,
              ),
            ),
            const Text(
              '•',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _showLegalDocument(
                documentId: 'privacyPolicy',
                title: 'Politique de confidentialité',
              ),
              child: const Text(
                'Politique de confidentialité',
                style: linkStyle,
              ),
            ),
            const Text(
              '•',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _showLegalDocument(
                documentId: 'rgpdNotice',
                title: 'Informations RGPD',
              ),
              child: const Text(
                'RGPD',
                style: linkStyle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdentityStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'IDENTIFIEZ-VOUS',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _blue,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Saisissez votre identifiant ou votre adresse e-mail',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _blue,
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _identifierController,
          focusNode: _identifierFocusNode,
          autofocus: true,
          enabled: !_isResolvingIdentity && !_isLoggingIn,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [
            AutofillHints.username,
            AutofillHints.email,
          ],
          onTap: _activateEditingMode,
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() => _errorMessage = null);
            }
          },
          onSubmitted: (_) => _continueWithIdentifier(),
          style: const TextStyle(
            color: _blue,
            fontWeight: FontWeight.w700,
          ),
          decoration: _inputDecoration(
            hintText: 'Identifiant ou adresse e-mail',
          ),
        ),
        const SizedBox(height: 14),
        SphotAccessButton(
          label: 'CONTINUER',
          loading: _isResolvingIdentity,
          onPressed: _continueWithIdentifier,
        ),
        _errorArea(),
        const SizedBox(height: 12),
        _buildLegalNotice(),
        const SizedBox(height: 18),
        Container(
          height: 1,
          color: _blue.withOpacity(0.22),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed:
              _isResolvingIdentity ? null : _openProfessionalCreation,
          icon: const Icon(Icons.add_business_rounded, size: 20),
          label: const Text(
            'CRÉER UN ACCÈS PROFESSIONNEL',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          style: TextButton.styleFrom(
            foregroundColor: _blue,
          ),
        ),
      ],
    );
  }

  Widget _buildAudienceChoice() {
    final choices = <Widget>[];

    if (_hasAdmin) {
      choices.add(
        RadioListTile<_LoginAudience>(
          value: _LoginAudience.admin,
          groupValue: _selectedAudience,
          onChanged: _isLoggingIn
              ? null
              : (value) => setState(() => _selectedAudience = value),
          activeColor: _red,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'SPHOT ADMIN',
            style: TextStyle(
              color: _blue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    if (_hasAdvertiser) {
      choices.add(
        RadioListTile<_LoginAudience>(
          value: _LoginAudience.advertiser,
          groupValue: _selectedAudience,
          onChanged: _isLoggingIn
              ? null
              : (value) => setState(() => _selectedAudience = value),
          activeColor: _red,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'SPHOT PUBLICITAIRE',
            style: TextStyle(
              color: _blue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    if (choices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Espace de connexion',
            style: TextStyle(
              color: _blue,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        ...choices,
      ],
    );
  }

  Widget _buildPasswordStep() {
    final identifier = _identifierController.text.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'S’IDENTIFIER',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _blue,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                identifier,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _blue,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: _isLoggingIn
                  ? null
                  : () {
                      setState(() {
                        _step = 0;
                        _passwordController.clear();
                        _accountTypes = const [];
                        _selectedAudience = null;
                        _errorMessage = null;
                      });
                      Future.delayed(
                        const Duration(milliseconds: 80),
                        () {
                          if (mounted) {
                            _identifierFocusNode.requestFocus();
                          }
                        },
                      );
                    },
              child: const Text(
                'Modifier',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        _buildAudienceChoice(),
        const SizedBox(height: 8),
        TextField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          enabled: !_isLoggingIn,
          obscureText: !_showPassword,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          onTap: _activateEditingMode,
          onChanged: (_) {
            if (_errorMessage != null) {
              setState(() => _errorMessage = null);
            }
          },
          onSubmitted: (_) => _login(),
          style: const TextStyle(
            color: _blue,
            fontWeight: FontWeight.w700,
          ),
          decoration: _inputDecoration(
            hintText: 'Mot de passe',
            suffixIcon: IconButton(
              tooltip: _showPassword
                  ? 'Masquer le mot de passe'
                  : 'Afficher le mot de passe',
              onPressed: _isLoggingIn
                  ? null
                  : () {
                      setState(() => _showPassword = !_showPassword);
                    },
              icon: Icon(
                _showPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: _red,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SphotAccessButton(
          label: 'SE CONNECTER',
          loading: _isLoggingIn,
          onPressed: _login,
        ),
        _errorArea(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SphotAccessPage(
      title: 'CONNEXION SPHOT',
      onBackgroundTap: _closeKeyboard,
      onBack: _goBack,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(
          key: ValueKey(_step),
          child: _step == 0
              ? _buildIdentityStep()
              : _buildPasswordStep(),
        ),
      ),
    );
  }
}
