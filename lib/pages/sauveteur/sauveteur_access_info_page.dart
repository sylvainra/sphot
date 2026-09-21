import 'package:flutter/material.dart';

import 'sauveteur_menu_page.dart';

class SauveteurAccessInfoPage extends StatelessWidget {
  final String login;
  final String territoireId;
  final String userRole;
  final String sphotMode;
  final String sphotModeReason;
  final String sauveteurSessionToken;
  final List<String> postesAffectes;
  final bool canManageRestrictedOperationalData;

  const SauveteurAccessInfoPage({
    super.key,
    required this.login,
    required this.territoireId,
    required this.userRole,
    required this.sphotMode,
    required this.sphotModeReason,
    required this.sauveteurSessionToken,
    required this.postesAffectes,
    required this.canManageRestrictedOperationalData,
  });

  bool get _isSphotOn => sphotMode.toUpperCase() == 'ON';

  void _openSauveteur(BuildContext context) {
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

  Widget _section({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 1.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 23),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _line(String text, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xFF1F2937),
          fontSize: 12.5,
          fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFEF4444);
    const blue = Color(0xFF1E3A8A);
    const green = Color(0xFF15803D);
    const purple = Color(0xFF8E24AA);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

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
              padding: EdgeInsets.fromLTRB(
                18,
                8,
                18,
                14 + safeBottom,
              ),
              child: Column(
                children: [
                  Image.asset(
                    'data/icons/title.png',
                    height: 54,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'BIENVENUE DANS SPHOT SAUVETEUR',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: red,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Avant de commencer, voici vos droits, devoirs et '
                    'responsabilités professionnelles dans SPHOT SAUVETEUR.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 650),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.30),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: red, width: 2),
                      ),
                      child: ListView(
                        children: [
                          _section(
                            title: _isSphotOn
                                ? 'SPHOT ON'
                                : 'SPHOT OFF',
                            icon: _isSphotOn
                                ? Icons.toggle_on_rounded
                                : Icons.toggle_off_rounded,
                            color: _isSphotOn ? green : red,
                            children: [
                              if (_isSphotOn)
                                _line(
                                  'Vous êtes actuellement autorisé à agir, '
                                  'dans le cadre de vos fonctions '
                                  'professionnelles, sur les données '
                                  'opérationnelles réelles des SPHOTS '
                                  'auxquels vous êtes affecté.',
                                  strong: true,
                                )
                              else
                                _line(
                                  'Vous êtes actuellement en SPHOT OFF.\n'
                                  'Vous pouvez découvrir et tester '
                                  'SPHOT SAUVETEUR. Vos actions de test '
                                  'ne modifient jamais l’état opérationnel '
                                  'réel ni les informations renseignées '
                                  'par les sauveteurs en SPHOT ON.',
                                  strong: true,
                                ),
                              _line(
                                'Le passage SPHOT OFF / SPHOT ON dépend '
                                'de vos affectations et des droits de diffusion '
                                'ouverts par votre administration de tutelle '
                                'SPHOT ADMIN.',
                              ),
                            ],
                          ),
                          _section(
                            title: 'SPHOT ON',
                            icon: Icons.health_and_safety_rounded,
                            color: red,
                            children: [
                              _line(
                                'Vous basculerez en SPHOT ON dès lors que '
                                'votre administration SPHOT ADMIN bénéficiera '
                                'des droits de diffusion sur SPHOT.\n'
                                'Tous les sauveteurs SPHOT ON affectés au même '
                                'poste peuvent agir professionnellement sur '
                                'les paramètres opérationnels partagés : '
                                'drapeau, statut de baignade, dangers, météo, '
                                'éphéméride et autres renseignements métier.',
                              ),
                              _line(
                                'Si plusieurs sauveteurs sont SPHOT ON sur '
                                'le même poste, ils travaillent sur le même '
                                'état opérationnel réel. Chaque modification '
                                'professionnelle validée devient visible par '
                                'les autres sauveteurs autorisés.',
                              ),
                              _line(
                                'Un sauveteur SPHOT OFF ne peut jamais '
                                'altérer ces données réelles.',
                                strong: true,
                              ),
                            ],
                          ),
                          _section(
                            title: 'RÔLES CHEF DE POSTE ET ADJOINT',
                            icon: Icons.supervisor_account_rounded,
                            color: blue,
                            children: [
                              _line(
                                'Le chef de poste et son adjoint disposent '
                                'des mêmes droits opérationnels professionnels '
                                'que les autres sauveteurs SPHOT ON.',
                              ),
                              _line(
                                'Ils disposent en plus des droits de gestion '
                                'du planning et de saisie de la MAIN COURANTE.',
                                strong: true,
                              ),
                              _line(
                                'Les autres sauveteurs peuvent consulter '
                                'le planning et la partie de la main courante '
                                'qui leur est accessible, sans la modifier.',
                              ),
                            ],
                          ),
                          _section(
                            title: 'MAIN COURANTE ET DROITS DE REGARD',
                            icon: Icons.menu_book_rounded,
                            color: purple,
                            children: [
                              _line(
                                'La MAIN COURANTE est un outil professionnel '
                                'interne et n’est jamais destinée à la '
                                'diffusion publique SPHOT.',
                                strong: true,
                              ),
                              _line(
                                'Votre administrateur SPHOT ADMIN dispose '
                                'd’un droit de consultation de la main courante '
                                'et de ses archives.',
                              ),
                              _line(
                                'L’administration peut également habiliter '
                                'un ou plusieurs membres institutionnels '
                                'à la consulter en lecture seule, y compris '
                                'les informations restreintes prévues à cet '
                                'effet.',
                              ),
                              _line(
                                'Ces personnes ne disposent d’aucun droit '
                                'de modification des paramètres opérationnels '
                                'du poste.',
                              ),
                            ],
                          ),
                          _section(
                            title: 'FIN D’AFFECTATION',
                            icon: Icons.event_busy_rounded,
                            color: const Color(0xFFD97706),
                            children: [
                              _line(
                                'Votre compte SPHOT SAUVETEUR reste '
                                'accessible, mais votre espace repasse en '
                                'SPHOT OFF dès que votre affectation ne permet '
                                'plus une action réelle.',
                              ),
                              _line(
                                'Vos actions ne modifieront plus l’état '
                                'opérationnel réel ni les informations '
                                'renseignées par les sauveteurs en SPHOT ON.',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => _openSauveteur(context),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text(
                        'J’AI COMPRIS — ACCÉDER À SPHOT SAUVETEUR',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
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
