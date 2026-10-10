import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/flag_state.dart';
import '../services/public_favorites_service.dart';
import '../widgets/danger_pictogram.dart';
import 'flag_marker.dart';
import 'public_webcam_view.dart';

const Color _sphotWarmRed = Color(0xFFE72B20);
const Color _sphotWarmOrange = Color(0xFFF97316);
const Color _sphotWarmYellow = Color(0xFFF6B51B);
const Color _sphotWarmBorder = Color(0xFFF28A22);
const Color _sphotWarmSurface = Color(0xFFFFFBF7);

const LinearGradient _sphotWarmGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[
    _sphotWarmRed,
    _sphotWarmOrange,
    _sphotWarmYellow,
  ],
  stops: <double>[0, 0.56, 1],
);

const LinearGradient _sphotWarmSoftGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[
    Color(0xFFFFF1EE),
    Color(0xFFFFF8F2),
    Color(0xFFFFFBEA),
  ],
  stops: <double>[0, 0.56, 1],
);

const TextStyle _publicSectionTitleStyle = TextStyle(
  color: _sphotWarmRed,
  fontSize: 10,
  fontWeight: FontWeight.w900,
  letterSpacing: 0.5,
);

// Même référentiel de couleurs que les types de SPHOTS sur la carte.
Color _publicSpotTypeTextColor(SpotFlagState spot) {
  final type = spot.normalizedType;
  if (spot.isPosteSecours) return const Color(0xFFFF0000);
  if (spot.isNaturisme) return const Color(0xFFD87A5C);
  if (type.contains('ACCES PLAGE')) return const Color(0xFFFFD000);
  if (type.contains('LAC') ||
      type.contains("PLAN D'EAU") ||
      type.contains('BARRAGE')) {
    return const Color(0xFF1E3A8A);
  }
  if (type.contains('FLEUVE') || type.contains('RIVIERE')) {
    return const Color(0xFF2E7D32);
  }
  if (type.contains('LAGON') || type.contains('PISCINE NATURELLE')) {
    return const Color(0xFF00ACC1);
  }
  return Colors.black;
}

/// Messages de sécurité du bandeau, calculés à partir de l'état public
/// issu des droits Admin et des publications sauveteur. Ne certifie jamais
/// qu'un poste déclaré surveillé est effectivement surveillé.
List<String> _publicSpotHeaderAlerts(SpotFlagState spot) {
  if (!spot.isPosteSecours) {
    return const [
      'BAIGNADE NON SURVEILLÉE',
      'BAIGNADE À VOS RISQUES ET PÉRILS',
    ];
  }

  if (spot.isRealtimeAwaitingUpdate) {
    return const [
      'SURVEILLANCE NON RENSEIGNÉE',
      'COULEUR DE LA FLAMME NON RENSEIGNÉE',
    ];
  }

  if (!spot.realtimeAvailable) {
    return const ['INFORMATIONS EN TEMPS RÉEL INDISPONIBLES'];
  }

  if (spot.flagPosition == FlagPosition.affale) {
    return const [
      'BAIGNADE NON SURVEILLÉE TEMPORAIREMENT',
      'BAIGNADE À VOS RISQUES ET PÉRILS',
    ];
  }

  if (spot.flagPosition == FlagPosition.none ||
      spot.flagColor == FlagColor.none) {
    return const [
      'SURVEILLANCE NON RENSEIGNÉE',
      'COULEUR DE LA FLAMME NON RENSEIGNÉE',
    ];
  }

  if (spot.hasValidFlag) {
    return [spot.displayStatut.replaceAll('⚠️ ', '')];
  }

  return const [
    'BAIGNADE NON SURVEILLÉE',
    'BAIGNADE À VOS RISQUES ET PÉRILS',
  ];
}

class PublicSpotDetailPage extends StatelessWidget {
  final SpotFlagState spot;

  const PublicSpotDetailPage({super.key, required this.spot});

  @override
  Widget build(BuildContext context) {
    final nameColor = spot.isPosteSecours ? const Color(0xFFFF0000) : Colors.black;
    final typeColor = _publicSpotTypeTextColor(spot);
    final commune = spot.ville.trim();
    final typeLabel = spot.typeSphot.trim();

    return Scaffold(
      backgroundColor: _sphotWarmSurface,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 14, 10, 14),
              color: _sphotWarmSurface,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spot.mapDisplayName.toUpperCase(),
                          style: TextStyle(
                            color: nameColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.10,
                          ),
                        ),
                        if (commune.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            commune.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF1E3A8A),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        if (spot.isPosteSecours || typeLabel.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          if (spot.isPosteSecours)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'data/icons/flag_red_yellow_5x3.svg',
                                  width: 18,
                                  height: 20,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(width: 7),
                                const Text(
                                  'POSTE DE SECOURS',
                                  style: const TextStyle(
                                    color: Color(0xFFFF0000),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.15,
                                  ),
                                ),
                              ],
                            )
                          else
                            Text(
                              typeLabel.toUpperCase(),
                              style: TextStyle(
                                color: typeColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.15,
                              ),
                            ),
                        ],
                        // Le bandeau desktop suit aussi le direct Firebase.
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('publicSpots')
                              .doc(spot.id)
                              .snapshots(),
                          builder: (context, snapshot) {
                            var currentSpot = spot;
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final data = snapshot.data!.data();
                              if (data != null) {
                                currentSpot = SpotFlagState.fromFirestore(
                                  snapshot.data!.id,
                                  data,
                                );
                              }
                            }
                            final alerts = _publicSpotHeaderAlerts(currentSpot);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final alert in alerts) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '⚠️ $alert',
                                    style: const TextStyle(
                                      color: Color(0xFFFF0000),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF53657A),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: PublicSpotMobileSheet(
                  spot: spot,
                  desktopMode: true,
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
  final bool desktopMode;

  const PublicSpotMobileSheet({
    super.key,
    required this.spot,
    this.desktopMode = false,
  });

  @override
  State<PublicSpotMobileSheet> createState() =>
      _PublicSpotMobileSheetState();
}

class _PublicSpotMobileSheetState extends State<PublicSpotMobileSheet> {
  int _selectedPage = 0;
  bool _isSaved = false;
  late final List<GlobalKey> _pageTabKeys;
  late final ScrollController _contentScrollController;

  static const List<(String, IconData)> _pages = [
    ('Live', Icons.sensors_rounded),
    ('Signaux', Icons.flag_outlined),
    ('Météo terrestre', Icons.wb_sunny_outlined),
    ('Météo marine', Icons.water_rounded),
    ('Dicton & Éphéméride', Icons.calendar_today_outlined),
    ('Infos', Icons.info_outline_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _pageTabKeys = List<GlobalKey>.generate(
      _pages.length,
      (_) => GlobalKey(),
    );
    _contentScrollController = ScrollController();
    _loadSavedState();
  }

  @override
  void dispose() {
    _contentScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedState() async {
    final saved = await PublicFavoritesService.contains(widget.spot.id);

    if (!mounted) return;

    setState(() {
      _isSaved = saved;
    });
  }

  Future<void> _openDirections(SpotFlagState spot) async {
    final destination = '${spot.lat},${spot.lng}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destination',
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _startNavigation(SpotFlagState spot) async {
    final destination = '${spot.lat},${spot.lng}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/'
      '?api=1&destination=$destination&dir_action=navigate',
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareSpot(
    BuildContext context,
    SpotFlagState spot,
  ) async {
    final mapsUrl =
        'https://www.google.com/maps/search/?api=1&query='
        '${spot.lat},${spot.lng}';
    final placeName = spot.mapDisplayName.trim().isEmpty
        ? 'SPHOT'
        : spot.mapDisplayName.trim();

    final box = context.findRenderObject();
    Rect? shareOrigin;
    if (box is RenderBox) {
      shareOrigin = box.localToGlobal(Offset.zero) & box.size;
    }

    await SharePlus.instance.share(
      ShareParams(
        subject: placeName,
        text: '$placeName\n$mapsUrl',
        sharePositionOrigin: shareOrigin,
      ),
    );
  }

  Future<void> _toggleSaved(SpotFlagState spot) async {
    final nextSaved = await PublicFavoritesService.toggle(spot.id);

    if (!mounted) return;

    setState(() {
      _isSaved = nextSaved;
    });
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

  Future<void> _openAdvertiserWebsite() async {
    if (!mounted) return;

    await Navigator.of(context).pushNamed('/advertiser');
  }

  Widget _buildAdvertisingSpace() {
    return GestureDetector(
      onTap: _openAdvertiserWebsite,
      child: Container(
        width: double.infinity,
        height: 90,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.black.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: SvgPicture.asset(
                'data/icons/fire_red_icon.svg',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AJOUTE TON SPHOT PUBLICITAIRE ICI !',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Visuel : PNG, JPG ou WEBP\n'
                    '1200 × 600 px - 2 Mo max',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
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

  Future<void> _selectPage(int index) async {
    if (_contentScrollController.hasClients) {
      _contentScrollController.jumpTo(
        _contentScrollController.position.minScrollExtent,
      );
    }

    if (_selectedPage != index) {
      setState(() => _selectedPage = index);
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    if (_contentScrollController.hasClients) {
      _contentScrollController.jumpTo(
        _contentScrollController.position.minScrollExtent,
      );
    }

    final tabContext = _pageTabKeys[index].currentContext;
    if (tabContext != null) {
      await Scrollable.ensureVisible(
        tabContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Widget _buildSpotActions(
    BuildContext context,
    SpotFlagState spot,
  ) {
    return _MobileSpotActionBar(
      isSaved: _isSaved,
      onDirections: () => _openDirections(spot),
      onShare: () => _shareSpot(context, spot),
      onSave: () => _toggleSaved(spot),
    );
  }

  List<String> _valuesForPrefixes(
    List<String> values,
    List<String> prefixes,
  ) {
    return values.where((value) {
      return prefixes.any(
        (prefix) => value == prefix || value.startsWith('$prefix :'),
      );
    }).toList(growable: false);
  }

  List<String> _stripDisplayedPrefix(
    List<String> values,
    String prefix,
  ) {
    final marker = '$prefix :';

    return values.map((value) {
      final trimmed = value.trim();

      if (trimmed.startsWith(marker)) {
        return trimmed.substring(marker.length).trim();
      }

      return trimmed;
    }).where((value) => value.isNotEmpty).toList(growable: false);
  }

  Widget _buildGroupedPage({
    required BuildContext context,
    required SpotFlagState spot,
    required ScrollController controller,
    required List<(IconData, String, List<String>)> groups,
  }) {
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          _MobilePublicCard(
            child: _LiveDataBlock(
              icon: groups[index].$1,
              title: groups[index].$2,
              values: groups[index].$3,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _buildAdvertisingSpace(),
        const SizedBox(height: 10),
        _buildSpotActions(context, spot),
      ],
    );
  }

  Widget _buildTerrestrialPage(
    BuildContext context,
    SpotFlagState spot,
    ScrollController controller,
  ) {
    final values = _PublicLiveDataSection._formatTerrestrialValues(
      spot.meteoTerrestre,
    );

    return _buildGroupedPage(
      context: context,
      spot: spot,
      controller: controller,
      groups: [
        (
          Icons.thermostat_outlined,
          'Températures',
          _valuesForPrefixes(
            values,
            const [
              'Température de l’air mini',
              'Température de l’air maxi',
            ],
          ),
        ),
        (
          Icons.wb_cloudy_outlined,
          'Ciel',
          _valuesForPrefixes(
            values,
            const ['Ciel matin', 'Ciel après-midi'],
          ),
        ),
        (
          Icons.air_rounded,
          'Vent',
          _valuesForPrefixes(
            values,
            const [
              'Direction vent matin',
              'Vent matin',
              'Direction vent après-midi',
              'Vent après-midi',
              'Rafales',
            ],
          ),
        ),
        (
          Icons.wb_sunny_outlined,
          'Indice UV',
          _valuesForPrefixes(values, const ['Indice UV']),
        ),
        (
          Icons.local_fire_department_outlined,
          'Canicule',
          _valuesForPrefixes(values, const ['Niveau canicule']),
        ),
      ],
    );
  }

  Widget _buildMarinePage(
    BuildContext context,
    SpotFlagState spot,
    ScrollController controller,
  ) {
    final marineData =
        _PublicLiveDataSection._asStringMap(spot.meteoMarine);
    final tidesPresent = marineData['Marées présentes'] != false;
    final values = _PublicLiveDataSection._formatMarineValues(
      spot.meteoMarine,
    );

    return _buildGroupedPage(
      context: context,
      spot: spot,
      controller: controller,
      groups: [
        (
          Icons.thermostat_outlined,
          'Températures de l’eau',
          _valuesForPrefixes(
            values,
            const [
              'Température de l’eau mini',
              'Température de l’eau maxi',
            ],
          ),
        ),
        (
          Icons.water_outlined,
          'État de la mer',
          _valuesForPrefixes(values, const ['État de la mer']),
        ),
        (
          Icons.waves_rounded,
          'Houle',
          _valuesForPrefixes(
            values,
            const [
              'Direction de la houle matin',
              'Direction de la houle après-midi',
              'Houle matin',
              'Houle après-midi',
            ],
          ),
        ),
        (
          Icons.timelapse_rounded,
          'Périodes de houle',
          _valuesForPrefixes(
            values,
            const ['Période houle mini', 'Période houle maxi'],
          ),
        ),
        (
          Icons.tsunami_rounded,
          'Marées et coefficients',
          tidesPresent
              ? _valuesForPrefixes(
                  values,
                  const [
                    'Basses mer',
                    'Pleines mer',
                    'Coefficient basse mer',
                    'Coefficient haute mer',
                  ],
                )
              : const ['Absentes ou non significatives'],
        ),
      ],
    );
  }

  Widget _buildEphemeridePage(
    BuildContext context,
    SpotFlagState spot,
    ScrollController controller,
  ) {
    final values = _PublicLiveDataSection._formatEphemerideValues(
      spot.ephemeride,
    );

    return _buildGroupedPage(
      context: context,
      spot: spot,
      controller: controller,
      groups: [
        (
          Icons.format_quote_rounded,
          'Dicton',
          _stripDisplayedPrefix(
            _valuesForPrefixes(values, const ['Dicton']),
            'Dicton',
          ),
        ),
        (
          Icons.calendar_today_outlined,
          'Éphéméride',
          _stripDisplayedPrefix(
            _valuesForPrefixes(values, const ['Éphéméride']),
            'Éphéméride',
          ),
        ),
      ],
    );
  }

  Widget _buildUnsupervisedSpotPage(
    BuildContext context,
    SpotFlagState spot,
    ScrollController controller,
  ) {
    final hasCoreInfo =
        spot.periode.trim().isNotEmpty ||
        spot.heureDebut.trim().isNotEmpty ||
        spot.heureFin.trim().isNotEmpty ||
        spot.activite.trim().isNotEmpty;

    final warningTitle = spot.normalizedType.contains('PLAGE')
        ? 'PLAGE NON SURVEILLÉE'
        : 'BAIGNADE NON SURVEILLÉE';

    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        _UnsupervisedWarning(title: warningTitle),
        const SizedBox(height: 10),

        _MobilePublicCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spot.mapDisplayName,
                style: const TextStyle(
                  color: Color(0xFF172033),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              if (spot.ville.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  spot.ville.toUpperCase(),
                  style: const TextStyle(
                    color: _sphotWarmRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),

        if (spot.publicMediaUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MobilePublicCard(
            child: _PublicWebcamSection(
              url: spot.publicMediaUrl,
              isPhoto: spot.publicMediaIsPhoto,
            ),
          ),
        ],

        if (hasCoreInfo) ...[
          const SizedBox(height: 10),
          _MobilePublicCard(
            child: Column(
              children: [
                if (spot.periode.isNotEmpty)
                  _PublicInfoLine(
                    icon: Icons.date_range_outlined,
                    label: 'Période',
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
                if (spot.activite.isNotEmpty)
                  _PublicInfoLine(
                    icon: Icons.waves_outlined,
                    label: 'Activités',
                    value: spot.activite,
                  ),
              ],
            ),
          ),
        ],

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
                    icon: Icons.language_rounded,
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

        const SizedBox(height: 12),
        _buildAdvertisingSpace(),
        const SizedBox(height: 10),
        _buildSpotActions(context, spot),
      ],
    );
  }

  Widget _buildSelectedPage(
    BuildContext context,
    SpotFlagState spot,
  ) {
    switch (_selectedPage) {
      case 1:
        return _buildSignalsPage(
          context,
          spot,
          _contentScrollController,
        );
      case 2:
        return _buildTerrestrialPage(
          context,
          spot,
          _contentScrollController,
        );
      case 3:
        return _buildMarinePage(
          context,
          spot,
          _contentScrollController,
        );
      case 4:
        return _buildEphemeridePage(
          context,
          spot,
          _contentScrollController,
        );
      case 5:
        return _buildInfoPage(
          context,
          spot,
          _contentScrollController,
        );
      default:
        return _buildActionsPage(
          context,
          spot,
          _contentScrollController,
        );
    }
  }

  // Identité toujours visible lorsque la carte est masquée par la fiche.
  // Ce bandeau reste hors de la zone défilante de chaque rubrique.
  Widget _buildMobileSpotHeader(SpotFlagState spot) {
    final name = spot.mapDisplayName.trim();
    final city = spot.ville.trim().toUpperCase();
    final type = spot.isPosteSecours
        ? 'POSTE DE SECOURS'
        : spot.typeSphot.trim().toUpperCase();
    final nameColor =
        spot.isPosteSecours ? const Color(0xFFFF0000) : Colors.black;
    final typeColor = _publicSpotTypeTextColor(spot);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 7, 6, 6),
      decoration: const BoxDecoration(
        gradient: _sphotWarmSoftGradient,
        border: Border(
          bottom: BorderSide(color: _sphotWarmBorder),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'SPHOT' : name.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: nameColor,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
                if (city.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (type.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  if (spot.isPosteSecours)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'data/icons/flag_red_yellow_5x3.svg',
                          width: 12,
                          height: 14,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: typeColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: typeColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
                for (final alert in _publicSpotHeaderAlerts(spot)) ...[
                  const SizedBox(height: 3),
                  Text(
                    '⚠️ $alert',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFF0000),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fermer la fiche',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close_rounded,
              size: 23,
              color: Color(0xFF53657A),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            decoration: BoxDecoration(
              color: _sphotWarmSurface,
              borderRadius: widget.desktopMode
                  ? BorderRadius.circular(18)
                  : const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 22,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              children: [
                if (!widget.desktopMode)
                  _buildMobileSpotHeader(currentSpot)
                else
                  const SizedBox(height: 10),
                if (currentSpot.isPosteSecours)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      height: 48,
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          2,
                          MediaQuery.sizeOf(context).width * 0.55,
                          8,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: _pages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 4),
                        itemBuilder: (context, index) {
                          final page = _pages[index];
                          final selected = _selectedPage == index;

                          return InkWell(
                            borderRadius: BorderRadius.circular(99),
                            onTap: () => _selectPage(index),
                            child: AnimatedContainer(
                              key: _pageTabKeys[index],
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: selected
                                    ? _sphotWarmGradient
                                    : _sphotWarmSoftGradient,
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: selected
                                      ? _sphotWarmRed
                                      : _sphotWarmBorder,
                                  width: selected ? 1.2 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    page.$2,
                                    size: 17,
                                    color: selected
                                        ? Colors.white
                                        : _sphotWarmRed,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    page.$1.toUpperCase(),
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : _sphotWarmRed,
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
                  ),
                Expanded(
                  child: currentSpot.isPosteSecours
                      ? _buildSelectedPage(context, currentSpot)
                      : _buildUnsupervisedSpotPage(
                          context,
                          currentSpot,
                          _contentScrollController,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatFrenchPhoneForDisplay(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length == 10 && digits.startsWith('0')) {
      final groups = <String>[];

      for (var index = 0; index < digits.length; index += 2) {
        groups.add(digits.substring(index, index + 2));
      }

      return groups.join(' ');
    }

    return rawPhone.trim();
  }

  Widget _buildActionsPage(
    BuildContext context,
    SpotFlagState spot,
    ScrollController controller,
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
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
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
        _PublicDangerList(values: dangerValues),
        if (notificationActive && notificationMessage.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PublicNotificationCard(
            message: notificationMessage,
            publishedAt: notificationPublishedAt,
          ),
        ],
        if (spot.phone.isNotEmpty) ...[
          const SizedBox(height: 10),
          _MobileQuickAction(
            icon: Icons.call_outlined,
            label: 'Appeler',
            onTap: () => _call(spot),
          ),
        ],
        const SizedBox(height: 10),
        if (spot.publicMediaUrl.isNotEmpty)
          _MobilePublicCard(
            child: _PublicWebcamSection(
              url: spot.publicMediaUrl,
              isPhoto: spot.publicMediaIsPhoto,
            ),
          )
        else
          const _MobilePublicCard(
            child: _MobileMediaPlaceholder(),
          ),
        const SizedBox(height: 12),
        _buildAdvertisingSpace(),
        const SizedBox(height: 10),
        _buildSpotActions(context, spot),
      ],
    );
  }

  Widget _buildSignalsPage(
    BuildContext context,
    SpotFlagState spot,
    ScrollController controller,
  ) {
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        const _MobilePublicCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.flag_outlined,
                    size: 19,
                    color: _sphotWarmRed,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SIGNIFICATION DES SIGNAUX DE BAIGNADE',
                      style: _publicSectionTitleStyle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _BathingSignalsLegend(),
        const SizedBox(height: 12),
        _buildAdvertisingSpace(),
        const SizedBox(height: 10),
        _buildSpotActions(context, spot),
      ],
    );
  }

  Widget _buildInfoPage(
    BuildContext context,
    SpotFlagState spot,
    ScrollController controller,
  ) {
    final hasCoreInfo =
        spot.periode.trim().isNotEmpty ||
        spot.heureDebut.trim().isNotEmpty ||
        spot.heureFin.trim().isNotEmpty ||
        spot.activite.trim().isNotEmpty;

    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(
        parent: ClampingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      children: [
        _MobilePublicCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spot.mapDisplayName,
                style: TextStyle(
                  color: spot.isPosteSecours
                      ? const Color(0xFFFF0000)
                      : const Color(0xFF172033),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              if (spot.ville.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  spot.ville.toUpperCase(),
                  style: const TextStyle(
                    color: _sphotWarmRed,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (spot.phone.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _MobilePublicCard(
            child: _PublicInfoLine(
              icon: Icons.phone_in_talk_outlined,
              label: 'Téléphone du poste de secours',
              value: _formatFrenchPhoneForDisplay(spot.phone),
              onTap: () => _call(spot),
            ),
          ),
        ],
        if (hasCoreInfo) ...[
          const SizedBox(height: 10),
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
                if (spot.activite.isNotEmpty)
                  _PublicInfoLine(
                    icon: Icons.waves_outlined,
                    label: 'Activités',
                    value: spot.activite,
                  ),
              ],
            ),
          ),
        ],
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
                    icon: Icons.language_rounded,
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
        const SizedBox(height: 12),
        _buildAdvertisingSpace(),
        const SizedBox(height: 10),
        _buildSpotActions(context, spot),
      ],
    );
  }
}

class _BathingSignalsLegend extends StatelessWidget {
  const _BathingSignalsLegend();

  @override
  Widget build(BuildContext context) {
    const signals = <_BathingSignalData>[
      _BathingSignalData(
        visual: _BathingSignalVisual.greenFlag,
        title: 'Drapeau vert',
        description: 'Baignade surveillée sans danger apparent.',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.yellowFlag,
        title: 'Drapeau jaune',
        description:
            'Baignade surveillée avec danger limité ou marqué.',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.redFlag,
        title: 'Drapeau rouge',
        description: 'Baignade interdite.',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.redYellowFlag,
        title: 'Drapeau rouge et jaune',
        description:
            'Zone de baignade surveillée pendant les horaires d’ouverture du poste de secours.',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.purpleFlag,
        title: 'Drapeau violet',
        description:
            'Pollution ou présence d’espèces aquatiques dangereuses, ou zone marine et sous-marine protégée (faune aquatique, récifs…).',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.orangeWindsock,
        title: 'Manche à air orange',
        description:
            'Conditions défavorables de vent pour certains équipements nautiques (ex. : gonflables).',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.checkeredFlag,
        title: 'Drapeau à damier noir et blanc',
        description:
            'Zone de pratiques aquatiques et nautiques.',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.temporaryBan,
        title: 'Interdiction temporaire',
        description:
            'Interdiction temporaire de la baignade, hors zone surveillée.',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.blueObligation,
        title: 'Disque bleu',
        description: 'Obligation ou autorisation.',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.prohibition,
        title: 'Cercle rouge barré',
        description: 'Interdiction.',
      ),
      _BathingSignalData(
        visual: _BathingSignalVisual.warning,
        title: 'Triangle jaune',
        description: 'Avertissement.',
      ),
    ];

    return _MobilePublicCard(
      child: Column(
        children: [
          for (var index = 0; index < signals.length; index++) ...[
            _BathingSignalRow(data: signals[index]),
            if (index < signals.length - 1)
              const Divider(
                height: 18,
                color: Color(0xFFE2E8F0),
              ),
          ],
        ],
      ),
    );
  }
}

enum _BathingSignalVisual {
  greenFlag,
  yellowFlag,
  redFlag,
  redYellowFlag,
  purpleFlag,
  orangeWindsock,
  checkeredFlag,
  temporaryBan,
  blueObligation,
  prohibition,
  warning,
}

class _BathingSignalData {
  final _BathingSignalVisual visual;
  final String title;
  final String description;

  const _BathingSignalData({
    required this.visual,
    required this.title,
    required this.description,
  });
}

class _BathingSignalRow extends StatelessWidget {
  final _BathingSignalData data;

  const _BathingSignalRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          height: data.visual == _BathingSignalVisual.temporaryBan ? 78 : 56,
          child: Center(
            child: _BathingSignalSymbol(visual: data.visual),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF172033),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data.description,
                style: const TextStyle(
                  color: Color(0xFF526077),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BathingSignalSymbol extends StatelessWidget {
  final _BathingSignalVisual visual;

  const _BathingSignalSymbol({required this.visual});

  @override
  Widget build(BuildContext context) {
    switch (visual) {
      case _BathingSignalVisual.greenFlag:
        return const _SolidSignalFlag(color: Color(0xFF49B43B));
      case _BathingSignalVisual.yellowFlag:
        return const _SolidSignalFlag(color: Color(0xFFFFE500));
      case _BathingSignalVisual.redFlag:
        return const _SolidSignalFlag(color: Color(0xFFE31B13));
      case _BathingSignalVisual.redYellowFlag:
        return const _RedYellowSignalFlag();
      case _BathingSignalVisual.purpleFlag:
        return const _SolidSignalFlag(color: Color(0xFFD946EF));
      case _BathingSignalVisual.orangeWindsock:
        return const WindsockGlyph(
          width: 54,
          height: 32,
        );
      case _BathingSignalVisual.checkeredFlag:
        return const _CheckeredSignalFlag();
      case _BathingSignalVisual.temporaryBan:
        return const _TemporarySwimmingBanSymbol();
      case _BathingSignalVisual.blueObligation:
        return Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Color(0xFF365FA8),
            shape: BoxShape.circle,
          ),
        );
      case _BathingSignalVisual.prohibition:
        return const _ProhibitionSymbol();
      case _BathingSignalVisual.warning:
        return const Icon(
          Icons.warning_amber_rounded,
          size: 49,
          color: Color(0xFFFFE500),
          shadows: [
            Shadow(
              color: Colors.black,
              blurRadius: 0,
            ),
          ],
        );
    }
  }
}

class _SolidSignalFlag extends StatelessWidget {
  final Color color;

  const _SolidSignalFlag({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 9,
            top: 4,
            bottom: 2,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF8A8A8A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 6,
            child: Container(
              width: 39,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                border: Border.all(
                  color: Colors.black.withOpacity(0.20),
                  width: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RedYellowSignalFlag extends StatelessWidget {
  const _RedYellowSignalFlag();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 50,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 8,
            top: 3,
            bottom: 1,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF8A8A8A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: 11,
            top: 5,
            child: SizedBox(
              width: 43,
              height: 26,
              child: SvgPicture.asset(
                'data/icons/flag_red_yellow_5x3.svg',
                fit: BoxFit.fill,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckeredSignalFlag extends StatelessWidget {
  const _CheckeredSignalFlag();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 56,
      child: SvgPicture.asset(
        'data/icons/signal_checkered_flag.svg',
        fit: BoxFit.contain,
      ),
    );
  }
}

class _TemporarySwimmingBanSymbol extends StatelessWidget {
  const _TemporarySwimmingBanSymbol();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      height: 78,
      child: SvgPicture.asset(
        'data/icons/signal_temporary_swimming_ban.svg',
        fit: BoxFit.contain,
      ),
    );
  }
}

class _ProhibitionSymbol extends StatelessWidget {
  const _ProhibitionSymbol();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFE31B13),
                width: 5,
              ),
            ),
          ),
          Transform.rotate(
            angle: -0.78,
            child: Container(
              width: 5,
              height: 48,
              color: const Color(0xFFE31B13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileSpotActionBar extends StatelessWidget {
  final bool isSaved;
  final VoidCallback onDirections;
  final VoidCallback onShare;
  final VoidCallback onSave;

  const _MobileSpotActionBar({
    required this.isSaved,
    required this.onDirections,
    required this.onShare,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    // Les trois actions tiennent sur la largeur, sans défilement horizontal.
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
        child: Row(
          children: [
            Expanded(
              child: _MobileSpotActionButton(
                icon: Icons.directions_rounded,
                label: 'ITINÉRAIRE',
                onTap: onDirections,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MobileSpotActionButton(
                icon: Icons.share_rounded,
                label: 'PARTAGER',
                onTap: onShare,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MobileSpotActionButton(
                icon: isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: isSaved ? 'ENREGISTRÉ' : 'ENREGISTRER',
                selected: isSaved,
                onTap: onSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSpotActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MobileSpotActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          gradient: selected
              ? _sphotWarmGradient
              : _sphotWarmSoftGradient,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? _sphotWarmRed : _sphotWarmBorder,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? Colors.white
                    : _sphotWarmRed,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : _sphotWarmRed,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.all(1.15),
      decoration: BoxDecoration(
        gradient: _sphotWarmGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          gradient: _sphotWarmSoftGradient,
          borderRadius: BorderRadius.circular(17),
        ),
        child: child,
      ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _sphotWarmSoftGradient,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _sphotWarmBorder,
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: _sphotWarmRed),
              const SizedBox(width: 7),
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: _sphotWarmRed,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
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
    if (spot.isRealtimeAwaitingUpdate) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          gradient: _sphotWarmSoftGradient,
          color: _sphotWarmSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _sphotWarmBorder),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sync_rounded,
                  size: 18,
                  color: _sphotWarmOrange,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'INFORMATIONS EN TEMPS RÉEL EN ATTENTE DE MISE À JOUR',
                    style: TextStyle(
                      color: _sphotWarmRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Le service temps réel est actif, mais aucune information '
              'opérationnelle actualisée n’a encore été transmise depuis '
              'son activation. Consultez les consignes affichées sur place.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    if (!spot.realtimeAvailable) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          gradient: _sphotWarmSoftGradient,
          color: _sphotWarmSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _sphotWarmBorder),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: _sphotWarmOrange,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'INFORMATIONS EN TEMPS RÉEL INDISPONIBLES',
                    style: TextStyle(
                      color: _sphotWarmRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Les informations opérationnelles de surveillance ne sont '
              'actuellement pas diffusées sur SPHOT. Consultez les '
              'informations et consignes affichées sur place.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

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
        gradient: _sphotWarmSoftGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _sphotWarmBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sensors_rounded,
                size: 18,
                color: _sphotWarmRed,
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
            Icons.warning_amber_rounded,
            size: 21,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DANGERS DU JOUR',
                  style: TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                if (values.isEmpty)
                  const Text(
                    'Aucun danger signalé',
                    style: TextStyle(
                      color: Colors.black54,
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
      ),
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
            style: const TextStyle(
              color: Colors.black87,
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
          color: _sphotWarmRed,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: _sphotWarmRed,
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
  final bool isPhoto;

  const _PublicWebcamSection({
    required this.url,
    this.isPhoto = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = isPhoto ? 'PHOTO' : 'WEBCAM';
    final fullscreenLabel =
        isPhoto ? 'AGRANDIR LA PHOTO' : 'AGRANDIR LA WEBCAM';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isPhoto
                  ? Icons.photo_outlined
                  : Icons.videocam_outlined,
              size: 19,
              color: _sphotWarmRed,
            ),
            const SizedBox(width: 7),
            Text(
              title,
              style: _publicSectionTitleStyle,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: PublicWebcamView(
              url: url,
              forceImage: isPhoto,
            ),
          ),
        ),
        const SizedBox(height: 9),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PublicWebcamFullScreenPage(
                  url: url,
                  forceImage: isPhoto,
                ),
              ),
            ),
            icon: const Icon(Icons.fullscreen_rounded),
            label: Text(fullscreenLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: _sphotWarmRed,
              side: const BorderSide(color: _sphotWarmRed),
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
  final String title;

  const _UnsupervisedWarning({
    this.title = 'BAIGNADE NON SURVEILLÉE',
  });

  Widget _warningLine(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 18,
          color: Color(0xFFFFC107),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFF0000),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

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
      child: Column(
        children: [
          _warningLine(title),
          const SizedBox(height: 3),
          _warningLine('BAIGNADE À VOS RISQUES ET PÉRILS'),
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
              Icon(icon, size: 17, color: _sphotWarmRed),
            const SizedBox(width: 8),
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
                                  : _sphotWarmRed),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
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
              color: _sphotWarmRed,
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

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        gradient: _sphotWarmSoftGradient,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: _sphotWarmBorder.withOpacity(0.55),
          width: 0.8,
        ),
      ),
      child: Row(
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
          Flexible(
            child: Text(
              displayName,
              style: const TextStyle(
                color: Color(0xFF3F4650),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _sphotWarmRed,
        side: const BorderSide(color: _sphotWarmRed),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
