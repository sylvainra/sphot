import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/flag_state.dart';

class PublicSpotDetailPage extends StatelessWidget {
  final SpotFlagState spot;

  const PublicSpotDetailPage({
    super.key,
    required this.spot,
  });

  Color _typeColor() {
    final type = spot.normalizedType;

    if (spot.isPosteSecours) {
      return const Color(0xFFFF0000);
    }

    if (spot.isNaturisme) {
      return const Color(0xFFD87A5C);
    }

    if (type.contains('PLAGE')) {
      return const Color(0xFFFFD000);
    }

    if (type.contains('LAC') ||
        type.contains("PLAN D'EAU") ||
        type.contains('BARRAGE')) {
      return const Color(0xFF1E3A8A);
    }

    if (type.contains('FLEUVE') || type.contains('RIVIERE')) {
      return const Color(0xFF2E7D32);
    }

    if (type.contains('LAGON') ||
        type.contains('PISCINE NATURELLE')) {
      return const Color(0xFF00ACC1);
    }

    return const Color(0xFFFFA500);
  }

  Future<void> _callRescueStation(BuildContext context) async {
    final rawPhone = spot.phone.trim();

    if (rawPhone.isEmpty) {
      return;
    }

    final phone = rawPhone.replaceAll(
      RegExp(r'[^0-9+]'),
      '',
    );

    if (phone.isEmpty) {
      return;
    }

    final opened = await launchUrl(
      Uri(
        scheme: 'tel',
        path: phone,
      ),
      mode: LaunchMode.externalApplication,
    );

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d’ouvrir l’application téléphone.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerColor = _typeColor();
    final statusColor = Color(spot.statutColor);

    final flagIsLowered =
        spot.isPosteSecours &&
        spot.flagPosition == FlagPosition.affale;

    final showUnsupervisedWarning =
        spot.isMissingFlagColorDuringSurveillance ||
        flagIsLowered;

    final statusText = flagIsLowered
        ? '⚠️ BAIGNADE NON SURVEILLÉE TEMPORAIREMENT'
        : spot.displayStatut.replaceFirst(
            ' ⚠️ BAIGNADE À VOS RISQUES ET PÉRILS',
            '\n⚠️ BAIGNADE À VOS RISQUES ET PÉRILS',
          );

    final displayName = [
      spot.name.trim(),
      spot.nomSphot.trim(),
    ].where((value) => value.isNotEmpty).join(' - ');

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                18,
                14,
                10,
                14,
              ),
              color: headerColor,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (displayName.isEmpty ? 'SPHOT' : displayName)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (spot.ville.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            spot.ville.trim().toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  18,
                  16,
                  28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 760,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFDCE3EA),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x16000000),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _StatusBanner(
                            color: statusColor,
                            text: statusText,
                          ),

                          const SizedBox(height: 10),

                          _InfosBanner(
                            phone: spot.phone,
                            onPhoneTap: spot.phone.trim().isEmpty
                                ? null
                                : () => _callRescueStation(context),
                          ),

                          if (showUnsupervisedWarning) ...[
                            const SizedBox(height: 10),
                            const _UnsupervisedWarningBanner(),
                          ],

                          const SizedBox(height: 18),

                          _InfoLine(
                            icon: Icons.place_outlined,
                            label: 'Type de SPHOT',
                            value: spot.typeSphot,
                          ),

                          if (spot.periode.trim().isNotEmpty)
                            _InfoLine(
                              icon: Icons.date_range_outlined,
                              label: 'Période de surveillance',
                              value: spot.periode,
                            ),

                          if (spot.heureDebut.trim().isNotEmpty ||
                              spot.heureFin.trim().isNotEmpty)
                            _InfoLine(
                              icon: Icons.schedule_outlined,
                              label: 'Horaires',
                              value: [
                                spot.heureDebut.trim(),
                                spot.heureFin.trim(),
                              ]
                                  .where(
                                    (value) => value.isNotEmpty,
                                  )
                                  .join(' – '),
                            ),

                          if (spot.activite.trim().isNotEmpty)
                            _InfoLine(
                              icon: Icons.waves_outlined,
                              label: 'Activités',
                              value: spot.activite,
                            ),

                          const SizedBox(height: 22),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.map_outlined,
                              ),
                              label: const Text(
                                'RETOUR À LA CARTE',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF1E3A8A),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Color color;
  final String text;

  const _StatusBanner({
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(0.65),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 14,
          height: 1.3,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfosBanner extends StatelessWidget {
  final String phone;
  final VoidCallback? onPhoneTap;

  const _InfosBanner({
    required this.phone,
    required this.onPhoneTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhone = phone.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF1E3A8A),
          width: 1.3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF1E3A8A),
                size: 20,
              ),
              SizedBox(width: 7),
              Text(
                'INFOS',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          if (hasPhone) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: onPhoneTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.phone_in_talk_rounded,
                      color: Color(0xFFDC2626),
                      size: 22,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'POSTE DE SECOURS',
                            style: TextStyle(
                              color: Color(0xFF1E3A8A),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            phone.trim(),
                            style: const TextStyle(
                              color: Color(0xFF1E3A8A),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              decoration:
                                  TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.call_rounded,
                      color: Color(0xFFDC2626),
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UnsupervisedWarningBanner extends StatelessWidget {
  const _UnsupervisedWarningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF0000),
        ),
      ),
      child: const Column(
        children: [
          Text(
            '⚠️ BAIGNADE NON SURVEILLÉE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFFF0000),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 3),
          Text(
            '⚠️ BAIGNADE À VOS RISQUES ET PÉRILS',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFFF0000),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 21,
            color: const Color(0xFF1E3A8A),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF1E3A8A),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
