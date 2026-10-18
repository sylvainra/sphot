import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

import '../../../map/map_page.dart';
import '../../../models/advertising_pricing_config.dart';
import '../../../services/published_commercial_quote_service.dart';
import '../../../widgets/adaptive_asset_image.dart';
import '../../shared/web_colors.dart';
import '../models/advertiser_request_status.dart';
import '../models/advertising_visual_data.dart';
import '../models/diffusion_preview_data.dart';
import '../models/planning_data.dart';
import '../services/advertiser_territory_service.dart';
import '../services/advertiser_country_boundary_service.dart';
import '../widgets/advertising_spot_section.dart';
import '../widgets/advertiser_application_section.dart';
import '../widgets/advertiser_legal_acceptance_section.dart';
import '../widgets/diffusion_central_preview.dart';
import '../widgets/diffusion_section.dart';
import '../widgets/establishment_section.dart';
import '../widgets/identity_professional_section.dart';
import '../widgets/planning_section.dart';
import '../widgets/quote_order_section.dart';

class AdvertiserDashboardPage extends StatefulWidget {
  const AdvertiserDashboardPage({
    super.key,
    required this.user,
    required this.onSignOut,
    this.developmentBypass = false,
    this.advertiserRequestId,
    this.approvedAccess = false,
    this.existingRequestOnly = false,
  });

  final User? user;
  final Future<void> Function() onSignOut;
  final bool developmentBypass;
  final String? advertiserRequestId;
  final bool approvedAccess;
  final bool existingRequestOnly;

  @override
  State<AdvertiserDashboardPage> createState() =>
      _AdvertiserDashboardPageState();
}

class _AdvertiserDashboardPageState extends State<AdvertiserDashboardPage> {
  static const _applicationSections = <_AdvertiserSection>[
    _AdvertiserSection(
      'IDENTITÉ & ENTREPRISE',
      Icons.verified_user_outlined,
      'Présentez votre identité professionnelle et votre entreprise.',
    ),
    _AdvertiserSection(
      'LOCALISATION & DEMANDE',
      Icons.fact_check_outlined,
      'Positionnez votre entreprise et enregistrez votre visuel.',
    ),
    _AdvertiserSection(
      'VALIDATIONS JURIDIQUES',
      Icons.gavel_rounded,
      'Consultez et acceptez les documents avant de transmettre la demande.',
    ),
  ];

  static const _approvedSections = <_AdvertiserSection>[
    _AdvertiserSection(
      'IDENTITÉ & ENTREPRISE',
      Icons.verified_user_outlined,
      'Profil professionnel validé par SPHOT.',
    ),
    _AdvertiserSection(
      'SPHOT PUBLICITAIRE',
      Icons.location_on_outlined,
      'Choisissez cinq rayons rouges ou le pays entier dans le monde.',
    ),
    _AdvertiserSection(
      'DIFFUSION',
      Icons.campaign_outlined,
      'Choisissez vos deux zones : CARTE SPHOT et FICHES SPHOT. '
          'Les deux réunies constituent le PACK VISIBILITÉ TOTALE.'
    ),
    _AdvertiserSection(
      'PLANIFICATION',
      Icons.calendar_month_outlined,
      'Planifiez votre publicité sans exclusivité territoriale ni sectorielle.',
    ),
    _AdvertiserSection(
      'DEVIS & COMMANDE',
      Icons.assignment_turned_in_outlined,
      'Tarification, devis, bon de commande et validation.',
    ),
    _AdvertiserSection(
      'PAIEMENT CB',
      Icons.credit_card_outlined,
      'Paiement sécurisé du devis confirmé, sans renouvellement automatique.',
    ),
    _AdvertiserSection(
      'DOCUMENTS & FACTURES',
      Icons.description_outlined,
      'Documents contractuels et facturation électronique.',
    ),
    _AdvertiserSection(
      'STATISTIQUES',
      Icons.query_stats_outlined,
      'Affichages, clics et fréquentation de la campagne.',
    ),
  ];

  int _selectedIndex = 0;
  final MapController _mapController = MapController();

  // Le dézoom dépend de la largeur RÉELLE de la carte centrale, pas de
  // la fenêtre entière. Un tour du monde reste légèrement plus large que
  // la carte afin de ne pas afficher deux fois les mêmes continents.
  double _minimumWorldZoom(double mapWidth) {
    final width = math.max(256.0, mapWidth);
    return math.max(
      1.0,
      math.log(width / 256.0) / math.ln2 + 0.10,
    );
  }
  final ScrollController _detailScrollController = ScrollController();
  LatLng? _advertisingPoint;
  double _advertisingRadiusKm = 0;
  AdvertiserTerritory? _advertisingTerritory;
  final AdvertiserCountryBoundaryService _countryBoundaries =
      AdvertiserCountryBoundaryService();
  List<List<LatLng>> _countryOutline = const [];
  int _countryOutlineRequest = 0;
  AdvertisingVisualData _advertisingVisual = const AdvertisingVisualData();
  DiffusionPreviewData _diffusionPreview = const DiffusionPreviewData();
  PlanningData _planningData = const PlanningData();
  final PublishedCommercialQuoteService _quoteService =
      const PublishedCommercialQuoteService();
  Map<String, int> _publishedPrices = <String, int>{};
  Map<String, int> _publishedPayableCents = <String, int>{};
  int _publishedDiscountPercent = 0;
  String? _publishedPricingReference;
  String? _publishedPricingError;
  int _publishedPricingRequest = 0;
  Map<String, dynamic> _requestData = <String, dynamic>{};
  String _requestStatus = 'loading';
  bool _requestReady = false;
  String? _requestLoadError;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _requestSubscription;
  bool _restoredRequestAssets = false;
  String? _requestedScopeOverride;

  String? get _requestId {
    final explicitId = widget.advertiserRequestId?.trim() ?? '';
    if (explicitId.isNotEmpty) return explicitId;
    if (widget.user != null) return widget.user!.uid;
    if (widget.developmentBypass) return 'advertiser-dev-preview';
    return null;
  }

  bool get _approvedFlow {
    return widget.approvedAccess || isAdvertiserRequestApproved(_requestStatus);
  }

  bool get _applicationLocked {
    return !_requestReady ||
        _requestLoadError != null ||
        isAdvertiserApplicationLocked(_requestStatus) ||
        _approvedFlow;
  }

  bool get _assetChangeAuthorized {
    final request = _map(_requestData['assetChangeRequest']);
    return request['status']?.toString() == 'authorized';
  }

  String get _assetChangeStatus {
    final request = _map(_requestData['assetChangeRequest']);
    return request['status']?.toString() ?? '';
  }

  String get _requestedScope {
    if (_requestedScopeOverride != null) return _requestedScopeOverride!;
    final advertisingSpot = _map(_requestData['advertisingSpot']);
    final approvedApplication = _map(_requestData['approvedApplication']);
    return (advertisingSpot['scope'] ??
            _requestData['requestedScope'] ??
            approvedApplication['scope'] ??
            'local')
        .toString();
  }

  String get _activityType {
    final establishment = _map(_requestData['establishment']);
    final activity = establishment['activityType']?.toString().trim() ?? '';
    if (activity == 'Autre') {
      final other = establishment['activityTypeOther']?.toString().trim() ?? '';
      return other.isEmpty ? activity : other;
    }
    return activity;
  }

  bool get _usesNationalPricing =>
      _requestedScope == 'national' || _requestedScope == 'local_and_national';

  List<_AdvertiserSection> get _sections =>
      _approvedFlow ? _approvedSections : _applicationSections;

  @override
  void initState() {
    super.initState();
    _listenToRequest();
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    _detailScrollController.dispose();
    super.dispose();
  }

  void _listenToRequest() {
    final requestId = _requestId;
    if (requestId == null) {
      _requestLoadError = 'Impossible d’identifier votre dossier.';
      return;
    }
    _requestSubscription = FirebaseFirestore.instance
        .collection('advertiserRequests')
        .doc(requestId)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (!mounted) return;
            if (snapshot.metadata.isFromCache) return;
            final data = snapshot.data() ?? <String, dynamic>{};
            final missingRequest =
                !snapshot.exists && widget.existingRequestOnly;
            final status = snapshot.exists
                ? (data['status'] ?? 'unknown').toString().trim().toLowerCase()
                : (missingRequest ? 'unknown' : 'draft');
            setState(() {
              _requestReady = !missingRequest;
              _requestLoadError = missingRequest
                  ? 'Votre dossier est introuvable. La saisie reste verrouillée.'
                  : null;
              _requestData = data;
              _requestStatus = status;
              if (_selectedIndex >= _sections.length) _selectedIndex = 0;
            });
            if (!_restoredRequestAssets) _restoreRequestAssets(data);
          },
          onError: (Object error) {
            debugPrint('Écoute demande annonceur impossible : $error');
            if (!mounted) return;
            setState(() {
              _requestReady = false;
              _requestLoadError = 'Impossible de vérifier l’état du dossier. Actualisez la page.';
            });
          },
        );
  }

  Map<String, dynamic> _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  int? _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  String? _nullableText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  void _restoreRequestAssets(Map<String, dynamic> data) {
    final restoredTerritory =
        AdvertiserTerritory.fromFirestore(data['advertisingTerritory']);
    final approved = _map(data['approvedApplication']);
    final location = approved.isNotEmpty
        ? _map(approved['location'])
        : _map(data['applicantLocation']);
    final visual = approved.isNotEmpty
        ? _map(approved['visual'])
        : _map(data['proposedVisual']);
    final latitude = _double(location['latitude']);
    final longitude = _double(location['longitude']);
    if (latitude != null && longitude != null) {
      _setAdvertisingPoint(LatLng(latitude, longitude), centerMap: false);
    }
    if (restoredTerritory != null) {
      _setAdvertisingTerritory(restoredTerritory);
    }
    final url = _nullableText(visual['url'] ?? data['bannerUrl']);
    if (url != null) {
      _setAdvertisingVisual(
        AdvertisingVisualData(
          url: url,
          fileName: _nullableText(visual['fileName']),
          extension: _nullableText(visual['extension']),
          mimeType: _nullableText(visual['mimeType']),
          fileSizeBytes: _int(visual['fileSizeBytes']),
          width: _int(visual['width']),
          height: _int(visual['height']),
        ),
      );
    }
    _restoredRequestAssets = true;
  }

  Future<void> _loadPublishedPrices() async {
    final territory = _advertisingTerritory;
    if (!mounted || territory == null) return;
    final offer = _visibilityType;
    final ticket = ++_publishedPricingRequest;
    setState(() {
      _publishedPrices = <String, int>{};
      _publishedPayableCents = <String, int>{};
      _publishedDiscountPercent = 0;
      _publishedPricingReference = null;
      _publishedPricingError = null;
    });

    try {
      final quotes = await Future.wait([
        for (final duration in AdvertisingPricingConfig.durations)
          _quoteService.advertiserRadius(
            radius: territory.level.storageKey,
            offer: offer,
            duration: duration,
          ),
      ]);
      if (!mounted || ticket != _publishedPricingRequest) return;
      final versions = quotes.map((quote) => quote.pricingReference).toSet();
      if (versions.length != 1) {
        throw StateError('Versions tarifaires incompatibles.');
      }
      if (quotes.map((q) => q.discountPercent).toSet().length != 1) {
        throw StateError('La remise a changé pendant le calcul des tarifs.');
      }
      setState(() {
        _publishedPayableCents = {
          for (var i = 0; i < quotes.length; i++)
            AdvertisingPricingConfig.durations[i]:
                quotes[i].payableExclTaxCents,
        };
        _publishedDiscountPercent = quotes.first.discountPercent;
        _publishedPrices = <String, int>{
          for (var i = 0; i < quotes.length; i++)
            AdvertisingPricingConfig.durations[i]: quotes[i].amountExclTax,
        };
        _publishedPricingReference = quotes.first.pricingReference;
      });
    } catch (error) {
      if (!mounted || ticket != _publishedPricingRequest) return;
      setState(() {
        _publishedPricingError =
            'Tarifs publiés indisponibles. Aucun prix historique utilisé.';
      });
      debugPrint('Tarifs annonceur publiés indisponibles : $error');
    }
  }

  String get _visibilityType {
    switch (_diffusionPreview.type) {
      case DiffusionPreviewType.premium:
        return 'premium';
      case DiffusionPreviewType.pack:
        return 'pack';
      case DiffusionPreviewType.map:
      case null:
        return 'map';
    }
  }

  int _payableCentsFor(String durationLabel) =>
      _publishedPayableCents[durationLabel] ?? 0;

  int _costFor({
    required String durationLabel,
    String? visibilityType,
    double? radiusKm,
  }) {
    // Aucun calcul fondé sur les rayons ou sur des tarifs non publiés.
    if (visibilityType != null && visibilityType != _visibilityType) {
      return 0;
    }
    return _publishedPrices[durationLabel] ?? 0;
  }

  void _selectSection(int index) {
    setState(() => _selectedIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_detailScrollController.hasClients) return;
      _detailScrollController.jumpTo(0);
    });
  }

  void _setAdvertisingPoint(LatLng point, {required bool centerMap}) {
    final moved = _advertisingPoint != null &&
        _advertisingPoint != point;
    if (moved && _advertisingTerritory?.isWholeCountry == true) {
      ++_countryOutlineRequest;
      setState(() {
        _advertisingPoint = point;
        _advertisingTerritory = null;
        _countryOutline = const [];
        _publishedPrices = <String, int>{};
        _publishedPayableCents = <String, int>{};
        _publishedPricingReference = null;
      });
    } else {
      setState(() => _advertisingPoint = point);
    }
    if (!centerMap) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(
        point,
        _advertisingTerritory?.level.suggestedZoom ?? 15,
      );
    });
  }

  void _setDiffusionPreview(DiffusionPreviewData preview) {
    if (!mounted) return;
    final offerChanged = _diffusionPreview.type != preview.type;
    setState(() => _diffusionPreview = preview);
    if (offerChanged) _loadPublishedPrices();
  }

  void _setAdvertisingVisual(AdvertisingVisualData visual) {
    if (!mounted) return;
    setState(() => _advertisingVisual = visual);
  }

  void _setAdvertisingTerritory(AdvertiserTerritory territory) {
    if (!mounted) return;
    final old = _advertisingTerritory;
    if (old?.level == territory.level && old?.code == territory.code) return;
    ++_countryOutlineRequest;
    setState(() {
      _advertisingTerritory = territory;
      _countryOutline = const [];
    });
    // Les cinq rayons restent indépendants du pays sélectionné.
    _setAdvertisingRadius(territory.radiusKm);
    _loadPublishedPrices();
    if (territory.isWholeCountry) {
      unawaited(_loadCountryOutline(territory, _countryOutlineRequest));
      return;
    }
    final center = _advertisingPoint;
    if (center != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(center, territory.level.suggestedZoom);
        }
      });
    }
  }

  Future<void> _loadCountryOutline(
    AdvertiserTerritory territory,
    int request,
  ) async {
    try {
      final boundary = await _countryBoundaries.findByIso3(territory.code);
      if (!mounted || request != _countryOutlineRequest ||
          _advertisingTerritory?.code != territory.code) {
        return;
      }
      if (boundary == null || boundary.allPoints.isEmpty) {
        debugPrint('Frontière absente pour ${territory.code}');
        return;
      }
      final selectedSpot = _advertisingPoint;
      if (selectedSpot == null) return;
      final focusPoints = boundary.focusPointsNear(selectedSpot);
      if (focusPoints.length < 3) return;
      setState(() => _countryOutline = boundary.polygons);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || request != _countryOutlineRequest) return;
        // Le cadrage utilise la composante du pays où se trouve le SPHOT,
        // sans être repoussé vers l'océan par les territoires ultramarins.
        // L'ensemble des contours nationaux demeure dessiné en rouge.
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: focusPoints,
            padding: const EdgeInsets.all(32),
            maxZoom: 7,
          ),
        );
      });
    } catch (error) {
      // Aucune frontière inventée si le service cartographique échoue.
      debugPrint('Contour national indisponible : $error');
    }
  }

  void _setAdvertisingRadius(double radiusKm) {
    if (!mounted) return;
    if (_advertisingRadiusKm == radiusKm) return;
    setState(() {
      _advertisingRadiusKm = radiusKm;
      _planningData = PlanningData(
        durationLabel: _planningData.durationLabel,
        startDate: _planningData.startDate,
        endDate: _planningData.endDate,
        exclusiveReservation: _planningData.exclusiveReservation,
        availabilityConfirmed: false,
      );
    });
  }

  void _setRequestedScope(String scope) {
    if (!mounted || _requestedScope == scope) return;
    setState(() {
      _requestedScopeOverride = scope;
      _planningData = PlanningData(
        durationLabel: _planningData.durationLabel,
        startDate: _planningData.startDate,
        endDate: _planningData.endDate,
        exclusiveReservation: _planningData.exclusiveReservation,
        availabilityConfirmed: false,
      );
    });
  }

  void _setDiffusionType(DiffusionPreviewType type) {
    final current = _diffusionPreview;
    _setDiffusionPreview(
      DiffusionPreviewData(
        type: type,
        bannerBytes: current.bannerBytes,
        bannerUrl: current.bannerUrl,
        advertiserName: current.advertiserName,
        logoUrl: current.logoUrl,
        latitude: current.latitude,
        longitude: current.longitude,
      ),
    );
  }

  Map<String, int> get _durationPrices =>
      Map<String, int>.unmodifiable(_publishedPrices);

  void _setPlanningData(PlanningData planning) {
    if (!mounted) return;
    setState(() => _planningData = planning);
  }

  void _returnToPublicMap() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MapPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1250;
          final sidebarWidth = compact ? 250.0 : 330.0;
          final panelWidth = compact ? 370.0 : 470.0;

          return Row(
            children: [
              SizedBox(width: sidebarWidth, child: _buildSidebar()),
              Expanded(
                child: _buildMap(
                  mapWidth: math.max(
                    0.0,
                    constraints.maxWidth - sidebarWidth - panelWidth,
                  ),
                ),
              ),
              SizedBox(width: panelWidth, child: _buildDetailPanel()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar() {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            children: [
              const Text(
                'BIENVENUE SUR SPHOT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: WebColors.red,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Configurez votre demande de SPHOT PUBLICITAIRE en suivant les étapes ci-dessous.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: WebColors.blue,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              // Toutes les étapes restent visibles, sans défilement du menu.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final count = _sections.length;
                    if (count == 0) return const SizedBox.shrink();

                    const desiredButtonHeight = 68.0;
                    const desiredSpacing = 10.0;
                    const maxSpacing = 12.0;

                    final buttonHeight = ((constraints.maxHeight -
                                desiredSpacing * (count - 1)) /
                            count)
                        .clamp(0.0, desiredButtonHeight)
                        .toDouble();
                    final spacing = count > 1
                        ? ((constraints.maxHeight - buttonHeight * count) /
                                (count - 1))
                            .clamp(0.0, maxSpacing)
                            .toDouble()
                        : 0.0;

                    return Column(
                      children: [
                        for (var index = 0; index < count; index++) ...[
                          if (index > 0) SizedBox(height: spacing),
                          _SidebarButton(
                            number: index + 1,
                            label: _sections[index].label,
                            selected: index == _selectedIndex,
                            height: buttonHeight,
                            onTap: () => _selectSection(index),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMap({required double mapWidth}) {
    if (_approvedFlow &&
        _selectedIndex == 2 &&
        _diffusionPreview.hasSelection) {
      return DiffusionCentralPreview(data: _diffusionPreview);
    }

    final canSelectApplicationPosition =
        !_approvedFlow && _selectedIndex == 1 && !_applicationLocked;
    final canEditApprovedPosition =
        _approvedFlow && _selectedIndex == 1 && _assetChangeAuthorized;
    final showApprovedRadius = _approvedFlow && _selectedIndex == 1;

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(20, 0),
            initialZoom: _minimumWorldZoom(mapWidth),
            minZoom: _minimumWorldZoom(mapWidth),
            maxZoom: 18,
            onTap: canSelectApplicationPosition || canEditApprovedPosition
                ? (_, point) => _setAdvertisingPoint(point, centerMap: false)
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sphot.app',
            ),
            if (showApprovedRadius &&
                _advertisingTerritory?.isWholeCountry == true &&
                _countryOutline.isNotEmpty)
              PolygonLayer(
                polygons: [
                  for (final ring in _countryOutline)
                    Polygon(
                      points: ring,
                      color: WebColors.red.withOpacity(0.10),
                      borderColor: WebColors.red,
                      borderStrokeWidth: 2.2,
                    ),
                ],
              ),
            if (showApprovedRadius &&
                _advertisingPoint != null &&
                _advertisingTerritory != null &&
                !_advertisingTerritory!.isWholeCountry)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _advertisingPoint!,
                    radius: _advertisingTerritory!.radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: WebColors.red.withOpacity(0.10),
                    borderColor: WebColors.red,
                    borderStrokeWidth: 2.2,
                  ),
                ],
              ),
            if (_advertisingPoint != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _advertisingPoint!,
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    child: Transform.translate(
                      offset: const Offset(0, -28),
                      child: AdaptiveAssetImage(
                        'data/icons/fire_red_icon.svg',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (canSelectApplicationPosition || canEditApprovedPosition)
          Positioned(
            top: 88,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: WebColors.blue, width: 1.4),
                  ),
                  child: Text(
                    canEditApprovedPosition
                        ? 'CLIQUEZ SUR LA CARTE POUR PROPOSER UNE NOUVELLE POSITION'
                        : 'CLIQUEZ SUR LA CARTE POUR POSITIONNER VOTRE ENTREPRISE',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: WebColors.blue,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_selectedIndex == 0 && _requestStatus.toLowerCase() != 'pending')
          Positioned(
            top: 92,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 760),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: WebColors.blue, width: 1.6),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'FAITES CONNAÎTRE VOTRE ACTIVITÉ PROFESSIONNELLE AVEC SPHOT !',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebColors.blue,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'SPHOT ouvre le monde au grand public. Choisissez cinq rayons de proximité ou le pays entier. Le contour national s’adapte au pays du SPHOT. La diffusion reste partagée équitablement, sans exclusivité. Le public accède à votre site d’un simple clic.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF4B5F97),
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!_approvedFlow &&
                        _requestStatus.toLowerCase() != 'pending') ...[
                      const SizedBox(height: 14),
                      const Text(
                        'Dans un premier temps, nous vous invitons à remplir une demande de renseignements préalables. Si votre demande est acceptée par l’équipe SPHOT, vous pourrez accéder à la conception de votre SPHOT PUBLICITAIRE.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: WebColors.blue,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (!_approvedFlow && _requestStatus.toLowerCase() == 'pending')
          Positioned(
            top: 92,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 720),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.97),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: WebColors.red, width: 1.8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      color: WebColors.red,
                      size: 34,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'VOTRE DEMANDE A BIEN ÉTÉ TRANSMISE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebColors.red,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 9),
                    Text(
                      'L’équipe SPHOT vous remercie et traitera votre demande dans les meilleurs délais. Vous recevrez par e-mail les prochaines indications pour finaliser votre SPHOT PUBLICITAIRE. À TRÈS BIENTÔT SUR SPHOT !',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WebColors.blue,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Image.asset(
              'data/icons/title.png',
              height: 68,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
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
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: WebColors.blue, width: 2),
              ),
              child: IconButton(
                onPressed: _returnToPublicMap,
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: WebColors.blue,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailPanel() {
    final section = _sections[_selectedIndex];

    return ColoredBox(
      color: const Color(0xFFF5F7FA),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 100,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFD5DCE8))),
              ),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'data/icons/fire_red_icon.svg',
                    width: 38,
                    height: 54,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      section.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _detailScrollController,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      section.description,
                      style: const TextStyle(
                        color: WebColors.blue,
                        fontSize: 16,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ..._buildSectionContent(_selectedIndex),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSectionContent(int index) {
    if (_requestLoadError != null) {
      return [
        Text(_requestLoadError!, style: const TextStyle(color: WebColors.red)),
      ];
    }
    if (!_requestReady) {
      return [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 12),
        const Text('Vérification de l’état de votre dossier…'),
      ];
    }
    if (!_approvedFlow) {
      switch (index) {
        case 0:
          return [
            IdentityProfessionalSection(
              key: ValueKey('identity-$_requestStatus'),
              user: widget.user,
              requestId: _requestId,
              readOnly: _applicationLocked,
            ),
            const SizedBox(height: 8),
            EstablishmentSection(
              key: ValueKey('establishment-$_requestStatus'),
              user: widget.user,
              requestId: _requestId,
              readOnly: _applicationLocked,
            ),
          ];
        case 1:
          return [
            AdvertiserApplicationSection(
              readOnly: _applicationLocked,
              user: widget.user,
              requestId: _requestId,
              position: _advertisingPoint,
              initialVisual: _advertisingVisual,
              requestStatus: _requestStatus,
              onPositionChanged: _setAdvertisingPoint,
              onVisualChanged: _setAdvertisingVisual,
              onSubmitted: () {
                if (!mounted) return;
                setState(() => _selectedIndex = 2);
              },
            ),
          ];
        case 2:
        default:
          return [
            AdvertiserLegalAcceptanceSection(
              readOnly: _applicationLocked,
              key: ValueKey<String>(
                'advertiser-legal-${_requestId ?? 'unknown'}',
              ),
              requestId: _requestId,
              requestStatus: _requestStatus,
              onSubmitted: () {
                if (!mounted) return;
                setState(() => _requestStatus = 'pending');
              },
            ),
          ];
      }
    }

    switch (index) {
      case 0:
        return [
          IdentityProfessionalSection(
            user: widget.user,
            requestId: _requestId,
            readOnly: true,
          ),
          const SizedBox(height: 8),
          EstablishmentSection(
            user: widget.user,
            requestId: _requestId,
            readOnly: true,
          ),
        ];
      case 1:
        return [
          AdvertisingSpotSection(
            user: widget.user,
            requestId: _requestId,
            position: _advertisingPoint,
            initialVisual: _advertisingVisual,
            initialRadiusKm: _advertisingRadiusKm,
            startingPriceExclTax: _costFor(
              durationLabel: '1 semaine',
              visibilityType: 'map',
            ),
            onPositionChanged: _setAdvertisingPoint,
            onVisualChanged: _setAdvertisingVisual,
            onRadiusChanged: _setAdvertisingRadius,
            onScopeChanged: _setRequestedScope,
            approvedAssetsLocked: !_assetChangeAuthorized,
            assetChangeMode: _assetChangeAuthorized,
            assetChangeRequestStatus: _assetChangeStatus,
            requestedScope: _requestedScope,
            initialTerritory: _advertisingTerritory,
            onTerritoryChanged: _setAdvertisingTerritory,
          ),
        ];
      case 2:
        return [
          DiffusionSection(
            user: widget.user,
            requestId: _requestId,
            advertisingPosition: _advertisingPoint,
            advertisingVisual: _advertisingVisual,
            radiusKm: _advertisingRadiusKm,
            startingPriceExclTax: _costFor(durationLabel: '1 semaine'),
            initialPreview: _diffusionPreview,
            onPreviewChanged: _setDiffusionPreview,
            onRadiusChanged: _setAdvertisingRadius,
            requestedScope: _requestedScope,
          ),
        ];
      case 3:
        return [
          PlanningSection(
            user: widget.user,
            requestId: _requestId,
            advertisingPosition: _advertisingPoint,
            radiusKm: _advertisingRadiusKm,
            hasDiffusionSelection: _diffusionPreview.hasSelection,
            developmentBypass: widget.developmentBypass,
            costExclTax: _costFor(
              durationLabel: _planningData.durationLabel ?? '1 semaine',
            ),
            pricingReference: _publishedPricingReference,
            pricingError: _publishedPricingError,
            durationPrices: _durationPrices,
            discountPercent: _publishedDiscountPercent,
            payableExclTaxCents: _payableCentsFor(
              _planningData.durationLabel ?? '1 semaine',
            ),
            initialPlanning: _planningData,
            onPlanningChanged: _setPlanningData,
            requestedScope: _requestedScope,
            activityType: _activityType,
          ),
        ];
      case 4:
        return [
          QuoteOrderSection(
            user: widget.user,
            requestId: _requestId,
            radiusKm: _advertisingRadiusKm,
            diffusionType: _diffusionPreview.type,
            planning: _planningData,
            costExclTax: _costFor(
              durationLabel: _planningData.durationLabel ?? '1 semaine',
            ),
            durationPrices: _durationPrices,
            pricingReference: _publishedPricingReference,
            pricingError: _publishedPricingError,
            discountPercent: _publishedDiscountPercent,
            payableExclTaxCents: _payableCentsFor(
              _planningData.durationLabel ?? '1 semaine',
            ),
            selectedTerritory: _advertisingTerritory,
            onRadiusChanged: _setAdvertisingRadius,
            onDiffusionChanged: _setDiffusionType,
            requestedScope: _requestedScope,
            onEditStep: (oldStep) {
              final mergedStep = oldStep <= 1 ? 0 : oldStep - 1;
              _selectSection(mergedStep);
            },
          ),
        ];
      case 5:
        return [
          _StatusCard(
            icon: Icons.credit_card_outlined,
            title: 'PAIEMENT SÉCURISÉ',
            description: _publishedPricingReference == null ||
                    !_planningData.isComplete
                ? 'La grille des six rayons doit être publiée et '
                    'la planification confirmée avant toute commande.'
                : 'Devis et commande à établir dans Odoo. '
                    'Paiement CB par Stripe après confirmation '
                    'de la commande côté serveur.',
            status: 'PAIEMENT NON ACTIVÉ',
          ),
          const _StatusCard(
            icon: Icons.lock_outline,
            title: 'AUCUN PAIEMENT INITIÉ',
            description: 'Aucun prélèvement automatique. '
                'La campagne ne devient pas active avant '
                'la confirmation de paiement authentifiée.',
            status: 'SÉCURISÉ',
          ),
        ];
      case 6:
        return const [
          _StatusCard(
            icon: Icons.receipt_long_outlined,
            title: 'FACTURATION ÉLECTRONIQUE',
            description: 'Numérotation, intégrité et transmission seront préparées pour une plateforme agréée.',
            status: 'À RACCORDER',
          ),
          _StatusCard(
            icon: Icons.inventory_2_outlined,
            title: 'ARCHIVAGE',
            description: 'Les documents finalisés seront conservés sans écrasement et corrigés par avoir ou facture rectificative.',
            status: 'À RACCORDER',
          ),
        ];
      default:
        return [
          _StatusCard(
            icon: _sections[index].icon,
            title: _sections[index].label,
            description: 'Cette rubrique est prête à recevoir les données et règles déjà validées du parcours annonceur.',
            status: 'À COMPLÉTER',
          ),
        ];
    }
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.number,
    required this.label,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? WebColors.red : WebColors.blue;
    final iconHeight = (height - 8).clamp(0.0, 52.0).toDouble();
    final fontSize = height >= 58 ? 16.0 : 14.0;

    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              height: iconHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AdaptiveAssetImage(
                    'data/icons/fire_red_icon.svg',
                    width: iconHeight * 44 / 56,
                    height: iconHeight,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  Text(
                    '$number',
                    style: TextStyle(
                      color: color,
                      fontSize: height >= 50 ? 13 : 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
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
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    this.statusColor = const Color(0xFF6B7280),
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: WebColors.blue, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: WebColors.blue,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF4B5F97),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
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

class _AdvertiserSection {
  const _AdvertiserSection(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;
}
