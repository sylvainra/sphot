import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/flag_state.dart';

class PublicSpotDetailPage extends StatelessWidget {
  final SpotFlagState spot;

  const PublicSpotDetailPage({super.key, required this.spot});

  Future<void> _openUrl(BuildContext context, String rawUrl) async {
    var url = rawUrl.trim();
    if (url.isEmpty) return;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final uri = Uri.tryParse(url);
    final opened =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir ce lien.')),
      );
    }
  }

  Future<void> _call(BuildContext context) async {
    final phone = spot.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;

    final opened = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appel indisponible sur cet appareil.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = Color(spot.statutColor);
    final commune = spot.ville.trim();
    final flagIsLowered =
        spot.isPosteSecours && spot.flagPosition == FlagPosition.affale;
    final showUnsupervisedWarning =
        spot.isMissingFlagColorDuringSurveillance || flagIsLowered;
    final publicDetailStatus = flagIsLowered
        ? 'BAIGNADE NON SURVEILLÉE TEMPORAIREMENT'
        : spot.displayStatut;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
              color: statusColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.mapDisplayName.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (commune.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      commune.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDCE3EA)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x16000000),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StatusCard(
                            color: statusColor,
                            text: publicDetailStatus,
                          ),
                          if (showUnsupervisedWarning) ...[
                            const SizedBox(height: 10),
                            const _UnsupervisedWarning(),
                          ],
                          const SizedBox(height: 18),
                          _PublicInfoLine(
                            icon: spot.isPosteSecours
                                ? Icons.health_and_safety_outlined
                                : Icons.place_outlined,
                            label: 'Type de SPHOT',
                            value: spot.typeSphot,
                          ),
                          if (spot.periode.isNotEmpty)
                            _PublicInfoLine(
                              icon: Icons.date_range_outlined,
                              label: 'Période de surveillance',
                              value: spot.periode,
                            ),
                          if (spot.heureDebut.isNotEmpty ||
                              spot.heureFin.isNotEmpty)
                            _PublicInfoLine(
                              icon: Icons.schedule_outlined,
                              label: 'Horaires',
                              value: [
                                spot.heureDebut,
                                spot.heureFin,
                              ].where((value) => value.isNotEmpty).join(' – '),
                            ),
                          if (spot.phone.isNotEmpty)
                            _PublicInfoLine(
                              icon: Icons.phone_outlined,
                              label: 'Téléphone public',
                              value: spot.phone,
                              onTap: () => _call(context),
                            ),
                          if (spot.activite.isNotEmpty)
                            _PublicInfoLine(
                              icon: Icons.waves_outlined,
                              label: 'Activités',
                              value: spot.activite,
                            ),
                          if (spot.publicEquipment.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _PublicChips(
                              title: 'Équipements',
                              values: spot.publicEquipment,
                            ),
                          ],
                          if (spot.publicLabels.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _PublicChips(
                              title: 'Labels',
                              values: spot.publicLabels,
                              showLabelIcons: true,
                            ),
                          ],
                          if (spot.siteInternetVille.isNotEmpty ||
                              spot.adresseWebcam.isNotEmpty ||
                              spot.arretesMunicipaux.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 8),
                            const Text(
                              'LIENS PUBLICS',
                              style: TextStyle(
                                color: Color(0xFF1E3A8A),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (spot.siteInternetVille.isNotEmpty)
                                  _PublicLinkButton(
                                    icon: Icons.language,
                                    label: 'Site de la commune',
                                    onTap: () => _openUrl(
                                      context,
                                      spot.siteInternetVille,
                                    ),
                                  ),
                                if (spot.adresseWebcam.isNotEmpty)
                                  _PublicLinkButton(
                                    icon: Icons.videocam_outlined,
                                    label: 'Webcam',
                                    onTap: () =>
                                        _openUrl(context, spot.adresseWebcam),
                                  ),
                                if (spot.arretesMunicipaux.isNotEmpty)
                                  _PublicLinkButton(
                                    icon: Icons.gavel_outlined,
                                    label: 'Arrêtés municipaux',
                                    onTap: () => _openUrl(
                                      context,
                                      spot.arretesMunicipaux,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('RETOUR À LA CARTE'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E3A8A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
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

class _StatusCard extends StatelessWidget {
  final Color color;
  final String text;

  const _StatusCard({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.65)),
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

class _UnsupervisedWarning extends StatelessWidget {
  const _UnsupervisedWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF0000)),
      ),
      child: const Column(
        children: [
          Text(
            'BAIGNADE NON SURVEILLÉE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFFF0000),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'BAIGNADE À VOS RISQUES ET PÉRILS',
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

class _PublicInfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _PublicInfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: const Color(0xFF1E3A8A)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: onTap == null
                          ? Colors.black87
                          : const Color(0xFF1E3A8A),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      decoration: onTap == null
                          ? null
                          : TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicChips extends StatelessWidget {
  final String title;
  final List<String> values;
  final bool showLabelIcons;

  const _PublicChips({
    required this.title,
    required this.values,
    this.showLabelIcons = false,
  });

  static const Map<String, String> _labelIconPaths = {
    '🟦 PAVILLON BLEU': 'data/icons/pavillon_bleu.png',
    '♿ HANDIPLAGE NIVEAU I': 'data/icons/handiplage1.png',
    '♿ HANDIPLAGE NIVEAU II': 'data/icons/handiplage2.png',
    '♿ HANDIPLAGE NIVEAU III': 'data/icons/handiplage3.png',
    '♿ HANDIPLAGE NIVEAU IV': 'data/icons/handiplage4.png',
    '🚭 PLAGE SANS TABAC': 'data/icons/plage_sans_tabac.png',
    'QUALITÉ DES EAUX : EXCELLENTE':
        'data/icons/qualite_eau_excellente.png',
    'QUALITÉ DES EAUX : BONNE': 'data/icons/qualite_eau_bonne.png',
    'QUALITÉ DES EAUX : SUFFISANTE':
        'data/icons/qualite_eau_suffisante.png',
    'QUALITÉ DES EAUX : INSUFFISANTE':
        'data/icons/qualite_eau_insuffisante.png',
  };

  static const Map<String, String> _labelDisplayNames = {
    '🟦 PAVILLON BLEU': 'PAVILLON BLEU',
    '♿ HANDIPLAGE NIVEAU I': 'HANDIPLAGE NIVEAU I',
    '♿ HANDIPLAGE NIVEAU II': 'HANDIPLAGE NIVEAU II',
    '♿ HANDIPLAGE NIVEAU III': 'HANDIPLAGE NIVEAU III',
    '♿ HANDIPLAGE NIVEAU IV': 'HANDIPLAGE NIVEAU IV',
    '🚭 PLAGE SANS TABAC': 'PLAGE SANS TABAC',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF1E3A8A),
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: values
              .map((value) => _buildChip(value))
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildChip(String value) {
    final normalizedValue = value.trim().toUpperCase();
    final iconPath = showLabelIcons ? _labelIconPaths[normalizedValue] : null;
    final displayName = showLabelIcons
        ? (_labelDisplayNames[normalizedValue] ?? value)
        : value;

    return Chip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconPath != null) ...[
            Image.asset(
              iconPath,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(child: Text(displayName)),
        ],
      ),
      visualDensity: VisualDensity.compact,
      backgroundColor: const Color(0xFFF2F6FB),
      side: const BorderSide(color: Color(0xFFD7E0EC)),
    );
  }
}

class _PublicLinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PublicLinkButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1E3A8A),
        side: const BorderSide(color: Color(0xFF1E3A8A)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
