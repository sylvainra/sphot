import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;

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
  });

  final String? correctionRequestId;
  final String? correctionToken;

  @override
  State<WebAdvertiserAccessPage> createState() =>
      _WebAdvertiserAccessPageState();
}

class _WebAdvertiserAccessPageState extends State<WebAdvertiserAccessPage> {
  bool _starting = false;
  bool _opened = false;
  String? _requestId;
  User? _user;
  String? _error;

  bool get _isCorrection =>
      (widget.correctionRequestId?.trim().isNotEmpty ?? false) &&
      (widget.correctionToken?.trim().isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    if (_isCorrection || _advertiserDevBypassEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open());
    }
  }

  Future<void> _open() async {
    if (_starting) return;
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
        User? user = FirebaseAuth.instance.currentUser;
        user ??= (await FirebaseAuth.instance.signInAnonymously()).user;
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
      error: _error,
      onStart: _open,
    );
  }
}

class _StartPage extends StatelessWidget {
  const _StartPage({
    required this.loading,
    required this.correction,
    required this.error,
    required this.onStart,
  });

  final bool loading;
  final bool correction;
  final String? error;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('data/images/map_background.jpg', fit: BoxFit.cover),
        ColoredBox(color: Colors.white.withOpacity(0.72)),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: 540,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.97),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: WebColors.blue, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'data/icons/fire_red_icon.svg',
                    width: 42,
                    height: 58,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'SPHOT PUBLICITAIRE',
                    style: TextStyle(
                      color: WebColors.blue,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    correction
                        ? 'Retrouvez votre dossier et effectuez la modification demandée.'
                        : 'Créez votre demande annonceur en trois étapes. Aucun compte ProConnect n’est requis.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: WebColors.blue,
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: loading ? null : onStart,
                      icon: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.campaign_outlined),
                      label: Text(
                        loading
                            ? 'OUVERTURE DU DOSSIER…'
                            : correction
                            ? 'ACCÉDER À MA DEMANDE'
                            : 'COMMENCER MA DEMANDE',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: WebColors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 22,
          child: Center(
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: WebColors.blue, width: 2),
              ),
              child: IconButton(
                onPressed: () =>
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/', (route) => false),
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: WebColors.blue,
                  size: 36,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
