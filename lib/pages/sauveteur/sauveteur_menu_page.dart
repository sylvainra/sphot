import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'sauveteur_actions_rapides_page.dart';
import 'sauveteur_espace_reserve_page.dart';
import 'sauveteur_meteo_terrestre_page.dart';
import 'sauveteur_meteo_marine_page.dart';
import 'sauveteur_recherche_personne_page.dart';
import 'sauveteur_ephemeride_dicton_page.dart';
import 'sauveteur_planning_page.dart';
import 'sauveteur_main_courante.dart';

class SauveteurMenuPage extends StatefulWidget {
  final Color profileColor;
  final String userRole;
  final String territoireId;
  final String login;
  final String sphotMode;
  final String sphotModeReason;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final bool canManageRestrictedOperationalData;

  const SauveteurMenuPage({
    super.key,
    required this.profileColor,
    required this.userRole,
    required this.territoireId,
    required this.login,
    required this.sphotMode,
    required this.sphotModeReason,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.canManageRestrictedOperationalData,
  });

  @override
  State<SauveteurMenuPage> createState() => _SauveteurMenuPageState();
}

class _SauveteurMenuPageState extends State<SauveteurMenuPage>
    with WidgetsBindingObserver {
  late String _userRole;
  late String _sphotMode;
  late String _sphotModeReason;
  late List<String> _postesAffectes;
  late bool _canManageRestrictedOperationalData;

  Timer? _modeRefreshTimer;
  bool _refreshingMode = false;

  bool get _isSphotOn => _sphotMode.toUpperCase() == 'ON';

  String get _modeExplanation {
    if (_isSphotOn) {
      return 'SPHOT ON : vous êtes autorisé à agir sur les données '
          'opérationnelles réelles des SPHOTS auxquels vous êtes affecté.';
    }

    switch (_sphotModeReason) {
      case 'no_active_assignment':
        return 'SPHOT OFF : aucun poste de secours ne vous est actuellement '
            'affecté. Vous pouvez utiliser l’application en mode préparation '
            'et test.';
      case 'assignment_not_started':
        return 'SPHOT OFF : votre période d’affectation n’a pas encore '
            'commencé. Vous pouvez préparer et tester SPHOT SAUVETEUR sans '
            'modifier l’état opérationnel réel.';
      case 'assignment_ended':
        return 'SPHOT OFF : votre période d’affectation est terminée. '
            'Votre compte reste accessible, mais vos actions ne modifient '
            'plus les données opérationnelles réelles.';
      case 'assignment_period_unavailable':
      case 'no_active_assignment_period':
        return 'SPHOT OFF : aucune période d’affectation active ne peut être '
            'confirmée. Contactez votre administrateur SPHOT si nécessaire.';
      case 'account_inactive':
        return 'SPHOT OFF : votre compte n’est pas actuellement autorisé à '
            'agir sur les données opérationnelles réelles.';
      default:
        return 'SPHOT OFF : votre administration de tutelle n’a pas '
            'actuellement ouvert les droits de diffusion. Vous pouvez tester '
            'SPHOT SAUVETEUR, mais vos actions ne modifient pas le SPHOT réel.';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _userRole = widget.userRole;
    _sphotMode = widget.sphotMode.toUpperCase();
    _sphotModeReason = widget.sphotModeReason;
    _postesAffectes = List<String>.from(widget.postesAffectes);
    _canManageRestrictedOperationalData =
        widget.canManageRestrictedOperationalData;

    _refreshMode();
    _modeRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshMode(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _modeRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshMode();
    }
  }

  Future<void> _refreshMode() async {
    if (_refreshingMode || widget.sauveteurSessionToken.trim().isEmpty) {
      return;
    }

    _refreshingMode = true;

    try {
      final response = await http.post(
        Uri.parse(
          'https://us-central1-sphot-ab80b.cloudfunctions.net/'
          'getSauveteurSessionState',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sauveteurSessionToken': widget.sauveteurSessionToken,
        }),
      );

      if (!mounted ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        return;
      }

      final currentSpots = decoded['postesAffectes'] is List
          ? (decoded['postesAffectes'] as List)
              .map((value) => value.toString())
              .where((value) => value.trim().isNotEmpty)
              .toList()
          : <String>[];

      setState(() {
        _userRole = (decoded['userRole'] ?? _userRole).toString();
        _sphotMode =
            (decoded['sphotMode'] ?? _sphotMode).toString().toUpperCase();
        _sphotModeReason =
            (decoded['sphotModeReason'] ?? _sphotModeReason).toString();
        _postesAffectes = currentSpots;
        _canManageRestrictedOperationalData =
            decoded['canManageRestrictedOperationalData'] == true;
      });
    } catch (_) {
      // Le dernier état connu reste affiché. Les écritures sensibles sont
      // de toute façon revérifiées côté Cloud Functions.
    } finally {
      _refreshingMode = false;
    }
  }

  Future<void> _showModeInfo() async {
    await _refreshMode();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _isSphotOn ? 'SPHOT ON' : 'SPHOT OFF',
          style: TextStyle(
            color: _isSphotOn
                ? const Color(0xFF15803D)
                : const Color(0xFFDC2626),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          _modeExplanation,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('FERMER'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileColor = widget.profileColor;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'data/images/map_background.jpg',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                  Text(
                    'RENSEIGNEMENTS SAUVETEURS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: profileColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _showModeInfo,
                    child: Container(
                      width: double.infinity,
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _isSphotOn
                            ? const Color(0xFFEAF7EE)
                            : const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isSphotOn
                              ? const Color(0xFF15803D)
                              : const Color(0xFFDC2626),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isSphotOn
                                ? Icons.toggle_on_rounded
                                : Icons.toggle_off_rounded,
                            color: _isSphotOn
                                ? const Color(0xFF15803D)
                                : const Color(0xFFDC2626),
                            size: 26,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _isSphotOn
                                  ? 'SPHOT ON — DIFFUSION ACTIVE'
                                  : 'SPHOT OFF',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _isSphotOn
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFDC2626),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 430,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.black,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          _MenuSquare(
                            title: 'ACTIONS RAPIDES',
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFFD50000),
                            height: 82,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SauveteurActionsRapidesPage(
                                    profileColor: profileColor,
                                    sphotMode: _sphotMode,
                                    territoireId: widget.territoireId,
                                    sauveteurSessionToken:
                                        widget.sauveteurSessionToken,
                                    postesAffectes: _postesAffectes,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: GridView.count(
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.74,
                              children: [
                                _MenuSquare(
                                  title: 'MÉTÉO TERRESTRE',
                                  icon: Icons.wb_sunny_rounded,
                                  color: const Color(0xFF8D6E63),
                                  iconColor: const Color(0xFFFBC02D),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            SauveteurMeteoTerrestrePage(
                                          profileColor: profileColor,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _MenuSquare(
                                  title: 'MÉTÉO MARINE',
                                  icon: Icons.waves_rounded,
                                  color: const Color(0xFF1E88E5),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            SauveteurMeteoMarinePage(
                                          profileColor: profileColor,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _MenuSquare(
                                  title: 'ÉPHÉMÉRIDE\nDICTON',
                                  icon: Icons.auto_awesome_rounded,
                                  color: const Color(0xFFF9A825),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            SauveteurEphemerideDictonPage(
                                          profileColor: profileColor,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _MenuSquare(
                                  title: 'RECHERCHE DE PERSONNE',
                                  icon: Icons.person_search_rounded,
                                  color: const Color(0xFF00897B),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            SauveteurRecherchePersonnePage(
                                          profileColor: profileColor,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _MenuSquare(
                                  title: 'EMPLOI DU TEMPS',
                                  icon: Icons.calendar_month_rounded,
                                  color: const Color(0xFF43A047),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => SauveteurPlanningPage(
                                          profileColor:
                                              const Color(0xFF43A047),
                                          userRole: _userRole,
                                          territoireId: widget.territoireId,
                                          sphotMode: _sphotMode,
                                          sauveteurSessionToken:
                                              widget.sauveteurSessionToken,
                                          postesAffectes: _postesAffectes,
                                          canManageRestrictedOperationalData:
                                              _canManageRestrictedOperationalData,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _MenuSquare(
                                  title: 'STATS',
                                  icon: Icons.bar_chart_rounded,
                                  color: const Color(0xFF546E7A),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            SauveteurEspaceReservePage(
                                          title: 'STATS',
                                          profileColor: profileColor,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          _MenuSquare(
                            title: 'MAIN COURANTE',
                            icon: Icons.menu_book_rounded,
                            color: const Color(0xFF8E24AA),
                            height: 82,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SauveteurMainCourantePage(
                                    profileColor: profileColor,
                                    userRole: _userRole,
                                    territoireId: widget.territoireId,
                                    login: widget.login,
                                    sphotMode: _sphotMode,
                                    sauveteurSessionToken:
                                        widget.sauveteurSessionToken,
                                    postesAffectes: _postesAffectes,
                                    canManageRestrictedOperationalData:
                                        _canManageRestrictedOperationalData,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, 9),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black,
                            width: 2,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.black,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuSquare extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Color? iconColor;
  final double? height;

  const _MenuSquare({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.iconColor,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        width: double.infinity,

        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: color,
            width: 2.1,
          ),
        ),

        child: Padding(
          padding: const EdgeInsets.all(9),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: iconColor ?? color,
                size: 34,
              ),

              const SizedBox(height: 7),

              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}