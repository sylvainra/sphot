import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../shared/sphot_access_page.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../shared/web_colors.dart';
import 'pages/advertiser_dashboard_page.dart';

const bool _advertiserDevBypassEnabled = bool.fromEnvironment(
  'SPHOT_ADVERTISER_DEV_BYPASS',
  defaultValue: false,
);
const String _correctionEndpoint =
    'https://us-central1-sphot-ab80b.cloudfunctions.net/'
    'redeemAdvertiserCorrectionAccess';

class WebAdvertiserApp extends StatelessWidget {
  const WebAdvertiserApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SPHOT Annonceur',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: WebColors.blue,
      scaffoldBackgroundColor: const Color(0xFFF3F6FA),
    ),
    home: const WebAdvertiserAccessPage(),
  );
}

class WebAdvertiserAccessPage extends StatefulWidget {
  const WebAdvertiserAccessPage({
    super.key,
    this.correctionRequestId,
    this.correctionToken,
    this.autoStart = false,
  });

  final String? correctionRequestId;
  final String? correctionToken;
  final bool autoStart;

  @override
  State<WebAdvertiserAccessPage> createState() =>
      _WebAdvertiserAccessPageState();
}

class _WebAdvertiserAccessPageState extends State<WebAdvertiserAccessPage> {
  bool _starting = false;
  bool _opened = false;
  bool _modificationRequested = false;
  String? _requestId;
  User? _user;
  String? _error;

  bool get _isCorrection =>
      (widget.correctionRequestId?.trim().isNotEmpty ?? false) &&
      (widget.correctionToken?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    if (_isCorrection ||
        _advertiserDevBypassEnabled ||
        (kIsWeb && widget.autoStart)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    }
  }

  Future<void> _open() async {
    if (_starting) return;

    if (!kIsWeb && !_isCorrection && !_advertiserDevBypassEnabled) {
      setState(() {
        _starting = true;
        _error = null;
      });

      final opened = await launchUrl(
        Uri.parse('https://sphot.app/#/advertiser?start=1'),
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;

      setState(() {
        _starting = false;
        if (!opened) {
          _error = 'Impossible d’ouvrir la demande SPHOT PUBLICITAIRE.';
        }
      });
      return;
    }

    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      if (_advertiserDevBypassEnabled && !_isCorrection) {
        _requestId = 'advertiser-dev-${DateTime.now().millisecondsSinceEpoch}';
      } else if (_isCorrection) {
        final response = await http.post(
          Uri.parse(_correctionEndpoint),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'requestId': widget.correctionRequestId!.trim(),
            'token': widget.correctionToken!.trim(),
          }),
        );
        final body = response.body.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        _modificationRequested = body['modificationRequested'] == true;
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            body['error']?.toString() ?? 'Lien invalide ou expiré.',
          );
        }
        final credential = await FirebaseAuth.instance.signInWithCustomToken(
          body['token']?.toString() ?? '',
        );
        _user = credential.user;
        _requestId =
            body['requestId']?.toString() ?? widget.correctionRequestId!.trim();
      } else {
        // Ce bouton crée une candidature ; il ne reprend jamais une session
        // de consultation, de correction ou d'annonceur déjà approuvé.
        final auth = FirebaseAuth.instance;
        await auth.signOut();
        final user = (await auth.signInAnonymously()).user;
        if (user == null) throw Exception('Session annonceur indisponible.');
        _user = user;
        _requestId = user.uid;
      }
      if (!mounted) return;
      setState(() {
        _opened = true;
        _starting = false;
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = error.code == 'operation-not-allowed'
            ? 'Activez la connexion anonyme dans Firebase Authentication.'
            : '[${error.code}] ${error.message ?? 'Erreur Firebase'}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_opened) {
      return AdvertiserDashboardPage(
        user: _user,
        advertiserRequestId: _requestId,
        existingRequestOnly: _isCorrection,
        developmentBypass: _advertiserDevBypassEnabled && !_isCorrection,
        onSignOut: () async {
          await FirebaseAuth.instance.signOut();
          if (mounted) setState(() => _opened = false);
        },
      );
    }
    return _StartPage(
      loading: _starting,
      correction: _isCorrection,
      modificationRequested: _modificationRequested,
      error: _error,
      onStart: _open,
    );
  }
}

class _StartPage extends StatelessWidget {
  const _StartPage({
    required this.loading,
    required this.correction,
    required this.modificationRequested,
    required this.error,
    required this.onStart,
  });

  final bool loading;
  final bool correction;
  final bool modificationRequested;
  final String? error;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) => SphotAccessPage(
    title: 'SPHOT PUBLICITAIRE',
    onBack: () => Navigator.of(context).pushNamedAndRemoveUntil('/map', (route) => false),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          correction
              ? (modificationRequested
                    ? 'Retrouvez votre dossier et effectuez la modification demandée.'
                    : 'Retrouvez votre dossier et votre demande.')
              : 'Accès réservé aux professionnels.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: WebColors.blue,
            fontSize: 16,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (!correction) ...[
          const SizedBox(height: 16),
          Text(
            kIsWeb
                ? "Professionnels, créez votre SPHOT PUBLICITAIRE en quelques clics, après validation de votre demande préalable auprès de l'équipe SPHOT."
                : "Pour créer votre SPHOT PUBLICITAIRE dans de meilleures conditions de confort et de lisibilité, vous allez être redirigé vers le site SPHOT afin de compléter votre demande.",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WebColors.blue,
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEEEE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WebColors.red),
            ),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WebColors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SphotAccessButton(
          loading: loading,
          onPressed: onStart,
          label: correction
              ? 'ACCÉDER À MA DEMANDE'
              : kIsWeb
                  ? 'COMMENCER MA DEMANDE'
                  : 'CONTINUER SUR LE SITE SPHOT',
        ),
      ],
    ),
  );
}
