import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'map/map_page.dart';
import 'map/profil_login_page.dart';
import 'web/shared/sphot_access_page.dart';
import 'web/advertiser/web_advertiser_app.dart';
import 'web/advertiser/pages/advertiser_first_access_page.dart';
import 'web/admin/pages/admin_access_page.dart';
import 'web/admin/pages/admin_trial_request_page.dart';
import 'web/admin/pages/admin_dashboard_page.dart';
import 'web/institutional/pages/institutional_main_courante_page.dart';
import 'web/super_admin/web_super_admin_app.dart';
import 'services/web_pending_auth_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final pendingAuth = WebPendingAuthStorage.getPendingAuth();

  if (pendingAuth == 'advertiser') {
    WebPendingAuthStorage.clearPendingAuth();
    if (Uri.base.fragment.trim().isEmpty) {
      runApp(const SphotApp(initialRoute: '/advertiser'));
      return;
    }
  }

  final institutionalToken =
      Uri.base.queryParameters['institutionnelMainCouranteToken']
          ?.trim() ??
      '';

  if (institutionalToken.isNotEmpty) {
    final encodedToken = Uri.encodeQueryComponent(institutionalToken);
    runApp(
      SphotApp(
        initialRoute:
            '/institutionnel-main-courante?token=$encodedToken',
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

  // Le navigateur Web utilise le fragment d'URL (/#/route).
  // Android transmet les App Links au moteur Flutter : il faut conserver
  // la route initiale reçue de la plateforme pour les démarrages à froid.
  final platformInitialRoute =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  final initialRoute = kIsWeb
      ? (fragment.isEmpty
          ? (Uri.base.path == '/sauveteur-login'
              ? '/sauveteur-login'
              : '/')
          : (fragment.startsWith('/') ? fragment : '/$fragment'))
      : (platformInitialRoute.isNotEmpty ? platformInitialRoute : '/');

  runApp(SphotApp(initialRoute: initialRoute));
}

class SphotApp extends StatelessWidget {
  final String initialRoute;

  const SphotApp({super.key, required this.initialRoute});

  Route<dynamic> _generateRoute(RouteSettings settings) {
    String routeName = settings.name?.trim() ?? '/';

    /*
     * Sécurité supplémentaire :
     * certains navigateurs peuvent transmettre "/" à Flutter alors que
     * la véritable route se trouve encore dans le fragment de l'URL.
     */
    if (routeName == '/' && Uri.base.fragment.trim().isNotEmpty) {
      final fragment = Uri.base.fragment.trim();

      routeName = fragment.startsWith('/') ? fragment : '/$fragment';
    }

    final uri = Uri.parse(routeName);

    if (uri.path == '/map') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const MapPage(),
      );
    }

    if (uri.path == '/advertiser') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => WebAdvertiserAccessPage(
          autoStart: uri.queryParameters['start'] == '1',
        ),
      );
    }

    if (uri.path == '/advertiser-correction') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => WebAdvertiserAccessPage(
          correctionRequestId: uri.queryParameters['requestId'],
          correctionToken: uri.queryParameters['token'],
        ),
      );
    }

    if (uri.path == '/advertiser-first-access') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => AdvertiserFirstAccessPage(
          login: uri.queryParameters['login'] ?? '',
          token: uri.queryParameters['token'] ?? '',
        ),
      );
    }

    if (uri.path == '/professional-login') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const ProfilLoginPage(),
      );
    }

    if (uri.path == '/sauveteur-login') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => kIsWeb
            ? const _SauveteurMobileAccessPage()
            : const ProfilLoginPage(),
      );
    }

    if (uri.path == '/login') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const ProfilLoginPage(),
      );
    }

    if (uri.path == '/institutionnel-main-courante') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => InstitutionalMainCourantePage(
          token: uri.queryParameters['token'] ?? '',
        ),
      );
    }

    if (uri.path == '/admin-request') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const AdminAccessPage(),
      );
    }

    if (uri.path == '/admin-request-form') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const AdminTrialRequestPage(),
      );
    }

    if (uri.path == '/super-admin') {
      final token = uri.queryParameters['token']?.trim() ?? '';
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => _SuperAdminSessionGate(token: token),
      );
    }

    if (uri.path == '/web-admin') {
      final requestId = uri.queryParameters['requestId']?.trim() ?? '';

      if (requestId.isNotEmpty) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminDashboardPage(),
        );
      }
    }

    if (uri.path == '/admin-request-correction') {
      final requestId = uri.queryParameters['requestId']?.trim() ?? '';

      if (requestId.isNotEmpty) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => AdminTrialRequestPage(correctionRequestId: requestId),
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
      supportedLocales: const [Locale('fr', 'FR')],
      theme: ThemeData(primarySwatch: Colors.blue),
      onGenerateInitialRoutes: (initialRouteName) => [
        _generateRoute(RouteSettings(name: initialRouteName)),
      ],
      onGenerateRoute: _generateRoute,
    );
  }
}

// Page de repli : le domaine HTTPS est réservé aux liens de l'application.
class _SauveteurMobileAccessPage extends StatelessWidget {
  const _SauveteurMobileAccessPage();

  @override
  Widget build(BuildContext context) {
    return SphotAccessPage(
      title: 'SPHOT SAUVETEUR',
      onBack: () => Navigator.of(context)
          .pushNamedAndRemoveUntil('/map', (route) => false),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smartphone_rounded, color: Color(0xFF1E3A8A), size: 45),
          SizedBox(height: 16),
          Text(
            'La connexion SPHOT SAUVETEUR se fait dans l’application mobile SPHOT.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF1E3A8A),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Installez ou ouvrez l’application SPHOT sur votre téléphone '
            'pour accéder à votre espace sauveteur.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _SuperAdminSessionGate extends StatefulWidget {
  const _SuperAdminSessionGate({required this.token});

  final String token;

  @override
  State<_SuperAdminSessionGate> createState() => _SuperAdminSessionGateState();
}

class _SuperAdminSessionGateState extends State<_SuperAdminSessionGate> {
  bool _loading = true;
  bool _authorized = false;
  String _pricingSessionToken = '';

  @override
  void initState() {
    super.initState();
    _consumeSession();
  }

  Future<void> _consumeSession() async {
    try {
      if (widget.token.isEmpty) return;

      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'consumeSuperAdminWebSession',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'token': widget.token}),
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data['success'] == true) {
        final pricingToken = data['pricingSessionToken']?.toString() ?? '';
        if (pricingToken.isEmpty) return;
        final firebaseToken = data['firebaseToken']?.toString() ?? '';
        if (firebaseToken.isNotEmpty) {
          final credential = await FirebaseAuth.instance.signInWithCustomToken(
            firebaseToken,
          );
          // Les claims doivent provenir du serveur Super Admin et expirer.
          final tokenResult = await credential.user?.getIdTokenResult(true);
          final claims = tokenResult?.claims ?? const <String, dynamic>{};
          final expiry = claims['sphotSaSessionExpiresAt'];
          final expiryMillis = expiry is num ? expiry.toInt() : 0;
          if (claims['role'] != 'SPHOT_SUPER_ADMIN' ||
              claims['sphotSuperAdmin'] != true ||
              expiryMillis <= DateTime.now().millisecondsSinceEpoch) {
            throw StateError('Identite Firebase Super Admin non valide.');
          }
        } else {
          // Compatibilite temporaire avec la fonction deja publiee.
          // Ne pas activer les regles Firestore restrictives avant son deploy.
          debugPrint('Super Admin : fonction Firebase pas encore mise a jour.');
        }
        _pricingSessionToken = pricingToken;
        _authorized = true;
      }
    } catch (error, stackTrace) {
      debugPrint('Ouverture session Super Admin impossible : $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_authorized) {
      return const Scaffold(
        body: Center(
          child: Text(
            'SESSION SUPER ADMIN INVALIDE OU EXPIRÉE',
            style: TextStyle(
              color: Color(0xFFDC2626),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }

    return WebSuperAdminApp(pricingSessionToken: _pricingSessionToken);
  }
}
