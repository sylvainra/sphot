import 'dart:math';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/adaptive_asset_image.dart';
import '../widgets/sphot_advertising_invitation_visual.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/flag_state.dart';
import '../services/firestore_service.dart';
import '../services/public_favorites_service.dart';
import 'flag_marker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'app_info_page.dart';
import 'public_spot_detail_page.dart';

import 'package:url_launcher/url_launcher.dart';


enum SpotFilter {
  all,
  secours,
  plage,
  eauBleue,
  eauVerte,
  lagon,
  naturisme,
  autre,
}

class _MapTileStyle {
  final String name;
  final String url;
  final List<String> subdomains;
  final int maxZoom;

  const _MapTileStyle({
    required this.name,
    required this.url,
    this.subdomains = const [],
    this.maxZoom = 19,
  });
}

class _SphotSingleWorldCrs extends Epsg3857 {
  const _SphotSingleWorldCrs();

  @override
  bool get replicatesWorldLongitude => false;
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirestoreService _firestoreService = FirestoreService();
  final MapController _mapController = MapController();
  late final Future<List<Map<String, dynamic>>>
      _publicAdvertisingSpotsFuture;
  late final Future<List<Map<String, dynamic>>>
      _publicMapAdvertisementsFuture;

  // La bande publicitaire ne réinitialise jamais le flux des SPHOTS.
  final ValueNotifier<int> _mapAdRotation = ValueNotifier<int>(0);
  Timer? _mapAdRotationTimer;
  LatLng _mapAdCenter = const LatLng(46.4006176, -1.5064563);

  SpotFilter _selectedFilter = SpotFilter.all;

  double _currentRotation = 0;
  // Fond satellite dès l'ouverture sur Web et mobile ; l'utilisateur peut
  // toujours choisir Plan ou Relief via le sélecteur de cartes.
  int _selectedTileStyle = 1;
  int _mapTileRefreshVersion = 0;
  int _selectedBottomIndex = 1;
  String? _selectedPublicSpotId;
  // Le volet public natif est affiché dans la Stack de la carte, sans
  // barrière modale : les zones dégagées restent manipulables.
  SpotFlagState? _mobileDetailSpot;
  // Sur le Web grand écran, le volet à droite appartient à la même Stack
  // que FlutterMap : aucun barrier modal ne capte les gestes sur la carte.
  SpotFlagState? _desktopDetailSpot;
  final ValueNotifier<double> _mobileDetailHeightFraction =
      ValueNotifier<double>(1.0);
  static const double _mobileDetailMinHeightFraction = 0.20;
  // Le menu inférieur mesure 52 px et se trouve à 6 px du bas.
  // Le volet laisse 6 px supplémentaires au-dessus de son contour.
  static const double _mobileBottomMenuSideInset = 8.0;
  static const double _mobileBottomMenuHeight = 52.0;
  static const double _mobileBottomMenuBottom = 6.0;
  static const double _mobileDetailMenuGap = 6.0;
  static const double _mobileDetailBottomOffset =
      _mobileBottomMenuHeight +
      _mobileBottomMenuBottom +
      _mobileDetailMenuGap;
  static const double _mapHeaderLogoHeight = 68.0;
  static const double _mapHeaderLogoTop = 3.0;
  String? _hoveredRescueSpotId;
  static const double _desktopSelectedAdBottom = 6.0;
  static const double _desktopSelectedAdHeight = 142.0;
  Set<String> _favoriteSpotIds = <String>{};
  bool _showFavoritesOnly = false;
  bool _isMovingMap = false;
  Timer? _mapMoveTimer;
Timer? _searchTimer;

bool _isFilterOpen = false;
bool _isMapStyleOpen = false;
bool _isSearchPanelOpen = false;

final TextEditingController _searchController = TextEditingController();
final FocusNode _searchFocusNode = FocusNode();

late stt.SpeechToText _speech;
bool _isListening = false;

static const List<_MapTileStyle> _tileStyles = [
  _MapTileStyle(
    name: 'Plan',
    url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxZoom: 19,
  ),
  _MapTileStyle(
  name: 'Satellite',
  url:
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  maxZoom: 19,
  ),
];

@override
void initState() {
  super.initState();
  _speech = stt.SpeechToText();
  _publicAdvertisingSpotsFuture =
      _firestoreService.getPublicAdvertisingSpots();
  _publicMapAdvertisementsFuture =
      _firestoreService.getPublicMapAdvertisements();
  _mapAdRotationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
    if (mounted) _mapAdRotation.value += 1;
  });
  unawaited(_loadFavoriteSpotIds());
}

Future<void> _loadFavoriteSpotIds() async {
  final ids = await PublicFavoritesService.loadFavoriteIds();

  if (!mounted) return;

  setState(() {
    _favoriteSpotIds = ids;
    if (_showFavoritesOnly && ids.isEmpty) {
      _showFavoritesOnly = false;
    }
  });
}

Future<void> _toggleFavoritesFilter() async {
  final ids = await PublicFavoritesService.loadFavoriteIds();

  if (!mounted) return;

  if (ids.isEmpty) {
    setState(() {
      _favoriteSpotIds = ids;
      _showFavoritesOnly = false;
    });
    return;
  }

  setState(() {
    _favoriteSpotIds = ids;
    _showFavoritesOnly = !_showFavoritesOnly;
    if (_showFavoritesOnly) {
      _selectedFilter = SpotFilter.all;
    }
    _isFilterOpen = false;
    _isMapStyleOpen = false;
  });
}

  bool _showTextForZoom(double zoom) {
    final isTouchDevice =
        Theme.of(context).platform == TargetPlatform.android ||
            Theme.of(context).platform == TargetPlatform.iOS;

    if (isTouchDevice) {
      return zoom >= 16.0;
    }

    return zoom >= 13.0;
  }

  double _labelOpacity(double zoom) {
    if (zoom >= 14.5) return 1.0;
    if (zoom >= 13.8) return 0.88;
    if (zoom >= 13.0) return 0.72;
    return 0.0;
  }

  bool get _useAutomaticTouchLabels {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  double _automaticLabelMinimumDistance(double zoom) {
    if (zoom >= 17.5) return 82;
    if (zoom >= 17.0) return 92;
    if (zoom >= 16.5) return 108;
    if (zoom >= 16.0) return 124;
    if (zoom >= 15.5) return 145;
    if (zoom >= 15.0) return 170;
    return 200;
  }

  Offset _mercatorPixelPoint(SpotFlagState spot, double zoom) {
    final worldSize = 256.0 * pow(2.0, zoom);
    final latitude = spot.lat.clamp(-85.05112878, 85.05112878);
    final sinLatitude = sin(latitude * pi / 180);

    final x = (spot.lng + 180.0) / 360.0 * worldSize;
    final y = (0.5 -
            log((1 + sinLatitude) / (1 - sinLatitude)) /
                (4 * pi)) *
        worldSize;

    return Offset(x, y);
  }

  LatLng _latLngFromMercatorPixelPoint(
    Offset point,
    double zoom,
  ) {
    final worldSize = 256.0 * pow(2.0, zoom).toDouble();
    final lng = (point.dx / worldSize) * 360.0 - 180.0;
    final n = pi - (2.0 * pi * point.dy / worldSize);
    final lat =
        180.0 /
        pi *
        atan((exp(n) - exp(-n)) / 2.0);

    return LatLng(lat, lng);
  }

  double _measureSelectedLabelHeight(
    String text, {
    required double fontSize,
    required double maxWidth,
    FontWeight fontWeight = FontWeight.w800,
  }) {
    final value = text.trim();
    if (value.isEmpty) return 0;

    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    return painter.height;
  }

  ({double above, double below}) _selectedSpotVisualExtents(
    SpotFlagState spot,
    double screenWidth,
  ) {
    const lineSpacing = _mapInfoLineGap;

    if (spot.isPosteSecours) {
      final labelWidth = min(420.0, max(180.0, screenWidth - 24));
      final nameHeight = _measureSelectedLabelHeight(
        spot.mapDisplayName,
        fontSize: 13,
        maxWidth: labelWidth,
        fontWeight: FontWeight.bold,
      );
      final cityHeight = _measureSelectedLabelHeight(
        spot.ville.toUpperCase(),
        fontSize: 12,
        maxWidth: labelWidth,
      );

      final statusText = spot.hasValidFlag
          ? spot.displayStatut.replaceAll('⚠️ ', '')
          : _rescueWarningLines(spot).join(' ');
      final statusHeight = spot.hasValidFlag
          ? max(
              24.0,
              _measureSelectedLabelHeight(
                statusText,
                fontSize: 13.2,
                maxWidth: max(150.0, labelWidth - 34),
                fontWeight: FontWeight.w900,
              ),
            )
          : _rescueWarningLines(spot).length == 1
              ? 27.0
              : 49.0;

      // Le haut réel du mât se situe environ 75 px au-dessus
      // du point GPS du marker sélectionné.
      const above = 75.0;
      final below =
          8.0 +
          nameHeight +
          (cityHeight > 0 ? lineSpacing + 3 + cityHeight : 0) +
          lineSpacing +
          34.0 +
          lineSpacing +
          statusHeight;

      return (above: above, below: below);
    }

    final labelWidth = min(380.0, max(180.0, screenWidth - 24));
    final nameHeight = _measureSelectedLabelHeight(
      spot.mapDisplayName,
      fontSize: 13,
      maxWidth: labelWidth,
      fontWeight: FontWeight.w700,
    );
    final cityHeight = _measureSelectedLabelHeight(
      spot.ville.toUpperCase(),
      fontSize: 12,
      maxWidth: labelWidth,
    );
    final typeHeight = _measureSelectedLabelHeight(
      spot.typeSphot,
      fontSize: 14,
      maxWidth: labelWidth,
      fontWeight: FontWeight.w700,
    );

    // Référence de placement : pointe haute réelle du marker FIRE.
    // Le FIRE standard fait 48 px et le naturisme 52 px, tous deux centrés
    // sur le point GPS. Leur pointe supérieure doit s'aligner sur la même
    // référence visuelle que le haut du mât d'un poste de secours.
    final above = spot.isNaturisme ? 26.0 : 24.0;
    final below =
        24.0 +
        nameHeight +
        (cityHeight > 0 ? lineSpacing + 3 + cityHeight : 0) +
        lineSpacing +
        typeHeight +
        lineSpacing +
        24.0 +
        lineSpacing +
        24.0;

    return (above: above, below: below);
  }

  static const double _selectedSpotEdgeGap = 8.0;
  static const double _selectedSpotHeaderVisualHeight = 63.0;
  static const double _selectedSpotBottomExtentSafety = 10.0;

  double _selectedSpotVisualTop(double topSafeInset) {
    // Le logo SPHOT mesure 68 px et déborde de 5 px vers le haut.
    // Sa limite visuelle basse se situe donc à ~63 px sous le SafeArea.
    // Le haut du mât ou la pointe du marker FIRE vient ensuite avec la
    // même marge que celle conservée entre la dernière ligne et le volet.
    return topSafeInset +
        _selectedSpotHeaderVisualHeight +
        _selectedSpotEdgeGap;
  }

  double _selectedSpotSheetHeight(
    SpotFlagState spot,
    Size screenSize,
    double topSafeInset,
  ) {
    final extents = _selectedSpotVisualExtents(spot, screenSize.width);

    // La sécurité absorbe les ombres de texte et les petites différences
    // de hauteur de rendu entre Android, iOS, téléphone et tablette.
    final visualBottom =
        _selectedSpotVisualTop(topSafeInset) +
        extents.above +
        extents.below +
        _selectedSpotBottomExtentSafety;

    // Le haut du volet ne doit jamais remonter au-dessus de la dernière
    // ligne du SPHOT sélectionné. On garde exactement la même marge que
    // sous le header.
    final sheetTop = min(
      screenSize.height,
      visualBottom + _selectedSpotEdgeGap,
    );

    return max(0.0, screenSize.height - sheetTop);
  }

  double _selectedSpotTargetScreenY(
    SpotFlagState spot,
    Size screenSize,
    double topSafeInset,
  ) {
    final extents = _selectedSpotVisualExtents(spot, screenSize.width);

    // Le haut du marker / du mât est aligné juste sous le header SPHOT.
    return _selectedSpotVisualTop(topSafeInset) + extents.above;
  }

  LatLng _selectedSpotCameraCenter(
    SpotFlagState spot,
    double zoom,
    double rotation, {
    required Size screenSize,
    required double topSafeInset,
  }) {
    final spotPoint = _mercatorPixelPoint(spot, zoom);
    final targetScreenY = _selectedSpotTargetScreenY(
      spot,
      screenSize,
      topSafeInset,
    );
    final desiredScreenOffset = Offset(
      0,
      targetScreenY - (screenSize.height / 2),
    );
    final angle = rotation * pi / 180.0;

    // Le décalage doit rester vertical à l'écran même si la carte est tournée.
    final mapDx =
        desiredScreenOffset.dx * cos(angle) +
        desiredScreenOffset.dy * sin(angle);
    final mapDy =
        -desiredScreenOffset.dx * sin(angle) +
        desiredScreenOffset.dy * cos(angle);

    final centerPoint = Offset(
      spotPoint.dx - mapDx,
      spotPoint.dy - mapDy,
    );

    return _latLngFromMercatorPixelPoint(centerPoint, zoom);
  }

  LatLng _webSelectedSpotCameraCenter(
    SpotFlagState spot,
    double zoom,
    double rotation, {
    required Size screenSize,
    required double panelWidth,
    required double bottomOverlayHeight,
  }) {
    final spotPoint = _mercatorPixelPoint(spot, zoom);

    // Le panneau droit retire de la largeur utile et la publicité agrandie
    // retire de la hauteur utile. Le SPHOT est centré dans le rectangle
    // réellement visible de la carte, au-dessus de la publicité.
    final desiredScreenOffset = Offset(
      -panelWidth / 2,
      -bottomOverlayHeight / 2,
    );
    final angle = rotation * pi / 180.0;

    final mapDx =
        desiredScreenOffset.dx * cos(angle) +
        desiredScreenOffset.dy * sin(angle);
    final mapDy =
        -desiredScreenOffset.dx * sin(angle) +
        desiredScreenOffset.dy * cos(angle);

    final centerPoint = Offset(
      spotPoint.dx - mapDx,
      spotPoint.dy - mapDy,
    );

    return _latLngFromMercatorPixelPoint(centerPoint, zoom);
  }

  // Affichage automatique commun au Web et au mobile : les marqueurs
  // restent toujours présents, seules les étiquettes sont arbitrées.
  // Priorité au SPHOT sélectionné, puis aux postes de secours.
  // La zone réservée est mesurée d'après les lignes réellement affichées,
  // plutôt qu'un rectangle fixe exagérément large et haut.
  Set<String> _automaticLabelIds(
    List<SpotFlagState> spots,
    double zoom,
  ) {
    if (zoom < 16.0) return const <String>{};

    final candidates = spots
        .where((spot) =>
            spot.lat.isFinite &&
            spot.lng.isFinite &&
            spot.mapDisplayName.trim().isNotEmpty)
        .toList()
      ..sort((a, b) {
        if (a.id == _selectedPublicSpotId) return -1;
        if (b.id == _selectedPublicSpotId) return 1;
        if (a.isPosteSecours != b.isPosteSecours) {
          return a.isPosteSecours ? -1 : 1;
        }
        final latitudeCompare = a.lat.compareTo(b.lat);
        if (latitudeCompare != 0) return latitudeCompare;
        final longitudeCompare = a.lng.compareTo(b.lng);
        if (longitudeCompare != 0) return longitudeCompare;
        return a.id.compareTo(b.id);
      });

    final acceptedAreas = <Rect>[];
    final acceptedIds = <String>{};
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textScaler = MediaQuery.textScalerOf(context);

    for (final spot in candidates) {
      final point = _mercatorPixelPoint(spot, zoom);
      final isRescue = spot.isPosteSecours;
      final selected = spot.id == _selectedPublicSpotId;
      final maxLabelWidth = min(
        screenWidth - 24.0,
        isRescue ? 420.0 : 380.0,
      );

      double actualWidth = 0;
      double actualHeight = 0;
      bool hasLine = false;

      void addLine(
        String value,
        double fontSize, {
        double leadingIconWidth = 0,
        double leadingIconHeight = 0,
      }) {
        if (value.trim().isEmpty) return;
        final painter = TextPainter(
          text: TextSpan(
            text: value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
          textWidthBasis: TextWidthBasis.longestLine,
        )..layout(maxWidth: max(50.0, maxLabelWidth - leadingIconWidth));

        if (hasLine) actualHeight += _mapInfoLineGap;
        actualWidth = max(
          actualWidth,
          painter.width + leadingIconWidth,
        );
        actualHeight +=
            max(_mapWarningIconSize, max(painter.height, leadingIconHeight));
        hasLine = true;
        painter.dispose();
      }

      // Les tailles sont celles utilisées par les widgets de marqueurs,
      // y compris les pictogrammes devant les lignes de baignade.
      addLine(spot.mapDisplayName, 13.0);
      addLine(spot.ville.toUpperCase(), 12.0);

      if (isRescue) {
        addLine(
          'POSTE DE SECOURS',
          _mapTypeFontSize,
          leadingIconWidth: 16.0,
          leadingIconHeight: 14.0,
        );
        const iconSize = _mapWarningIconSize;
        if (spot.hasValidFlag) {
          addLine(
            spot.displayStatut.replaceAll('⚠️ ', ''),
            iconSize * 0.55,
            leadingIconWidth: spot.flagColor == FlagColor.green
                ? 0.0
                : iconSize + 2,
            leadingIconHeight: spot.flagColor == FlagColor.green
                ? 0.0
                : iconSize,
          );
        } else {
          for (final line in _rescueWarningLines(spot)) {
            addLine(
              line,
              iconSize * 0.55,
              leadingIconWidth: iconSize + 2,
              leadingIconHeight: iconSize,
            );
          }
        }
      } else {
        addLine(spot.typeSphot.toUpperCase(), _mapTypeFontSize);
        const iconSize = _mapWarningIconSize;
        addLine(
          'BAIGNADE NON SURVEILLÉE',
          iconSize * 0.55,
          leadingIconWidth: iconSize + 2,
          leadingIconHeight: iconSize,
        );
        addLine(
          'BAIGNADE À VOS RISQUES ET PÉRILS',
          iconSize * 0.55,
          leadingIconWidth: iconSize + 2,
          leadingIconHeight: iconSize,
        );
      }

      // Coordonnées des étiquettes : la carte centre le marqueur sur
      // la position du SPHOT. Les labels commencent sous le pictogramme.
      final labelTopOffset = isRescue
          ? (selected ? 6.5 : 4.5)
          : (selected ? 22.0 : 20.0);
      const horizontalMargin = 6.0;
      const verticalMargin = 4.0;
      final area = Rect.fromLTWH(
        point.dx - actualWidth / 2 - horizontalMargin,
        point.dy + labelTopOffset - verticalMargin,
        actualWidth + horizontalMargin * 2,
        actualHeight + verticalMargin * 2,
      );

      if (!selected && acceptedAreas.any((other) => other.overlaps(area))) {
        continue;
      }
      acceptedIds.add(spot.id);
      acceptedAreas.add(area);
    }

    return acceptedIds;
  }

  Future<void> _openLoginPage() async {
    if (!mounted) return;

    await Navigator.of(context).pushNamed('/login');
  }

  Future<void> _openAdvertiserWebsite() async {
    if (!mounted) return;

    await Navigator.of(context).pushNamed('/advertiser');
  }

  double _publicAdvertisingDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _openPublicAdvertisingSpot(
    Map<String, dynamic> advertiser,
  ) async {
    var url = advertiser['destinationUrl']?.toString().trim() ?? '';
    if (url.isEmpty) {
      _showMapMessage('Site internet de l’annonceur non renseigné.');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showMapMessage('Adresse du site annonceur invalide.');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showMapMessage('Impossible d’ouvrir le site de l’annonceur.');
    }
  }

  List<Marker> _buildPublicAdvertisingMarkers(
    List<Map<String, dynamic>> advertisers,
    double zoom,
    double rotation,
  ) {
    final showText = _showTextForZoom(zoom);
    return advertisers.map((advertiser) {
      final latitude = _publicAdvertisingDouble(advertiser['latitude']);
      final longitude = _publicAdvertisingDouble(advertiser['longitude']);
      final name = advertiser['name']?.toString().trim() ?? '';

      return Marker(
        point: LatLng(latitude, longitude),
        width: 56,
        height: 56,
        alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openPublicAdvertisingSpot(advertiser),
          child: _PublicAdvertisingMarker(
            name: name.isEmpty ? 'SPHOT PUBLICITAIRE' : name,
            showTextAllowed: showText,
            alwaysShowName: zoom >= 16.0,
            rotation: rotation,
            labelOpacity: _labelOpacity(zoom),
          ),
        ),
      );
    }).toList();
  }

  Future<void> _openCityWebsite(
    String rawUrl,
    SpotFlagState spot,
  ) async {
  var url = rawUrl.trim();

  if (url.isEmpty) {
    _showMapMessage('Site internet de la ville non renseigné.');
    return;
  }

  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }

  final uri = Uri.tryParse(url);

  if (uri == null) {
    _showMapMessage('Adresse du site internet invalide.');
    return;
  }

  final territoireId = spot.territoireId.trim();
  final ville = spot.ville.trim();
  unawaited(
    _firestoreService.recordPublicClick(
      territoireId: territoireId,
      targetId: territoireId.isNotEmpty ? territoireId : ville.toUpperCase(),
      targetType: 'admin',
      targetName: 'SPHOT ADMIN - ${ville.toUpperCase()}',
      source: kIsWeb ? 'web' : 'app',
    ),
  );

  final opened = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: kIsWeb ? '_blank' : null,
  );

  if (!opened) {
    _showMapMessage('Impossible d’ouvrir le site internet.');
  }
}

List<Marker> _buildAdminMarkers(
  List<SpotFlagState> spots,
  double zoom,
  double rotation,
) {
  final markers = <Marker>[];

  if (zoom < 12) return markers;


  String cityKey(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll('É', 'E')
        .replaceAll('È', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Î', 'I')
        .replaceAll('Ï', 'I')
        .replaceAll('Ô', 'O')
        .replaceAll('Û', 'U')
        .replaceAll('Ù', 'U');
  }

  final cityCoordinates = <String, LatLng>{};

  for (final spot in spots) {
    final ville = spot.ville.trim();
    if (ville.isEmpty) continue;

    if (spot.villeLat != 0 && spot.villeLng != 0) {
      cityCoordinates.putIfAbsent(
        cityKey(ville),
        () => LatLng(spot.villeLat, spot.villeLng),
      );
    }
  }

  final admins = <String, SpotFlagState>{};

  for (final spot in spots) {
    final ville = spot.ville.trim();
    if (ville.isEmpty) continue;

    final directCoordinatesValid =
        spot.villeLat != 0 && spot.villeLng != 0;
    final fallbackCoordinates =
        cityCoordinates[cityKey(ville)];

    if (!directCoordinatesValid && fallbackCoordinates == null) {
      continue;
    }

    final adminKey = spot.territoireId.trim().isNotEmpty
        ? spot.territoireId.trim()
        : cityKey(ville);

    final currentSpot = admins[adminKey];

    if (currentSpot == null) {
      admins[adminKey] = spot;
      continue;
    }

    if (currentSpot.logoVille.trim().isEmpty &&
        spot.logoVille.trim().isNotEmpty) {
      admins[adminKey] = spot;
    }
  }

  for (final spot in admins.values) {
    final logoVille = spot.logoVille.trim();
    final siteInternetVille = spot.siteInternetVille.trim();
    final fallbackCoordinates =
        cityCoordinates[cityKey(spot.ville)];

    final markerLat = spot.villeLat != 0
        ? spot.villeLat
        : fallbackCoordinates?.latitude;
    final markerLng = spot.villeLng != 0
        ? spot.villeLng
        : fallbackCoordinates?.longitude;

    if (markerLat == null || markerLng == null) {
      continue;
    }

    markers.add(
      Marker(
        point: LatLng(markerLat, markerLng),
        width: 85,
        height: 85,
        alignment: Alignment.topCenter,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _mapController.move(
                LatLng(markerLat, markerLng),
                max(zoom, 15.5),
              );

              Future<void>.delayed(
                const Duration(milliseconds: 350),
                () => _openCityWebsite(siteInternetVille, spot),
              );
            },
            child: Tooltip(
              message: spot.ville.toUpperCase(),
              preferBelow: true,
              verticalOffset: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFF0000),
                borderRadius: BorderRadius.circular(5),
              ),
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              child: Transform.rotate(
                angle: -rotation * pi / 180,
                child: SizedBox(
                  width: 85,
                  height: 85,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Image.asset(
                        'data/icons/fire_red_icon.png',
                        width: 85,
                        height: 85,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                      Positioned(
                        top: 23,
                        child: Container(
                          width: 38,
                          height: 38,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: ClipOval(
                            child: logoVille.isEmpty
                                ? const Icon(
                                    Icons.account_balance_rounded,
                                    color: Color(0xFF1E3A8A),
                                    size: 23,
                                  )
                                : IgnorePointer(
                                    child: logoVille
                                            .toLowerCase()
                                            .contains('.svg')
                                        ? SvgPicture.network(
                                            logoVille,
                                            key: ValueKey<String>(
                                              'public-admin-svg-logo-$logoVille',
                                            ),
                                            width: 34,
                                            height: 34,
                                            fit: BoxFit.contain,
                                            placeholderBuilder: (_) =>
                                                const Center(
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                        : Image.network(
                                            logoVille,
                                            key: ValueKey<String>(
                                              'public-admin-logo-$logoVille',
                                            ),
                                            width: 34,
                                            height: 34,
                                            fit: BoxFit.contain,
                                            gaplessPlayback: true,
                                            webHtmlElementStrategy:
                                                WebHtmlElementStrategy.prefer,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                              Icons.account_balance_rounded,
                                              color: Color(0xFF1E3A8A),
                                              size: 23,
                                            ),
                                          ),
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
      ),
    );
  }

  return markers;
}

  String _getMarkerIconPath(SpotFlagState spot) {
    final type = spot.normalizedType;

    if (spot.isNaturisme) return 'data/icons/fire_skin_icon.svg';
    if (type.contains('ACCES PLAGE')) return 'data/icons/fire_orange_icon.svg';

    if (type.contains('LAC') ||
        type.contains("PLAN D'EAU") ||
        type.contains('BARRAGE')) {
      return 'data/icons/fire_blue_icon.svg';
    }

    if (type.contains('FLEUVE') || type.contains('RIVIERE')) {
      return 'data/icons/fire_green_icon.svg';
    }

    if (type.contains('LAGON') || type.contains('PISCINE NATURELLE')) {
      return 'data/icons/fire_cyan_icon.svg';
    }

    return 'data/icons/fire_orange_icon.svg';
  }

  Color _typeColor(SpotFlagState spot) {
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

  bool _matchesFilterFor(SpotFlagState spot, SpotFilter filter) {
    final type = spot.normalizedType;

    switch (filter) {
      case SpotFilter.all:
        return true;
      case SpotFilter.secours:
        return spot.isPosteSecours;
      case SpotFilter.plage:
        // Inclure les libellés actuels « Plage » et historiques
        // « Accès plage », comme le fait déjà le marqueur de plage.
        return type.contains('PLAGE');
      case SpotFilter.eauBleue:
        return type.contains('LAC') ||
            type.contains("PLAN D'EAU") ||
            type.contains('BARRAGE');
      case SpotFilter.eauVerte:
        return type.contains('FLEUVE') || type.contains('RIVIERE');
      case SpotFilter.lagon:
        return type.contains('LAGON') || type.contains('PISCINE NATURELLE');
      case SpotFilter.naturisme:
        return spot.isNaturisme;
      case SpotFilter.autre:
        return type.contains('AUTRE') || type.contains('NON RENSEIGNE');
    }
  }

  bool _matchesFilter(SpotFlagState spot) {
    return _matchesFilterFor(spot, _selectedFilter);
  }

  String _filterLabel(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
        return 'SPHOTS';
      case SpotFilter.secours:
        return 'SPHOT\nPoste de secours';
      case SpotFilter.plage:
        return 'SPHOT\nPlage';
      case SpotFilter.eauBleue:
        return "SPHOT\nLac\nPlan d'eau\nBarrage";
      case SpotFilter.eauVerte:
        return 'SPHOT\nFleuve\nRivière';
      case SpotFilter.lagon:
        return 'SPHOT\nLagon\nPiscine naturelle';
      case SpotFilter.naturisme:
        return 'SPHOT\nNaturisme';
      case SpotFilter.autre:
        return 'SPHOT\nBase de loisirs\nParc';
    }
  }

  Color _filterColor(SpotFilter filter) {
  switch (filter) {
    case SpotFilter.all:
      return const Color(0xFFFF0000);
    case SpotFilter.secours:
      return const Color(0xFFFF0000);
    case SpotFilter.plage:
      return const Color(0xFFFFD000);
    case SpotFilter.eauBleue:
      return const Color(0xFF1E3A8A);
    case SpotFilter.eauVerte:
      return const Color(0xFF2E7D32);
    case SpotFilter.lagon:
      return const Color(0xFF00ACC1);
    case SpotFilter.naturisme:
      return const Color(0xFFD87A5C);
    case SpotFilter.autre:
      return const Color(0xFFFFA500);
  }
}

  Widget _drawerAssetIcon(String path) {
    return AdaptiveAssetImage(
      path,
      width: 40,
      height: 40,
      fit: BoxFit.contain,
    );
  }

  Widget _filterIcon(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
        return const _SphotSpinnerIcon();
      case SpotFilter.secours:
        return const _DrawerFlagIcon();
      case SpotFilter.plage:
        return _drawerAssetIcon('data/icons/fire_orange_icon.svg');
      case SpotFilter.eauBleue:
        return _drawerAssetIcon('data/icons/fire_blue_icon.svg');
      case SpotFilter.eauVerte:
        return _drawerAssetIcon('data/icons/fire_green_icon.svg');
      case SpotFilter.lagon:
        return _drawerAssetIcon('data/icons/fire_cyan_icon.svg');
      case SpotFilter.naturisme:
        return _drawerAssetIcon('data/icons/fire_skin_icon.svg');
      case SpotFilter.autre:
        return _drawerAssetIcon('data/icons/fire_orange1_icon.svg');
    }
  }

String _normalizeSearch(String value) {
  var normalized = value
      .toLowerCase()
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .replaceAll('’', "'")
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ô', 'o')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ç', 'c')
      .trim();

  normalized = normalized.replaceAll(RegExp(r"\bl[' ]"), '');
  normalized = normalized.replaceAll(
  RegExp(r'\b(le|la|les|des|de|du|un|une|aux|au)\b'),
  '',
);

  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

  return normalized;
}

int _levenshtein(String s1, String s2) {
  final m = s1.length;
  final n = s2.length;

  final dp = List.generate(
    m + 1,
    (_) => List.filled(n + 1, 0),
  );

  for (int i = 0; i <= m; i++) {
    dp[i][0] = i;
  }

  for (int j = 0; j <= n; j++) {
    dp[0][j] = j;
  }

  for (int i = 1; i <= m; i++) {
    for (int j = 1; j <= n; j++) {
      final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;

      dp[i][j] = [
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      ].reduce((a, b) => a < b ? a : b);
    }
  }

  return dp[m][n];
}

SpotFlagState? _findBestSpotMatch(
  List<SpotFlagState> spots,
  String rawQuery,
) {
  final query = _normalizeSearch(rawQuery);

  if (query.length < 2) {
    return null;
  }

  SpotFlagState? bestMatch;
  int bestScore = 999;

  for (final spot in spots) {
    final fields = [
  spot.name,
  spot.nomSphot,
  spot.typeSphot,
  spot.ville,
  spot.departement,

  '${spot.ville} ${spot.name}',
  '${spot.ville} ${spot.nomSphot}',
  '${spot.ville} ${spot.typeSphot}',

  '${spot.departement} ${spot.ville}',
  '${spot.departement} ${spot.name}',
  '${spot.departement} ${spot.nomSphot}',
  '${spot.departement} ${spot.typeSphot}',

  '${spot.name} ${spot.nomSphot}',
  '${spot.name} ${spot.nomSphot} ${spot.typeSphot}',
  '${spot.ville} ${spot.name} ${spot.nomSphot} ${spot.typeSphot}',
  '${spot.departement} ${spot.ville} ${spot.name} ${spot.nomSphot}',
].map(_normalizeSearch).toList();

    for (final field in fields) {
      int score;

      if (field.contains(query)) {
        score = 0;
      } else {
        final words = field.split(RegExp(r'\s+'));

        score = words
            .map((word) => _levenshtein(query, word))
            .reduce((a, b) => a < b ? a : b);
      }

      if (score < bestScore) {
        bestScore = score;
        bestMatch = spot;
      }
    }
  }

  if (bestMatch != null && bestScore <= 3) {
    return bestMatch;
  }

  return null;
}

  void _showMapMessage(String message) {
  }

  Future<void> _openPublicSpotDetail(SpotFlagState spot) async {
    _searchFocusNode.unfocus();

    unawaited(
      _firestoreService.recordPublicClick(
        territoireId: spot.territoireId,
        targetId: spot.id,
        targetType: 'spot',
        targetName: spot.mapDisplayName,
        source: kIsWeb ? 'web' : 'app',
      ),
    );

    setState(() {
      _isFilterOpen = false;
      _isMapStyleOpen = false;
    });

    final screenWidth = MediaQuery.sizeOf(context).width;

    if (kIsWeb && screenWidth >= 900) {
      setState(() {
        _selectedPublicSpotId = spot.id;
        _desktopDetailSpot = spot;
        _mobileDetailSpot = null;
      });

      const selectedWebSpotZoom = 19.0;
      final screenSize = MediaQuery.sizeOf(context);
      final panelWidth = min(500.0, screenSize.width * 0.40);
      final bottomOverlayHeight =
          _desktopSelectedAdHeight + _desktopSelectedAdBottom;
      final selectedWebSpotCenter = _webSelectedSpotCameraCenter(
        spot,
        selectedWebSpotZoom,
        _currentRotation,
        screenSize: screenSize,
        panelWidth: panelWidth,
        bottomOverlayHeight: bottomOverlayHeight,
      );

      _mapController.move(
        selectedWebSpotCenter,
        selectedWebSpotZoom,
      );

      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 220),
          () {
            if (!mounted ||
                _selectedPublicSpotId != spot.id ||
                _isMovingMap) return;
            _mapController.move(
              selectedWebSpotCenter,
              selectedWebSpotZoom,
            );
          },
        ),
      );

      // Le panneau est dessiné plus bas dans la Stack, au-dessus de la map.
      // Il n'y a plus de route modale : la carte découverte reste manipulable.
      return;
    }

    // Sur un écran étroit, Web compris, le volet appartient à la Stack
    // non modale de la carte : la partie découverte reste interactive.
    setState(() {
      _selectedPublicSpotId = spot.id;
      _mobileDetailSpot = spot;
      _desktopDetailSpot = null;
    });
    // Chaque nouveau SPHOT ouvre initialement son volet en totalité.
    _mobileDetailHeightFraction.value = 1.0;

    const selectedSpotZoom = 17.2;
    final screenSize = MediaQuery.sizeOf(context);
    final topSafeInset = MediaQuery.of(context).padding.top;
    final selectedSpotCenter = _selectedSpotCameraCenter(
      spot,
      selectedSpotZoom,
      _currentRotation,
      screenSize: screenSize,
      topSafeInset: topSafeInset,
    );

    _mapController.move(
      selectedSpotCenter,
      selectedSpotZoom,
    );

    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 300),
        () {
          if (!mounted || _selectedPublicSpotId != spot.id) return;
          _mapController.move(
            selectedSpotCenter,
            selectedSpotZoom,
          );
        },
      ),
    );

    // Le volet mobile/Web étroit est déjà affiché par _buildMobileSpotPanel.
    // Ne jamais ouvrir de route modale qui bloquerait les gestes sur la carte.
    return;
  }

  void _closeDesktopSpotDetail() {
    final closingSpot = _desktopDetailSpot;
    if (closingSpot == null) return;

    setState(() {
      _desktopDetailSpot = null;
      if (_selectedPublicSpotId == closingSpot.id) {
        _selectedPublicSpotId = null;
      }
      _mapTileRefreshVersion++;
    });
    unawaited(_loadFavoriteSpotIds());
  }

  Widget _buildDesktopSpotPanel() {
    final spot = _desktopDetailSpot;
    if (spot == null) return const SizedBox.shrink();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = min(500.0, screenWidth * 0.40);

    // Le panneau ne capte les gestes que sur ses propres 500 px (max).
    // Le clic, le déplacement, la rotation et le zoom sur le reste de
    // FlutterMap ne ferment plus le volet.
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: panelWidth,
      // Le SafeArea du Scaffold inclut la hauteur de l'AppBar dans ce
      // contexte Web. Ne pas l'appliquer au panneau de droite : il doit
      // commencer tout en haut, comme l'ancienne fiche plein écran.
      child: TweenAnimationBuilder<double>(
        key: ValueKey('desktop_detail_${spot.id}'),
        tween: Tween<double>(begin: 1.0, end: 0.0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (context, fraction, child) => Transform.translate(
          offset: Offset(panelWidth * fraction, 0),
          child: child,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          // La fiche elle-même possède un SafeArea : neutraliser ici
          // l'inset supérieur provenant de la barre de la carte.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: PublicSpotDetailPage(
              spot: spot,
              onClose: _closeDesktopSpotDetail,
            ),
          ),
        ),
      ),
    );
  }

  void _closeMobileSpotDetail() {
    final closingSpot = _mobileDetailSpot;
    if (closingSpot == null) return;

    setState(() {
      _mobileDetailSpot = null;
      if (_selectedPublicSpotId == closingSpot.id) {
        _selectedPublicSpotId = null;
      }
      _mapTileRefreshVersion++;
    });
    unawaited(_loadFavoriteSpotIds());
  }

  Widget _buildMobileSpotPanel() {
    final spot = _mobileDetailSpot;
    if (spot == null) return const SizedBox.shrink();

    final padding = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);
    final availableHeight = max(
      1.0,
      size.height - padding.top - _mobileDetailBottomOffset,
    );

    // Seule la surface réellement occupée par le volet capte les gestes.
    // Le reste de la Stack laisse la carte recevoir déplacements et zooms.
    return Positioned(
      left: _mobileBottomMenuSideInset,
      right: _mobileBottomMenuSideInset,
      bottom: _mobileDetailBottomOffset,
      child: ValueListenableBuilder<double>(
        valueListenable: _mobileDetailHeightFraction,
        child: PublicSpotMobileSheet(
          key: ValueKey('mobile_detail_${spot.id}'),
          spot: spot,
          onClose: _closeMobileSpotDetail,
          onResize: (verticalDelta) {
            final nextFraction = (_mobileDetailHeightFraction.value -
                    verticalDelta / availableHeight)
                .clamp(_mobileDetailMinHeightFraction, 1.0)
                .toDouble();
            _mobileDetailHeightFraction.value = nextFraction;
          },
        ),
        builder: (context, fraction, child) => SizedBox(
          width: double.infinity,
          height: availableHeight * fraction,
          child: child,
        ),
      ),
    );
  }

  // L'en-tête SPHOT appartient à la carte et se dessine au-dessus du volet.
  // On le masque uniquement lorsque la position réelle du volet le recouvre.
  bool _mobileDetailOverlapsMapHeader(double fraction) {
    if (_mobileDetailSpot == null) return false;

    final media = MediaQuery.of(context);
    final availableHeight = max(
      1.0,
      media.size.height -
          media.padding.top -
          _mobileDetailBottomOffset,
    );
    final sheetTop = media.size.height -
        _mobileDetailBottomOffset -
        availableHeight * fraction;
    final logoBottom =
        media.padding.top + _mapHeaderLogoTop + _mapHeaderLogoHeight;

    return sheetTop < logoBottom;
  }

  void _resetNorth() {
    _mapController.rotate(0);
    setState(() => _currentRotation = 0);
  }

  // La recherche reste volontairement invisible sur la carte tant que
  // l'utilisateur n'a pas appuyé sur la loupe du menu inférieur.
  void _closeSearchPanel() {
    _isSearchPanelOpen = false;
    _searchTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    if (_isListening) {
      _isListening = false;
      unawaited(_speech.stop());
    }
  }

  void _toggleSearchPanel() {
    setState(() {
      if (_isSearchPanelOpen) {
        _closeSearchPanel();
      } else {
        _isSearchPanelOpen = true;
        _isFilterOpen = false;
        _isMapStyleOpen = false;
      }
    });
  }

  void _toggleMapStyleBar() {
  setState(() {
    _isMapStyleOpen = !_isMapStyleOpen;

    if (_isMapStyleOpen) {
      _isFilterOpen = false;
      _closeSearchPanel();
      _searchController.clear();
      _searchFocusNode.unfocus();
    }
  });
}

void _selectMapStyle(int index) {
  debugPrint('STYLE CLIQUÉ : $index - ${_tileStyles[index].name}');
  debugPrint('URL : ${_tileStyles[index].url}');

  setState(() {
    _selectedTileStyle = index;
    _isMapStyleOpen = false;
    _isFilterOpen = false;
  });

  _showMapMessage('Carte : ${_tileStyles[index].name}');
}

  Future<void> _goToUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        _showMapMessage('Active la localisation de ton appareil.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMapMessage('Autorisation de localisation refusée.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _mapController.move(
        LatLng(position.latitude, position.longitude),
        15.5,
      );
    } catch (_) {
      _showMapMessage('Position actuelle indisponible.');
    }
  }

void _searchAndMoveToSpot(
  List<SpotFlagState> spots,
  String value,
) {
  _searchTimer?.cancel();

  _searchTimer = Timer(
    const Duration(milliseconds: 650),
    () {
      if (!mounted) return;

      final query = _normalizeSearch(value);

      if (query.length < 2) return;

      bool matchText(String field) {
        final normalizedField = _normalizeSearch(field);

        return normalizedField == query ||
            normalizedField.contains(query) ||
            query.contains(normalizedField);
      }

      final cityMatch = spots.where((spot) {
        return matchText(spot.ville) &&
            spot.villeLat != 0 &&
            spot.villeLng != 0;
      }).toList();

      if (cityMatch.isNotEmpty) {
        final spot = cityMatch.first;

        debugPrint('VILLE TROUVÉE : ${spot.ville}');
        debugPrint('GPS VILLE : ${spot.villeLat}, ${spot.villeLng}');

        _searchController.clear();
        setState(() {});

        _mapController.move(
          LatLng(spot.villeLat, spot.villeLng),
          12.5,
        );
        return;
      }

      final departementMatch = spots.where((spot) {
        return matchText(spot.departement) &&
            spot.departementLat != 0 &&
            spot.departementLng != 0;
      }).toList();

      if (departementMatch.isNotEmpty) {
        final spot = departementMatch.first;

        debugPrint('DÉPARTEMENT TROUVÉ : ${spot.departement}');
        debugPrint(
          'GPS DÉPARTEMENT : ${spot.departementLat}, ${spot.departementLng}',
        );

        _searchController.clear();
        setState(() {});

        _mapController.move(
          LatLng(spot.departementLat, spot.departementLng),
          9.5,
        );
        return;
      }

      final spot = _findBestSpotMatch(spots, value);

      if (spot == null) {
        debugPrint('AUCUN RÉSULTAT POUR : $value');
        return;
      }

      debugPrint('SPHOT TROUVÉ : ${spot.name}');
      debugPrint('GPS SPHOT : ${spot.lat}, ${spot.lng}');

      _searchController.clear();
      setState(() {});

      _mapController.move(
        LatLng(spot.lat, spot.lng),
        16.5,
      );
    },
  );
}

void _startVoiceSearch(List<SpotFlagState> spots) async {
  if (!_isListening) {
    bool available = await _speech.initialize();

    if (available) {
      setState(() => _isListening = true);

      _speech.listen(
        localeId: 'fr_FR',
        onResult: (result) {
          final text = result.recognizedWords;

         _searchController.text = text;
_searchController.selection = TextSelection.fromPosition(
  TextPosition(offset: _searchController.text.length),
);

setState(() {});

if (result.finalResult) {
  _searchAndMoveToSpot(spots, text);
  setState(() => _isListening = false);
}
        },
      );
    } else {
      _showMapMessage('Micro non disponible');
    }
  } else {
    setState(() => _isListening = false);
    _speech.stop();
  }
}

  Widget _mapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double rotation = 0,
  }) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.white.withOpacity(0.92),
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                child: Transform.rotate(
                  angle: rotation,
                  child: Icon(
                    icon,
                    color: Colors.black87,
                    size: 25,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

void _toggleFilterBar() {
  setState(() {
    _isFilterOpen = !_isFilterOpen;

    if (_isFilterOpen) {
      _isMapStyleOpen = false;
      _closeSearchPanel();
      _searchController.clear();
      _searchFocusNode.unfocus();
    }
  });
}

String _filterShortLabel(SpotFilter filter) {
  switch (filter) {
    case SpotFilter.all:
      return 'Tous les SPHOTS';
    case SpotFilter.secours:
      return 'Poste de secours';
    case SpotFilter.plage:
      return 'Plage';
    case SpotFilter.eauBleue:
      return "Lac\nPlan d'eau\nBarrage";
    case SpotFilter.eauVerte:
      return 'Fleuve\nRivière';
    case SpotFilter.lagon:
      return 'Lagon\nPiscine naturelle';
    case SpotFilter.naturisme:
      return 'Naturisme';
    case SpotFilter.autre:
      return 'Base de loisirs\nParc';
  }
}

Widget _verticalFilterChoiceButton(SpotFilter filter, int index) {
  final selected = filter == _selectedFilter;
  final color = _filterColor(filter);

  return AnimatedOpacity(
    duration: Duration(milliseconds: 350 + index * 80),
    opacity: _isFilterOpen ? 1.0 : 0.0,
    child: AnimatedSlide(
      duration: Duration(milliseconds: 1400 + index * 260),
      curve: Curves.easeOutBack,
      offset: _isFilterOpen ? Offset.zero : const Offset(0, 0.35),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
  color: Colors.white.withOpacity(0.95),
  elevation: 2,
  borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                _selectedFilter = filter;
                _isFilterOpen = false;
              });
            },
            child: Container(
  width: 190,
  height: 52,
  padding: const EdgeInsets.symmetric(horizontal: 10),
  decoration: BoxDecoration(
  color: Colors.white.withOpacity(0.95),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(
      color: selected ? color : Colors.grey.withOpacity(0.5),
      width: selected ? 2 : 1.2,
    ),
  ),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: Center(child: _filterIcon(filter)),
                  ),
                  const SizedBox(width: 0),
                  Expanded(
                    child: Text(
                      _filterShortLabel(filter),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: filter == SpotFilter.all
    ? Colors.black87
    : color,
                        fontSize: 14,
                        height: 1.05,
                        fontWeight:
                            selected ? FontWeight.w900 : FontWeight.w700,
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
  );
}

double _bottomMenuLeft({
  required double menuWidth,
  required int itemIndex,
}) {
  const sideInset = 8.0;
  const itemWidth = 58.0;
  const itemCount = 5;

  final screenWidth = MediaQuery.of(context).size.width;
  final barWidth = screenWidth - (sideInset * 2);
  final spacing =
      ((barWidth - (itemWidth * itemCount)) / (itemCount + 1))
          .clamp(0.0, double.infinity)
          .toDouble();
  final itemCenter = sideInset +
      (spacing * (itemIndex + 1)) +
      (itemWidth * itemIndex) +
      (itemWidth / 2);
  final maxLeft = (screenWidth - menuWidth - sideInset)
      .clamp(sideInset, double.infinity)
      .toDouble();

  return (itemCenter - (menuWidth / 2))
      .clamp(sideInset, maxLeft)
      .toDouble();
}

Widget _buildVerticalFilterMenu() {
  final orderedFilters = [
    SpotFilter.all,
    SpotFilter.secours,
    SpotFilter.eauVerte,
    SpotFilter.lagon,
    SpotFilter.eauBleue,
    SpotFilter.plage,
    SpotFilter.naturisme,
    SpotFilter.autre,
  ];

  return Positioned(
    left: _bottomMenuLeft(
      menuWidth: 190,
      itemIndex: 0,
    ),
    bottom: 154,
    child: IgnorePointer(
      ignoring: !_isFilterOpen,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.68,
        child: SingleChildScrollView(
          reverse: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(
              orderedFilters.length,
              (index) {
                return _verticalFilterChoiceButton(
                  orderedFilters[index],
                  index,
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _buildMapStyleVerticalMenu() {
  return IgnorePointer(
    ignoring: !_isMapStyleOpen,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        _tileStyles.length,
        (index) {
          final reversedIndex = _tileStyles.length - 1 - index;

          return _animatedMapStyleButton(
            reversedIndex,
            index,
          );
        },
      ),
    ),
  );
}

Widget _animatedMapStyleButton(int tileIndex, int animationIndex) {
  return AnimatedOpacity(
    duration: Duration(
      milliseconds: 350 + animationIndex * 80,
    ),
    opacity: _isMapStyleOpen ? 1.0 : 0.0,
    child: AnimatedSlide(
      duration: Duration(
        milliseconds: 1400 + animationIndex * 260,
      ),
      curve: Curves.easeOutBack,
      offset: _isMapStyleOpen
          ? Offset.zero
          : const Offset(0, 0.35),
      child: _mapStyleVerticalButton(tileIndex),
    ),
  );
}

Widget _mapStyleVerticalButton(int index) {
  final selected = index == _selectedTileStyle;

  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: Colors.white.withOpacity(0.94),
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _selectMapStyle(index),
        child: Container(
          width: 150, // ⬅️ un peu plus large
          height: 48, // ⬅️ plus haut
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
  color: selected
      ? _mapStyleColor(index)
      : Colors.grey.withOpacity(0.5),
  width: selected ? 2.2 : 1.2,
),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: Center(child: _mapStyleIcon(index)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tileStyles[index].name,
                  style: TextStyle(
                    fontSize: 16, // ⬅️ texte plus grand
                    fontWeight:
                        selected ? FontWeight.w900 : FontWeight.w700,
                    color: _mapStyleColor(index).withOpacity(selected ? 1.0 : 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Color _mapStyleColor(int index) {
  switch (index) {
    case 0:
      return const Color(0xFF2E7D32); // Plan
    case 1:
      return const Color(0xFF1E3A8A); // Satellite
    default:
      return Colors.black;
  }
}

Widget _mapStyleIcon(int index) {
  final selected = index == _selectedTileStyle;

  /// STYLE PLAN
  if (index == 0) {
    return Icon(
      Icons.map,
      size: 26,
      color: _mapStyleColor(index).withOpacity(selected ? 1.0 : 0.6),
    );
  }

  /// STYLE SATELLITE
  if (index == 1) {
    return Icon(
      Icons.satellite_alt,
      size: 26,
      color: _mapStyleColor(index).withOpacity(selected ? 1.0 : 0.6),
    );
  }

  return Icon(
    Icons.satellite_alt,
    size: 26,
    color: _mapStyleColor(index).withOpacity(selected ? 1.0 : 0.6),
  );
}

Widget _buildLeftMapControls(List<SpotFlagState> spots) {
  
  final isSearching = _searchController.text.trim().isNotEmpty || _isListening;

  return Positioned(
    left: 8,
    right: 8,
    top: MediaQuery.of(context).padding.top +
        (kIsWeb ? 78 : (_useAutomaticTouchLabels ? 64 : 50)),
    child: Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.white.withOpacity(0.94),
            elevation: 4,
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: Colors.black.withOpacity(0.4),
                  width: 1.2,
                ),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textAlignVertical: TextAlignVertical.center,
                onChanged: (value) {
                  setState(() {});
                  _searchAndMoveToSpot(spots, value);
                },
                decoration: InputDecoration(
  hintText: 'Rechercher un SPHOT',
  prefixIcon: const Icon(Icons.search, size: 21),
  prefixIconConstraints: const BoxConstraints(
    minHeight: 0,
    minWidth: 40,
  ),
  suffixIcon: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_searchController.text.trim().isNotEmpty)
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () {
            _searchTimer?.cancel();
            _searchController.clear();
            setState(() {});
          },
        ),
      IconButton(
  icon: AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    child: Icon(
      _isListening
          ? Icons.radio_button_checked
          : Icons.keyboard_voice_rounded,
      key: ValueKey(_isListening),
      color: _isListening
          ? const Color(0xFFFF0000)
          : Colors.black87,
      size: 22,
    ),
  ),
  onPressed: () => _startVoiceSearch(spots),
),
    ],
  ),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(vertical: 0),
  border: InputBorder.none,
),
              ),
            ),
          ),
        ),
        if (!isSearching) ...[
  const SizedBox(width: 6),
  _mapControlButton(
    icon: Icons.my_location,
    tooltip: 'Ma position',
    onTap: _goToUserLocation,
  ),
  const SizedBox(width: 4),
  _mapControlButton(
    icon: Icons.navigation,
    tooltip: 'Remettre le Nord',
    rotation: _currentRotation * pi / 180,
    onTap: _resetNorth,
  ),
],
      ],
    ),
  );
}

  Marker _buildOtherSpotMarker(
    SpotFlagState spot,
    bool showText,
    bool autoShowName,
    double zoom,
    double rotation, {
    bool compactIcon = false,
  }) {
    return Marker(
      point: LatLng(spot.lat, spot.lng),
      width: compactIcon ? 44 : 56,
      height: compactIcon ? 44 : 56,
      alignment: Alignment.center,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_openPublicSpotDetail(spot)),
        child: _OtherSpotMarker(
          spot: spot,
          iconPath: _getMarkerIconPath(spot),
          showTextAllowed: showText,
          forceShowText: _selectedPublicSpotId == spot.id,
          autoShowName: autoShowName,
          zoom: zoom,
          rotation: rotation,
          labelOpacity: _labelOpacity(zoom),
          typeTextColor: _typeColor(spot),
          compactIcon: compactIcon,
        ),
      ),
    );
  }

  Marker _buildSecoursMarker(
    SpotFlagState spot,
    bool showText,
    bool autoShowName,
    double zoom,
    double rotation,
  ) {
    return Marker(
      point: LatLng(spot.lat, spot.lng),
      width: 120,
      height: 260,
      alignment: Alignment.center,
      // Zone cliquable prolongée vers le sommet des drapeaux. Le marqueur
      // centré gagne 90 px ; le contenu descend de 45 px dans la boîte pour
      // conserver exactement sa position géographique et visuelle.
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (!showText || _hoveredRescueSpotId == spot.id) return;
          setState(() => _hoveredRescueSpotId = spot.id);
        },
        onExit: (_) {
          if (_hoveredRescueSpotId != spot.id) return;
          setState(() => _hoveredRescueSpotId = null);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_openPublicSpotDetail(spot)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 82.5,
                left: 25,
                child: _HoverMarker(
                  spot: spot,
                  showTextAllowed: showText,
                  forceShowText: _selectedPublicSpotId == spot.id ||
                      (_hoveredRescueSpotId == spot.id && showText),
                  autoShowName: autoShowName,
                  zoom: zoom,
                  rotation: rotation,
                  labelOpacity: _labelOpacity(zoom),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Marker> _buildMarkers(
    List<SpotFlagState> spots,
    Set<String> automaticLabelIds,
    double zoom,
    double rotation,
  ) {
    final showText = _showTextForZoom(zoom);

    debugPrint('MARKERS À AFFICHER : ${spots.length}');

    return spots
        .where((spot) => spot.lat.isFinite && spot.lng.isFinite)
        .map(
          (spot) => _buildOtherSpotMarker(
            spot,
            showText,
            automaticLabelIds.contains(spot.id),
            zoom,
            rotation,
          ),
        )
        .toList();
  }

  List<Marker> _buildSecoursMarkers(
    List<SpotFlagState> spots,
    Set<String> automaticLabelIds,
    double zoom,
    double rotation,
  ) {
    final showText = _showTextForZoom(zoom);

    return spots
        .where(
          (spot) =>
              spot.isPosteSecours &&
              spot.lat.isFinite &&
              spot.lng.isFinite,
        )
        .map(
          (spot) => _buildSecoursMarker(
            spot,
            showText,
            automaticLabelIds.contains(spot.id),
            zoom,
            rotation,
          ),
        )
        .toList();
  }


  // Conserve l'identité du SPHOT dans chaque marqueur pour calculer
  // la couleur du fire icon MAJORITAIRE dans les regroupements.
  Marker _tagSpotMarker(SpotFlagState spot, Marker marker) {
    return Marker(
      point: marker.point,
      width: marker.width,
      height: marker.height,
      alignment: marker.alignment,
      child: _SphotClusterMember(
        spot: spot,
        child: marker.child,
      ),
    );
  }

  // Affichage progressif commun aux cartes Web et Android.
  // Les mâts validés sont toujours utilisés pour un poste de secours
  // isolé dès le niveau local (zoom >= 12).
  // A partir de 16, tous les marqueurs reprennent le rendu historique.
  Marker _buildProgressiveSpotMarker(
    SpotFlagState spot,
    double zoom,
    double rotation,
    Set<String> automaticLabelIds,
  ) {
    if (spot.isPosteSecours && zoom >= 12.0) {
      return _tagSpotMarker(
        spot,
        _buildSecoursMarker(
          spot,
          _showTextForZoom(zoom),
          automaticLabelIds.contains(spot.id),
          zoom,
          rotation,
        ),
      );
    }

    if (zoom >= 16.0) {
      return _tagSpotMarker(
        spot,
        _buildOtherSpotMarker(
          spot,
          _showTextForZoom(zoom),
          automaticLabelIds.contains(spot.id),
          zoom,
          rotation,
        ),
      );
    }

    if (zoom < 12.0) {
      // Une occurrence isolée sur la carte mondiale est également un
      // fire icon de sa propre catégorie (avec le chiffre 1).
      return _tagSpotMarker(
        spot,
        Marker(
          point: LatLng(spot.lat, spot.lng),
          width: 46,
          height: 54,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _mapController.move(
              LatLng(spot.lat, spot.lng),
              zoom < 7.0 ? 7.0 : 12.0,
            ),
            child: _buildFireCountIcon(
              iconPath: spot.markerIconPath,
              count: 1,
              rotation: rotation,
              size: 46.0,
            ),
          ),
        ),
      );
    }

    // Zoom 12 à 15 : icône compacte, sans infobulle grise.
    // Les caractéristiques habituelles peuvent apparaître au survol dès
    // le seuil de zoom autorisé, sans modifier la taille des lignes.
    return _tagSpotMarker(
      spot,
      _buildOtherSpotMarker(
        spot,
        _showTextForZoom(zoom),
        automaticLabelIds.contains(spot.id),
        zoom,
        rotation,
        compactIcon: true,
      ),
    );
  }

  // L'icône de regroupement reste de la charte SPHOT, quelle que soit
  // la taille du groupe ; le chiffre est placé dans le centre du pictogramme.
  Widget _buildFireCountIcon({
    required String iconPath,
    required int count,
    required double rotation,
    required double size,
  }) {
    final countText = count.toString();
    return Transform.rotate(
      angle: -rotation * pi / 180,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AdaptiveAssetImage(
              iconPath,
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
            Text(
              countText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFFF0000),
                fontWeight: FontWeight.w900,
                fontSize: countText.length >= 4
                    ? 10
                    : countText.length == 3
                        ? 12
                        : 15,
                shadows: const [
                  Shadow(
                    color: Colors.white,
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
  return Drawer(
    backgroundColor: Colors.transparent,
    elevation: 0,
    child: SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.35),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Center(
                child: Image.asset(
                  'data/icons/title.png',
                  height: 76,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ...SpotFilter.values.map((filter) {
                    final selected = filter == _selectedFilter;
                    final color = _filterColor(filter);

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: SizedBox(
                          width: 42,
                          height: 42,
                          child: Center(child: _filterIcon(filter)),
                        ),
                        title: _OutlinedMenuText(
                          text: _filterLabel(filter),
                          color: color,
                          selected: selected,
                        ),
                        trailing: selected
                            ? Icon(Icons.check, color: color, size: 24)
                            : null,
                        selected: selected,
                        selectedTileColor: color.withOpacity(0.10),
                        onTap: () {
                          setState(() {
                            _selectedFilter = filter;
                            _showFavoritesOnly = false;
                          });
                          Navigator.of(context).pop();
                        },
                      ),
                    );
                  }),
                  const Divider(height: 28),
                  _infoItem(Icons.info_outline, 'À propos de SPHOT'),
                  _infoItem(Icons.description_outlined, 'Mentions légales'),
                  _infoItem(
                    Icons.privacy_tip_outlined,
                    'Politique de confidentialité',
                  ),
                  _infoItem(Icons.gavel_outlined, 'Conditions d’utilisation'),
                  _infoItem(Icons.contact_support_outlined, 'Contact'),
                  _infoItem(Icons.settings_outlined, 'Paramètres'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _infoItem(IconData icon, String label) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(
        label,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => Navigator.of(context).pop(),
    );
  }

  Color _clusterBorderColor(List<Marker> markers) {
  final colors = <Color>{};

  for (final marker in markers) {
    final markerChild = marker.child;
    final child = markerChild is GestureDetector
        ? markerChild.child
        : markerChild;
    if (child is _OtherSpotMarker) {
      colors.add(child.typeTextColor);
    }
  }

  if (colors.contains(const Color(0xFFD87A5C))) {
    return const Color(0xFFD87A5C); // Naturisme
  }

  if (colors.contains(const Color(0xFFFFD000))) {
    return const Color(0xFFFFD000); // Accès plage
  }

  if (colors.contains(const Color(0xFF1E3A8A))) {
    return const Color(0xFF1E3A8A); // Lac / plan d'eau / barrage
  }

  if (colors.contains(const Color(0xFF2E7D32))) {
    return const Color(0xFF2E7D32); // Fleuve / rivière
  }

  if (colors.contains(const Color(0xFF00ACC1))) {
    return const Color(0xFF00ACC1); // Lagon
  }

  return Colors.white;
}

String _clusterIconPath(Color color) {
  if (color == const Color(0xFFD87A5C)) {
    return 'data/icons/fire_skin_icon.svg';
  }

  if (color == const Color(0xFFFFD000)) {
    return 'data/icons/fire_orange_icon.svg';
  }

  if (color == const Color(0xFF1E3A8A)) {
    return 'data/icons/fire_blue_icon.svg';
  }

  if (color == const Color(0xFF2E7D32)) {
    return 'data/icons/fire_green_icon.svg';
  }

  if (color == const Color(0xFF00ACC1)) {
    return 'data/icons/fire_cyan_icon.svg';
  }

  return 'data/icons/fire_orange1_icon.svg';
}

  Widget _buildCluster(BuildContext context, List<Marker> markers) {
    // Chaque marqueur porte le SPHOT qui lui correspond, même lorsqu'il
    // s'agit d'un poste de secours. On compte les catégories réelles.
    final frequencies = <String, int>{};
    for (final marker in markers) {
      final tagged = marker.child;
      if (tagged is! _SphotClusterMember) continue;
      final path = tagged.spot.markerIconPath;
      frequencies.update(
        path,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    // Priorité à la catégorie la plus représentée. En cas d'égalité,
    // ordre alphabétique stable : le rendu ne dépend pas de Firestore.
    final ordered = frequencies.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    final majorityIcon = ordered.isEmpty
        ? 'data/icons/fire_orange1_icon.svg'
        : ordered.first.key;

    final count = markers.length;
    final rotation = MapCamera.of(context).rotation;

    return Center(
      child: _buildFireCountIcon(
        iconPath: majorityIcon,
        count: count,
        rotation: rotation,
        size: 54.0,
      ),
    );
  }

/// Seules les campagnes CARTE ou PACK diffusées dans la zone courante
/// peuvent remplacer l'encart d'invitation.
bool _isPublicMapAdVisible(Map<String, dynamic> ad) {
  // L'ancienne API n'exposait pas visibilityType : compatibilité conservée.
  // La nouvelle API exclut explicitement les campagnes Premium de la carte.
  final visibility = ad['visibilityType']?.toString() ?? '';
  if (visibility.isNotEmpty && visibility != 'map' && visibility != 'pack') {
    return false;
  }
  final deadline = ad['campaignEndAt'];
  if (deadline is! num ||
      DateTime.now().millisecondsSinceEpoch >= deadline.toInt()) {
    return false;
  }

  final scope = ad['broadcastType']?.toString() ?? '';
  if (scope == 'national') return true;
  if (scope != 'local') return false;

  final latitude = (ad['centerLat'] as num?)?.toDouble();
  final longitude = (ad['centerLng'] as num?)?.toDouble();
  final radius = (ad['radiusKm'] as num?)?.toDouble();
  if (latitude == null || longitude == null ||
      radius == null || radius <= 0) {
    return false;
  }

  final distanceKm = const Distance().as(
    LengthUnit.Kilometer,
    _mapAdCenter,
    LatLng(latitude, longitude),
  );
  return distanceKm <= radius;
}

Future<void> _openMapAdDestination(String destinationUrl) async {
  final uri = Uri.tryParse(destinationUrl.trim());
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    return;
  }

  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && mounted) {
    _showMapMessage('Impossible d’ouvrir le site de l’annonceur.');
  }
}

/// Bandeau et zone de création alignés sur le menu inférieur.
Widget _buildAdBanner() {
  final screenSize = MediaQuery.sizeOf(context);
  final isMobile = screenSize.width < 600;
  final detailPanelOpen = kIsWeb &&
      screenSize.width >= 900 &&
      _desktopDetailSpot != null;
  final detailPanelWidth =
      detailPanelOpen ? min(500.0, screenSize.width * 0.40) : 0.0;

  // Même géométrie horizontale que _buildBottomBar dans tous les cas.
  // La zone de création fait partie de la largeur totale.
  final inset = _mobileBottomMenuSideInset;
  const gapAboveMenu = 6.0;
  final bannerBottom = _mobileBottomMenuBottom +
      _mobileBottomMenuHeight + gapAboveMenu;

  return Positioned(
    left: inset,
    right: detailPanelWidth + inset,
    bottom: bannerBottom,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;

        // Le bouton fait partie de la largeur totale, sans largeur ajoutée
        // par un Container parent : aucune somme ne peut déborder du Row.
        // Un bandeau Web panoramique distinct peut être fourni.
        // Sans lui, afficher la totalité du visuel standard : ne jamais
        // appliquer BoxFit.cover à un JPG dont les textes sont en bordure.
        final wideWebBanner = kIsWeb && !isMobile;
        // La zone de création reste volontairement courte : elle ne
        // doit pas diminuer inutilement la surface publicitaire.
        final preferredCreationWidth = isMobile
            ? 46.0
            : wideWebBanner
                ? 92.0
                : 96.0;
        final creationWidth = min(
          preferredCreationWidth,
          max(0.0, availableWidth - 90.0),
        );
        final panoramicWidth = max(0.0, availableWidth - creationWidth);
        final bannerHeight = wideWebBanner
            ? min(118.0, panoramicWidth / 6.0)
            : max(52.0, panoramicWidth / 6.0);

        // Même géométrie et même destination qu'auparavant : seul le visuel
        // de candidature change, en utilisant les créations SPHOT validées.
        Widget createAdvertisingInvitation({
          bool hasAdvertisement = false,
        }) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => unawaited(_openAdvertiserWebsite()),
              child: Semantics(
                button: true,
                label: hasAdvertisement
                    ? 'Votre SPHOT PUBLICITAIRE ici!'
                    : 'CRÉER VOTRE SPHOT PUBLICITAIRE ICI!',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    // Rétablit le fin contour orange validé par-dessus les
                    // visuels recentrés, sans retoucher le texte, le fond,
                    // les proportions ni l'arrondi de 18 px.
                    foregroundDecoration: hasAdvertisement
                        ? null
                        : BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFFF9800),
                              width: 1.5,
                            ),
                          ),
                    child: SphotAdvertisingInvitationVisual(
                      compact: hasAdvertisement,
                      mobileMap: isMobile && !hasAdvertisement,
                      // L'image adaptée au mobile conserve ses proportions.
                      // La bande Web reste remplie comme auparavant.
                      fit: (isMobile || hasAdvertisement)
                          ? BoxFit.contain
                          : BoxFit.fill,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        Widget occupiedAdvertisingSpace(Map<String, dynamic> ad) {
          final standardBannerUrl = ad['bannerUrl']?.toString() ?? '';
          final panoramicBannerUrl = ad['webBannerUrl']?.toString() ?? '';
          // Le visuel 1800 x 300 soumis par l'annonceur fait foi,
          // sur le Web comme sur mobile. Un ancien webBannerUrl n'est
          // consulté qu'en secours pour les données historiques.
          final bannerUrl = standardBannerUrl.isNotEmpty
              ? standardBannerUrl
              : panoramicBannerUrl;
          final destinationUrl = ad['destinationUrl']?.toString() ?? '';
          final advertiserName =
              ad['advertiserName']?.toString().trim() ?? '';

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Zone 1 : toute l'image ouvre exclusivement le site
              // approuvé. La couche Flutter au-dessus du rendu HTML garantit
              // que le clic reste accessible dans Chrome et sur mobile.
              Expanded(
                child: ColoredBox(
                  color: const Color(0xFF063551),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                          bannerUrl,
                          width: double.infinity,
                          height: bannerHeight,
                          // Le visuel complet est compressé dans le bandeau
                          // Web compact, sans aucune découpe verticale.
                          fit: wideWebBanner ? BoxFit.fill : BoxFit.contain,
                          alignment: Alignment.center,
                          webHtmlElementStrategy:
                              WebHtmlElementStrategy.prefer,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            onTap: destinationUrl.isEmpty
                                ? null
                                : () => unawaited(
                                    _openMapAdDestination(destinationUrl),
                                  ),
                            child: Semantics(
                              button: destinationUrl.isNotEmpty,
                              label: advertiserName.isEmpty
                                  ? 'Visiter le site de l’annonceur'
                                  : 'Visiter le site de $advertiserName',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Zone 2 : carte transparente sur Web, distincte de l'annonce.
              SizedBox(
                width: creationWidth,
                child: createAdvertisingInvitation(
                  hasAdvertisement: true,
                ),
              ),
            ],
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: availableWidth,
            height: bannerHeight,
            child: ValueListenableBuilder<int>(
              valueListenable: _mapAdRotation,
              builder: (context, rotation, _) {
                return FutureBuilder<List<Map<String, dynamic>>>(
                  future: _publicMapAdvertisementsFuture,
                  builder: (context, snapshot) {
                    final ads =
                        (snapshot.data ?? const <Map<String, dynamic>>[])
                            .where(_isPublicMapAdVisible)
                            .toList();
                    if (ads.isEmpty) {
                      // Sans annonce, afficher la zone d'invitation.
                      return createAdvertisingInvitation();
                    }
                    return occupiedAdvertisingSpace(
                      ads[rotation % ads.length],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    ),
  );
}

Widget _buildBottomBar() {
  // Six zones de clic de largeur égale : compatible avec un mobile étroit,
  // sans texte sous les icônes ni fond opaque / translucide.
  final icons = <IconData>[
    Icons.tune,
    Icons.layers_outlined,
    _isSearchPanelOpen ? Icons.close_rounded : Icons.search_rounded,
    _favoriteSpotIds.isNotEmpty ? Icons.star : Icons.star_border,
    Icons.info_outline,
    Icons.person_outline_rounded,
  ];
  final labels = <String>[
    'Filtres',
    'Cartes',
    _isSearchPanelOpen ? 'Fermer la recherche' : 'Rechercher un SPHOT',
    'Favoris',
    'Informations',
    'Profil / Connexion',
  ];
  final colors = <Color>[
    Colors.black87,
    const Color(0xFF8B5E3C),
    _isSearchPanelOpen ? const Color(0xFFFF7F00) : Colors.black87,
    const Color(0xFFFFD000),
    const Color(0xFF1E3A8A),
    const Color(0xFFFF0000),
  ];

  return Positioned(
    left: _mobileBottomMenuSideInset,
    right: kIsWeb &&
            MediaQuery.sizeOf(context).width >= 900 &&
            _desktopDetailSpot != null
        ? min(500.0, MediaQuery.sizeOf(context).width * 0.40) +
            _mobileBottomMenuSideInset
        : _mobileBottomMenuSideInset,
    bottom: _mobileBottomMenuBottom,
    child: Container(
      height: _mobileBottomMenuHeight,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFF0000),
          width: 2,
        ),
      ),
      child: Row(
        children: List.generate(icons.length, (index) {
          return Expanded(
            child: Tooltip(
              message: labels[index],
              child: Semantics(
                label: labels[index],
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    setState(() {
                      _selectedBottomIndex = index;
                      if (index != 2 && _isSearchPanelOpen) {
                        _closeSearchPanel();
                      }
                    });

                    if (index == 0) {
                      _toggleFilterBar();
                    } else if (index == 1) {
                      _toggleMapStyleBar();
                    } else if (index == 2) {
                      _toggleSearchPanel();
                    } else if (index == 3) {
                      unawaited(_toggleFavoritesFilter());
                    } else if (index == 4) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AppInfoPage(),
                        ),
                      );
                    } else if (index == 5) {
                      unawaited(_openLoginPage());
                    }
                  },
                  child: SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: Center(
                      child: Icon(
                        icons[index],
                        size: 26,
                        color: colors[index],
                        shadows: const [
                          Shadow(
                            color: Colors.white,
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

  PreferredSizeWidget _buildAppBar() {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final isDesktopWebDetailOpen =
      kIsWeb && screenWidth >= 900 && _selectedPublicSpotId != null;
  final detailPanelWidth =
      isDesktopWebDetailOpen ? min(500.0, screenWidth * 0.40) : 0.0;

  return PreferredSize(
    preferredSize: const Size.fromHeight(66),
    child: SafeArea(
      bottom: false,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: _mapHeaderLogoTop,
            left: 0,
            right: detailPanelWidth,
            child: ValueListenableBuilder<double>(
              valueListenable: _mobileDetailHeightFraction,
              builder: (context, fraction, child) {
                if (_mobileDetailOverlapsMapHeader(fraction)) {
                  return const SizedBox.shrink();
                }
                return child!;
              },
              child: Center(
                child: Image.asset(
                  'data/icons/title.png',
                  height: _mapHeaderLogoHeight,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  @override
void dispose() {
  _mapMoveTimer?.cancel();
  _mapAdRotationTimer?.cancel();
  _mapAdRotation.dispose();
  _searchTimer?.cancel();
  _searchController.dispose();
  _searchFocusNode.dispose();
  _mobileDetailHeightFraction.dispose();
  super.dispose();
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  key: _scaffoldKey,
  drawerScrimColor: Colors.transparent,
  backgroundColor: Colors.transparent,
  extendBodyBehindAppBar: true,
  appBar: _buildAppBar(),
  endDrawer: _buildDrawer(),
  body: StreamBuilder<List<SpotFlagState>>(
        stream: _firestoreService.getSpotsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allSpots = snapshot.data!;
final spots = allSpots
    .where(_matchesFilter)
    .where(
      (spot) =>
          !_showFavoritesOnly || _favoriteSpotIds.contains(spot.id),
    )
    .toList();

// Garder tous les marqueurs accessibles, même avec un volet ouvert sur
// desktop ou mobile. Cliquer sur un autre SPHOT remplace sa fiche à droite.
final visibleSpots = spots;

debugPrint('SPHOTS CHARGÉS : ${allSpots.length}');
debugPrint('SPHOTS AFFICHÉS : ${visibleSpots.length}');

          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _publicAdvertisingSpotsFuture,
            builder: (context, advertisingSnapshot) {
              final publicAdvertisers =
                  advertisingSnapshot.data ?? const <Map<String, dynamic>>[];
              return Stack(
                children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
  crs: const _SphotSingleWorldCrs(),

  initialCenter: const LatLng(46.4006176, -1.5064563),
  initialZoom: 13,

  // Le monde ne doit pas devenir plus petit que
  // la plus grande dimension de l'écran.
  minZoom: max(
    1.0,
    log(
      max(
        MediaQuery.sizeOf(context).width,
        MediaQuery.sizeOf(context).height,
      ) / 256.0,
    ) / ln2,
  ),

  // Empêche de dépasser le zoom des tuiles disponibles.
  maxZoom: 19.0,

  // Évite les débordements verticaux au dézoom.
  cameraConstraint: const CameraConstraint.containLatitude(),
  interactionOptions: const InteractionOptions(
  flags: InteractiveFlag.all,
),

onTap: (_, __) {
  if (_isFilterOpen || _isMapStyleOpen || _isSearchPanelOpen) {
    _searchFocusNode.unfocus();

    setState(() {
      _isFilterOpen = false;
      _isMapStyleOpen = false;
      if (_isSearchPanelOpen) _closeSearchPanel();
    });
  }
},

onPositionChanged: (position, hasGesture) {
  // L'éligibilité locale suit la zone consultée sur la carte.
  _mapAdCenter = position.center;
  if ((_currentRotation - position.rotation).abs() > 0.5 || hasGesture) {
    setState(() {
      _currentRotation = position.rotation;
      if (hasGesture) {
        _isMovingMap = true;
      }
    });
  }

  if (hasGesture) {
    if (_isFilterOpen || _isMapStyleOpen || _isSearchPanelOpen) {
      _searchFocusNode.unfocus();

      setState(() {
        _isFilterOpen = false;
        _isMapStyleOpen = false;
        if (_isSearchPanelOpen) _closeSearchPanel();
      });
    }

    _mapMoveTimer?.cancel();
    _mapMoveTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _isMovingMap = false;
      });
    });
  }
},
),
                children: [
                  TileLayer(
  key: ValueKey(
    'tile_style_${_selectedTileStyle}_$_mapTileRefreshVersion',
  ),
  urlTemplate: _tileStyles[_selectedTileStyle].url,
  subdomains: _tileStyles[_selectedTileStyle].subdomains,
  maxZoom: _tileStyles[_selectedTileStyle].maxZoom.toDouble(),
  maxNativeZoom: _tileStyles[_selectedTileStyle].maxZoom,
  userAgentPackageName: 'com.sylvainra.sphot',
  keepBuffer: 5,
  errorTileCallback: (tile, error, stackTrace) {
    debugPrint('ERREUR TILE MAP : $error');
  },
),
                  if (_selectedPublicSpotId == null)
                    Builder(
                      builder: (context) {
                        final zoom = MapCamera.of(context).zoom;
                        final rotation = MapCamera.of(context).rotation;

                        return MarkerLayer(
                          markers: _buildAdminMarkers(
                            allSpots,
                            zoom,
                            rotation,
                          ),
                        );
                      },
                    ),
                  // Monde / régions : tous les SPHOTS sont regroupés.
                  // Dès le zoom 12, les mâts surveillés sont indépendants
                  // et dessinés AU-DESSUS des fire icons des autres SPHOTS.
                  Builder(
                    builder: (context) {
                      final zoom = MapCamera.of(context).zoom;
                      final rotation = MapCamera.of(context).rotation;
                      final automaticLabelIds =
                          _automaticLabelIds(visibleSpots, zoom);

                      final eligibleSpots = visibleSpots
                          .where((spot) =>
                              spot.lat.isFinite && spot.lng.isFinite)
                          .toList();

                      final rescueSpots = zoom >= 12.0
                          ? eligibleSpots
                              .where((spot) => spot.isPosteSecours)
                              .toList()
                          : <SpotFlagState>[];

                      final toCluster = eligibleSpots.where((spot) {
                        // A faible zoom, même les mâts entrent dans les
                        // groupes : aucun grand drapeau ne couvre la carte.
                        if (zoom < 12.0) return true;
                        if (spot.isPosteSecours) return false;

                        // A zoom >= 16, tous les lieux redeviennent visibles.
                        if (zoom >= 16.0 || rescueSpots.isEmpty) {
                          return true;
                        }

                        // Tant qu'ils chevaucheraient visuellement un mât,
                        // les fire icons voisins attendent. Ils apparaissent
                        // naturellement quand la distance en pixels grandit
                        // à mesure que l'utilisateur zoome.
                        final point = _mercatorPixelPoint(spot, zoom);
                        for (final rescue in rescueSpots) {
                          final rescuePoint =
                              _mercatorPixelPoint(rescue, zoom);
                          if ((point.dx - rescuePoint.dx).abs() < 90.0 &&
                              (point.dy - rescuePoint.dy).abs() < 110.0) {
                            return false;
                          }
                        }
                        return true;
                      }).toList();

                      final markers = toCluster
                          .map((spot) => _buildProgressiveSpotMarker(
                                spot,
                                zoom,
                                rotation,
                                automaticLabelIds,
                              ))
                          .toList();

                      return MarkerClusterLayerWidget(
                        options: MarkerClusterLayerOptions(
                          markers: markers,
                          size: const Size(54, 54),
                          alignment: Alignment.center,
                          maxZoom: 19.0,
                          maxClusterRadius: zoom < 7.0
                              ? 92
                              : zoom < 12.0
                                  ? 64
                                  : zoom < 16.0
                                      ? 42
                                      : 2,
                          disableClusteringAtZoom: 16,
                          zoomToBoundsOnClick: true,
                          centerMarkerOnClick: false,
                          spiderfyCluster: true,
                          showPolygon: false,
                          markerChildBehavior: true,
                          builder: _buildCluster,
                        ),
                      );
                    },
                  ),

                  // Dessinés en dernier, les mâts restent prioritaires sur
                  // TOUS les autres marqueurs, à partir de leur zoom actuel.
                  Builder(
                    builder: (context) {
                      final zoom = MapCamera.of(context).zoom;
                      final rotation = MapCamera.of(context).rotation;
                      final automaticLabelIds =
                          _automaticLabelIds(visibleSpots, zoom);

                      return MarkerLayer(
                        markers: zoom < 12.0
                            ? const <Marker>[]
                            : _buildSecoursMarkers(
                                visibleSpots,
                                automaticLabelIds,
                                zoom,
                                rotation,
                              ),
                      );
                    },
                  ),
                ],
              ),
              if (_selectedPublicSpotId == null && _isSearchPanelOpen)
                _buildLeftMapControls(allSpots),


Positioned(
  left: _bottomMenuLeft(
    menuWidth: 150,
    itemIndex: 1,
  ),
  bottom: 154,
  child: _buildMapStyleVerticalMenu(),
),

_buildVerticalFilterMenu(),
// La publicité figure déjà dans la fiche : ne rien laisser dépasser
// dans l'espace de 6 px réservé entre le volet et le menu inférieur.
if (_mobileDetailSpot == null)
  _buildAdBanner(),
_buildBottomBar(),
if (_mobileDetailSpot != null)
  _buildMobileSpotPanel(),
if (kIsWeb &&
    MediaQuery.sizeOf(context).width >= 900 &&
    _desktopDetailSpot != null)
  _buildDesktopSpotPanel(),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// Métadonnées invisibles permettant au clustering de déterminer la catégorie
// majoritaire, sans changer l'affichage ni le comportement des marqueurs.
class _SphotClusterMember extends StatelessWidget {
  final SpotFlagState spot;
  final Widget child;

  const _SphotClusterMember({
    required this.spot,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => child;
}

class _ColoredSphotsText extends StatelessWidget {
  const _ColoredSphotsText();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'SPHOTS',
        style: TextStyle(
          fontSize: 15.4,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: -0.1,
          foreground: Paint()
            ..shader = const LinearGradient(
              colors: [
                Color(0xFFFF7F00),
                Color(0xFF1E3A8A),
                Color(0xFF2E7D32),
                Color(0xFF00ACC1),
                Color(0xFFD87A5C),
                Colors.black87,
              ],
            ).createShader(const Rect.fromLTWH(0, 0, 120, 20)),
        ),
      ),
    );
  }
}

class _OutlinedMenuText extends StatelessWidget {
  final String text;
  final Color color;
  final bool selected;

  const _OutlinedMenuText({
    required this.text,
    required this.color,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lines.first == 'SPHOTS')
          const _ColoredSphotsText()
        else
          Text(
  lines.first,
  style: TextStyle(
    color: color,
    fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
    fontSize: 15,
    height: 1.1,
    shadows: color == const Color(0xFFFFD000)
        ? const [
            Shadow(
              color: Colors.white,
              offset: Offset(0.6, 0),
              blurRadius: 0.8,
            ),
            Shadow(
              color: Colors.white,
              offset: Offset(-0.6, 0),
              blurRadius: 0.8,
            ),
            Shadow(
              color: Colors.white,
              offset: Offset(0, 0.6),
              blurRadius: 0.8,
            ),
            Shadow(
              color: Colors.white,
              offset: Offset(0, -0.6),
              blurRadius: 0.8,
            ),
          ]
        : null,
  ),
),
        ...lines.skip(1).map(
              (line) => Text(
                line,
                style: TextStyle(
  color: color.withOpacity(0.85),
  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
  fontSize: 13,
  height: 1.15,
  shadows: color == const Color(0xFFFFD000)
      ? const [
          Shadow(
            color: Colors.black,
            offset: Offset(0.5, 0),
            blurRadius: 0.7,
          ),
          Shadow(
            color: Colors.black,
            offset: Offset(-0.5, 0),
            blurRadius: 0.7,
          ),
        ]
      : null,
),
              ),
            ),
      ],
    );
  }
}



class _SphotSpinnerIcon extends StatefulWidget {
  const _SphotSpinnerIcon();

  @override
  State<_SphotSpinnerIcon> createState() => _SphotSpinnerIconState();
}

class _SphotSpinnerIconState extends State<_SphotSpinnerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _markerColor(double progress) {
    if (progress < 0.12) {
      return Color.lerp(
        Colors.black,
        const Color(0xFFFF0000),
        progress / 0.12,
      )!;
    }

    if (progress < 0.78) {
      final hue = ((progress - 0.12) / 0.66) * 360;

      return HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    }

    if (progress < 0.90) {
      return Color.lerp(
        const Color(0xFFFF0000),
        Colors.white,
        (progress - 0.78) / 0.12,
      )!;
    }

    return Color.lerp(
      Colors.white,
      Colors.black,
      (progress - 0.90) / 0.10,
    )!;
  }

  Widget _colorLayer(Color color) {
    return SvgPicture.asset(
      'data/icons/fire_all_sphots_color_layer.svg',
      width: 40,
      height: 40,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final color = _markerColor(_controller.value);

          return Stack(
            alignment: Alignment.center,
            children: [
              SvgPicture.asset(
                'data/icons/fire_green_icon.svg',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
              ),
              _colorLayer(color),
            ],
          );
        },
      ),
    );
  }
}

class _DrawerFlagIcon extends StatefulWidget {
  const _DrawerFlagIcon();

  @override
  State<_DrawerFlagIcon> createState() => _DrawerFlagIconState();
}

class _DrawerFlagIconState extends State<_DrawerFlagIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double iconWidth = 28;
  static const double iconHeight = 34;

  static const double poleWidth = 3;
  static const double poleHeight = 31;
  static const double poleLeft = 7;

  static const double flagLeft = poleLeft + poleWidth - 0.5;
  static const double flagTop = -1;
  static const double flagWidth = 16;
  static const double flagHeight = 22;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: iconWidth,
      height: iconHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: poleLeft,
            bottom: 0,
            child: Container(
              width: poleWidth,
              height: poleHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: flagLeft,
            top: flagTop,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(flagWidth, flagHeight),
                  painter: MiniWavingFlagPainter(
                    color: const Color(0xFF22C55E),
                    phase: _controller.value * 2 * pi,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MiniWavingFlagPainter extends CustomPainter {
  final Color color;
  final double phase;

  MiniWavingFlagPainter({
    required this.color,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final path = ui.Path();

    const int steps = 30;
    const double verticalMargin = 5;

    final topPoints = <Offset>[];
    final bottomPoints = <Offset>[];

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = size.width * t;

      final amplitude = 0.3 + 1.2 * t;
      final wave = sin(t * pi * 1.8 - phase) * amplitude;

      topPoints.add(Offset(x, verticalMargin + wave));
      bottomPoints.add(Offset(x, size.height - verticalMargin + wave));
    }

    path.moveTo(topPoints.first.dx, topPoints.first.dy);

    for (final point in topPoints) {
      path.lineTo(point.dx, point.dy);
    }

    for (final point in bottomPoints.reversed) {
      path.lineTo(point.dx, point.dy);
    }

    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant MiniWavingFlagPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.color != color;
  }
}


class _PublicAdvertisingMarker extends StatefulWidget {
  const _PublicAdvertisingMarker({
    required this.name,
    required this.showTextAllowed,
    required this.alwaysShowName,
    required this.rotation,
    required this.labelOpacity,
  });

  final String name;
  final bool showTextAllowed;
  final bool alwaysShowName;
  final double rotation;
  final double labelOpacity;

  @override
  State<_PublicAdvertisingMarker> createState() =>
      _PublicAdvertisingMarkerState();
}

class _PublicAdvertisingMarkerState extends State<_PublicAdvertisingMarker> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isTouchDevice =
        Theme.of(context).platform == TargetPlatform.android ||
            Theme.of(context).platform == TargetPlatform.iOS;
    final showText =
        widget.showTextAllowed && (widget.alwaysShowName || isTouchDevice || _isHovering);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Transform.rotate(
          angle: -widget.rotation * pi / 180,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const AdaptiveAssetImage(
                'data/icons/fire_green_icon.svg',
                width: 48,
                height: 48,
                fit: BoxFit.contain,
              ),
              if (showText)
                Positioned(
                  top: 50,
                  left: -160,
                  child: Opacity(
                    opacity: widget.labelOpacity,
                    child: SizedBox(
                      width: 380,
                      child: Text(
                        widget.name,
                        textAlign: TextAlign.center,
                        style: _mapLabelStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherSpotMarker extends StatefulWidget {
  final SpotFlagState spot;
  final String iconPath;
  final bool showTextAllowed;
  final bool forceShowText;
  final bool autoShowName;
  final double zoom;
  final double rotation;
  final double labelOpacity;
  final Color typeTextColor;
  final bool compactIcon;

  const _OtherSpotMarker({
    required this.spot,
    required this.iconPath,
    required this.showTextAllowed,
    required this.forceShowText,
    required this.autoShowName,
    required this.zoom,
    required this.rotation,
    required this.labelOpacity,
    required this.typeTextColor,
    this.compactIcon = false,
  });

  @override
  State<_OtherSpotMarker> createState() => _OtherSpotMarkerState();
}

// Style des étiquettes commun à tous les SPHOT, sur carte Web et mobile.
// Le survol peut révéler des lignes, jamais grossir ni espacer le texte.
const double _mapInfoLineGap = 3.0;
const double _mapNameFontSize = 13.0;
const double _mapCityFontSize = 12.0;
const double _mapTypeFontSize = 12.0;
const double _mapWarningIconSize = 22.0;

// Une même hauteur minimale pour les lignes de texte et les alertes évite
// les décalages optiques entre les lignes avec ou sans pictogramme.
// Les textes longs conservent la liberté de se répartir sur plusieurs lignes.
Widget _mapUniformInfoLine(Widget child) {
  return ConstrainedBox(
    constraints: const BoxConstraints(minHeight: _mapWarningIconSize),
    child: Center(child: child),
  );
}

class _OtherSpotMarkerState extends State<_OtherSpotMarker> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;

    final isTouchDevice =
        Theme.of(context).platform == TargetPlatform.android ||
            Theme.of(context).platform == TargetPlatform.iOS;

    final showFullText = widget.forceShowText ||
        (widget.showTextAllowed && !isTouchDevice && isHovering);
    final showAutomaticName = !showFullText && widget.autoShowName;

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: SizedBox(
        width: widget.compactIcon ? 44 : 56,
        height: widget.compactIcon ? 44 : 56,
        child: Transform.rotate(
          angle: -widget.rotation * pi / 180,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AdaptiveAssetImage(
                widget.iconPath,
                width: widget.compactIcon ? 38 : (spot.isNaturisme ? 52 : 48),
                height: widget.compactIcon ? 38 : (spot.isNaturisme ? 52 : 48),
                fit: BoxFit.contain,
              ),
              if (showAutomaticName)
                Positioned(
                  top: widget.compactIcon ? 42 : 48,
                  left:
                      ((widget.compactIcon ? 44 : 56) -
                           min(380.0, MediaQuery.sizeOf(context).width - 24)) /
                      2,
                  child: SizedBox(
                    width:
                        min(380.0, MediaQuery.sizeOf(context).width - 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _mapUniformInfoLine(Text(
                          spot.mapDisplayName,
                          textAlign: TextAlign.center,
                          softWrap: true,
                          style: _mapLabelStyle(
                            fontSize: _mapNameFontSize,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        )),
                        if (spot.ville.trim().isNotEmpty) ...[
                          const SizedBox(height: _mapInfoLineGap),
                          _mapUniformInfoLine(Text(
                            spot.ville.toUpperCase(),
                            textAlign: TextAlign.center,
                            softWrap: true,
                            style: _mapLabelStyle(
                              fontSize: _mapCityFontSize,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1E3A8A),
                            ),
                          )),
                        ],
                        if (widget.zoom >= 16.0) ...[
                          const SizedBox(height: _mapInfoLineGap),
                          _mapUniformInfoLine(Text(
                            spot.typeSphot.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _mapCityFontSize,
                              fontWeight: FontWeight.w700,
                              color: widget.typeTextColor,
                              useBlackOutline:
                                  spot.normalizedType.contains('ACCES PLAGE'),
                            ),
                          )),
                          const SizedBox(height: _mapInfoLineGap),
                          _mapUniformInfoLine(_warningLineUniform(
                            'BAIGNADE NON SURVEILLÉE',
                            _mapWarningIconSize,
                          )),
                          const SizedBox(height: _mapInfoLineGap),
                          _mapUniformInfoLine(_warningLineUniform(
                            'BAIGNADE À VOS RISQUES ET PÉRILS',
                            _mapWarningIconSize,
                          )),
                        ],
                      ],
                    ),
                  ),
                ),
              if (showFullText)
                Positioned(
                  top: widget.compactIcon ? 42 : 48,
                  left:
                      ((widget.compactIcon ? 44 : 56) -
                           min(380.0, MediaQuery.sizeOf(context).width - 24)) /
                      2,
                  child: Opacity(
                    opacity: widget.labelOpacity,
                    child: SizedBox(
                      width:
                          min(380.0, MediaQuery.sizeOf(context).width - 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _mapUniformInfoLine(Text(
                            spot.mapDisplayName,
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _mapNameFontSize,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          )),
                          if (spot.ville.trim().isNotEmpty) ...[
                            const SizedBox(height: _mapInfoLineGap),
                            _mapUniformInfoLine(Text(
                              spot.ville.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: _mapLabelStyle(
                                fontSize: _mapCityFontSize,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E3A8A),
                              ),
                            )),
                          ],
                          const SizedBox(height: _mapInfoLineGap),
                          _mapUniformInfoLine(Text(
                            spot.typeSphot.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _mapTypeFontSize,
                              fontWeight: FontWeight.w700,
                              color: widget.typeTextColor,
                              useBlackOutline:
                                  spot.normalizedType.contains('ACCES PLAGE'),
                            ),
                          )),
                          const SizedBox(height: _mapInfoLineGap),
                          _mapUniformInfoLine(_warningLineUniform(
                            'BAIGNADE NON SURVEILLÉE',
                            _mapWarningIconSize,
                          )),
                          const SizedBox(height: _mapInfoLineGap),
                          _mapUniformInfoLine(_warningLineUniform(
                            'BAIGNADE À VOS RISQUES ET PÉRILS',
                            _mapWarningIconSize,
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverMarker extends StatefulWidget {
  final SpotFlagState spot;
  final bool showTextAllowed;
  final bool forceShowText;
  final bool autoShowName;
  final double zoom;
  final double rotation;
  final double labelOpacity;

  const _HoverMarker({
    required this.spot,
    required this.showTextAllowed,
    required this.forceShowText,
    required this.autoShowName,
    required this.zoom,
    required this.rotation,
    required this.labelOpacity,
  });

  @override
  State<_HoverMarker> createState() => _HoverMarkerState();
}

class _HoverMarkerState extends State<_HoverMarker> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;

    final isTouchDevice =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    final showFullText = widget.forceShowText ||
        (widget.showTextAllowed && !isTouchDevice && isHovering);
    final showAutomaticName = !showFullText && widget.autoShowName;

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: SizedBox(
        width: 70,
        height: 132,
        child: Transform.rotate(
          angle: -widget.rotation * pi / 180,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                // Mât de carte raccourci de 8 px, pied toujours ancré
                // exactement au même point sur les cartes mobile et Web.
                offset: const Offset(0, -76.5),
                child: FlagMarker.map(spot: spot),
              ),
              if (showAutomaticName)
                Positioned(
                  top: 52,
                  left:
                      (70 - min(420.0, MediaQuery.sizeOf(context).width - 24)) /
                      2,
                  child: Opacity(
                    opacity: 1,
                    child: SizedBox(
                      width:
                          min(420.0, MediaQuery.sizeOf(context).width - 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _mapUniformInfoLine(Text(
                            spot.mapDisplayName,
                            textAlign: TextAlign.center,
                            softWrap: true,
                            style: _mapLabelStyle(
                              fontSize: _mapNameFontSize,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFFF0000),
                            ),
                          )),
                          if (spot.ville.trim().isNotEmpty) ...[
                            const SizedBox(height: _mapInfoLineGap),
                            _mapUniformInfoLine(Text(
                              spot.ville.toUpperCase(),
                              textAlign: TextAlign.center,
                              softWrap: true,
                              style: _mapLabelStyle(
                                fontSize: _mapCityFontSize,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E3A8A),
                              ),
                            )),
                          ],
                          if (widget.zoom >= 16.0) ...[
                            const SizedBox(height: _mapInfoLineGap),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'data/icons/flag_red_yellow_5x3.svg',
                                  // Réduire la longueur, sans diminuer la hauteur.
                                  width: 20,
                                  height: 16,
                                  fit: BoxFit.fill,
                                ),
                                const SizedBox(width: 4),
                                _mapUniformInfoLine(Text(
                                  'POSTE DE SECOURS',
                                  style: _mapLabelStyle(
                                    fontSize: _mapTypeFontSize,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFFFF0000),
                                  ),
                                )),
                              ],
                            ),
                            const SizedBox(height: _mapInfoLineGap),
                            _mapUniformInfoLine(_rescueStatusUnderMarker(
                              spot,
                              _mapWarningIconSize,
                            )),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              if (showFullText)
                Positioned(
                  top: 52,
                  left:
                      (70 - min(420.0, MediaQuery.sizeOf(context).width - 24)) /
                      2,
                  child: Opacity(
                    opacity: widget.labelOpacity,
                    child: SizedBox(
                      width:
                          min(420.0, MediaQuery.sizeOf(context).width - 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _mapUniformInfoLine(Text(
                            spot.mapDisplayName,
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _mapNameFontSize,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFFF0000),
                            ),
                          )),
                          if (spot.ville.trim().isNotEmpty) ...[
                            const SizedBox(height: _mapInfoLineGap),
                            _mapUniformInfoLine(Text(
                              spot.ville.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: _mapLabelStyle(
                                fontSize: _mapCityFontSize,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E3A8A),
                              ),
                            )),
                          ],

                          const SizedBox(height: _mapInfoLineGap),

                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SvgPicture.asset(
                                'data/icons/flag_red_yellow_5x3.svg',
                                // Même dimensions sur la fiche complète au survol.
                                width: 20,
                                height: 16,
                                fit: BoxFit.fill,
                              ),
                              const SizedBox(width: 4),
                              _mapUniformInfoLine(Text(
                                'POSTE DE SECOURS',
                                style: _mapLabelStyle(
                                  fontSize: _mapTypeFontSize,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFFFF0000),
                                ),
                              )),
                            ],
                          ),

                          const SizedBox(height: _mapInfoLineGap),

                          _mapUniformInfoLine(_rescueStatusUnderMarker(
                            spot,
                            _mapWarningIconSize,
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Les messages affichés sous le marqueur correspondent exclusivement
// aux informations publiques, aux droits temps réel et aux signaux sauveteur.
// Aucune période de surveillance n'est supposée si elle n'est pas renseignée.
List<String> _rescueWarningLines(SpotFlagState spot) {
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

  return const [
    'BAIGNADE NON SURVEILLÉE',
    'BAIGNADE À VOS RISQUES ET PÉRILS',
  ];
}

Widget _rescueStatusUnderMarker(
  SpotFlagState spot,
  double size,
) {
  if (spot.hasValidFlag) {
    final statusColor = Color(spot.statutColor);
    final statusText = spot.displayStatut.replaceAll('⚠️ ', '');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spot.flagColor != FlagColor.green) ...[
          // Même halo blanc que les autres avertissements de la carte.
          Stack(
            children: [
              Transform.translate(
                offset: const Offset(1, 0),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: size,
                  color: Colors.white,
                ),
              ),
              Transform.translate(
                offset: const Offset(-1, 0),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: size,
                  color: Colors.white,
                ),
              ),
              Transform.translate(
                offset: const Offset(0, 1),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: size,
                  color: Colors.white,
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -1),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: size,
                  color: Colors.white,
                ),
              ),
              Icon(
                Icons.warning_amber_rounded,
                size: size,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(width: 2),
        ],
        Flexible(
          child: Text(
            statusText,
            textAlign: TextAlign.center,
            style: _mapLabelStyle(
              fontSize: size * 0.55,
              fontWeight: FontWeight.w900,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }

  final warnings = _rescueWarningLines(spot);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < warnings.length; i++) ...[
        if (i > 0) const SizedBox(height: _mapInfoLineGap),
        _warningLineUniform(warnings[i], size),
      ],
    ],
  );
}

Widget _warningLineUniform(String text, double size) {
  return Row(
    mainAxisSize: MainAxisSize.min,
        children: [
      Stack(
        children: [
          Transform.translate(
            offset: const Offset(1, 0),
            child: Icon(Icons.warning_amber_rounded, size: size, color: Colors.white),
          ),
          Transform.translate(
            offset: const Offset(-1, 0),
            child: Icon(Icons.warning_amber_rounded, size: size, color: Colors.white),
          ),
          Transform.translate(
            offset: const Offset(0, 1),
            child: Icon(Icons.warning_amber_rounded, size: size, color: Colors.white),
          ),
          Transform.translate(
            offset: const Offset(0, -1),
            child: Icon(Icons.warning_amber_rounded, size: size, color: Colors.white),
          ),
          Icon(
            Icons.warning_amber_rounded,
            size: size,
            color: const Color(0xFFFFC107),
          ),
        ],
      ),
      const SizedBox(width: 2),
      Flexible(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: _mapLabelStyle(
            fontSize: size * 0.55,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFFF0000),
          ),
        ),
      ),
    ],
  );
}

TextStyle _mapLabelStyle({
  required double fontSize,
  required FontWeight fontWeight,
  required Color color,
  bool useBlackOutline = false,
}) {
  if (useBlackOutline) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: 1,
      letterSpacing: -0.1,
      shadows: const [
  Shadow(
    color: Colors.white,
    offset: Offset(0.8, 0),
    blurRadius: 1,
  ),
  Shadow(
    color: Colors.white,
    offset: Offset(-0.8, 0),
    blurRadius: 1,
  ),
  Shadow(
    color: Colors.white,
    offset: Offset(0, 0.8),
    blurRadius: 1,
  ),
  Shadow(
    color: Colors.white,
    offset: Offset(0, -0.8),
    blurRadius: 1,
  ),
],
    );
  }

  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: 1,
    letterSpacing: -0.1,
    shadows: const [
      Shadow(color: Colors.white, offset: Offset(0, 0), blurRadius: 5),

      Shadow(color: Colors.white, offset: Offset(1.5, 0), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(-1.5, 0), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(0, 1.5), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(0, -1.5), blurRadius: 2),

      Shadow(color: Colors.white, offset: Offset(1.2, 1.2), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(-1.2, 1.2), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(1.2, -1.2), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(-1.2, -1.2), blurRadius: 2),
    ],
  );
}


