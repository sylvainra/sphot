import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/flag_state.dart';
import '../widgets/danger_pictogram.dart';
import 'flag_marker.dart';
import 'public_webcam_view.dart';

const TextStyle _publicSectionTitleStyle = TextStyle(
  color: Color(0xFF1E3A8A),
  fontSize: 11,
  fontWeight: FontWeight.w900,
  letterSpacing: 0.5,
);

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
    }
  }

  Future<void> _call(BuildContext context) async {
    final phone = spot.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;

    final opened = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!opened && context.mounted) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerColor = Color(spot.markerColor);
    final commune = spot.ville.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 16, 18, 18),
              color: headerColor,
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
                    const SizedBox(height: 3),
                    Text(
                      commune.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFDCE3EA),
                  ),
                ),
                child: _PublicInfoLine(
                  iconAssetPath: spot.isPosteSecours
                      ? 'data/icons/fire_red_icon.svg'
                      : spot.markerIconPath,
                  iconVerticalOffset: -9,
                  label: 'Type de SPHOT',
                  value: spot.typeSphot,
                  valueColor: const Color(0xFF1E3A8A),
                  valueWidget: spot.isPosteSecours
                      ? const _PublicRescueStationValue()
                      : null,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
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
                          _LiveOperationalSnapshot(
                            initialSpot: spot,
                          ),
                          if (spot.adresseWebcam.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Divider(),
                            const SizedBox(height: 8),
                            _PublicWebcamSection(url: spot.adresseWebcam),
                            const SizedBox(height: 14),
                            const Divider(),
                          ],
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
                              spot.arretesMunicipaux.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 8),
                            const Text(
                              'LIENS PUBLICS',
                              style: _publicSectionTitleStyle,
                            ),
                            const SizedBox(height: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (spot.siteInternetVille.isNotEmpty)
                                  _PublicLinkButton(
                                    icon: Icons.language,
                                    label: 'Site internet du lieu',
                                    onTap: () => _openUrl(
                                      context,
                                      spot.siteInternetVille,
                                    ),
                                  ),
                                if (spot.siteInternetVille.isNotEmpty &&
                                    spot.arretesMunicipaux.isNotEmpty)
                                  const SizedBox(height: 8),
                                if (spot.arretesMunicipaux.isNotEmpty)
                                  _PublicLinkButton(
                                    icon: Icons.gavel_outlined,
                                    label: 'Réglementation de baignade',
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


class PublicSpotMobileSheet extends StatefulWidget {
  final SpotFlagState spot;
  final ScrollController sheetScrollController;

  const PublicSpotMobileSheet({
    super.key,
    required this.spot,
    required this.sheetScrollController,
  });

  @override
  State<PublicSpotMobileSheet> createState() =>
      _PublicSpotMobileSheetState();
}

class _PublicSpotMobileSheetState extends State<PublicSpotMobileSheet> {
  final PageController _pageController = PageController();
  int _selectedPage = 0;

  static const List<(String, IconData)> _pages = [
    ('Actions rapides', Icons.flash_on_rounded),
    ('Météo terrestre', Icons.wb_sunny_outlined),
    ('Météo marine', Icons.water_rounded),
    ('Dicton & Éphéméride', Icons.calendar_today_outlined),
    ('Infos', Icons.info_outline_rounded),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String rawUrl) async {
    var url = rawUrl.trim();
    if (url.isEmpty) return;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _call(SpotFlagState spot) async {
    final phone = spot.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.isEmpty) return;

    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  void _selectPage(int index) {
    if (_selectedPage == index) return;

    setState(() => _selectedPage = index);

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('publicSpots')
          .doc(widget.spot.id)
          .snapshots(),
      builder: (context, snapshot) {
        var currentSpot = widget.spot;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          if (data != null) {
            currentSpot = SpotFlagState.fromFirestore(
              snapshot.data!.id,
              data,
            );
          }
        }

        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF4F7FA),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 22,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: ListView(
              controller: widget.sheetScrollController,
              padding: EdgeInsets.zero,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB9C2CC),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 8, 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentSpot.mapDisplayName.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF172033),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                            ),
                            if (currentSpot.ville.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                currentSpot.ville.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
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
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                    scrollDirection: Axis.horizontal,
                    itemCount: _pages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final page = _pages[index];
                      final selected = _selectedPage == index;

                      return InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => _selectPage(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF1E3A8A)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF1E3A8A)
                                  : const Color(0xFFD5DEE7),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                page.$2,
                                size: 17,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF1E3A8A),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                page.$1.toUpperCase(),
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF1E3A8A),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  height: screenHeight * 0.68,
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => _selectedPage = index);
                    },
                    children: [
                      _buildActionsPage(context, currentSpot),
                      _buildDataPage(
                        title: 'Météo terrestre',
                        icon: Icons.wb_sunny_outlined,
                        values: _PublicLiveDataSection
                            ._formatTerrestrialValues(
                          currentSpot.meteoTerrestre,
                        ),
                      ),
                      _buildDataPage(
                        title: 'Météo marine',
                        icon: Icons.water_rounded,
                        values: _PublicLiveDataSection._formatMarineValues(
                          currentSpot.meteoMarine,
                        ),
                      ),
                      _buildDataPage(
                        title: 'Dicton & Éphéméride',
                        icon: Icons.calendar_today_outlined,
                        values:
                            _PublicLiveDataSection._formatEphemerideValues(
                          currentSpot.ephemeride,
                        ),
                      ),
                      _buildInfoPage(context, currentSpot),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionsPage(
    BuildContext context,
    SpotFlagState spot,
  ) {
    final flagIsLowered =
        spot.isPosteSecours &&
        spot.flagPosition == FlagPosition.affale;
    final showUnsupervisedWarning =
        spot.isMissingFlagColorDuringSurveillance || flagIsLowered;
    final rawStatus = flagIsLowered
        ? '⚠️ BAIGNADE NON SURVEILLÉE TEMPORAIREMENT'
        : spot.displayStatut;
    final publicStatus = rawStatus.replaceFirst(
      ' ⚠️ BAIGNADE À VOS RISQUES ET PÉRILS',
      '\n⚠️ BAIGNADE À VOS RISQUES ET PÉRILS',
    );
    final statusColor = Color(spot.statutColor);
    final dangerValues =
        _PublicLiveDataSection._flattenValues(spot.dangers);

    final notification = spot.notificationPublique is Map
        ? Map<String, dynamic>.from(spot.notificationPublique as Map)
        : <String, dynamic>{};
    final notificationMessage =
        (notification['message'] ?? '').toString().trim();
    final notificationActive = notification['active'] != false;
    final notificationPublishedAt =
        _PublicLiveDataSection._formatTimestamp(
      notification['publishedAt'],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        _MobilePublicCard(
          child: _PublicInfoLine(
            iconAssetPath: spot.isPosteSecours
                ? 'data/icons/fire_red_icon.svg'
                : spot.markerIconPath,
            iconVerticalOffset: -7,
            label: 'Type de SPHOT',
            value: spot.typeSphot,
            valueColor: const Color(0xFF1E3A8A),
            valueWidget: spot.isPosteSecours
                ? const _PublicRescueStationValue()
                : null,
          ),
        ),
        const SizedBox(height: 10),
        _MobilePublicCard(
          child: Column(
            children: [
              Row(
                children: [
                  if (spot.isPosteSecours) ...[
                    SizedBox(
                      width: 78,
                      height: 98,
                      child: Center(
                        child: FlagMarker(spot: spot),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: _StatusCard(
                      color: statusColor,
                      text: publicStatus,
                    ),
                  ),
                ],
              ),
              if (showUnsupervisedWarning) ...[
                const SizedBox(height: 10),
                const _UnsupervisedWarning(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (spot.adresseWebcam.isNotEmpty)
          _MobilePublicCard(
            child: _PublicWebcamSection(url: spot.adresseWebcam),
          )
        else
          const _MobilePublicCard(
            child: _MobileMediaPlaceholder(),
          ),
        if (notificationActive && notificationMessage.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PublicNotificationCard(
            message: notificationMessage,
            publishedAt: notificationPublishedAt,
          ),
        ],
        const SizedBox(height: 10),
        _MobilePublicCard(
          child: _PublicDangerList(values: dangerValues),
        ),
        if (spot.phone.isNotEmpty ||
            spot.siteInternetVille.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (spot.phone.isNotEmpty)
                Expanded(
                  child: _MobileQuickAction(
                    icon: Icons.call_outlined,
                    label: 'Appeler',
                    onTap: () => _call(spot),
                  ),
                ),
              if (spot.phone.isNotEmpty &&
                  spot.siteInternetVille.isNotEmpty)
                const SizedBox(width: 8),
              if (spot.siteInternetVille.isNotEmpty)
                Expanded(
                  child: _MobileQuickAction(
                    icon: Icons.language_rounded,
                    label: 'Site',
                    onTap: () => _openUrl(spot.siteInternetVille),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDataPage({
    required String title,
    required IconData icon,
    required List<String> values,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        _MobilePublicCard(
          child: _LiveDataBlock(
            icon: icon,
            title: title,
            values: values,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoPage(
    BuildContext context,
    SpotFlagState spot,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        _MobilePublicCard(
          child: Column(
            children: [
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
                  onTap: () => _call(spot),
                ),
              if (spot.activite.isNotEmpty)
                _PublicInfoLine(
                  icon: Icons.waves_outlined,
                  label: 'Activités',
                  value: spot.activite,
                ),
            ],
          ),
        ),
        if (spot.publicEquipment.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MobilePublicCard(
            child: _PublicChips(
              title: 'Équipements',
              values: spot.publicEquipment,
            ),
          ),
        ],
        if (spot.publicLabels.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MobilePublicCard(
            child: _PublicChips(
              title: 'Labels',
              values: spot.publicLabels,
              showLabelIcons: true,
            ),
          ),
        ],
        if (spot.siteInternetVille.isNotEmpty ||
            spot.arretesMunicipaux.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MobilePublicCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'LIENS PUBLICS',
                  style: _publicSectionTitleStyle,
                ),
                const SizedBox(height: 10),
                if (spot.siteInternetVille.isNotEmpty)
                  _PublicLinkButton(
                    icon: Icons.language,
                    label: 'Site internet du lieu',
                    onTap: () => _openUrl(spot.siteInternetVille),
                  ),
                if (spot.siteInternetVille.isNotEmpty &&
                    spot.arretesMunicipaux.isNotEmpty)
                  const SizedBox(height: 8),
                if (spot.arretesMunicipaux.isNotEmpty)
                  _PublicLinkButton(
                    icon: Icons.gavel_outlined,
                    label: 'Réglementation de baignade',
                    onTap: () => _openUrl(spot.arretesMunicipaux),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MobilePublicCard extends StatelessWidget {
  final Widget child;

  const _MobilePublicCard({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE3EA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MobileMediaPlaceholder extends StatelessWidget {
  const _MobileMediaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const AspectRatio(
      aspectRatio: 16 / 7,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_camera_back_outlined,
              size: 34,
              color: Color(0xFF94A3B8),
            ),
            SizedBox(height: 7),
            Text(
              'PHOTO / WEBCAM NON RENSEIGNÉE',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MobileQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1E3A8A),
        side: const BorderSide(color: Color(0xFF1E3A8A)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class _LiveOperationalSnapshot extends StatelessWidget {
  final SpotFlagState initialSpot;

  const _LiveOperationalSnapshot({
    required this.initialSpot,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('publicSpots')
          .doc(initialSpot.id)
          .snapshots(),
      builder: (context, snapshot) {
        var currentSpot = initialSpot;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          if (data != null) {
            currentSpot = SpotFlagState.fromFirestore(
              snapshot.data!.id,
              data,
            );
          }
        }

        final flagIsLowered =
            currentSpot.isPosteSecours &&
            currentSpot.flagPosition == FlagPosition.affale;
        final showUnsupervisedWarning =
            currentSpot.isMissingFlagColorDuringSurveillance ||
            flagIsLowered;
        final rawStatus = flagIsLowered
            ? '⚠️ BAIGNADE NON SURVEILLÉE TEMPORAIREMENT'
            : currentSpot.displayStatut;
        final publicStatus = rawStatus.replaceFirst(
          ' ⚠️ BAIGNADE À VOS RISQUES ET PÉRILS',
          '\n⚠️ BAIGNADE À VOS RISQUES ET PÉRILS',
        );
        final statusColor = Color(currentSpot.statutColor);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (currentSpot.isPosteSecours) ...[
                  SizedBox(
                    width: 88,
                    height: 104,
                    child: Center(
                      child: FlagMarker(spot: currentSpot),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _StatusCard(
                    color: statusColor,
                    text: publicStatus,
                  ),
                ),
              ],
            ),
            if (showUnsupervisedWarning) ...[
              const SizedBox(height: 10),
              const _UnsupervisedWarning(),
            ],
            const SizedBox(height: 14),
            _PublicLiveDataSection(spot: currentSpot),
          ],
        );
      },
    );
  }
}

class _PublicLiveDataSection extends StatelessWidget {
  final SpotFlagState spot;

  const _PublicLiveDataSection({
    required this.spot,
  });

  @override
  Widget build(BuildContext context) {
    final dangerValues = _flattenValues(spot.dangers);
    final terrestrialValues =
        _formatTerrestrialValues(spot.meteoTerrestre);
    final marineValues = _formatMarineValues(spot.meteoMarine);
    final ephemerideValues = _formatEphemerideValues(spot.ephemeride);
    final notification = spot.notificationPublique is Map
        ? Map<String, dynamic>.from(spot.notificationPublique as Map)
        : <String, dynamic>{};
    final notificationMessage =
        (notification['message'] ?? '').toString().trim();
    final notificationActive = notification['active'] != false;
    final notificationPublishedAt =
        _formatTimestamp(notification['publishedAt']);
    final updatedAt = _formatTimestamp(spot.updatedAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE3EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sensors_rounded,
                size: 18,
                color: Color(0xFF1E3A8A),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'INFORMATIONS OPÉRATIONNELLES EN DIRECT',
                  style: _publicSectionTitleStyle,
                ),
              ),
              if (updatedAt.isNotEmpty)
                Text(
                  updatedAt,
                  style: const TextStyle(
                    color: Colors.black45,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (notificationActive && notificationMessage.isNotEmpty) ...[
            _PublicNotificationCard(
              message: notificationMessage,
              publishedAt: notificationPublishedAt,
            ),
            const SizedBox(height: 10),
          ],
          _PublicDangerList(values: dangerValues),
          const SizedBox(height: 8),
          _LiveDataBlock(
            icon: Icons.wb_sunny_outlined,
            title: 'Météo terrestre',
            values: terrestrialValues,
          ),
          const SizedBox(height: 8),
          _LiveDataBlock(
            icon: Icons.water_rounded,
            title: 'Météo marine',
            values: marineValues,
          ),
          const SizedBox(height: 8),
          _LiveDataBlock(
            icon: Icons.calendar_today_outlined,
            title: 'Dicton & Éphéméride',
            values: ephemerideValues,
          ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is! Map) return const <String, dynamic>{};

    return value.map(
      (key, mapValue) => MapEntry(key.toString(), mapValue),
    );
  }

  static String _textValue(Map<String, dynamic> values, String key) {
    final value = values[key];
    if (value == null) return '';
    return value.toString().trim();
  }

  static void _addValue(
    List<String> target,
    String label,
    String value, {
    String suffix = '',
  }) {
    final text = value.trim();
    if (text.isEmpty) return;

    target.add('$label : $text$suffix');
  }

  static String _expandDirection(String rawDirection) {
    final raw = rawDirection.trim();
    if (raw.isEmpty) return '';

    final normalized = raw
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('-', '');

    const directions = <String, String>{
      'N': 'Nord',
      'NNE': 'Nord-Nord-Est',
      'NE': 'Nord-Est',
      'ENE': 'Est-Nord-Est',
      'E': 'Est',
      'ESE': 'Est-Sud-Est',
      'SE': 'Sud-Est',
      'SSE': 'Sud-Sud-Est',
      'S': 'Sud',
      'SSO': 'Sud-Sud-Ouest',
      'SO': 'Sud-Ouest',
      'OSO': 'Ouest-Sud-Ouest',
      'O': 'Ouest',
      'ONO': 'Ouest-Nord-Ouest',
      'NO': 'Nord-Ouest',
      'NNO': 'Nord-Nord-Ouest',
      'W': 'Ouest',
      'WSW': 'Ouest-Sud-Ouest',
      'SW': 'Sud-Ouest',
      'WNW': 'Ouest-Nord-Ouest',
      'NW': 'Nord-Ouest',
    };

    return directions[normalized] ?? raw;
  }

  static String _uvIndexText(String rawIndex) {
    final index = int.tryParse(rawIndex.trim());

    if (index == null) {
      return rawIndex.trim();
    }

    if (index <= 2) {
      return '$index – Faible – Protection non nécessaire';
    }

    if (index <= 5) {
      return '$index – Modéré – Protection nécessaire : '
          'chapeau, t-shirt, lunettes de soleil et crème solaire';
    }

    if (index <= 7) {
      return '$index – Élevé – Protection nécessaire : '
          'chapeau, t-shirt, lunettes de soleil et crème solaire';
    }

    if (index <= 10) {
      return '$index – Très élevé – Protection supplémentaire nécessaire : '
          'éviter, si possible, tout séjour en plein air';
    }

    return '$index – Extrême – Protection supplémentaire nécessaire : '
        'éviter, si possible, tout séjour en plein air';
  }

  static String _caniculeLevelText(String rawLevel) {
    final level = int.tryParse(rawLevel.trim());

    switch (level) {
      case 1:
        return 'Niveau 1 – Veille saisonnière';
      case 2:
        return 'Niveau 2 – Avertissement chaleur';
      case 3:
        return 'Niveau 3 – Alerte canicule';
      case 4:
        return 'Niveau 4 – Mobilisation maximale';
      default:
        return rawLevel.trim();
    }
  }

  static List<String> _formatTerrestrialValues(dynamic value) {
    final values = _asStringMap(value);
    if (values.isEmpty) return _flattenValues(value);

    final result = <String>[];

    _addValue(
      result,
      'Température de l’air mini',
      _textValue(values, 'Température air min'),
      suffix: ' °C',
    );
    _addValue(
      result,
      'Température de l’air maxi',
      _textValue(values, 'Température air max'),
      suffix: ' °C',
    );
    _addValue(result, 'Ciel matin', _textValue(values, 'Ciel matin'));
    _addValue(
      result,
      'Ciel après-midi',
      _textValue(values, 'Ciel après-midi'),
    );
    _addValue(
      result,
      'Direction vent matin',
      _expandDirection(_textValue(values, 'Direction vent matin')),
    );
    _addValue(
      result,
      'Vent matin',
      _textValue(values, 'Vent matin km/h'),
      suffix: ' km/h',
    );
    _addValue(
      result,
      'Direction vent après-midi',
      _expandDirection(_textValue(values, 'Direction vent après-midi')),
    );
    _addValue(
      result,
      'Vent après-midi',
      _textValue(values, 'Vent après-midi km/h'),
      suffix: ' km/h',
    );
    _addValue(
      result,
      'Rafales',
      _textValue(values, 'Rafales km/h'),
      suffix: ' km/h',
    );
    final uvIndex = _textValue(values, 'Indice UV');
    if (uvIndex.isNotEmpty) {
      result.add('Indice UV : ${_uvIndexText(uvIndex)}');
    }

    final canicule = _textValue(values, 'Niveau canicule');
    if (canicule.isNotEmpty) {
      result.add('Niveau canicule : ${_caniculeLevelText(canicule)}');
    }

    return result;
  }

  static List<String> _formatMarineValues(dynamic value) {
    final values = _asStringMap(value);
    if (values.isEmpty) return _flattenValues(value);

    final result = <String>[];

    _addValue(
      result,
      'Température de l’eau mini',
      _textValue(values, 'Température eau min'),
      suffix: ' °C',
    );
    _addValue(
      result,
      'Température de l’eau maxi',
      _textValue(values, 'Température eau max'),
      suffix: ' °C',
    );
    _addValue(
      result,
      'État de la mer',
      _textValue(values, 'État de la mer'),
    );
    _addValue(
      result,
      'Direction de la houle matin',
      _expandDirection(_textValue(values, 'Direction houle matin')),
    );
    _addValue(
      result,
      'Direction de la houle après-midi',
      _expandDirection(_textValue(values, 'Direction houle après-midi')),
    );
    _addValue(
      result,
      'Houle matin',
      _textValue(values, 'Houle matin'),
    );
    _addValue(
      result,
      'Houle après-midi',
      _textValue(values, 'Houle après-midi'),
    );
    _addValue(
      result,
      'Période houle mini',
      _textValue(values, 'Période houle min secondes'),
      suffix: ' s',
    );
    _addValue(
      result,
      'Période houle maxi',
      _textValue(values, 'Période houle max secondes'),
      suffix: ' s',
    );

    final lowTides = [
      _textValue(values, 'Basse mer 1'),
      _textValue(values, 'Basse mer 2'),
    ].where((item) => item.isNotEmpty).join(' • ');
    _addValue(result, 'Basses mer', lowTides);

    final highTides = [
      _textValue(values, 'Pleine mer 1'),
      _textValue(values, 'Pleine mer 2'),
    ].where((item) => item.isNotEmpty).join(' • ');
    _addValue(result, 'Pleines mer', highTides);

    _addValue(
      result,
      'Coefficient basse mer',
      _textValue(values, 'Coefficient basse mer'),
    );
    _addValue(
      result,
      'Coefficient haute mer',
      _textValue(values, 'Coefficient pleine mer'),
    );

    return result;
  }

  static List<String> _formatEphemerideValues(dynamic value) {
    final values = _asStringMap(value);
    if (values.isEmpty) return _flattenValues(value);

    final result = <String>[];
    _addValue(result, 'Dicton', _textValue(values, 'Dicton'));
    _addValue(
      result,
      'Éphéméride',
      _textValue(values, 'Éphéméride'),
    );
    return result;
  }

  static List<String> _flattenValues(dynamic value) {
    if (value == null) return const [];

    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    if (value is Map) {
      return value.entries
          .where((entry) => !_isTechnicalKey(entry.key.toString()))
          .map((entry) {
            final raw = entry.value;
            if (raw == null) return '';

            final label = _humanizeKey(entry.key.toString());
            if (raw is Iterable) {
              final values = raw
                  .map((item) => item.toString().trim())
                  .where((item) => item.isNotEmpty)
                  .join(' • ');
              return values.isEmpty ? '' : '$label : $values';
            }

            if (raw is Map) {
              final nested = raw.entries
                  .map((nestedEntry) {
                    return '${_humanizeKey(nestedEntry.key.toString())} '
                        '${nestedEntry.value}';
                  })
                  .join(' • ');
              return nested.isEmpty ? '' : '$label : $nested';
            }

            final text = raw.toString().trim();
            return text.isEmpty ? '' : '$label : $text';
          })
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    final text = value.toString().trim();
    return text.isEmpty ? const [] : <String>[text];
  }

  static bool _isTechnicalKey(String key) {
    final normalized = key.toLowerCase();

    return normalized.endsWith(' index') ||
        normalized.endsWith(' heure') ||
        normalized.endsWith(' minute') ||
        normalized.endsWith(' mètres') ||
        normalized.endsWith(' décimales');
  }

  static String _humanizeKey(String key) {
    final spaced = key
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .trim();

    if (spaced.isEmpty) return '';
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  static String _formatTimestamp(dynamic value) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate().toLocal();
    } else if (value is DateTime) {
      date = value.toLocal();
    }

    if (date == null) return '';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '$day/$month • $hour:$minute';
  }
}

class _PublicNotificationCard extends StatelessWidget {
  final String message;
  final String publishedAt;

  const _PublicNotificationCard({
    required this.message,
    required this.publishedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.campaign_rounded,
            size: 21,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'INFORMATION DU POSTE',
                  style: TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (publishedAt.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    publishedAt,
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicDangerList extends StatelessWidget {
  final List<String> values;

  const _PublicDangerList({
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 17,
          color: Color(0xFF1E3A8A),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DANGERS DU JOUR',
                style: TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              if (values.isEmpty)
                const Text(
                  'Aucun danger signalé',
                  style: TextStyle(
                    color: Colors.black38,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                ...values.map((value) => _PublicDangerRow(value: value)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublicDangerRow extends StatelessWidget {
  final String value;

  const _PublicDangerRow({
    required this.value,
  });

  String get _displayValue {
    final normalized = value.toUpperCase();

    if ((normalized.contains('BAÏNE') || normalized.contains('BAINE')) &&
        !normalized.contains('RISQUE')) {
      final match = RegExp(r'NIVEAU\s*([1-5])').firstMatch(normalized);
      final level = int.tryParse(match?.group(1) ?? '') ?? 1;

      final String risk;
      if (level <= 2) {
        risk = 'Risque faible à modéré';
      } else if (level == 3) {
        risk = 'Risque marqué';
      } else if (level == 4) {
        risk = 'Risque très élevé';
      } else {
        risk = 'Risque maximal (Alerte maximale)';
      }

      return '$value : $risk';
    }

    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 38,
            height: 28,
            child: Center(
              child: DangerPictogram(
                danger: value,
                size: 27,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              _displayValue,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UvContext {
  final int index;
  final String label;
  final String advice;
  final Color color;

  const _UvContext({
    required this.index,
    required this.label,
    required this.advice,
    required this.color,
  });
}

class _LiveDataBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> values;

  const _LiveDataBlock({
    required this.icon,
    required this.title,
    required this.values,
  });

  static _UvContext? _uvContextFromValue(String value) {
    if (!value.startsWith('Indice UV :')) return null;

    final raw = value.substring('Indice UV :'.length).trim();
    final match = RegExp(r'^(\d+)').firstMatch(raw);
    final index = int.tryParse(match?.group(1) ?? '');
    if (index == null) return null;

    if (index <= 2) {
      return _UvContext(
        index: index,
        label: 'Faible',
        advice: 'Protection non nécessaire',
        color: const Color(0xFF2FAF34),
      );
    }

    if (index <= 5) {
      return _UvContext(
        index: index,
        label: 'Moyen',
        advice:
            'Protection nécessaire : chapeau, t-shirt, lunettes de soleil '
            'et crème solaire',
        color: const Color(0xFFD4B000),
      );
    }

    if (index <= 7) {
      return _UvContext(
        index: index,
        label: 'Élevé',
        advice:
            'Protection nécessaire : chapeau, t-shirt, lunettes de soleil '
            'et crème solaire',
        color: const Color(0xFFF28C00),
      );
    }

    if (index <= 10) {
      return _UvContext(
        index: index,
        label: 'Très élevé',
        advice:
            'Protection supplémentaire nécessaire : éviter, si possible, '
            'tout séjour en plein air',
        color: const Color(0xFFE73312),
      );
    }

    return _UvContext(
      index: index,
      label: 'Extrême',
      advice:
          'Protection supplémentaire nécessaire : éviter, si possible, '
          'tout séjour en plein air',
      color: const Color(0xFFB05AA8),
    );
  }

  static Widget _buildValue(String value) {
    final uv = _uvContextFromValue(value);

    if (uv == null) {
      return Text(
        value,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        children: [
          const TextSpan(text: 'Indice UV : '),
          TextSpan(
            text: '${uv.index} – ${uv.label} – ${uv.advice}',
            style: TextStyle(
              color: uv.color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: const Color(0xFF1E3A8A),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              if (values.isEmpty)
                const Text(
                  'Non renseigné',
                  style: TextStyle(
                    color: Colors.black38,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                ...values.map(
                  (value) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: _buildValue(value),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PublicWebcamSection extends StatelessWidget {
  final String url;

  const _PublicWebcamSection({required this.url});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.videocam_outlined,
              size: 19,
              color: Color(0xFF1E3A8A),
            ),
            SizedBox(width: 7),
            Text(
              'WEBCAM',
              style: _publicSectionTitleStyle,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PublicWebcamView(url: url),
          ),
        ),
        const SizedBox(height: 9),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PublicWebcamFullScreenPage(url: url),
              ),
            ),
            icon: const Icon(Icons.fullscreen_rounded),
            label: const Text('AGRANDIR LA WEBCAM'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1E3A8A),
              side: const BorderSide(color: Color(0xFF1E3A8A)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
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

class _PublicInfoLine extends StatelessWidget {
  final IconData? icon;
  final String? iconAssetPath;
  final double iconVerticalOffset;
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? valueWidget;
  final VoidCallback? onTap;

  const _PublicInfoLine({
    this.icon,
    this.iconAssetPath,
    this.iconVerticalOffset = 0,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueWidget,
    this.onTap,
  }) : assert(icon != null || iconAssetPath != null);

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
            if (iconAssetPath != null)
              Transform.translate(
                offset: Offset(0, iconVerticalOffset),
                child: SvgPicture.asset(
                  iconAssetPath!,
                  width: 34,
                  height: 34,
                  fit: BoxFit.contain,
                  placeholderBuilder: (_) =>
                      const SizedBox.square(dimension: 34),
                ),
              )
            else
              Icon(icon, size: 22, color: const Color(0xFF1E3A8A)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: _publicSectionTitleStyle,
                  ),
                  const SizedBox(height: 2),
                  valueWidget ??
                      Text(
                        value,
                        style: TextStyle(
                          color: valueColor ??
                              (onTap == null
                                  ? Colors.black87
                                  : const Color(0xFF1E3A8A)),
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

class _PublicRescueStationValue extends StatelessWidget {
  const _PublicRescueStationValue();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
  scaleX: 0.8,
  scaleY: 1.4,
  alignment: Alignment.centerLeft,
  child: SizedBox(
    width: 18,
    height: 28,
    child: SvgPicture.asset(
      'data/icons/flag_red_yellow_5x3.svg',
      fit: BoxFit.contain,
    ),
  ),
),
const SizedBox(width: 2),
        const Flexible(
          child: Text(
            'POSTE DE SECOURS',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Color(0xFF1E3A8A),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
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
    '🟦 PAVILLON BLEU': 'data/icons/pavillon_bleu.svg',
    '♿ HANDIPLAGE NIVEAU I': 'data/icons/handiplage1.svg',
    '♿ HANDIPLAGE NIVEAU II': 'data/icons/handiplage2.svg',
    '♿ HANDIPLAGE NIVEAU III': 'data/icons/handiplage3.svg',
    '♿ HANDIPLAGE NIVEAU IV': 'data/icons/handiplage4.svg',
    '🚭 PLAGE SANS TABAC': 'data/icons/plage_sans_tabac.svg',
    'QUALITÉ DES EAUX : EXCELLENTE': 'data/icons/qualite_eau_excellente.svg',
    'QUALITÉ DES EAUX : BONNE': 'data/icons/qualite_eau_bonne.svg',
    'QUALITÉ DES EAUX : SUFFISANTE': 'data/icons/qualite_eau_suffisante.svg',
    'QUALITÉ DES EAUX : INSUFFISANTE':
        'data/icons/qualite_eau_insuffisante.svg',
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
          style: _publicSectionTitleStyle,
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < values.length; index++) ...[
              _buildChip(values[index]),
              if (index < values.length - 1) const SizedBox(height: 7),
            ],
          ],
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
            SvgPicture.asset(
              iconPath,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              placeholderBuilder: (_) => const SizedBox.square(dimension: 24),
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
