import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../models/advertising_pricing_config.dart';
import '../../../widgets/adaptive_asset_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:math' as math;
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../map/map_page.dart';
import 'package:flutter/services.dart';
import 'admin_subscription_panel.dart';
import 'admin_statistics_panel.dart';

enum DashboardSpotFilter {
  none,
  all,
  secours,
  eauVerte,
  lagon,
  eauBleue,
  plage,
  naturisme,
  loisirs,
}

enum DashboardAdminFilter {
  none,
  all,
  trialRequest,
  trial,
  active,
  overdue,
  cancelled,
}

enum DashboardAdvertiserFilter {
  none,
  pending,
  all,
  active,
  expiringSoon,
  finished,
}

class _SuperAdminTileStyle {
  final String name;
  final String url;
  final List<String> subdomains;
  final int maxZoom;

  const _SuperAdminTileStyle({
    required this.name,
    required this.url,
    this.subdomains = const [],
    this.maxZoom = 19,
  });
}

class AdminDashboardPage extends StatefulWidget {
  final String adminUid;
  final String territoireId;

  const AdminDashboardPage({
    super.key,
    this.adminUid = '',
    this.territoireId = '',
  });

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);
  static const Color pendingColor = Color(0xFF6B7280);
  static const String _rescueStationType = '🚨 POSTE DE SECOURS 🚨';
  static const String _rescueStationFlagAsset =
      'data/icons/flag_red_yellow_5x3.svg';

  final MapController _mapController = MapController();
  Timer? _mapMovementTimer;
  Timer? _trialEndRefreshTimer;
  DateTime? _scheduledTrialEndDate;
  OverlayEntry? _sphotHoverOverlayEntry;
  Timer? _sphotHoverExitTimer;

  String? _sphotHoveredMarkerKey;
  String _sphotHoverText = '';
  Offset _sphotHoverAnchor = Offset.zero;
  Color _sphotHoverColor = adminColor;

  bool _showSphotEditorPanel = false;
  bool _showSauveteurEditorPanel = false;
  bool _showSauveteursManagementPanel = false;
  bool _showSurveillancePeriodsPanel = false;
  bool _showTrialSummaryPanel = false;
  bool _showSubscriptionPanel = false;
  bool _showBillingDocumentsPanel = false;
  bool _showStatisticsPanel = false;
  bool _trialSummaryDialogOpen = false;
  Future<Map<String, dynamic>>? _trialSummaryPanelFuture;
  bool _placingSphotOnMap = false;
  bool _isSavingSphot = false;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _cachedSpotsStream;

  String? _expandedSphotDropdown;
  String? _editingSphotDocId;
  String _activeTerritoireId = '';
  String _selectedSphotType = '';
  final Set<String> _selectedSphotEquipments = <String>{};
  final Set<String> _selectedSphotLabels = <String>{};
  final TextEditingController _sphotIdController = TextEditingController();
  final TextEditingController _sphotNameController = TextEditingController();
  final TextEditingController _sphotLatController = TextEditingController();

  final TextEditingController _sphotLngController = TextEditingController();

  final TextEditingController _sphotOtherEquipmentController =
      TextEditingController();

  final TextEditingController _sphotOtherLabelController =
      TextEditingController();

  final TextEditingController _sphotWebcamUrlController =
      TextEditingController();

  final TextEditingController _sauveteurNomController = TextEditingController();
  final TextEditingController _sauveteurPrenomController =
      TextEditingController();
  final TextEditingController _sauveteurDateNaissanceController =
      TextEditingController();
  final TextEditingController _sauveteurAgeController = TextEditingController();
  final TextEditingController _sauveteurAdresseController =
      TextEditingController();
  final TextEditingController _sauveteurCodePostalController =
      TextEditingController();
  final TextEditingController _sauveteurVilleController =
      TextEditingController();
  final TextEditingController _sauveteurTelephoneController =
      TextEditingController();
  final TextEditingController _sauveteurEmailController =
      TextEditingController();
  final TextEditingController _sauveteurExperienceController =
      TextEditingController();
  final TextEditingController _sauveteurObservationsController =
      TextEditingController();
  final TextEditingController _sphotOtherTypeController =
      TextEditingController();

  final Set<String> _sauveteurFonctions = <String>{};
  final Set<String> _sauveteurPostes = <String>{};
  final Set<String> _sauveteurPeriodesSurveillance = <String>{};

  bool _isSavingSauveteur = false;
  bool _sauveteurAccessGenerated = false;
  bool _sauveteurPasswordRegenerated = false;
  bool _sauveteurHasUnsavedChanges = false;
  bool _sauveteurEmailSent = false;
  String _sauveteurGeneratedLogin = '';
  String _sauveteurGeneratedPassword = '';
  String? _sauveteurCivilite;
  String? _createdSauveteurDocId;
  String? _editingSauveteurDocId;
  final Set<String> _originalSauveteurPostes = <String>{};

  static const List<String> _sauveteurFonctionChoices = <String>[
    'CHEF DE POSTE',
    'ADJOINT CHEF DE POSTE',
    'SAUVETEUR',
  ];

  static const List<String> _sphotTypeChoices = [
    _rescueStationType,
    '🏖️ PLAGE',
    '🏞️ LAC',
    '🏞️ ÉTANG',
    '🌊 FLEUVE',
    '🏞️ RIVIÈRE',
    '💧 CASCADE',
    '🧱 BARRAGE',
    '🏝️ LAGON',
    '🏊 PISCINE NATURELLE',
    '🎡 BASE DE LOISIRS',
    '🌳 PARC',
    '💧 PLAN D’EAU',
    '🏖️ NATURISME',
    'AUTRE',
  ];

  static const List<String> _sphotEquipmentChoices = [
    'AUCUN',
    '🟡 ZONE DE BAIN DÉLIMITÉE',
    '🟡 CHENAL EMBARCATION NON MOTORISÉE',
    '🟡 CHENAL EMBARCATION MOTORISÉE',
    '🏁 ZONE D’ACTIVITÉS NAUTIQUES',
    '🎠 JEUX POUR ENFANTS',
    '🏐 TERRAIN DE VOLLEY',
    '🏓 TABLE DE TENNIS DE TABLE',
    '🏋️ FITNESS AREA',
    '🗑️ POUBELLE',
    '🚯 SANS POUBELLE',
    '🚻 TOILETTES GRATUITES',
    '🚻 TOILETTES PAYANTES',
    '🅿️ PARKING GRATUIT',
    '🅿️ PARKING PAYANT',
    '🚐 PARKING CAMPING-CAR GRATUIT',
    '🚐 PARKING CAMPING-CAR PAYANT',
    '🚿 DOUCHE',
    '🤿 PLONGEOIR',
    '🛟 PLATE FORME FLOTTANTE',
    '🎠 TOBOGAN AQUATIQUE',
    '⚓ PONTON',
    'AUTRE',
  ];

  static const List<String> _sphotLabelChoices = [
    'AUCUN',
    '🟦 PAVILLON BLEU',
    '♿ HANDIPLAGE NIVEAU I',
    '♿ HANDIPLAGE NIVEAU II',
    '♿ HANDIPLAGE NIVEAU III',
    '♿ HANDIPLAGE NIVEAU IV',
    '🚭 PLAGE SANS TABAC',

    // Qualité des eaux
    'QUALITÉ DES EAUX : EXCELLENTE',
    'QUALITÉ DES EAUX : BONNE',
    'QUALITÉ DES EAUX : SUFFISANTE',
    'QUALITÉ DES EAUX : INSUFFISANTE',

    '🌿 GREEN COAST AWARD',
    '🌸 VILLES ET VILLAGES FLEURIS',
    '🏄 VILLE DE SURF',
    '🌱 NATURA 2000',
    '🏞️ PARC NATUREL RÉGIONAL DU MARAIS POITEVIN',
    '🌳 STATION VERTE',
    '🏖️ QUALITÉ TOURISME',
    '🌊 FRANCE STATION NAUTIQUE',
    '🐦 RAMSAR',
    '🌍 UNESCO',
    'AUTRE',
  ];

  static const Set<String> _sphotWaterQualityChoices = {
    'QUALITÉ DES EAUX : EXCELLENTE',
    'QUALITÉ DES EAUX : BONNE',
    'QUALITÉ DES EAUX : SUFFISANTE',
    'QUALITÉ DES EAUX : INSUFFISANTE',
  };

  static const Set<String> _sphotHandiplageChoices = {
    '♿ HANDIPLAGE NIVEAU I',
    '♿ HANDIPLAGE NIVEAU II',
    '♿ HANDIPLAGE NIVEAU III',
    '♿ HANDIPLAGE NIVEAU IV',
  };

  static const Map<String, String> _sphotLabelIconPaths = {
    '🟦 PAVILLON BLEU': 'data/icons/pavillon_bleu.png',

    '♿ HANDIPLAGE NIVEAU I': 'data/icons/handiplage1.png',

    '♿ HANDIPLAGE NIVEAU II': 'data/icons/handiplage2.png',

    '♿ HANDIPLAGE NIVEAU III': 'data/icons/handiplage3.png',

    '♿ HANDIPLAGE NIVEAU IV': 'data/icons/handiplage4.png',

    '🚭 PLAGE SANS TABAC': 'data/icons/plage_sans_tabac.png',

    'QUALITÉ DES EAUX : EXCELLENTE': 'data/icons/qualite_eau_excellente.png',

    'QUALITÉ DES EAUX : BONNE': 'data/icons/qualite_eau_bonne.png',

    'QUALITÉ DES EAUX : SUFFISANTE': 'data/icons/qualite_eau_suffisante.png',

    'QUALITÉ DES EAUX : INSUFFISANTE':
        'data/icons/qualite_eau_insuffisante.png',
  };

  static const Map<String, String> _sphotLabelDisplayNames = {
    '🟦 PAVILLON BLEU': 'PAVILLON BLEU',

    '♿ HANDIPLAGE NIVEAU I': 'HANDIPLAGE NIVEAU I',

    '♿ HANDIPLAGE NIVEAU II': 'HANDIPLAGE NIVEAU II',

    '♿ HANDIPLAGE NIVEAU III': 'HANDIPLAGE NIVEAU III',

    '♿ HANDIPLAGE NIVEAU IV': 'HANDIPLAGE NIVEAU IV',

    '🚭 PLAGE SANS TABAC': 'PLAGE SANS TABAC',
  };

  LatLng _territoryCenter = const LatLng(20, 0);
  double _territoryZoom = 2.2;

  Map<String, dynamic>? _administratorTerritoryMarkerData;

  bool _territoryCenterLoaded = false;

  int _selectedTileStyle = 0;

  static const List<_SuperAdminTileStyle> _tileStyles = [
    _SuperAdminTileStyle(
      name: 'Plan',
      url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      maxZoom: 19,
    ),
    _SuperAdminTileStyle(
      name: 'Satellite',
      url:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      maxZoom: 19,
    ),
    _SuperAdminTileStyle(
      name: 'Relief',
      url: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
      maxZoom: 17,
    ),
  ];

  Map<String, dynamic>? _selectedSpot;

  Map<String, dynamic>? _selectedAdmin;

  Map<String, dynamic>? _selectedAdvertiser;

  bool _showLegalDocumentsPanel = false;

  String? _selectedLegalDocument;
  String? _selectedLegalChapter;

  final TextEditingController _legalTitleController = TextEditingController();
  final TextEditingController _legalContentController = TextEditingController();
  final TextEditingController _legalVersionController = TextEditingController();
  final TextEditingController _legalPublicationDateController =
      TextEditingController();
  final TextEditingController _legalChangeLogController =
      TextEditingController();
  final Set<String> _modifiedDocuments = {};

  final Map<String, List<String>> _documentChapters = {
    'CGU': [],
    'Politique de confidentialité': [],
    'RGPD': [],
  };

  final Map<String, Set<String>> _modifiedChapters = {
    'CGU': {},
    'Politique de confidentialité': {},
    'RGPD': {},
  };

  String _selectedVersionDocument = 'CGU';
  String _selectedLegalStatus = 'Publié';
  String _legalLastUpdatedText = 'Non renseignée';

  bool _legalVersionSaved = false;
  bool _legalVersionButtonRed = false;
  bool _isSavingLegalVersion = false;

  bool _isSavingLegalChapter = false;
  bool _isLoadingLegalChapter = false;

  int _visibleAdvertiserCount = 0;

  final GlobalKey _advertiserFiltersKey = GlobalKey();
  final GlobalKey _legalStatusKey = GlobalKey();

  DashboardAdvertiserFilter _selectedAdvertiserFilter =
      DashboardAdvertiserFilter.pending;

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestSpotDocs = [];

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestAdminDocs = [];

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _latestAdDocs = [];

  Map<String, Map<String, dynamic>> _subscriptionsByUid = {};

  late stt.SpeechToText _speech;
  bool _isListening = false;

  int _visibleOnMapSpotCount = 0;
  int _visibleOnMapAdminCount = 0;
  int _visibleOnMapSauveteurCount = 0;
  int _sauveteurCountRequestId = 0;

  OverlayEntry? _dropdownOverlay;

  final GlobalKey _filtersKey = GlobalKey();
  final GlobalKey _sphotTypeKey = GlobalKey();
  final GlobalKey _sphotEquipmentKey = GlobalKey();
  final GlobalKey _sphotLabelKey = GlobalKey();
  final GlobalKey _adminFiltersKey = GlobalKey();
  final GlobalKey _sauveteurCiviliteKey = GlobalKey();

  final Set<DashboardSpotFilter> _selectedFilters = {DashboardSpotFilter.all};

  DashboardAdminFilter _selectedAdminFilter = DashboardAdminFilter.all;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> get _spotsStream {
    return _cachedSpotsStream ??= _buildSpotsStream();
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _buildSpotsStream() async* {
    final uid = widget.adminUid.trim();

    if (uid.isEmpty) {
      yield <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      return;
    }

    final firestore = FirebaseFirestore.instance;

    Map<String, dynamic>? administratorData;

    // Priorité à adminRequests, qui contient le territoire
    // renseigné par l’Administrateur.
    final requestSnapshot = await firestore
        .collection('adminRequests')
        .doc(uid)
        .get();

    if (requestSnapshot.exists) {
      administratorData = requestSnapshot.data();
    }

    // Sécurité pour un Administrateur déjà approuvé.
    if (administratorData == null) {
      final approvedAdminSnapshot = await firestore
          .collection('admins')
          .doc(uid)
          .get();

      if (approvedAdminSnapshot.exists) {
        administratorData = approvedAdminSnapshot.data();
      }
    }

    if (administratorData == null) {
      yield <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      return;
    }

    final territoire = Map<String, dynamic>.from(
      administratorData['territoire'] ?? <String, dynamic>{},
    );

    final territoireId = _cleanText(
      territoire['territoireId'] ??
          administratorData['territoireId'] ??
          administratorData['organisationId'] ??
          widget.territoireId,
    );

    if (territoireId.isEmpty) {
      yield <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      return;
    }

    _activeTerritoireId = territoireId;

    // Cette écoute reste maintenant active pendant toute la durée
    // d’affichage du dashboard.
    yield* firestore
        .collection('territoires')
        .doc(territoireId)
        .collection('spots')
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) => snapshot.docs);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _adminRequestsStream {
    return FirebaseFirestore.instance.collection('adminRequests').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _subscriptionsStream {
    return FirebaseFirestore.instance.collection('subscriptions').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _adRequestsStream {
    return FirebaseFirestore.instance.collection('adRequests').snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _sauveteursStream {
    return FirebaseFirestore.instance.collection('sauveteurs').snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _subscriptionStream(
    String uid,
  ) {
    return FirebaseFirestore.instance
        .collection('subscriptions')
        .doc(uid)
        .snapshots();
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371.0;

    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  String _cleanText(dynamic value) {
    return (value ?? '').toString().trim();
  }

  String _spotName(Map<String, dynamic> data) {
    return _cleanText(
      data['nomSphot'] ??
          data['nomSecours'] ??
          data['name'] ??
          data['nom'] ??
          data['title'] ??
          'SPHOT sans nom',
    );
  }

  String _normalizeType(String value) {
    return value
        .toUpperCase()
        .replaceAll('É', 'E')
        .replaceAll('È', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Î', 'I')
        .replaceAll('Ô', 'O')
        .replaceAll('Ù', 'U')
        .replaceAll('Û', 'U')
        .replaceAll('Ç', 'C')
        .trim();
  }

  String _getMarkerIconPath(Map<String, dynamic> data) {
    final type = _normalizeType((data['typeSphot'] ?? '').toString());

    if (type.contains('POSTE DE SECOURS')) {
      return 'data/icons/fire_red_icon.svg';
    }

    if (type.contains('NATURISME') || type.contains('NATURISTE')) {
      return 'data/icons/fire_skin_icon.svg';
    }

    if (type.contains('PLAGE')) {
      return 'data/icons/fire_orange_icon.svg';
    }

    if (type.contains('LAC') ||
        type.contains('ETANG') ||
        type.contains("PLAN D'EAU") ||
        type.contains('PLAN D EAU') ||
        type.contains('BARRAGE')) {
      return 'data/icons/fire_blue_icon.svg';
    }

    if (type.contains('FLEUVE') ||
        type.contains('RIVIERE') ||
        type.contains('CASCADE')) {
      return 'data/icons/fire_green_icon.svg';
    }

    if (type.contains('LAGON') || type.contains('PISCINE NATURELLE')) {
      return 'data/icons/fire_cyan_icon.svg';
    }

    // Base de loisirs, parc et autre.
    return 'data/icons/fire_orange1_icon.svg';
  }

  Color _spotTypeColor(Map<String, dynamic> data) {
    final type = _normalizeType((data['typeSphot'] ?? '').toString());
    final nature = _normalizeType((data['natureSphot'] ?? '').toString());
    final label = _normalizeType((data['labelSphot'] ?? '').toString());

    final fullType = '$type $nature $label';

    if (fullType.contains('POSTE DE SECOURS')) {
      return const Color(0xFFFF0000);
    }

    if (fullType.contains('NATURISME')) {
      return const Color(0xFFD87A5C);
    }

    if (fullType.contains('ACCES PLAGE') || fullType.contains('ACCÈS PLAGE')) {
      return const Color(0xFFFFD000);
    }

    if (fullType.contains('LAC') ||
        fullType.contains("PLAN D'EAU") ||
        fullType.contains('PLAN D EAU') ||
        fullType.contains('BARRAGE')) {
      return const Color(0xFF1E3A8A);
    }

    if (fullType.contains('FLEUVE') || fullType.contains('RIVIERE')) {
      return const Color(0xFF2E7D32);
    }

    if (fullType.contains('LAGON') || fullType.contains('PISCINE NATURELLE')) {
      return const Color(0xFF00ACC1);
    }

    return const Color(0xFFFFA500);
  }

  bool _matchesFilter(Map<String, dynamic> data) {
    if (_selectedFilters.contains(DashboardSpotFilter.none)) {
      return false;
    }
    if (_selectedFilters.contains(DashboardSpotFilter.all)) {
      return true;
    }

    return _selectedFilters.any((filter) {
      final previous = _selectedFilters;
      switch (filter) {
        case DashboardSpotFilter.none:
          return false;
        case DashboardSpotFilter.all:
          return true;
        case DashboardSpotFilter.secours:
          return _matchesFilterType(data, DashboardSpotFilter.secours);
        case DashboardSpotFilter.eauVerte:
          return _matchesFilterType(data, DashboardSpotFilter.eauVerte);
        case DashboardSpotFilter.lagon:
          return _matchesFilterType(data, DashboardSpotFilter.lagon);
        case DashboardSpotFilter.eauBleue:
          return _matchesFilterType(data, DashboardSpotFilter.eauBleue);
        case DashboardSpotFilter.plage:
          return _matchesFilterType(data, DashboardSpotFilter.plage);
        case DashboardSpotFilter.naturisme:
          return _matchesFilterType(data, DashboardSpotFilter.naturisme);
        case DashboardSpotFilter.loisirs:
          return _matchesFilterType(data, DashboardSpotFilter.loisirs);
      }
    });
  }

  bool _matchesFilterType(
    Map<String, dynamic> data,
    DashboardSpotFilter filter,
  ) {
    final type = _normalizeType((data['typeSphot'] ?? '').toString());
    final nature = _normalizeType((data['natureSphot'] ?? '').toString());
    final label = _normalizeType((data['labelSphot'] ?? '').toString());
    final fullType = '$type $nature $label';

    switch (filter) {
      case DashboardSpotFilter.all:
        return true;

      case DashboardSpotFilter.none:
        return false;

      case DashboardSpotFilter.secours:
        return fullType.contains('POSTE DE SECOURS');

      case DashboardSpotFilter.eauVerte:
        return fullType.contains('FLEUVE') || fullType.contains('RIVIERE');

      case DashboardSpotFilter.lagon:
        return fullType.contains('LAGON') ||
            fullType.contains('PISCINE NATURELLE');

      case DashboardSpotFilter.eauBleue:
        return fullType.contains('LAC') ||
            fullType.contains("PLAN D'EAU") ||
            fullType.contains('PLAN D EAU') ||
            fullType.contains('BARRAGE');

      case DashboardSpotFilter.plage:
        return fullType.contains('PLAGE') || fullType.contains('ACCES PLAGE');

      case DashboardSpotFilter.naturisme:
        return fullType.contains('NATURISME');

      case DashboardSpotFilter.loisirs:
        return fullType.contains('BASE DE LOISIRS') ||
            fullType.contains('PARC');
    }
  }

  String _filterLabel(DashboardSpotFilter filter) {
    switch (filter) {
      case DashboardSpotFilter.none:
        return 'Aucun';
      case DashboardSpotFilter.all:
        return 'Tous les SPHOTS';
      case DashboardSpotFilter.secours:
        return 'Poste de secours';
      case DashboardSpotFilter.eauVerte:
        return 'Fleuve\nRivière';
      case DashboardSpotFilter.lagon:
        return 'Lagon\nPiscine naturelle';
      case DashboardSpotFilter.eauBleue:
        return "Lac\nPlan d'eau\nBarrage";
      case DashboardSpotFilter.plage:
        return 'Plage';
      case DashboardSpotFilter.naturisme:
        return 'Naturisme';
      case DashboardSpotFilter.loisirs:
        return 'Base de loisirs\nParc';
    }
  }

  Color _filterColor(DashboardSpotFilter filter) {
    switch (filter) {
      case DashboardSpotFilter.none:
        return Colors.grey;
      case DashboardSpotFilter.all:
        return adminColor;
      case DashboardSpotFilter.secours:
        return const Color(0xFFFF0000);
      case DashboardSpotFilter.plage:
        return const Color(0xFFFFD000);
      case DashboardSpotFilter.eauBleue:
        return const Color(0xFF1E3A8A);
      case DashboardSpotFilter.eauVerte:
        return const Color(0xFF2E7D32);
      case DashboardSpotFilter.lagon:
        return const Color(0xFF00ACC1);
      case DashboardSpotFilter.naturisme:
        return const Color(0xFFD87A5C);
      case DashboardSpotFilter.loisirs:
        return const Color(0xFFFFA500);
    }
  }

  Widget _buildFiltersBlock() {
    final displayText = _selectedFilters.contains(DashboardSpotFilter.all)
        ? 'Tous les SPHOTS'
        : _selectedFilters.map(_filterLabel).join(' | ');

    return GestureDetector(
      key: _filtersKey,
      onTap: _openFiltersMenu,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Filtres SPHOTS',
          labelStyle: const TextStyle(
            color: adminColor,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                softWrap: true,
                style: const TextStyle(
                  color: adminColor,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(Icons.checklist_rounded, color: redColor, size: 22),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: redColor,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminFiltersBlock() {
    final displayText = _adminFilterLabel(_selectedAdminFilter);

    return GestureDetector(
      key: _adminFiltersKey,
      onTap: _openAdminFiltersMenu,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Filtres ADMIN',
          labelStyle: const TextStyle(
            color: adminColor,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: redColor,
                ),
              ),
            ),
            const Icon(Icons.checklist_rounded, color: redColor, size: 22),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: redColor,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

  void _openFiltersMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;

    final renderBox =
        _filtersKey.currentContext!.findRenderObject() as RenderBox;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final scrollController = ScrollController();

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, overlaySetState) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      _dropdownOverlay?.remove();
                      _dropdownOverlay = null;
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: position.dx,
                  top: position.dy + size.height - 12,
                  width: size.width,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 245),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.94),
                        border: const Border(
                          left: BorderSide(color: adminColor, width: 1.4),
                          right: BorderSide(color: adminColor, width: 1.4),
                          bottom: BorderSide(color: adminColor, width: 1.4),
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                      ),
                      child: ScrollbarTheme(
                        data: const ScrollbarThemeData(
                          thumbColor: WidgetStatePropertyAll(adminColor),
                          trackVisibility: WidgetStatePropertyAll(false),
                        ),
                        child: Scrollbar(
                          controller: scrollController,
                          thumbVisibility: true,
                          thickness: 10,
                          radius: const Radius.circular(10),
                          child: ListView(
                            controller: scrollController,
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            children: DashboardSpotFilter.values.map((filter) {
                              final selected = _selectedFilters.contains(
                                filter,
                              );

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    if (filter == DashboardSpotFilter.none) {
                                      _selectedFilters
                                        ..clear()
                                        ..add(DashboardSpotFilter.none);
                                    } else if (filter ==
                                        DashboardSpotFilter.all) {
                                      _selectedFilters
                                        ..clear()
                                        ..add(DashboardSpotFilter.all);
                                    } else {
                                      _selectedFilters.remove(
                                        DashboardSpotFilter.none,
                                      );
                                      _selectedFilters.remove(
                                        DashboardSpotFilter.all,
                                      );

                                      if (selected) {
                                        _selectedFilters.remove(filter);
                                      } else {
                                        _selectedFilters.add(filter);
                                      }

                                      if (_selectedFilters.isEmpty) {
                                        _selectedFilters.add(
                                          DashboardSpotFilter.all,
                                        );
                                      }
                                    }

                                    _selectedSpot = null;
                                    _selectedAdmin = null;
                                  });

                                  overlaySetState(() {});
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.check_box_rounded
                                            : Icons
                                                  .check_box_outline_blank_rounded,
                                        color: selected ? redColor : adminColor,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _filterLabel(filter),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: selected
                                                ? redColor
                                                : adminColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_dropdownOverlay!);
  }

  void _openAdminFiltersMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;

    final renderBox =
        _adminFiltersKey.currentContext!.findRenderObject() as RenderBox;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final scrollController = ScrollController();

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _dropdownOverlay?.remove();
                  _dropdownOverlay = null;
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: position.dx,
              top: position.dy + size.height - 12,
              width: size.width,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 190),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.94),
                    border: const Border(
                      left: BorderSide(color: adminColor, width: 1.4),
                      right: BorderSide(color: adminColor, width: 1.4),
                      bottom: BorderSide(color: adminColor, width: 1.4),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ScrollbarTheme(
                    data: const ScrollbarThemeData(
                      thumbColor: MaterialStatePropertyAll(adminColor),
                      trackVisibility: MaterialStatePropertyAll(false),
                    ),
                    child: Scrollbar(
                      controller: scrollController,
                      thumbVisibility: true,
                      thickness: 10,
                      radius: Radius.circular(10),
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: DashboardAdminFilter.values.map((filter) {
                          final selected = _selectedAdminFilter == filter;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedAdminFilter = filter;
                                _selectedSpot = null;
                                _selectedAdmin = null;
                              });

                              _dropdownOverlay?.remove();
                              _dropdownOverlay = null;
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    color: selected ? redColor : adminColor,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _adminFilterLabel(filter),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: selected ? redColor : adminColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_dropdownOverlay!);
  }

  Color _clusterBorderColor(List<Marker> markers) {
    final colors = <Color>{};

    for (final marker in markers) {
      final child = marker.child;

      if (child is DashboardSpotMarker) {
        colors.add(child.typeColor);
      }
    }

    if (colors.contains(const Color(0xFFFF0000))) {
      return const Color(0xFFFF0000);
    }

    if (colors.contains(const Color(0xFFD87A5C))) {
      return const Color(0xFFD87A5C);
    }

    if (colors.contains(const Color(0xFFFFD000))) {
      return const Color(0xFFFFD000);
    }

    if (colors.contains(const Color(0xFF1E3A8A))) {
      return const Color(0xFF1E3A8A);
    }

    if (colors.contains(const Color(0xFF2E7D32))) {
      return const Color(0xFF2E7D32);
    }

    if (colors.contains(const Color(0xFF00ACC1))) {
      return const Color(0xFF00ACC1);
    }

    return const Color(0xFFFFA500);
  }

  String _clusterIconPath(Color color) {
    if (color == const Color(0xFFFF0000)) {
      return 'data/icons/fire_red_icon.svg';
    }

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

  void _showSphotHoverLabel({
    required String markerKey,
    required String label,
    required Color color,
    required BuildContext markerContext,
  }) {
    _sphotHoverExitTimer?.cancel();
    _sphotHoverExitTimer = null;

    final renderObject = markerContext.findRenderObject();

    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }

    final markerTopLeft = renderObject.localToGlobal(Offset.zero);

    _sphotHoveredMarkerKey = markerKey;
    _sphotHoverText = label;
    _sphotHoverColor = color;

    // Position sous la pointe du marker.
    _sphotHoverAnchor = Offset(
      markerTopLeft.dx + (renderObject.size.width / 2),
      markerTopLeft.dy + renderObject.size.height - 6,
    );

    if (_sphotHoverOverlayEntry != null) {
      _sphotHoverOverlayEntry!.markNeedsBuild();
      return;
    }

    _sphotHoverOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final viewportSize = MediaQuery.sizeOf(overlayContext);

        const labelWidth = 320.0;

        final maximumLeft = math.max(8.0, viewportSize.width - labelWidth - 8);

        final labelLeft = math
            .min(
              math.max(_sphotHoverAnchor.dx - (labelWidth / 2), 8.0),
              maximumLeft,
            )
            .toDouble();

        return Positioned(
          left: labelLeft,
          top: _sphotHoverAnchor.dy,
          width: labelWidth,
          child: IgnorePointer(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    _sphotHoverText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _sphotHoverColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_sphotHoverOverlayEntry!);
  }

  void _keepSphotHoverLabel(String markerKey) {
    if (_sphotHoveredMarkerKey != markerKey) {
      return;
    }

    _sphotHoverExitTimer?.cancel();
    _sphotHoverExitTimer = null;
  }

  void _scheduleSphotHoverLabelRemoval(String markerKey) {
    if (_sphotHoveredMarkerKey != markerKey) {
      return;
    }

    _sphotHoverExitTimer?.cancel();

    _sphotHoverExitTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _sphotHoveredMarkerKey == markerKey) {
        _removeSphotHoverLabel();
      }
    });
  }

  void _removeSphotHoverLabel() {
    _sphotHoverExitTimer?.cancel();
    _sphotHoverExitTimer = null;
    _sphotHoveredMarkerKey = null;

    final entry = _sphotHoverOverlayEntry;

    if (entry == null) {
      return;
    }

    _sphotHoverOverlayEntry = null;
    entry.remove();
    entry.dispose();
  }

  Marker _buildSpotMarker(Map<String, dynamic> data) {
    final lat = _toDouble(data['sphotLat']);
    final lng = _toDouble(data['sphotLng']);
    final name = _spotName(data);

    final idSphot = _cleanText(data['idSphot'] ?? data['_docId']);

    final tooltipText = idSphot.isEmpty ? name : '$idSphot - $name';

    final iconPath = _getMarkerIconPath(data);

    final markerKey = 'sphot-${data['_docId'] ?? idSphot}-$lat-$lng';

    return Marker(
      point: LatLng(lat, lng),
      width: 46,
      height: 46,
      alignment: const Alignment(0, -0.9),
      child: Builder(
        builder: (markerContext) {
          return MouseRegion(
            opaque: true,
            cursor: SystemMouseCursors.click,
            onEnter: (_) {
              _showSphotHoverLabel(
                markerKey: markerKey,
                label: tooltipText,
                color: _spotTypeColor(data),
                markerContext: markerContext,
              );
            },
            onHover: (_) {
              _keepSphotHoverLabel(markerKey);
            },
            onExit: (_) {
              _scheduleSphotHoverLabelRemoval(markerKey);
            },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) {
                _removeSphotHoverLabel();
                _loadSphotInEditor(data);
              },
              child: DashboardSpotMarker(
                data: data,
                name: name,
                iconPath: iconPath,
                typeColor: _spotTypeColor(data),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _selectedSpotCard() {
    final spot = _selectedSpot;

    if (spot == null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.25)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.tune, size: 18, color: Colors.grey),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cliquez sur un SPHOT pour afficher ses informations',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final name = _spotName(spot);
    final type = _cleanText(spot['typeSphot'] ?? 'Type non renseigné');
    final ville = _cleanText(spot['ville'] ?? 'Ville non renseignée');
    final departement = _cleanText(
      spot['departement'] ?? 'Département non renseigné',
    );
    final telephone = _cleanText(spot['telephonePoste'] ?? 'Non renseigné');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _spotTypeColor(spot).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _spotTypeColor(spot), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 3,
            softWrap: true,
            overflow: TextOverflow.fade,
            style: TextStyle(
              color: _spotTypeColor(spot),
              fontSize: 17,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          _spotInfoLine('Type', type),
          _spotInfoLine('Ville', ville),
          _spotInfoLine('Département', departement),

          if (_normalizeType(type).contains('POSTE DE SECOURS'))
            _spotInfoLine('Téléphone', telephone),
        ],
      ),
    );
  }

  Widget _spotInfoLine(
    String label,
    String value, {
    double labelWidth = 95,
    double bottomPadding = 4,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              '$label :',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _adminFilterLabel(DashboardAdminFilter filter) {
    switch (filter) {
      case DashboardAdminFilter.none:
        return 'Aucun';

      case DashboardAdminFilter.all:
        return 'Toutes';

      case DashboardAdminFilter.trialRequest:
        return "En demande d'essai";

      case DashboardAdminFilter.trial:
        return 'En essai';

      case DashboardAdminFilter.active:
        return 'Actives';

      case DashboardAdminFilter.overdue:
        return 'En retard';

      case DashboardAdminFilter.cancelled:
        return 'Résiliées';
    }
  }

  bool _matchesAdminFilter(Map<String, dynamic> data) {
    if (_selectedAdminFilter == DashboardAdminFilter.none) {
      return false;
    }

    if (_selectedAdminFilter == DashboardAdminFilter.all) {
      return true;
    }

    final uid = _cleanText(data['uid']);
    final subscription = _subscriptionsByUid[uid];

    switch (_selectedAdminFilter) {
      case DashboardAdminFilter.none:
        return false;

      case DashboardAdminFilter.all:
        return true;

      case DashboardAdminFilter.trialRequest:
        final status = _cleanText(data['status']).toLowerCase();
        return status == 'pending';

      case DashboardAdminFilter.trial:
        if (subscription == null) return false;
        return _cleanText(subscription['status']) == 'trial';

      case DashboardAdminFilter.active:
        if (subscription == null) return false;
        return _cleanText(subscription['status']) == 'active';

      case DashboardAdminFilter.overdue:
        if (subscription == null) return false;
        return _cleanText(subscription['status']) == 'overdue';

      case DashboardAdminFilter.cancelled:
        if (subscription == null) return false;
        return _cleanText(subscription['status']) == 'cancelled';
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'Non renseignée';

    if (value is Timestamp) {
      final date = value.toDate();
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }

    return value.toString();
  }

  void _scheduleTrialEndRefresh(DateTime? trialEndDate) {
    if (_scheduledTrialEndDate == trialEndDate) return;

    _scheduledTrialEndDate = trialEndDate;
    _trialEndRefreshTimer?.cancel();

    if (trialEndDate == null) return;

    final delay = trialEndDate.difference(DateTime.now());
    if (delay <= Duration.zero) return;

    _trialEndRefreshTimer = Timer(delay + const Duration(seconds: 1), () {
      if (!mounted) return;
      _scheduledTrialEndDate = null;
      setState(() {});
    });
  }

  Widget _selectedAdminCard() {
    final admin = _selectedAdmin;
    if (admin == null) return const SizedBox.shrink();

    final uid = _cleanText(admin['uid']);
    final territoire = Map<String, dynamic>.from(admin['territoire'] ?? {});
    final structure = Map<String, dynamic>.from(admin['structure'] ?? {});
    final profile = Map<String, dynamic>.from(admin['profile'] ?? {});

    final mairie = _cleanText(
      structure['nom'] ?? admin['nomStructure'] ?? 'ADMIN',
    );

    final email = _cleanText(profile['email'] ?? admin['email']);
    final siret = _cleanText(structure['siret'] ?? admin['siret']);
    final ville = _cleanText(territoire['ville']);
    final departement = _cleanText(territoire['departement']);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(uid)
          .get(),
      builder: (context, snapshot) {
        final subscription = snapshot.data?.data() ?? {};

        final status = _cleanText(subscription['status'] ?? admin['status']);

        final trialStart = subscription['trialStartDate'];
        final trialEnd = subscription['trialEndDate'];
        final subscriptionStart = subscription['subscriptionStartDate'];
        final subscriptionEnd = subscription['subscriptionEndDate'];

        final numberOfSpots = _toDouble(
          subscription['numberOfRescueStations'],
        ).toInt();

        final pricePerSpot = _toDouble(subscription['pricePerStationExclTax']);

        final totalPrice = numberOfSpots * pricePerSpot;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: adminColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: adminColor, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mairie,
                style: const TextStyle(
                  color: adminColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),

              _spotInfoLine(
                'Responsable',
                _cleanText(
                  profile['nomAffiche'] ??
                      admin['nomResponsable'] ??
                      admin['prenom'] ??
                      '',
                ),
              ),
              _spotInfoLine('Email', email),
              _spotInfoLine('Statut', status),
              _spotInfoLine(
                'Date départ',
                _formatDate(trialStart ?? subscriptionStart),
              ),
              _spotInfoLine(
                'Date fin',
                _formatDate(trialEnd ?? subscriptionEnd),
              ),
              _spotInfoLine('SPHOTS', '$numberOfSpots'),
              _spotInfoLine(
                'Coût',
                '${totalPrice.toStringAsFixed(0)} € HT / an',
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editAdminTerritoryLink({
    required String fieldName,
    required String dialogTitle,
    required String currentValue,
  }) async {
    final controller = TextEditingController(text: currentValue);

    final newValue = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            dialogTitle,
            style: const TextStyle(
              color: redColor,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Adresse internet',
                hintText: 'https://www.exemple.fr',
                prefixIcon: const Icon(Icons.link_rounded, color: adminColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                'ANNULER',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: adminColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text(
                'ENREGISTRER',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newValue == null) {
      return;
    }

    final uid = widget.adminUid.trim();

    if (uid.isEmpty) {
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;

      final requestReference = firestore.collection('adminRequests').doc(uid);

      final adminReference = firestore.collection('admins').doc(uid);

      final requestSnapshot = await requestReference.get();

      final adminSnapshot = await adminReference.get();

      final updateData = <String, dynamic>{
        'territoire.$fieldName': newValue,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (requestSnapshot.exists) {
        await requestReference.update(updateData);
      }

      if (adminSnapshot.exists) {
        await adminReference.update(updateData);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        if (_selectedAdmin != null) {
          final updatedAdmin = Map<String, dynamic>.from(_selectedAdmin!);

          final updatedTerritory = Map<String, dynamic>.from(
            updatedAdmin['territoire'] ?? <String, dynamic>{},
          );

          updatedTerritory[fieldName] = newValue;
          updatedAdmin['territoire'] = updatedTerritory;

          _selectedAdmin = updatedAdmin;
        }

        if (_administratorTerritoryMarkerData != null) {
          final updatedMarkerData = Map<String, dynamic>.from(
            _administratorTerritoryMarkerData!,
          );

          final updatedMarkerTerritory = Map<String, dynamic>.from(
            updatedMarkerData['territoire'] ?? <String, dynamic>{},
          );

          updatedMarkerTerritory[fieldName] = newValue;

          updatedMarkerData['territoire'] = updatedMarkerTerritory;

          _administratorTerritoryMarkerData = updatedMarkerData;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modification enregistrée.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’enregistrer : $error')),
      );
    }
  }

  Future<void> _editAdminReferent({
    required String currentFirstName,
    required String currentLastName,
    required String currentFunction,
    required String currentEmail,
    required String currentPhone,
  }) async {
    final firstNameController = TextEditingController(text: currentFirstName);

    final lastNameController = TextEditingController(text: currentLastName);

    final functionController = TextEditingController(text: currentFunction);

    final emailController = TextEditingController(text: currentEmail);

    final phoneController = TextEditingController(text: currentPhone);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            "MODIFIER L'ADMINISTRATEUR",
            style: TextStyle(color: redColor, fontWeight: FontWeight.w900),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: firstNameController,
                          style: const TextStyle(color: adminColor),
                          decoration: const InputDecoration(
                            labelText: 'Prénom',
                            labelStyle: TextStyle(color: adminColor),
                            floatingLabelStyle: TextStyle(color: adminColor),
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: lastNameController,
                          style: const TextStyle(color: adminColor),
                          decoration: const InputDecoration(
                            labelText: 'Nom',
                            labelStyle: TextStyle(color: adminColor),
                            floatingLabelStyle: TextStyle(color: adminColor),
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: functionController,
                    style: const TextStyle(color: adminColor),
                    decoration: const InputDecoration(
                      labelText: 'Fonction',
                      labelStyle: TextStyle(color: adminColor),
                      floatingLabelStyle: TextStyle(color: adminColor),
                      prefixIcon: Icon(Icons.work_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    style: const TextStyle(color: adminColor),
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      labelStyle: TextStyle(color: adminColor),
                      floatingLabelStyle: TextStyle(color: adminColor),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    style: const TextStyle(color: adminColor),
                    decoration: const InputDecoration(
                      labelText: 'Téléphone',
                      labelStyle: TextStyle(color: adminColor),
                      floatingLabelStyle: TextStyle(color: adminColor),
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('ANNULER'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: adminColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop({
                  'prenom': firstNameController.text.trim(),
                  'nom': lastNameController.text.trim(),
                  'fonction': functionController.text.trim(),
                  'email': emailController.text.trim(),
                  'telephone': phoneController.text.trim(),
                });
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text(
                'ENREGISTRER',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    firstNameController.dispose();
    lastNameController.dispose();
    functionController.dispose();
    emailController.dispose();
    phoneController.dispose();

    if (result == null) {
      return;
    }

    final uid = widget.adminUid.trim();

    if (uid.isEmpty) {
      return;
    }

    final updateData = <String, dynamic>{
      'profile.prenom': result['prenom'],
      'profile.prenomAffiche': result['prenom'],
      'profile.nom': result['nom'],
      'profile.nomAffiche': result['nom'],
      'profile.fonction': result['fonction'],
      'profile.email': result['email'],
      'profile.telephone': result['telephone'],
      'prenomResponsable': result['prenom'],
      'nomResponsable': result['nom'],
      'fonction': result['fonction'],
      'email': result['email'],
      'telephone': result['telephone'],
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final firestore = FirebaseFirestore.instance;

      final requestReference = firestore.collection('adminRequests').doc(uid);

      final adminReference = firestore.collection('admins').doc(uid);

      final requestSnapshot = await requestReference.get();

      final adminSnapshot = await adminReference.get();

      if (requestSnapshot.exists) {
        await requestReference.update(updateData);
      }

      if (adminSnapshot.exists) {
        await adminReference.update(updateData);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        void updateAdminMap(Map<String, dynamic> source) {
          final updatedProfile = Map<String, dynamic>.from(
            source['profile'] ?? <String, dynamic>{},
          );

          updatedProfile['prenom'] = result['prenom'];
          updatedProfile['prenomAffiche'] = result['prenom'];
          updatedProfile['nom'] = result['nom'];
          updatedProfile['nomAffiche'] = result['nom'];
          updatedProfile['fonction'] = result['fonction'];
          updatedProfile['email'] = result['email'];
          updatedProfile['telephone'] = result['telephone'];

          source['profile'] = updatedProfile;
          source['prenomResponsable'] = result['prenom'];
          source['nomResponsable'] = result['nom'];
          source['fonction'] = result['fonction'];
          source['email'] = result['email'];
          source['telephone'] = result['telephone'];
        }

        if (_selectedAdmin != null) {
          final updatedAdmin = Map<String, dynamic>.from(_selectedAdmin!);

          updateAdminMap(updatedAdmin);
          _selectedAdmin = updatedAdmin;
        }

        if (_administratorTerritoryMarkerData != null) {
          final updatedMarker = Map<String, dynamic>.from(
            _administratorTerritoryMarkerData!,
          );

          updateAdminMap(updatedMarker);

          _administratorTerritoryMarkerData = updatedMarker;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Référent administratif modifié.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’enregistrer : $error')),
      );
    }
  }

  Widget _buildAdminDetailPanel() {
    final admin = _selectedAdmin;

    if (admin == null) {
      return const SizedBox.shrink();
    }

    final territoire = Map<String, dynamic>.from(
      admin['territoire'] ?? <String, dynamic>{},
    );

    final structure = Map<String, dynamic>.from(
      admin['structure'] ?? <String, dynamic>{},
    );

    final profile = Map<String, dynamic>.from(
      admin['profile'] ?? <String, dynamic>{},
    );

    final organisationName = _cleanText(
      structure['nom'] ??
          admin['nomStructure'] ??
          admin['organisation'] ??
          territoire['ville'] ??
          'COLLECTIVITÉ',
    );

    final structureType = _cleanText(
      structure['type'] ??
          structure['typeStructure'] ??
          admin['typeStructure'] ??
          admin['organisationType'],
    );

    final siret = _cleanText(structure['siret'] ?? admin['siret']);

    String siren = _cleanText(structure['siren'] ?? admin['siren']);

    if (siren.isEmpty && siret.isNotEmpty) {
      final digitsOnly = siret.replaceAll(RegExp(r'[^0-9]'), '');

      if (digitsOnly.length >= 9) {
        siren = digitsOnly.substring(0, 9);
      }
    }

    String firstValidIdentityValue(List<dynamic> values) {
      const forbiddenValues = {'monsieur', 'madame', 'm.', 'mme', 'mr', 'mrs'};

      for (final rawValue in values) {
        final value = _cleanText(rawValue);

        if (value.isEmpty) {
          continue;
        }

        if (forbiddenValues.contains(value.toLowerCase())) {
          continue;
        }

        return value;
      }

      return '';
    }

    final prenom = firstValidIdentityValue([
      profile['prenomAffiche'],
      profile['prenom'],
      admin['prenomResponsable'],
      admin['prenom'],
      admin['firstName'],
    ]);

    final nom = firstValidIdentityValue([
      profile['nomAffiche'],
      profile['nom'],
      admin['nomResponsable'],
      admin['nom'],
      admin['lastName'],
    ]);

    final identiteAdministrateur = [prenom, nom]
        .where((value) {
          return value.trim().isNotEmpty;
        })
        .join(' ');

    final fonction = _cleanText(
      profile['fonction'] ?? profile['role'] ?? admin['fonction'],
    );

    final email = _cleanText(profile['email'] ?? admin['email']);

    final telephone = _cleanText(
      profile['telephone'] ?? profile['phone'] ?? admin['telephone'],
    );

    final logoUrl = _cleanText(territoire['logoVille'] ?? admin['logoVille']);

    final siteInternetVille = _cleanText(
      territoire['siteInternetVille'] ??
          territoire['siteInternet'] ??
          structure['siteInternet'],
    );

    final regulatoryDocumentUrl = _cleanText(
      territoire['reglementsBaignade'] ??
          territoire['reglementBaignade'] ??
          territoire['arretesMunicipaux'] ??
          territoire['siteReglements'],
    );

    Widget buildInternetTile({
      required IconData icon,
      required String label,
      required String url,
      required VoidCallback onEdit,
    }) {
      final hasUrl = url.trim().isNotEmpty;

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
        decoration: BoxDecoration(
          color: adminColor.withOpacity(0.055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: adminColor.withOpacity(0.30), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: adminColor.withOpacity(0.25)),
              ),
              child: Icon(icon, color: adminColor, size: 21),
            ),

            const SizedBox(width: 11),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: adminColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.15,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    hasUrl ? url : 'Non renseigné',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: adminColor,
                      decoration: TextDecoration.none,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),

            IconButton(
              tooltip: 'Modifier',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded, color: redColor, size: 19),
            ),
          ],
        ),
      );
    }

    return Material(
  color: Colors.transparent,
  child: Container(
    width: 420,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.40), width: 1.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ============================================================
            // EN-TÊTE
            // ============================================================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
              decoration: BoxDecoration(
                color: adminColor.withOpacity(0.07),
                border: Border(
                  bottom: BorderSide(color: adminColor.withOpacity(0.20)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: adminColor, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: logoUrl.isEmpty
                          ? const Icon(
                              Icons.account_balance_rounded,
                              color: adminColor,
                              size: 34,
                            )
                          : Image.network(
                              logoUrl,
                              key: ValueKey<String>(
                                'admin-detail-logo-$logoUrl',
                              ),
                              width: 52,
                              height: 52,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              webHtmlElementStrategy:
                                  WebHtmlElementStrategy.prefer,
                              errorBuilder:
                                  (
                                    BuildContext context,
                                    Object error,
                                    StackTrace? stackTrace,
                                  ) {
                                    return const Icon(
                                      Icons.account_balance_rounded,
                                      color: adminColor,
                                      size: 34,
                                    );
                                  },
                            ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Text(
                      organisationName.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: redColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.10,
                      ),
                    ),
                  ),

                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () {
                      setState(() {
                        _selectedAdmin = null;
                      });
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: adminColor,
                      size: 27,
                    ),
                  ),
                ],
              ),
            ),

            // ============================================================
            // CONTENU
            // ============================================================
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ====================================================
                    // ADMINISTRATION
                    // ====================================================
                    _adminPanelSectionTitle(
                      icon: Icons.account_balance_rounded,
                      title: 'ADMINISTRATION',
                    ),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 17, 16, 17),
                      decoration: BoxDecoration(
                        color: adminColor.withOpacity(0.055),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: adminColor.withOpacity(0.24),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: adminColor.withOpacity(0.30),
                              ),
                            ),
                            child: const Icon(
                              Icons.account_balance_rounded,
                              color: adminColor,
                              size: 25,
                            ),
                          ),

                          const SizedBox(width: 16),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (structureType.isNotEmpty) ...[
                                  Text(
                                    structureType.toUpperCase(),
                                    style: const TextStyle(
                                      color: adminColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                Text(
                                  organisationName.toUpperCase(),
                                  style: const TextStyle(
                                    color: adminColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.15,
                                  ),
                                ),

                                if (siren.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 58,
                                        child: Text(
                                          'SIREN',
                                          style: TextStyle(
                                            color: adminColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          siren,
                                          style: const TextStyle(
                                            color: adminColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                if (siret.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 58,
                                        child: Text(
                                          'SIRET',
                                          style: TextStyle(
                                            color: adminColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          siret,
                                          style: const TextStyle(
                                            color: adminColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // ====================================================
                    // ADMINISTRATEUR
                    // ====================================================
                    _adminPanelSectionTitle(
                      icon: Icons.person_outline_rounded,
                      title: 'ADMINISTRATEUR',
                    ),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: adminColor.withOpacity(0.055),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: adminColor.withOpacity(0.20)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: adminColor.withOpacity(0.35),
                              ),
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              color: adminColor,
                              size: 24,
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        identiteAdministrateur.isNotEmpty
                                            ? identiteAdministrateur
                                            : 'Nom et prénom non renseignés',
                                        style: const TextStyle(
                                          color: adminColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          height: 1.15,
                                        ),
                                      ),
                                    ),

                                    IconButton(
                                      tooltip: 'Modifier l’administrateur',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        _editAdminReferent(
                                          currentFirstName: prenom,
                                          currentLastName: nom,
                                          currentFunction: fonction,
                                          currentEmail: email,
                                          currentPhone: telephone,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        color: redColor,
                                        size: 19,
                                      ),
                                    ),
                                  ],
                                ),

                                if (fonction.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    fonction,
                                    style: const TextStyle(
                                      color: adminColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ],

                                if (email.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.email_outlined,
                                        color: adminColor,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          email,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: adminColor,
                                            decoration: TextDecoration.none,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                if (telephone.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.phone_outlined,
                                        color: adminColor,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          telephone,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: adminColor,
                                            decoration: TextDecoration.none,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ====================================================
                    // ADRESSES INTERNET
                    // ====================================================
                    _adminPanelSectionTitle(
                      icon: Icons.public_rounded,
                      title: 'ADRESSES INTERNET',
                    ),

                    buildInternetTile(
                      icon: Icons.language_rounded,
                      label: 'SITE OFFICIEL',
                      url: siteInternetVille,
                      onEdit: () {
                        _editAdminTerritoryLink(
                          fieldName: 'siteInternetVille',
                          dialogTitle:
                              "Modifier l'adresse internet du site officiel",
                          currentValue: siteInternetVille,
                        );
                      },
                    ),

                    buildInternetTile(
                      icon: Icons.menu_book_rounded,
                      label: 'RÈGLEMENT DE BAIGNADE',
                      url: regulatoryDocumentUrl,
                      onEdit: () {
                        _editAdminTerritoryLink(
                          fieldName: 'reglementsBaignade',
                          dialogTitle:
                              "Modifier l'adresse internet du règlement de baignade",
                          currentValue: regulatoryDocumentUrl,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
              ),
    ),
  ),
);
}

  Future<Map<String, dynamic>> _loadTrialSummaryData() async {
    final territoireId = _resolvedTerritoireId;

    if (territoireId.isEmpty) {
      throw StateError('Aucun territoire associé à cet espace administrateur.');
    }

    final territoryReference = FirebaseFirestore.instance
        .collection('territoires')
        .doc(territoireId);

    final spotsSnapshot = await territoryReference.collection('spots').get();

    final periodsSnapshot = await territoryReference
        .collection('periodesSurveillance')
        .get();

    final sauveteursSnapshot = await territoryReference
        .collection('sauveteurs')
        .get();
    final sauveteursById = <String, Map<String, dynamic>>{
      for (final document in sauveteursSnapshot.docs)
        document.id: <String, dynamic>{
          ...document.data(),
          '_docId': document.id,
        },
    };

    final periodsById = <String, Map<String, dynamic>>{
      for (final document in periodsSnapshot.docs)
        document.id: <String, dynamic>{
          ...document.data(),
          '_docId': document.id,
        },
    };

    final monitoredSpots = <Map<String, dynamic>>[];
    final otherSpots = <Map<String, dynamic>>[];

    for (final spotDocument in spotsSnapshot.docs) {
      final spot = <String, dynamic>{
        ...spotDocument.data(),
        '_docId': spotDocument.id,
      };

      final isRescueStation =
          spot['isPosteSecours'] == true ||
          _cleanText(spot['typeSphot']) == '🚨 POSTE DE SECOURS 🚨';

      if (!isRescueStation) {
        otherSpots.add(spot);
        continue;
      }

      final assignedSnapshot = await spotDocument.reference
          .collection('sauveteursAffectes')
          .get();

      final assignedSauveteurs = assignedSnapshot.docs.map((document) {
        final assignedData = document.data();

        final sauveteurId = _cleanText(
          assignedData['sauveteurId'] ?? document.id,
        );

        final fullData = sauveteursById[sauveteurId] ?? <String, dynamic>{};

        return <String, dynamic>{
          ...fullData,
          ...assignedData,
          '_docId': sauveteurId,
        };
      }).toList();

      final periodIds = <String>{};

      for (final sauveteur in assignedSauveteurs) {
        final rawPeriods = sauveteur['periodesSurveillance'];

        if (rawPeriods is Iterable) {
          periodIds.addAll(
            rawPeriods
                .map((value) => _cleanText(value))
                .where((value) => value.isNotEmpty),
          );
        }
      }

      final spotPeriods =
          periodIds
              .map((periodId) => periodsById[periodId])
              .whereType<Map<String, dynamic>>()
              .toList()
            ..sort((first, second) {
              final firstDate = first['startDate'];
              final secondDate = second['startDate'];

              if (firstDate is Timestamp && secondDate is Timestamp) {
                return firstDate.compareTo(secondDate);
              }

              return 0;
            });

      monitoredSpots.add({
        'spot': spot,
        'periods': spotPeriods,
        'sauveteurs': assignedSauveteurs,
      });
    }

    monitoredSpots.sort((first, second) {
      final firstSpot = Map<String, dynamic>.from(first['spot'] ?? {});
      final secondSpot = Map<String, dynamic>.from(second['spot'] ?? {});

      return _spotName(firstSpot).compareTo(_spotName(secondSpot));
    });

    otherSpots.sort((first, second) {
      return _spotName(first).compareTo(_spotName(second));
    });

    return {
      'territoireId': territoireId,
      'monitoredSpots': monitoredSpots,
      'otherSpots': otherSpots,
      'periodCount': periodsSnapshot.docs.length,
      'sauveteurCount': sauveteursSnapshot.docs.length,
    };
  }

  String _trialSeasonStatus(List<Map<String, dynamic>> periods) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    bool hasCurrentPeriod = false;
    bool hasFuturePeriod = false;
    bool hasPastPeriod = false;

    for (final period in periods) {
      final startValue = period['startDate'];
      final endValue = period['endDate'];

      if (startValue is! Timestamp || endValue is! Timestamp) {
        continue;
      }

      final rawStart = startValue.toDate();
      final rawEnd = endValue.toDate();

      final start = DateTime(rawStart.year, rawStart.month, rawStart.day);

      final end = DateTime(rawEnd.year, rawEnd.month, rawEnd.day);

      if (!today.isBefore(start) && !today.isAfter(end)) {
        hasCurrentPeriod = true;
      } else if (start.isAfter(today)) {
        hasFuturePeriod = true;
      } else if (end.isBefore(today)) {
        hasPastPeriod = true;
      }
    }

    if (hasCurrentPeriod) {
      return 'SURVEILLANCE EN COURS';
    }

    if (hasFuturePeriod) {
      return 'OUVERTURE PROGRAMMÉE';
    }

    if (hasPastPeriod) {
      return 'HORS SAISON';
    }

    return 'AUCUNE OUVERTURE PROGRAMMÉE';
  }

  Color _trialSeasonStatusColor(String status) {
    switch (status) {
      case 'SURVEILLANCE EN COURS':
        return const Color(0xFF16A34A);
      case 'OUVERTURE PROGRAMMÉE':
        return const Color(0xFFF59E0B);
      case 'HORS SAISON':
        return const Color(0xFF64748B);
      default:
        return redColor;
    }
  }

  Widget _buildTrialPeriodCard(Map<String, dynamic> period) {
    final periodId = _cleanText(period['_docId'] ?? period['id']);

    final name = _cleanText(period['name'] ?? 'PÉRIODE').toUpperCase();

    final startValue = period['startDate'];
    final endValue = period['endDate'];

    final startDate = startValue is Timestamp
        ? _formatSurveillanceDate(startValue.toDate())
        : '--/--/----';

    final endDate = endValue is Timestamp
        ? _formatSurveillanceDate(endValue.toDate())
        : '--/--/----';

    final startTime =
        _parseSurveillanceTime(period['startHour']) ??
        const TimeOfDay(hour: 0, minute: 0);

    final endTime =
        _parseSurveillanceTime(period['endHour']) ??
        const TimeOfDay(hour: 0, minute: 0);

    final secondStartTime = _parseSurveillanceTime(period['secondStartHour']);

    final secondEndTime = _parseSurveillanceTime(period['secondEndHour']);

    final startHour = _cleanText(
      period['startHour'] ?? '--:--',
    ).replaceFirst(':', 'h');

    final endHour = _cleanText(
      period['endHour'] ?? '--:--',
    ).replaceFirst(':', 'h');

    final secondStartHour = _cleanText(
      period['secondStartHour'],
    ).replaceFirst(':', 'h');

    final secondEndHour = _cleanText(
      period['secondEndHour'],
    ).replaceFirst(':', 'h');

    final hasSecondSlot =
        secondStartHour.isNotEmpty && secondEndHour.isNotEmpty;

    final hoursDescription = hasSecondSlot
        ? 'DE $startHour À $endHour — '
              'DE $secondStartHour À $secondEndHour'
        : 'DE $startHour À $endHour';

    final editablePeriod =
        periodId.isNotEmpty && startValue is Timestamp && endValue is Timestamp
        ? _DashboardSurveillancePeriod(
            id: periodId,
            name: name,
            startDate: startValue.toDate(),
            endDate: endValue.toDate(),
            startHour: startTime,
            endHour: endTime,
            secondStartHour: secondStartTime,
            secondEndHour: secondEndTime,
          )
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -1.5),
                      child: const Text(
                        '•',
                        style: TextStyle(
                          color: adminColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: adminColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Modifier la période',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: editablePeriod == null
                    ? null
                    : () {
                        _openSurveillancePeriodDialog(period: editablePeriod);
                      },
                icon: const Icon(
                  Icons.edit_rounded,
                  color: adminColor,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Supprimer la période',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: editablePeriod == null
                    ? null
                    : () {
                        _deleteSurveillancePeriod(editablePeriod);
                      },
                icon: const Icon(
                  Icons.delete_rounded,
                  color: redColor,
                  size: 18,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DU $startDate AU $endDate',
                  style: const TextStyle(
                    color: adminColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hoursDescription,
                  style: const TextStyle(
                    color: adminColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialSauveteurManagementRow({
    required Map<String, dynamic> sauveteur,
    required List<Map<String, dynamic>> periods,
  }) {
    final sauveteurId = _cleanText(
      sauveteur['_docId'] ?? sauveteur['sauveteurId'],
    );

    final prenom = _cleanText(sauveteur['prenom']);

    final nom = _cleanText(sauveteur['nom']).toUpperCase();

    final identity = [prenom, nom].where((value) => value.isNotEmpty).join(' ');

    final rawFunctions = sauveteur['fonctions'];

    final functions = rawFunctions is Iterable
        ? rawFunctions
              .map((value) => _cleanText(value))
              .where((value) => value.isNotEmpty)
              .join(', ')
        : _cleanText(rawFunctions);

    final rawPeriodIds = sauveteur['periodesSurveillance'];

    final periodIds = rawPeriodIds is Iterable
        ? rawPeriodIds
              .map((value) => _cleanText(value))
              .where((value) => value.isNotEmpty)
              .toSet()
        : <String>{};

    final periodTitles = periods
        .where((period) => periodIds.contains(_cleanText(period['_docId'])))
        .map((period) => _cleanText(period['name'] ?? 'PÉRIODE').toUpperCase())
        .where((title) => title.isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '• ${identity.isEmpty ? 'Sauveteur' : identity}',
                  style: const TextStyle(
                    color: adminColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Modifier le sauveteur',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: sauveteurId.isEmpty
                    ? null
                    : () {
                        _openSauveteurForEditing(sauveteurId, sauveteur);
                      },
                icon: const Icon(
                  Icons.edit_rounded,
                  color: adminColor,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Supprimer le sauveteur',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: sauveteurId.isEmpty
                    ? null
                    : () async {
                        await _deleteSauveteur(sauveteurId, sauveteur);

                        if (!mounted) {
                          return;
                        }

                        setState(() {
                          _showTrialSummaryPanel = true;
                          _showSubscriptionPanel = false;
                          _showBillingDocumentsPanel = false;
                          _trialSummaryPanelFuture = _loadTrialSummaryData();
                        });
                      },
                icon: const Icon(
                  Icons.delete_rounded,
                  color: redColor,
                  size: 18,
                ),
              ),
            ],
          ),
          if (functions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                functions,
                style: const TextStyle(
                  color: adminColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.30,
                ),
              ),
            ),
          if (periodTitles.isNotEmpty) ...[
            const SizedBox(height: 3),
            ...periodTitles.map(
              (title) => Padding(
                padding: const EdgeInsets.only(left: 12, top: 1),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: adminColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _trialCounter({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: adminColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: adminColor.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: adminColor, size: 19),
          const SizedBox(width: 7),
          Text(
            '$value $label',
            style: const TextStyle(
              color: adminColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrialMonitoredSpotCard(Map<String, dynamic> entry) {
    final spot = Map<String, dynamic>.from(entry['spot'] ?? {});

    final periods = List<Map<String, dynamic>>.from(
      entry['periods'] ?? const [],
    );

    final sauveteurs = List<Map<String, dynamic>>.from(
      entry['sauveteurs'] ?? const [],
    );

    final idSphot = _cleanText(spot['idSphot'] ?? spot['_docId']);

    final name = _spotName(spot);
    final status = _trialSeasonStatus(periods);
    final statusColor = _trialSeasonStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: adminColor.withOpacity(0.35), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdaptiveAssetImage(
                _getMarkerIconPath(spot),
                width: 42,
                height: 42,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idSphot.isEmpty ? name : '$idSphot - $name',
                      style: const TextStyle(
                        color: adminColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Modifier le SPHOT',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  _loadSphotInEditor(spot);
                },
                icon: const Icon(
                  Icons.edit_rounded,
                  color: adminColor,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Supprimer le SPHOT',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () {
                  _deleteSphotFromSummary(spot);
                },
                icon: const Icon(
                  Icons.delete_rounded,
                  color: redColor,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Text(
            'PÉRIODES',
            style: TextStyle(
              color: redColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 1),
          if (periods.isEmpty)
            const Text(
              'Aucune période de surveillance programmée.',
              style: TextStyle(
                color: adminColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...periods.map(
              (period) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: _buildTrialPeriodCard(period),
              ),
            ),
          const SizedBox(height: 6),
          const Text(
            'SAUVETEURS AFFECTÉS',
            style: TextStyle(
              color: redColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          if (sauveteurs.isEmpty)
            const Text(
              'Aucun sauveteur actuellement affecté.',
              style: TextStyle(
                color: adminColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...sauveteurs.map(
              (sauveteur) => _buildTrialSauveteurManagementRow(
                sauveteur: sauveteur,
                periods: periods,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTrialOtherSpotTile(
    Map<String, dynamic> spot, {
    required bool showActions,
  }) {
    final idSphot = _cleanText(spot['idSphot'] ?? spot['_docId']);

    final name = _spotName(spot);

    final type = _cleanText(spot['typeSphot'] ?? 'TYPE NON RENSEIGNÉ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: adminColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          AdaptiveAssetImage(
            _getMarkerIconPath(spot),
            width: 34,
            height: 34,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  idSphot.isEmpty ? name : '$idSphot - $name',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: adminColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  type,
                  style: TextStyle(
                    color: adminColor.withOpacity(0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          if (showActions) ...[
            IconButton(
              tooltip: 'Modifier le SPHOT',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              onPressed: () {
                _loadSphotInEditor(spot);
              },
              icon: const Icon(Icons.edit_rounded, color: adminColor, size: 18),
            ),
            IconButton(
              tooltip: 'Supprimer le SPHOT',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              onPressed: () {
                _deleteSphotFromSummary(spot);
              },
              icon: const Icon(Icons.delete_rounded, color: redColor, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitTrialRequest(
    Map<String, dynamic> summary,
    VoidCallback onCompleted,
  ) async {
    final uid = widget.adminUid.trim();

    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Administrateur non identifié.'),
          backgroundColor: redColor,
        ),
      );
      return;
    }

    final monitoredSpots = List<Map<String, dynamic>>.from(
      summary['monitoredSpots'] ?? const [],
    );

    final otherSpots = List<Map<String, dynamic>>.from(
      summary['otherSpots'] ?? const [],
    );

    final firestore = FirebaseFirestore.instance;
    final requestReference = firestore.collection('adminRequests').doc(uid);

    try {
      await firestore.runTransaction((transaction) async {
        final currentSnapshot = await transaction.get(requestReference);

        final currentData = currentSnapshot.data() ?? <String, dynamic>{};

        final rawTrialRequest = currentData['trialRequest'];

        final trialRequest = rawTrialRequest is Map
            ? Map<String, dynamic>.from(rawTrialRequest)
            : <String, dynamic>{};

        final currentStatus = _cleanText(
          currentData['trialRequestStatus'] ?? trialRequest['status'],
        ).toLowerCase();

        final hasAlreadyRequested =
            currentData['trialRequestedAt'] != null ||
            trialRequest['requestedAt'] != null ||
            currentStatus.isNotEmpty;

        if (hasAlreadyRequested) {
          throw StateError('TRIAL_ALREADY_REQUESTED');
        }

        transaction.set(requestReference, {
          'trialRequestStatus': 'pending',
          'trialRequestedAt': FieldValue.serverTimestamp(),
          'trialRequest': {
            'status': 'pending',
            'trialDurationDays': 8,
            'territoireId': summary['territoireId'],
            'numberOfRescueStations': monitoredSpots.length,
            'numberOfOtherSpots': otherSpots.length,
            'numberOfSurveillancePeriods': summary['periodCount'] ?? 0,
            'numberOfLifeguards': summary['sauveteurCount'] ?? 0,
            'requestedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      if (!mounted) {
        return;
      }

      onCompleted();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Votre demande d’essai gratuit a été envoyée.'),
          backgroundColor: adminColor,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final requestAlreadyExists =
          error is StateError && error.message == 'TRIAL_ALREADY_REQUESTED';

      if (requestAlreadyExists) {
        onCompleted();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Une demande d’essai gratuit a déjà été enregistrée.',
            ),
            backgroundColor: pendingColor,
          ),
        );

        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Envoi de la demande impossible : $error'),
          backgroundColor: redColor,
        ),
      );
    }
  }

  Widget _buildTrialSummaryContent({
    required Future<Map<String, dynamic>> summaryFuture,
    required VoidCallback onClose,
    required bool isSidePanel,
  }) {
    return FutureBuilder<Map<String, dynamic>>(
      future: summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: redColor,
                  size: 42,
                ),
                const SizedBox(height: 12),
                Text(
                  'Chargement du récapitulatif impossible : '
                  '${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: adminColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: () {
                    onClose();
                  },
                  child: const Text('FERMER'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const SizedBox(
            width: 520,
            height: 260,
            child: Center(child: CircularProgressIndicator(color: adminColor)),
          );
        }

        final summary = snapshot.data!;

        final monitoredSpots = List<Map<String, dynamic>>.from(
          summary['monitoredSpots'] ?? const [],
        );

        final otherSpots = List<Map<String, dynamic>>.from(
          summary['otherSpots'] ?? const [],
        );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  Transform.translate(
                    offset: const Offset(-12, 0),
                    child: Transform.scale(
                      scale: isSidePanel ? 1.5 : 1.8,
                      alignment: Alignment.center,
                      child: AdaptiveAssetImage(
                        'data/icons/fire_red_icon.svg',
                        width: 30,
                        height: 30,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSidePanel
                              ? 'ESPACE ADMIN SPHOT'
                              : 'ESSAI GRATUIT 8 JOURS',
                          style: const TextStyle(
                            color: adminColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (!isSidePanel) ...[
                          const SizedBox(height: 3),
                          const Text(
                            'Vérifiez votre organisation avant '
                            'd’envoyer la demande d’essai gratuit.',
                            style: TextStyle(
                              color: adminColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: adminColor.withOpacity(0.20)),
            Expanded(
              child: Container(
                color: const Color(0xFFF8FAFC),
                child: ListView(
                  padding: const EdgeInsets.all(22),
                  children: [
                    const Text(
                      'SPHOTS SURVEILLÉS',
                      style: TextStyle(
                        color: redColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (monitoredSpots.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: adminColor.withOpacity(0.25),
                          ),
                        ),
                        child: const Text(
                          'Aucun poste de secours enregistré.',
                          style: TextStyle(
                            color: adminColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      ...monitoredSpots.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildTrialMonitoredSpotCard(entry),
                        ),
                      ),
                    const SizedBox(height: 18),
                    const Text(
                      'AUTRES SPHOTS',
                      style: TextStyle(
                        color: redColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (otherSpots.isEmpty)
                      const Text(
                        'Aucun autre SPHOT enregistré.',
                        style: TextStyle(
                          color: adminColor,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else if (isSidePanel)
                      Column(
                        children: otherSpots.map((spot) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SizedBox(
                              width: double.infinity,
                              child: _buildTrialOtherSpotTile(
                                spot,
                                showActions: true,
                              ),
                            ),
                          );
                        }).toList(),
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: otherSpots.map((spot) {
                          return SizedBox(
                            width: 300,
                            child: _buildTrialOtherSpotTile(
                              spot,
                              showActions: true,
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: adminColor.withOpacity(0.20)),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _trialCounter(
                        icon: Icons.health_and_safety_outlined,
                        value: '${monitoredSpots.length}',
                        label: 'SPHOTS surveillés',
                      ),
                      _trialCounter(
                        icon: Icons.place_outlined,
                        value: '${otherSpots.length}',
                        label: 'autres SPHOTS',
                      ),
                      _trialCounter(
                        icon: Icons.date_range_outlined,
                        value: '${summary['periodCount'] ?? 0}',
                        label: 'périodes',
                      ),
                      _trialCounter(
                        icon: Icons.groups_outlined,
                        value: '${summary['sauveteurCount'] ?? 0}',
                        label: 'sauveteurs',
                      ),
                    ],
                  ),
                  if (!isSidePanel) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Les postes fermés, hors saison ou sans '
                      'ouverture programmée ne bloquent pas '
                      'la demande.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: adminColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: onClose,
                          child: const Text('RETOUR'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            _submitTrialRequest(summary, onClose);
                          },

                          style: OutlinedButton.styleFrom(
                            foregroundColor: redColor,
                            backgroundColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 15,
                            ),
                            side: const BorderSide(color: redColor, width: 1.8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),

                          icon: const Icon(Icons.send_rounded),

                          label: const Text(
                            'ENVOYER MA DEMANDE D’ESSAI GRATUIT 8 JOURS',
                            style: TextStyle(
                              color: redColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrialSummaryDialog(
    BuildContext dialogContext,
    Future<Map<String, dynamic>> summaryFuture,
  ) {
    final screenSize = MediaQuery.sizeOf(dialogContext);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: adminColor, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1040,
          maxHeight: screenSize.height * 0.88,
        ),
        child: _buildTrialSummaryContent(
          summaryFuture: summaryFuture,
          isSidePanel: false,
          onClose: () {
            Navigator.of(dialogContext).pop();
          },
        ),
      ),
    );
  }

  Future<void> _openTrialSummaryDialog() async {
    if (_resolvedTerritoireId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le territoire doit être chargé avant '
            'd’ouvrir le récapitulatif.',
          ),
          backgroundColor: redColor,
        ),
      );
      return;
    }

    final summaryFuture = _loadTrialSummaryData();

    setState(() {
      _showStatisticsPanel = false;
      _trialSummaryDialogOpen = true;
      _showTrialSummaryPanel = false;
      _showSubscriptionPanel = false;
      _showBillingDocumentsPanel = false;
      _showSauveteursManagementPanel = false;
      _showSurveillancePeriodsPanel = false;
      _showSauveteurEditorPanel = false;
      _showSphotEditorPanel = false;
      _placingSphotOnMap = false;
    });

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _buildTrialSummaryDialog(dialogContext, summaryFuture);
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _trialSummaryDialogOpen = false;
        });
      }
    }
  }

  void _openTrialSummaryPanel() {
    if (_resolvedTerritoireId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le territoire doit être chargé avant '
            'd’ouvrir le récapitulatif.',
          ),
          backgroundColor: redColor,
        ),
      );
      return;
    }

    setState(() {
      _showStatisticsPanel = false;
      _trialSummaryPanelFuture = _loadTrialSummaryData();
      _showTrialSummaryPanel = true;
      _showSubscriptionPanel = false;
      _showBillingDocumentsPanel = false;

      _showSauveteursManagementPanel = false;
      _showSurveillancePeriodsPanel = false;
      _showSauveteurEditorPanel = false;
      _showSphotEditorPanel = false;
      _placingSphotOnMap = false;

      _selectedSpot = null;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
      _showLegalDocumentsPanel = false;
    });
  }

  void _closeTrialSummaryPanel() {
    setState(() {
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
    });
  }

  void _closeTrialSummaryDialogBeforeEditing() {
    if (!_trialSummaryDialogOpen) {
      return;
    }

    _trialSummaryDialogOpen = false;

    Navigator.of(context, rootNavigator: true).pop();
  }

  Widget _buildTrialSummaryPanel() {
    final summaryFuture = _trialSummaryPanelFuture;

    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.45), width: 1.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: summaryFuture == null
              ? const Center(
                  child: CircularProgressIndicator(color: adminColor),
                )
              : _buildTrialSummaryContent(
                  summaryFuture: summaryFuture,
                  isSidePanel: true,
                  onClose: _closeTrialSummaryPanel,
                ),
        ),
      ),
    );
  }

  void _openSubscriptionPanel() {
    setState(() {
      _showStatisticsPanel = false;
      _showSubscriptionPanel = true;
      _showBillingDocumentsPanel = false;
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
      _showSauveteursManagementPanel = false;
      _showSurveillancePeriodsPanel = false;
      _showSauveteurEditorPanel = false;
      _showSphotEditorPanel = false;
      _placingSphotOnMap = false;
      _selectedSpot = null;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
      _showLegalDocumentsPanel = false;
    });
  }

  void _openBillingDocumentsPanel() {
    setState(() {
      _showStatisticsPanel = false;
      _showBillingDocumentsPanel = true;
      _showSubscriptionPanel = false;
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
      _showSauveteursManagementPanel = false;
      _showSurveillancePeriodsPanel = false;
      _showSauveteurEditorPanel = false;
      _showSphotEditorPanel = false;
      _placingSphotOnMap = false;
      _selectedSpot = null;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
      _showLegalDocumentsPanel = false;
    });
  }

  void _closeSubscriptionPanel() {
    setState(() {
      _showSubscriptionPanel = false;
    });
  }

  void _closeBillingDocumentsPanel() {
    setState(() {
      _showBillingDocumentsPanel = false;
    });
  }

  void _openStatisticsPanel() {
    setState(() {
      _showStatisticsPanel = true;
      _showSubscriptionPanel = false;
      _showBillingDocumentsPanel = false;
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
      _showSauveteursManagementPanel = false;
      _showSurveillancePeriodsPanel = false;
      _showSauveteurEditorPanel = false;
      _showSphotEditorPanel = false;
      _placingSphotOnMap = false;
      _selectedSpot = null;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
      _showLegalDocumentsPanel = false;
    });
  }

  void _closeStatisticsPanel() {
    setState(() {
      _showStatisticsPanel = false;
    });
  }

  Widget _buildCommercialPanelHeader({
    required String title,
    required VoidCallback onClose,
  }) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 6),
          Transform.translate(
            offset: const Offset(-12, 0),
            child: Transform.scale(
              scale: 1.5,
              alignment: Alignment.center,
              child: AdaptiveAssetImage(
                'data/icons/fire_red_icon.svg',
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: adminColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Fermer',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildCommercialSection({
    required IconData icon,
    required String title,
    required String description,
    String status = 'À COMPLÉTER',
    Color statusColor = pendingColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: adminColor.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: adminColor, size: 27),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: adminColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    color: adminColor.withOpacity(0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionPanel() {
    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.45), width: 1.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              _buildCommercialPanelHeader(
                title: 'ABONNEMENT',
                onClose: _closeSubscriptionPanel,
              ),
              Divider(height: 1, color: adminColor.withOpacity(0.20)),
              Expanded(
                child: Container(
                  color: const Color(0xFFF8FAFC),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildCommercialSection(
                        icon: Icons.apartment_rounded,
                        title: 'ORGANISME PAYEUR',
                        description:
                            'Coordonnées administratives et informations de facturation de votre organisme.',
                      ),
                      const SizedBox(height: 12),
                      _buildCommercialSection(
                        icon: Icons.description_outlined,
                        title: 'OFFRE ET DEVIS',
                        description:
                            'Nombre de postes de secours, durée et montant annuel de l’abonnement.',
                      ),
                      const SizedBox(height: 12),
                      _buildCommercialSection(
                        icon: Icons.assignment_turned_in_outlined,
                        title: 'COMMANDE',
                        description:
                            'Bon de commande, numéro d’engagement et code service si nécessaire.',
                      ),
                      const SizedBox(height: 12),
                      _buildCommercialSection(
                        icon: Icons.verified_outlined,
                        title: 'ACTIVATION',
                        description:
                            'L’abonnement sera activé après validation complète de la commande.',
                        status: 'EN ATTENTE',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int? _administrativeReferenceYear(Map<String, dynamic>? subscription) {
    if (subscription == null) return null;

    for (final field in const [
      'currentPeriodStartDate',
      'renewalStartDate',
      'subscriptionStartDate',
      'trialStartDate',
    ]) {
      final value = subscription[field];
      if (value is Timestamp) return value.toDate().year;
      if (value is DateTime) return value.year;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed.year;
      }
    }

    final explicitYear =
        subscription['billingYear'] ?? subscription['subscriptionYear'];
    return explicitYear is num ? explicitYear.toInt() : null;
  }

  String _referenceForSubscriptionPeriod(
    String reference,
    Map<String, dynamic>? subscription,
  ) {
    final year = _administrativeReferenceYear(subscription);
    if (reference.isEmpty || year == null) return reference;

    final pattern = RegExp(
      r'^(SPHOT-ADM-[A-Z]{3}-)\d{4}(-\d+)$',
      caseSensitive: false,
    );
    if (!pattern.hasMatch(reference)) return reference;

    return reference.replaceFirstMapped(
      pattern,
      (match) => '${match.group(1)}$year${match.group(2)}',
    );
  }

  String _currentAdministrativeReference() {
    final uid = widget.adminUid.trim();
    final subscription = _subscriptionsByUid[uid];

    final subscriptionReference = _cleanText(
      subscription?['administrativeReference'] ??
          subscription?['requestNumber'],
    );

    if (subscriptionReference.isNotEmpty) {
      return _referenceForSubscriptionPeriod(
        subscriptionReference,
        subscription,
      );
    }

    for (final document in _latestAdminDocs) {
      final data = document.data();

      if (document.id == uid || _cleanText(data['uid']) == uid) {
        return _cleanText(
          data['requestNumber'] ?? data['administrativeReference'],
        );
      }
    }

    return '';
  }

  Widget _buildBillingDocumentsPanel() {
  final administrativeReference =
      _currentAdministrativeReference();

  return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.45), width: 1.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Column(
            children: [
              _buildCommercialPanelHeader(
                title: 'DOCUMENTS & FACTURES',
                onClose: _closeBillingDocumentsPanel,
              ),
              Divider(height: 1, color: adminColor.withOpacity(0.20)),
              Expanded(
                child: Container(
                  color: const Color(0xFFF8FAFC),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (administrativeReference.isNotEmpty) ...[
  Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
    decoration: BoxDecoration(
      color: adminColor.withOpacity(0.06),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: adminColor.withOpacity(0.30),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RÉFÉRENCE ADMINISTRATIVE',
          style: TextStyle(
            color: pendingColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          administrativeReference,
          style: const TextStyle(
            color: redColor,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  ),
  const SizedBox(height: 12),
],

_buildCommercialSection(
  icon: Icons.request_quote_outlined,
  title: 'DEVIS',
                        description:
                            'Les devis générés pour votre organisme apparaîtront ici.',
                        status: 'AUCUN DOCUMENT',
                      ),
                      const SizedBox(height: 12),
                      _buildCommercialSection(
                        icon: Icons.shopping_cart_checkout_rounded,
                        title: 'COMMANDES',
                        description:
                            'Bons de commande et références d’engagement associés.',
                        status: 'AUCUN DOCUMENT',
                      ),
                      const SizedBox(height: 12),
                      _buildCommercialSection(
                        icon: Icons.receipt_long_outlined,
                        title: 'FACTURES ET AVOIRS',
                        description:
                            'Factures, avoirs et état de leur transmission électronique.',
                        status: 'AUCUN DOCUMENT',
                      ),
                      const SizedBox(height: 12),
                      _buildCommercialSection(
                        icon: Icons.account_balance_outlined,
                        title: 'SUIVI DU PAIEMENT',
                        description:
                            'État du dépôt, du traitement et du règlement des factures.',
                        status: 'AUCUNE FACTURE',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanel({
    required int visibleSpots,
    required bool canRequestTrial,
  }) {
    return Container(
      width: 360,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        border: Border(
          right: BorderSide(color: adminColor.withOpacity(0.25), width: 1.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(
              width: double.infinity,
              child: Text(
                'BIENVENUE SUR SPHOT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: redColor,
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
            ),

            const SizedBox(height: 6),

            SizedBox(
              width: double.infinity,
              child: Text(
                'Configurez votre espace admin SPHOT en suivant les étapes ci-dessous.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: adminColor.withOpacity(0.82),
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _summaryCard(
                            title: 'CRÉER UN SPHOT',
                            value: '',
                            color: adminColor,
                            iconPath: 'data/icons/fire_red_icon.svg',
                            stepNumber: 1,
                            titleFontSize: 17,
                            titleLetterSpacing: 0.8,
                            showValue: false,
                            isActive: _showSphotEditorPanel,
                            onTap: _openNewSphotEditor,
                          ),
                          _summaryCard(
                            title: 'CRÉER UNE PÉRIODE',
                            value: '',
                            color: adminColor,
                            iconPath: 'data/icons/fire_red_icon.svg',
                            stepNumber: 2,
                            titleFontSize: 17,
                            titleLetterSpacing: 0.8,
                            showValue: false,
                            isActive: _showSurveillancePeriodsPanel,
                            onTap: _openSurveillancePeriodsPanel,
                          ),
                          _summaryCard(
                            title: 'CRÉER UN SAUVETEUR',
                            value: '',
                            color: adminColor,
                            iconPath: 'data/icons/fire_red_icon.svg',
                            stepNumber: 3,
                            titleFontSize: 17,
                            titleLetterSpacing: 0.8,
                            showValue: false,
                            isActive: _showSauveteurEditorPanel ||
                                _showSauveteursManagementPanel,
                            onTap: _openNewSauveteurEditor,
                          ),
                          _summaryCard(
                            title: 'ESPACE ADMIN SPHOT',
                            value: '',
                            color: adminColor,
                            iconPath: 'data/icons/fire_red_icon.svg',
                            stepNumber: 4,
                            titleFontSize: 17,
                            titleLetterSpacing: 0.8,
                            showValue: false,
                            isActive: _showTrialSummaryPanel,
                            onTap: _openTrialSummaryPanel,
                          ),
                          _summaryCard(
                            title: 'ESSAI GRATUIT 8 JOURS',
                            value: '',
                            color: canRequestTrial ? adminColor : pendingColor,
                            iconPath: 'data/icons/fire_red_icon.svg',
                            stepNumber: 5,
                            titleFontSize: 17,
                            titleLetterSpacing: 0.8,
                            showValue: false,
                            grayscaleIcon: !canRequestTrial,
                            isActive: canRequestTrial &&
                                _trialSummaryDialogOpen,
                            onTap: canRequestTrial
                                ? _openTrialSummaryDialog
                                : null,
                          ),
                          _summaryCard(
                            title: 'ABONNEMENT',
                            value: '',
                            color: adminColor,
                            iconPath: 'data/icons/fire_red_icon.svg',
                            stepNumber: 6,
                            titleFontSize: 16,
                            titleLetterSpacing: 0.5,
                            showValue: false,
                            isActive: _showSubscriptionPanel,
                            onTap: _openSubscriptionPanel,
                          ),
                          _summaryCard(
                            title: 'DOCUMENTS & FACTURES',
                            value: '',
                            color: adminColor,
                            iconPath: 'data/icons/fire_red_icon.svg',
                            stepNumber: 7,
                            titleFontSize: 16,
                            titleLetterSpacing: 0.5,
                            showValue: false,
                            isActive: _showBillingDocumentsPanel,
                            onTap: _openBillingDocumentsPanel,
                          ),
                          _summaryCard(
                            title: 'STATISTIQUES',
                            value: '',
                            color: adminColor,
                            iconPath: 'data/icons/fire_red_icon.svg',
                            stepNumber: 8,
                            titleFontSize: 16,
                            titleLetterSpacing: 0.5,
                            showValue: false,
                            isActive: _showStatisticsPanel,
                            onTap: _openStatisticsPanel,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required Color color,
    String iconPath = 'data/icons/fire_blue_icon.svg',
    int? stepNumber,
    double titleFontSize = 13,
    double titleLetterSpacing = 0,
    bool showValue = true,
    bool grayscaleIcon = false,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    final effectiveColor = isActive ? redColor : color;
    final displayedStepNumberColor = grayscaleIcon
        ? pendingColor
        : isActive
        ? redColor
        : color;

    final icon = AdaptiveAssetImage(
      iconPath,
      width: 44,
      height: 56,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    final card = Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isActive ? redColor.withOpacity(0.04) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: effectiveColor, width: isActive ? 2 : 1.6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                grayscaleIcon
                    ? ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0.2126,
                          0.7152,
                          0.0722,
                          0,
                          0,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ]),
                        child: icon,
                      )
                    : icon,
                if (stepNumber != null)
                  Text(
                    '$stepNumber',
                    style: TextStyle(
                      color: displayedStepNumberColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: effectiveColor,
                      decoration: TextDecoration.none,
                      decorationColor: Colors.transparent,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: titleLetterSpacing,
                    ),
                  ),
                ),
                if (showValue) ...[
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: effectiveColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        selected: isActive,
        label: title,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: card,
        ),
      ),
    );
  }

  Widget _comingSoon(String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _advertiserFilterLabel(DashboardAdvertiserFilter filter) {
    switch (filter) {
      case DashboardAdvertiserFilter.none:
        return 'Aucun';

      case DashboardAdvertiserFilter.pending:
        return 'En attente';

      case DashboardAdvertiserFilter.all:
        return 'Tous';

      case DashboardAdvertiserFilter.active:
        return 'Actifs';

      case DashboardAdvertiserFilter.expiringSoon:
        return 'Expirant sous 7 jours';

      case DashboardAdvertiserFilter.finished:
        return 'Terminés';
    }
  }

  Widget _buildAdvertiserFiltersBlock() {
    final displayText = _advertiserFilterLabel(_selectedAdvertiserFilter);

    return GestureDetector(
      key: _advertiserFiltersKey,
      onTap: _openAdvertiserFiltersMenu,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Filtres ANNONCEURS',
          labelStyle: const TextStyle(
            color: adminColor,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: redColor,
                ),
              ),
            ),
            const Icon(Icons.checklist_rounded, color: redColor, size: 22),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: redColor,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

  void _openAdvertiserFiltersMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;

    final renderBox =
        _advertiserFiltersKey.currentContext!.findRenderObject() as RenderBox;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final scrollController = ScrollController();

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _dropdownOverlay?.remove();
                  _dropdownOverlay = null;
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: position.dx,
              top: position.dy + size.height - 12,
              width: size.width,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 190),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.94),
                    border: const Border(
                      left: BorderSide(color: adminColor, width: 1.4),
                      right: BorderSide(color: adminColor, width: 1.4),
                      bottom: BorderSide(color: adminColor, width: 1.4),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ScrollbarTheme(
                    data: const ScrollbarThemeData(
                      thumbColor: WidgetStatePropertyAll(adminColor),
                      trackVisibility: WidgetStatePropertyAll(false),
                    ),
                    child: Scrollbar(
                      controller: scrollController,
                      thumbVisibility: true,
                      thickness: 10,
                      radius: const Radius.circular(10),
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: DashboardAdvertiserFilter.values.map((
                          filter,
                        ) {
                          final selected = _selectedAdvertiserFilter == filter;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedAdvertiserFilter = filter;
                                _selectedSpot = null;
                                _selectedAdmin = null;
                                _selectedAdvertiser = null;
                              });

                              _dropdownOverlay?.remove();
                              _dropdownOverlay = null;
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    color: selected ? redColor : adminColor,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _advertiserFilterLabel(filter),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: selected ? redColor : adminColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

  bool _matchesAdvertiserFilter(Map<String, dynamic> data) {
    final status = _cleanText(data['status']).toLowerCase();

    if (_selectedAdvertiserFilter == DashboardAdvertiserFilter.none) {
      return false;
    }

    switch (_selectedAdvertiserFilter) {
      case DashboardAdvertiserFilter.none:
        return false;

      case DashboardAdvertiserFilter.pending:
        return status == 'pending';

      case DashboardAdvertiserFilter.all:
        return true;

      case DashboardAdvertiserFilter.active:
        return status == 'active';

      case DashboardAdvertiserFilter.expiringSoon:
        final endDate = data['campaignEndDate'];
        if (endDate is! Timestamp) return false;

        final now = DateTime.now();
        final limit = now.add(const Duration(days: 7));
        final date = endDate.toDate();

        return date.isAfter(now) && date.isBefore(limit);

      case DashboardAdvertiserFilter.finished:
        final endDate = data['campaignEndDate'];
        if (endDate is! Timestamp) return false;

        return endDate.toDate().isBefore(DateTime.now());
    }
  }

  bool _matchesAdvertiserSearch(Map<String, dynamic> data) {
    final query = _normalizeSearch(_searchText);
    if (query.isEmpty) return true;

    final fields = [
      data['advertiserName'],
      data['contactName'],
      data['email'],
      data['phone'],
      data['siret'],
      data['city'],
      data['department'],
      data['region'],
      data['status'],
      data['broadcastType'],
      data['visibilityLabel'],
      data['campaignTitle'],
      data['companyName'],
      data['businessName'],
      data['organisation'],
    ].map((value) => _normalizeSearch((value ?? '').toString())).toList();

    return fields.any(
      (field) => field.contains(query) || query.contains(field),
    );
  }

  Set<String> _readSphotMultiValue(dynamic value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet();
    }

    return _cleanText(value)
        .split('|')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  String get _resolvedTerritoireId {
    return _activeTerritoireId.trim().isNotEmpty
        ? _activeTerritoireId.trim()
        : widget.territoireId.trim();
  }

  String _formatSurveillanceDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatSurveillanceTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}h'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  TimeOfDay? _parseSurveillanceTime(dynamic value) {
    final rawValue = _cleanText(value);

    if (rawValue.isEmpty) {
      return null;
    }

    final parts = rawValue.split(':');

    if (parts.isEmpty) {
      return null;
    }

    final hour = int.tryParse(parts.first);
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '0');

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatSurveillancePeriodHours(_DashboardSurveillancePeriod period) {
    final firstSlot =
        'DE ${_formatSurveillanceTime(period.startHour)} '
        'À ${_formatSurveillanceTime(period.endHour)}';

    if (!period.hasMiddayBreak) {
      return firstSlot;
    }

    return '$firstSlot — DE '
        '${_formatSurveillanceTime(period.secondStartHour!)} '
        'À ${_formatSurveillanceTime(period.secondEndHour!)}';
  }

  void _openSurveillancePeriodsPanel() {
    if (_resolvedTerritoireId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le territoire doit être chargé avant de gérer les périodes.',
          ),
          backgroundColor: redColor,
        ),
      );
      return;
    }

    setState(() {
      _showStatisticsPanel = false;
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
      _showSubscriptionPanel = false;
      _showBillingDocumentsPanel = false;

      _showSurveillancePeriodsPanel = true;
      _showSauveteurEditorPanel = false;
      _showSauveteursManagementPanel = false;
      _showSphotEditorPanel = false;
      _placingSphotOnMap = false;
      _selectedSpot = null;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
      _showLegalDocumentsPanel = false;
    });
  }

  Future<void> _openSurveillancePeriodDialog({
    _DashboardSurveillancePeriod? period,
  }) async {
    final result = await showDialog<_DashboardSurveillancePeriod>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DashboardSurveillancePeriodDialog(period: period),
    );

    if (result == null) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('territoires')
          .doc(_resolvedTerritoireId)
          .collection('periodesSurveillance')
          .doc(result.id)
          .set({
            'id': result.id,
            'name': result.name.toUpperCase(),
            'territoireId': _resolvedTerritoireId,
            'startDate': Timestamp.fromDate(result.startDate),
            'endDate': Timestamp.fromDate(result.endDate),
            'startHour':
                '${result.startHour.hour.toString().padLeft(2, '0')}:'
                '${result.startHour.minute.toString().padLeft(2, '0')}',
            'endHour':
                '${result.endHour.hour.toString().padLeft(2, '0')}:'
                '${result.endHour.minute.toString().padLeft(2, '0')}',
            'hasMiddayBreak': result.hasMiddayBreak,
            'secondStartHour': result.hasMiddayBreak
                ? '${result.secondStartHour!.hour.toString().padLeft(2, '0')}:'
                      '${result.secondStartHour!.minute.toString().padLeft(2, '0')}'
                : FieldValue.delete(),
            'secondEndHour': result.hasMiddayBreak
                ? '${result.secondEndHour!.hour.toString().padLeft(2, '0')}:'
                      '${result.secondEndHour!.minute.toString().padLeft(2, '0')}'
                : FieldValue.delete(),
            'label':
                '${result.name.toUpperCase()} — '
                'DU ${_formatSurveillanceDate(result.startDate)} '
                'AU ${_formatSurveillanceDate(result.endDate)} — '
                '${_formatSurveillancePeriodHours(result)}',
            'updatedAt': FieldValue.serverTimestamp(),
            if (period == null) 'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) {
        return;
      }

      if (_showTrialSummaryPanel) {
        setState(() {
          _trialSummaryPanelFuture = _loadTrialSummaryData();
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            period == null
                ? 'Période enregistrée avec succès.'
                : 'Période modifiée avec succès.',
          ),
          backgroundColor: adminColor,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enregistrement impossible : $error'),
          backgroundColor: redColor,
        ),
      );
    }
  }

  Future<void> _deleteSurveillancePeriod(
    _DashboardSurveillancePeriod period,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'SUPPRIMER LA PÉRIODE',
            style: TextStyle(color: adminColor, fontWeight: FontWeight.w900),
          ),
          content: Text('Confirmer la suppression de « ${period.name} » ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ANNULER'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: redColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('SUPPRIMER'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('territoires')
          .doc(_resolvedTerritoireId)
          .collection('periodesSurveillance')
          .doc(period.id)
          .delete();
      if (!mounted) {
        return;
      }

      if (_showTrialSummaryPanel) {
        setState(() {
          _trialSummaryPanelFuture = _loadTrialSummaryData();
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Période supprimée.'),
          backgroundColor: adminColor,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suppression impossible : $error'),
          backgroundColor: redColor,
        ),
      );
    }
  }

  void _clearSauveteurEditor() {
    _sauveteurCivilite = null;
    _sauveteurNomController.clear();
    _sauveteurPrenomController.clear();
    _sauveteurDateNaissanceController.clear();
    _sauveteurAgeController.clear();
    _sauveteurAdresseController.clear();
    _sauveteurCodePostalController.clear();
    _sauveteurVilleController.clear();
    _sauveteurTelephoneController.clear();
    _sauveteurEmailController.clear();
    _sauveteurExperienceController.clear();
    _sauveteurObservationsController.clear();
    _sauveteurFonctions.clear();
    _sauveteurPostes.clear();
    _sauveteurPeriodesSurveillance.clear();
    _isSavingSauveteur = false;
    _sauveteurAccessGenerated = false;
    _sauveteurPasswordRegenerated = false;
    _sauveteurHasUnsavedChanges = false;
    _sauveteurEmailSent = false;
    _sauveteurGeneratedLogin = '';
    _sauveteurGeneratedPassword = '';
    _createdSauveteurDocId = null;
    _editingSauveteurDocId = null;
    _originalSauveteurPostes.clear();
  }

  String _normalizeSauveteurLogin(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâäãå]'), 'a')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[òóôöõ]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ýÿ]'), 'y')
        .replaceAll('æ', 'ae')
        .replaceAll('œ', 'oe')
        .replaceAll(RegExp(r"[' -]"), '');
  }

  Future<String> _generateUniqueSauveteurLogin(String baseLogin) async {
    final sauveteursRef = FirebaseFirestore.instance
        .collection('territoires')
        .doc(_resolvedTerritoireId)
        .collection('sauveteurs');

    var candidate = baseLogin;
    var counter = 2;

    while (true) {
      final existing = await sauveteursRef
          .where('login', isEqualTo: candidate)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        return candidate;
      }

      candidate = '$baseLogin$counter';
      counter++;
    }
  }

  void _showSauveteurError(String message) {
    if (!mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'ERREUR',
            style: TextStyle(color: redColor, fontWeight: FontWeight.w900),
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('FERMER'),
            ),
          ],
        );
      },
    );
  }

  bool _validateSauveteurContact() {
    if (_sauveteurCivilite != 'Monsieur' && _sauveteurCivilite != 'Madame') {
      _showSauveteurError('Sélectionnez la civilité du sauveteur.');
      return false;
    }
    if (_sauveteurNomController.text.trim().isEmpty) {
      _showSauveteurError('Le nom du sauveteur est obligatoire.');
      return false;
    }

    if (_sauveteurPrenomController.text.trim().isEmpty) {
      _showSauveteurError('Le prénom du sauveteur est obligatoire.');
      return false;
    }

    if (_sauveteurTelephoneController.text.trim().isEmpty) {
      _showSauveteurError('Le téléphone du sauveteur est obligatoire.');
      return false;
    }

    final email = _sauveteurEmailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSauveteurError('L’adresse email du sauveteur n’est pas valide.');
      return false;
    }

    return true;
  }

  Future<void> _upsertSauveteurAccount({
    required String login,
    required String temporaryPassword,
    required String sauveteurId,
  }) async {
    final uri = Uri.parse(
      'https://us-central1-sphot-ab80b.cloudfunctions.net/'
      'upsertSauveteurAccount',
    );

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'login': login,
        'temporaryPassword': temporaryPassword,
        'mustChangePassword': true,
        'accountStatus': 'ACTIVE',
        'territoireId': _resolvedTerritoireId,
        'sauveteurId': sauveteurId,
        'civilite': _sauveteurCivilite,
        'nom': _sauveteurNomController.text.trim().toUpperCase(),
        'prenom': _sauveteurPrenomController.text.trim(),
        'email': _sauveteurEmailController.text.trim(),
        'role': 'SAUVETEUR',
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Création du compte impossible (${response.statusCode}).',
      );
    }
  }

  Future<void> _generateSauveteurAccess() async {
    if (!_validateSauveteurContact()) {
      return;
    }

    final nom = _sauveteurNomController.text.trim();
    final prenom = _sauveteurPrenomController.text.trim();
    final baseLogin = _normalizeSauveteurLogin('${prenom.substring(0, 1)}$nom');

    setState(() {
      _isSavingSauveteur = true;
    });

    try {
      final login = await _generateUniqueSauveteurLogin(baseLogin);
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final random = math.Random.secure();
      final password = List<String>.generate(
        8,
        (_) => chars[random.nextInt(chars.length)],
      ).join();

      final sauveteursRef = FirebaseFirestore.instance
          .collection('territoires')
          .doc(_resolvedTerritoireId)
          .collection('sauveteurs');

      final docRef = _createdSauveteurDocId == null
          ? sauveteursRef.doc()
          : sauveteursRef.doc(_createdSauveteurDocId);

      _createdSauveteurDocId = docRef.id;

      await docRef.set({
        'login': login,
        'temporaryPassword': password,
        'mustChangePassword': true,
        'accountStatus': 'ACTIVE',
        'accessGeneratedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _upsertSauveteurAccount(
        login: login,
        temporaryPassword: password,
        sauveteurId: docRef.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingSauveteur = false;
        _sauveteurGeneratedLogin = login;
        _sauveteurGeneratedPassword = password;
        _sauveteurAccessGenerated = true;
        _sauveteurEmailSent = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingSauveteur = false;
      });
      _showSauveteurError('Génération impossible : $error');
    }
  }

  Future<void> _regenerateSauveteurPassword() async {
    final sauveteurId = _editingSauveteurDocId?.trim() ?? '';
    final login = _sauveteurGeneratedLogin.trim();

    if (sauveteurId.isEmpty || login.isEmpty) {
      _showSauveteurError(
        'Impossible de retrouver l’identifiant du sauveteur.',
      );
      return;
    }

    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = math.Random.secure();
    final password = List<String>.generate(
      8,
      (_) => chars[random.nextInt(chars.length)],
    ).join();

    setState(() {
      _isSavingSauveteur = true;
    });

    try {
      final sauveteurReference = FirebaseFirestore.instance
          .collection('territoires')
          .doc(_resolvedTerritoireId)
          .collection('sauveteurs')
          .doc(sauveteurId);

      await sauveteurReference.set({
        'temporaryPassword': password,
        'mustChangePassword': true,
        'passwordResetAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _upsertSauveteurAccount(
        login: login,
        temporaryPassword: password,
        sauveteurId: sauveteurId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingSauveteur = false;
        _sauveteurGeneratedPassword = password;
        _sauveteurAccessGenerated = true;
        _sauveteurPasswordRegenerated = true;
        _sauveteurEmailSent = false;
      });

      try {
        await _sendSauveteurCredentialsEmail(isReset: true);
      } catch (emailError) {
        if (!mounted) {
          return;
        }

        _showSauveteurError(
          'Le mot de passe a bien été régénéré, mais '
          'l’email n’a pas pu être envoyé : $emailError',
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingSauveteur = false;
      });

      _showSauveteurError('Régénération du mot de passe impossible : $error');
    }
  }

  Future<void> _sendSauveteurCredentialsEmail({bool isReset = false}) async {
    if (!_sauveteurAccessGenerated || _sauveteurEmailSent) {
      return;
    }

    final uri = Uri.https(
      'us-central1-sphot-ab80b.cloudfunctions.net',
      '/sendSauveteurCredentialsEmail',
      {
        'email': _sauveteurEmailController.text.trim(),
        'prenom': _sauveteurPrenomController.text.trim(),
        'nom': _sauveteurNomController.text.trim().toUpperCase(),
        'civilite': _sauveteurCivilite ?? '',
        'identifiant': _sauveteurGeneratedLogin,
        'motdepasse': _sauveteurGeneratedPassword,
        'type': isReset ? 'reset' : 'creation',
      },
    );

    final response = await http.get(uri);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Erreur lors de l’envoi de l’email '
        '(${response.statusCode}).',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _sauveteurEmailSent = true;
    });
  }

  Future<void> _selectSauveteurBirthDate() async {
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: adminColor,
              onPrimary: Colors.white,
              onSurface: adminColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    var age = now.year - selectedDate.year;
    if (now.month < selectedDate.month ||
        (now.month == selectedDate.month && now.day < selectedDate.day)) {
      age--;
    }

    setState(() {
      _sauveteurDateNaissanceController.text =
          '${selectedDate.day.toString().padLeft(2, '0')}/'
          '${selectedDate.month.toString().padLeft(2, '0')}/'
          '${selectedDate.year}';
      _sauveteurAgeController.text = age.toString();
      if (_editingSauveteurDocId != null) {
        _sauveteurHasUnsavedChanges = true;
      }
    });
  }

  bool _validateSauveteurBeforeSave() {
    if (!_validateSauveteurContact()) {
      return false;
    }

    if (_sauveteurFonctions.isEmpty) {
      _showSauveteurError('Sélectionnez au moins une fonction.');
      return false;
    }

    if (_sauveteurPostes.isEmpty) {
      _showSauveteurError(
        'Affectez au moins un poste de secours au sauveteur.',
      );
      return false;
    }

    if (_sauveteurPeriodesSurveillance.isEmpty) {
      _showSauveteurError('Sélectionnez au moins une période de surveillance.');
      return false;
    }

    if (_editingSauveteurDocId == null) {
      if (!_sauveteurAccessGenerated) {
        _showSauveteurError('Générez l’accès avant d’enregistrer.');
        return false;
      }
    }

    return true;
  }

  Future<void> _saveSauveteur() async {
    if (!_validateSauveteurBeforeSave()) {
      return;
    }

    final isEditing = _editingSauveteurDocId != null;
    final sauveteurId = _createdSauveteurDocId;
    if (sauveteurId == null) {
      _showSauveteurError('Identifiant du sauveteur introuvable.');
      return;
    }

    setState(() {
      _isSavingSauveteur = true;
    });

    try {
      final data = <String, dynamic>{
        'civilite': _sauveteurCivilite,
        'nom': _sauveteurNomController.text.trim().toUpperCase(),
        'prenom': _sauveteurPrenomController.text.trim(),
        'role': 'SAUVETEUR',
        'createdByAdmin': true,
        'dateNaissance': _sauveteurDateNaissanceController.text.trim(),
        'age': _sauveteurAgeController.text.trim(),
        'adresse': _sauveteurAdresseController.text.trim(),
        'codePostal': _sauveteurCodePostalController.text.trim(),
        'ville': _sauveteurVilleController.text.trim().toUpperCase(),
        'telephone': _sauveteurTelephoneController.text.trim(),
        'email': _sauveteurEmailController.text.trim(),
        'fonctions': _sauveteurFonctions.toList(),
        'postesAffectes': _sauveteurPostes.toList(),
        'periodesSurveillance': _sauveteurPeriodesSurveillance.toList(),
        'experience': _sauveteurExperienceController.text.trim(),
        'observations': _sauveteurObservationsController.text.trim(),
        'territoireId': _resolvedTerritoireId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!isEditing) {
        data.addAll({
          'accountStatus': 'ACTIVE',
          'accessInheritedStatus': 'ACTIVE',
          'authUid': '',
          'login': _sauveteurGeneratedLogin,
          'temporaryPassword': _sauveteurGeneratedPassword,
          'mustChangePassword': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final sauveteurRef = FirebaseFirestore.instance
          .collection('territoires')
          .doc(_resolvedTerritoireId)
          .collection('sauveteurs')
          .doc(sauveteurId);

      await sauveteurRef.set(data, SetOptions(merge: true));

      final removedPostes = _originalSauveteurPostes.difference(
        _sauveteurPostes,
      );

      for (final posteId in removedPostes) {
        await FirebaseFirestore.instance
            .collection('territoires')
            .doc(_resolvedTerritoireId)
            .collection('spots')
            .doc(posteId)
            .collection('sauveteursAffectes')
            .doc(sauveteurId)
            .delete();
      }

      for (final posteId in _sauveteurPostes) {
        await FirebaseFirestore.instance
            .collection('territoires')
            .doc(_resolvedTerritoireId)
            .collection('spots')
            .doc(posteId)
            .collection('sauveteursAffectes')
            .doc(sauveteurId)
            .set({
              'sauveteurId': sauveteurId,
              'nom': data['nom'],
              'prenom': data['prenom'],
              'fonctions': data['fonctions'],
              'postesAffectes': data['postesAffectes'],
              'periodesSurveillance': data['periodesSurveillance'],
              'territoireId': _resolvedTerritoireId,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }

      /*
 * Lors d’une création, le mail est envoyé uniquement après
 * l’enregistrement du sauveteur et de toutes ses affectations.
 */
      if (!isEditing) {
        try {
          await _sendSauveteurCredentialsEmail();
        } catch (error) {
          if (!mounted) {
            return;
          }

          setState(() {
            _isSavingSauveteur = false;
          });

          _showSauveteurError(
            'Le sauveteur a bien été créé, mais l’envoi '
            'de l’email a échoué : $error',
          );

          return;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingSauveteur = false;
        _clearSauveteurEditor();
      });

      // Ferme MODIFIER LE SAUVETEUR et ouvre ESPACE ADMIN SPHOT.
      _openTrialSummaryPanel();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingSauveteur = false;
      });
      _showSauveteurError('Enregistrement impossible : $error');
    }
  }

  void _clearSphotEditor() {
    _editingSphotDocId = null;
    _expandedSphotDropdown = null;
    _selectedSphotType = '';

    _selectedSphotEquipments.clear();
    _selectedSphotLabels.clear();

    _sphotIdController.clear();
_sphotNameController.clear();
_sphotLatController.clear();
_sphotLngController.clear();
_sphotOtherTypeController.clear();
_sphotOtherEquipmentController.clear();
_sphotOtherLabelController.clear();
_sphotWebcamUrlController.clear();
  }

  void _openNewSphotEditor() {
    setState(() {
      _showStatisticsPanel = false;
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
      _showSubscriptionPanel = false;
      _showBillingDocumentsPanel = false;

      _clearSphotEditor();
      _showSauveteurEditorPanel = false;
      _showSauveteursManagementPanel = false;
      _showSurveillancePeriodsPanel = false;
      _showSphotEditorPanel = true;
      _placingSphotOnMap = true;
      _selectedSpot = null;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
      _showLegalDocumentsPanel = false;
    });
  }

  void _openNewSauveteurEditor() {
    final territoireId = _activeTerritoireId.trim().isNotEmpty
        ? _activeTerritoireId.trim()
        : widget.territoireId.trim();

    if (territoireId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le territoire doit être chargé avant de créer un sauveteur.',
          ),
          backgroundColor: redColor,
        ),
      );
      return;
    }

    setState(() {
      _showStatisticsPanel = false;
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
      _showSubscriptionPanel = false;
      _showBillingDocumentsPanel = false;

      _clearSauveteurEditor();
      _showSauveteurEditorPanel = true;
      _showSauveteursManagementPanel = false;
      _showSurveillancePeriodsPanel = false;
      _showSphotEditorPanel = false;
      _placingSphotOnMap = false;
      _selectedSpot = null;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
      _showLegalDocumentsPanel = false;
    });
  }

  void _openSauveteursManagementPanel() {
    if (_resolvedTerritoireId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le territoire doit être chargé avant de gérer les sauveteurs.',
          ),
          backgroundColor: redColor,
        ),
      );
      return;
    }

    setState(() {
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
      _showSubscriptionPanel = false;
      _showBillingDocumentsPanel = false;

      _clearSauveteurEditor();
      _showSauveteursManagementPanel = true;
      _showSauveteurEditorPanel = false;
      _showSurveillancePeriodsPanel = false;
      _showSphotEditorPanel = false;
      _placingSphotOnMap = false;
      _selectedSpot = null;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
      _showLegalDocumentsPanel = false;
    });
  }

  void _openSauveteurForEditing(String sauveteurId, Map<String, dynamic> data) {
    _closeTrialSummaryDialogBeforeEditing();

    final fonctions = (data['fonctions'] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toSet();

    final postes = (data['postesAffectes'] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toSet();

    final periodes = (data['periodesSurveillance'] as List? ?? const [])
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .toSet();

    setState(() {
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
      _showSubscriptionPanel = false;
      _showBillingDocumentsPanel = false;

      _clearSauveteurEditor();

      _editingSauveteurDocId = sauveteurId;
      _createdSauveteurDocId = sauveteurId;
      _originalSauveteurPostes.addAll(postes);

      final civilite = _cleanText(data['civilite']).toLowerCase();

      _sauveteurCivilite = civilite == 'madame' || civilite == 'mme'
          ? 'Madame'
          : civilite == 'monsieur' || civilite == 'm' || civilite == 'm.'
          ? 'Monsieur'
          : '';

      _sauveteurNomController.text = _cleanText(data['nom']).toUpperCase();
      _sauveteurPrenomController.text = _cleanText(data['prenom']);
      _sauveteurDateNaissanceController.text = _cleanText(
        data['dateNaissance'],
      );
      _sauveteurAgeController.text = _cleanText(data['age']);
      _sauveteurAdresseController.text = _cleanText(data['adresse']);
      _sauveteurCodePostalController.text = _cleanText(data['codePostal']);
      _sauveteurVilleController.text = _cleanText(data['ville']).toUpperCase();
      _sauveteurTelephoneController.text = _cleanText(data['telephone']);
      _sauveteurEmailController.text = _cleanText(data['email']);
      _sauveteurExperienceController.text = _cleanText(data['experience']);
      _sauveteurObservationsController.text = _cleanText(data['observations']);

      _sauveteurFonctions.addAll(fonctions);
      _sauveteurPostes.addAll(postes);
      _sauveteurPeriodesSurveillance.addAll(periodes);

      _sauveteurGeneratedLogin = _cleanText(data['login']);
      _sauveteurGeneratedPassword = _cleanText(data['temporaryPassword']);
      _sauveteurAccessGenerated = _sauveteurGeneratedLogin.isNotEmpty;
      _sauveteurEmailSent = true;

      _showSauveteursManagementPanel = false;
      _showSauveteurEditorPanel = true;
      _showSurveillancePeriodsPanel = false;
      _showSphotEditorPanel = false;
    });
  }

  Future<void> _deleteSauveteur(
    String sauveteurId,
    Map<String, dynamic> data,
  ) async {
    final nom = [
      _cleanText(data['prenom']),
      _cleanText(data['nom']).toUpperCase(),
    ].where((value) => value.isNotEmpty).join(' ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'SUPPRIMER LE SAUVETEUR',
            style: TextStyle(color: redColor, fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Confirmer la suppression de '
            '${nom.isEmpty ? 'ce sauveteur' : '« $nom »'} ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ANNULER'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: redColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('SUPPRIMER'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final spotsSnapshot = await firestore
          .collection('territoires')
          .doc(_resolvedTerritoireId)
          .collection('spots')
          .get();

      final batch = firestore.batch();

      batch.delete(
        firestore
            .collection('territoires')
            .doc(_resolvedTerritoireId)
            .collection('sauveteurs')
            .doc(sauveteurId),
      );

      for (final spotDocument in spotsSnapshot.docs) {
        batch.delete(
          spotDocument.reference
              .collection('sauveteursAffectes')
              .doc(sauveteurId),
        );
      }

      await batch.commit();

      final login = _cleanText(data['login']);
      if (login.isNotEmpty) {
        final response = await http.post(
          Uri.parse(
            'https://us-central1-sphot-ab80b.cloudfunctions.net/'
            'deleteSauveteurAccount',
          ),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'login': login}),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'suppression du compte impossible '
            '(${response.statusCode})',
          );
        }
      }

      if (!mounted) {
        return;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showSauveteurError('Suppression impossible : $error');
    }
  }

  void _loadSphotInEditor(Map<String, dynamic> data) {
    _closeTrialSummaryDialogBeforeEditing();

    final lat = _toDouble(data['sphotLat']);
    final lng = _toDouble(data['sphotLng']);

    final loadedEquipments = _readSphotMultiValue(data['equipement']);

    // Compatibilité avec les SPHOTs créés avant la modification.
    if (loadedEquipments.remove('🅿️ PARKING')) {
      loadedEquipments.add('🅿️ PARKING GRATUIT');
    }

    if (loadedEquipments.remove('🚐 PARKING CAMPING-CAR')) {
      loadedEquipments.add('🚐 PARKING CAMPING-CAR GRATUIT');
    }

    setState(() {
      _showStatisticsPanel = false;
      _showTrialSummaryPanel = false;
      _trialSummaryPanelFuture = null;
      _showSubscriptionPanel = false;
      _showBillingDocumentsPanel = false;

      _editingSphotDocId = _cleanText(data['_docId']);

      _sphotIdController.text = _cleanText(data['idSphot'] ?? data['_docId']);

      _sphotNameController.text = _spotName(data) == 'SPHOT sans nom'
          ? ''
          : _spotName(data);

      _sphotLatController.text = lat == 0 ? '' : lat.toStringAsFixed(6);

      _sphotLngController.text = lng == 0 ? '' : lng.toStringAsFixed(6);

      _selectedSphotType = _cleanText(data['typeSphot']);

      _sphotOtherTypeController.text = _cleanText(
  data['autreTypeSphot'] ??
      data['typeSphotAutre'],
);

      _selectedSphotEquipments
        ..clear()
        ..addAll(loadedEquipments);

      _selectedSphotLabels
        ..clear()
        ..addAll(_readSphotMultiValue(data['labelSphot']));

      _sphotOtherEquipmentController.text = _cleanText(
        data['autreEquipement'] ?? data['equipementAutre'],
      );

      _sphotOtherLabelController.text = _cleanText(
        data['autreLabel'] ?? data['labelSphotAutre'],
      );

      _sphotWebcamUrlController.text = _cleanText(
        data['webcamUrl'] ?? data['urlWebcam'] ?? data['webcam'],
      );

      _showSauveteurEditorPanel = false;
      _showSauveteursManagementPanel = false;
      _showSurveillancePeriodsPanel = false;
      _showSphotEditorPanel = true;
      _placingSphotOnMap = false;
      _selectedSpot = data;
      _selectedAdmin = null;
      _selectedAdvertiser = null;
      _showLegalDocumentsPanel = false;
    });

    if (lat != 0 && lng != 0) {
      _mapController.move(LatLng(lat, lng), 18);
    }
  }

  void _setSphotPosition(LatLng point) {
    setState(() {
      _sphotLatController.text = point.latitude.toStringAsFixed(6);
      _sphotLngController.text = point.longitude.toStringAsFixed(6);
      _placingSphotOnMap = false;
    });
  }

  void _toggleSphotMultiChoice({
    required Set<String> selectedValues,
    required String choice,
  }) {
    setState(() {
      if (choice == 'AUCUN') {
        if (selectedValues.contains(choice)) {
          selectedValues.clear();
        } else {
          selectedValues
            ..clear()
            ..add(choice);
        }
        return;
      }

      selectedValues.remove('AUCUN');

      if (!selectedValues.add(choice)) {
        selectedValues.remove(choice);
      }
    });
  }

  Future<void> _saveSphotFromDashboard() async {
    final wasEditing = _editingSphotDocId?.trim().isNotEmpty == true;
    final territoireId = _activeTerritoireId.trim().isNotEmpty
        ? _activeTerritoireId.trim()
        : widget.territoireId.trim();
    final idSphot = _sphotIdController.text.trim();
    final lat = double.tryParse(
      _sphotLatController.text.trim().replaceAll(',', '.'),
    );
    final lng = double.tryParse(
      _sphotLngController.text.trim().replaceAll(',', '.'),
    );

    String? errorMessage;

    if (territoireId.isEmpty) {
      errorMessage = 'Aucun territoire associé à cet Admin.';
    } else if (idSphot.isEmpty) {
      errorMessage = 'Renseignez le numéro du SPHOT.';
    } else if (idSphot.contains('/')) {
      errorMessage = 'Le numéro du SPHOT ne peut pas contenir le caractère /.';
    } else if (lat == null ||
        lng == null ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180 ||
        (lat == 0 && lng == 0)) {
      errorMessage = 'Positionnez le SPHOT sur la carte.';
    } else if (_selectedSphotType.isEmpty) {
  errorMessage = 'Sélectionnez le type de SPHOT.';
} else if (_selectedSphotType == 'AUTRE' &&
    _sphotOtherTypeController.text.trim().isEmpty) {
  errorMessage =
      'Précisez l’autre type de SPHOT.';
} else if (_selectedSphotEquipments.contains('AUTRE') &&
        _sphotOtherEquipmentController.text.trim().isEmpty) {
      errorMessage = 'Précisez l’autre équipement du SPHOT.';
    } else if (_selectedSphotLabels.contains('AUTRE') &&
        _sphotOtherLabelController.text.trim().isEmpty) {
      errorMessage = 'Précisez l’autre label du SPHOT.';
    }

    if (errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
      return;
    }

    setState(() {
      _isSavingSphot = true;
    });

    try {
      final spots = FirebaseFirestore.instance
          .collection('territoires')
          .doc(territoireId)
          .collection('spots');
      final documentId = _editingSphotDocId?.trim().isNotEmpty == true
          ? _editingSphotDocId!.trim()
          : idSphot;
      final targetDocument = spots.doc(documentId);

      if (!wasEditing && (await targetDocument.get()).exists) {
        throw StateError(
          'Un SPHOT portant déjà le numéro $idSphot existe dans ce territoire.',
        );
      }

      final territorySnapshot = await FirebaseFirestore.instance
          .collection('territoires')
          .doc(territoireId)
          .get();
      final territoryData = territorySnapshot.data() ?? <String, dynamic>{};

      final data = <String, dynamic>{
        'idSphot': idSphot,
        'nomSphot': _sphotNameController.text.trim(),
        'typeSphot': _selectedSphotType,

'autreTypeSphot':
    _selectedSphotType == 'AUTRE'
        ? _sphotOtherTypeController.text.trim()
        : '',

'isPosteSecours':
    _selectedSphotType == '🚨 POSTE DE SECOURS 🚨',
        'sphotLat': lat,
        'sphotLng': lng,
        'equipement': _selectedSphotEquipments.join(' | '),

        'autreEquipement': _selectedSphotEquipments.contains('AUTRE')
            ? _sphotOtherEquipmentController.text.trim()
            : '',

        'labelSphot': _selectedSphotLabels.join(' | '),

        'autreLabel': _selectedSphotLabels.contains('AUTRE')
            ? _sphotOtherLabelController.text.trim()
            : '',

        'webcamUrl': _sphotWebcamUrlController.text.trim(),
        'pays': territoryData['pays'] ?? '',
        'region': territoryData['region'] ?? '',
        'departement': territoryData['departement'] ?? '',
        'ville': territoryData['ville'] ?? '',
        'villeLat': territoryData['villeLat'] ?? 0.0,
        'villeLng': territoryData['villeLng'] ?? 0.0,
        'logoVille': territoryData['logoVille'] ?? '',
        'siteInternetVille': territoryData['siteInternetVille'] ?? '',
        'arretesMunicipaux': territoryData['arretesMunicipaux'] ?? '',
        'territoireId': territoireId,
        'source': 'admin',
        'sphotValide': true,
        'dateValidation': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!wasEditing) {
        data['createdAt'] = FieldValue.serverTimestamp();
      }

      await targetDocument.set(data, SetOptions(merge: true));

      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingSphot = false;
        _showSphotEditorPanel = false;
        _placingSphotOnMap = false;
        _selectedSpot = null;
        _clearSphotEditor();
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSavingSphot = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enregistrement impossible : $error'),
          backgroundColor: redColor,
        ),
      );
    }
  }

  Future<void> _deleteSphotFromSummary(Map<String, dynamic> spot) async {
    final documentId = _cleanText(spot['_docId'] ?? spot['idSphot']);

    final territoireId = _resolvedTerritoireId.trim();

    if (documentId.isEmpty || territoireId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’identifier le SPHOT à supprimer.'),
          backgroundColor: redColor,
        ),
      );
      return;
    }

    final sphotName = _spotName(spot);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'SUPPRIMER CE SPHOT',
            style: TextStyle(color: redColor, fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Voulez-vous vraiment supprimer le SPHOT '
            '« $sphotName » ?\n\n'
            'Cette action est définitive.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ANNULER'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('SUPPRIMER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: redColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('territoires')
          .doc(territoireId)
          .collection('spots')
          .doc(documentId)
          .delete();

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedSpot = null;
        _showTrialSummaryPanel = true;
        _showSubscriptionPanel = false;
        _showBillingDocumentsPanel = false;
        _trialSummaryPanelFuture = _loadTrialSummaryData();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SPHOT supprimé avec succès.'),
          backgroundColor: adminColor,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suppression impossible : $error'),
          backgroundColor: redColor,
        ),
      );
    }
  }

  Future<void> _deleteSphotFromDashboard() async {
    final documentId = _editingSphotDocId?.trim() ?? '';

    final territoireId = _activeTerritoireId.trim().isNotEmpty
        ? _activeTerritoireId.trim()
        : widget.territoireId.trim();

    if (documentId.isEmpty || territoireId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’identifier le SPHOT à supprimer.'),
          backgroundColor: redColor,
        ),
      );
      return;
    }

    final sphotName = _sphotNameController.text.trim().isNotEmpty
        ? _sphotNameController.text.trim()
        : _sphotIdController.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'SUPPRIMER CE SPHOT',
            style: TextStyle(color: redColor, fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Voulez-vous vraiment supprimer le SPHOT '
            '« $sphotName » ?\n\n'
            'Cette action est définitive.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('ANNULER'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('SUPPRIMER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: redColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isSavingSphot = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('territoires')
          .doc(territoireId)
          .collection('spots')
          .doc(documentId)
          .delete();

      if (!mounted) return;

      setState(() {
        _isSavingSphot = false;
        _showSphotEditorPanel = false;
        _placingSphotOnMap = false;
        _selectedSpot = null;
        _clearSphotEditor();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SPHOT supprimé avec succès.'),
          backgroundColor: adminColor,
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSavingSphot = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suppression impossible : $error'),
          backgroundColor: redColor,
        ),
      );
    }
  }

  Widget _sphotEditorField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool readOnly = false,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      inputFormatters: inputFormatters,

      style: const TextStyle(
        color: adminColor,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),

      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: adminColor,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: adminColor.withOpacity(0.035),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: adminColor.withOpacity(0.55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: adminColor, width: 1.8),
        ),
      ),
    );
  }

  Widget _sphotMultiDropdown({
    required GlobalKey fieldKey,
    required String label,
    required List<String> choices,
    required Set<String> selectedValues,
    TextEditingController? otherController,
    double maxMenuHeight = 245,
  }) {
    final displayText = selectedValues.isEmpty
        ? label
        : selectedValues
              .map((value) => _sphotLabelDisplayNames[value] ?? value)
              .join('\n');

    return GestureDetector(
      key: fieldKey,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _openSphotMultiChoiceMenu(
          fieldKey: fieldKey,
          choices: choices,
          selectedValues: selectedValues,
          otherController: otherController,
          maxMenuHeight: maxMenuHeight,
        );
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: selectedValues.isEmpty ? null : label,
          labelStyle: const TextStyle(
            color: adminColor,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: adminColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(Icons.checklist_rounded, color: adminColor, size: 22),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: adminColor,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sphotTypeLabel(
    String type, {
    double fontSize = 14,
  }) {
    if (type == _rescueStationType) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
  scaleX: 0.4,
  scaleY: 0.7,
  alignment: Alignment.centerLeft,
  child: AdaptiveAssetImage(
    _rescueStationFlagAsset,
    width: 13,
    height: 20,
    fit: BoxFit.contain,
  ),
),
          Flexible(
  child: Transform.translate(
    offset: const Offset(-13, 0),
    child: Text(
      'POSTE DE SECOURS',
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: adminColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
),
        ],
      );
    }

    return Text(
      type.isEmpty ? 'Type de SPHOT' : type,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: adminColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  void _openSphotTypeMenu() {
  _dropdownOverlay?.remove();
  _dropdownOverlay = null;

  final renderBox =
      _sphotTypeKey.currentContext!.findRenderObject()
          as RenderBox;

  final position =
      renderBox.localToGlobal(Offset.zero);

  final size = renderBox.size;
  final scrollController = ScrollController();

  void closeMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;
  }

  void scrollToOtherField() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!scrollController.hasClients) {
          return;
        }

        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      },
    );
  }

  _dropdownOverlay = OverlayEntry(
    builder: (context) {
      return StatefulBuilder(
        builder: (context, overlaySetState) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: closeMenu,
                  child: Container(
                    color: Colors.transparent,
                  ),
                ),
              ),
              Positioned(
                left: position.dx,
                top: position.dy + size.height - 12,
                width: size.width,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(
                      maxHeight: 290,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.97),
                      border: const Border(
                        left: BorderSide(
                          color: adminColor,
                          width: 1.4,
                        ),
                        right: BorderSide(
                          color: adminColor,
                          width: 1.4,
                        ),
                        bottom: BorderSide(
                          color: adminColor,
                          width: 1.4,
                        ),
                      ),
                      borderRadius:
                          const BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                        bottomRight: Radius.circular(10),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ScrollbarTheme(
                      data: const ScrollbarThemeData(
                        thumbColor:
                            MaterialStatePropertyAll<Color>(
                          adminColor,
                        ),
                        thumbVisibility:
                            MaterialStatePropertyAll<bool>(
                          true,
                        ),
                        thickness:
                            MaterialStatePropertyAll<double>(
                          9,
                        ),
                        radius: Radius.circular(10),
                      ),
                      child: Scrollbar(
                        controller: scrollController,
                        thumbVisibility: true,
                        thickness: 9,
                        radius: const Radius.circular(10),
                        child: ListView.builder(
                          controller: scrollController,
                          primary: false,
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount:
                              _sphotTypeChoices.length,
                          itemBuilder: (context, index) {
                            final choice =
                                _sphotTypeChoices[index];

                            final selected =
                                _selectedSphotType ==
                                    choice;

                            final showOtherField =
                                choice == 'AUTRE' &&
                                    selected;

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () {
                                    if (choice ==
                                        'AUTRE') {
                                      setState(() {
                                        _selectedSphotType =
                                            'AUTRE';
                                      });

                                      overlaySetState(() {});
                                      scrollToOtherField();
                                      return;
                                    }

                                    setState(() {
                                      _selectedSphotType =
                                          choice;

                                      _sphotOtherTypeController
                                          .clear();
                                    });

                                    closeMenu();
                                  },
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 9,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _sphotTypeLabel(
                                            choice,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (selected)
                                          const Icon(
                                            Icons
                                                .check_rounded,
                                            color: redColor,
                                            size: 20,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Champ placé dans le menu,
                                // directement sous AUTRE.
                                if (showOtherField)
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(
                                      14,
                                      0,
                                      16,
                                      10,
                                    ),
                                    child: TextField(
                                      controller:
                                          _sphotOtherTypeController,
                                      autofocus: true,
                                      textCapitalization:
                                          TextCapitalization
                                              .sentences,
                                      onSubmitted: (_) {
                                        closeMenu();
                                      },
                                      decoration:
                                          InputDecoration(
                                        labelText:
                                            'Précisez :',
                                        isDense: true,
                                        filled: true,
                                        fillColor: adminColor
                                            .withOpacity(0.035),
                                        contentPadding:
                                            const EdgeInsets
                                                .symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        enabledBorder:
                                            OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius
                                                  .circular(10),
                                          borderSide:
                                              BorderSide(
                                            color: adminColor
                                                .withOpacity(
                                              0.55,
                                            ),
                                          ),
                                        ),
                                        focusedBorder:
                                            OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius
                                                  .circular(10),
                                          borderSide:
                                              const BorderSide(
                                            color: adminColor,
                                            width: 1.7,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  Overlay.of(context).insert(_dropdownOverlay!);

  if (_selectedSphotType == 'AUTRE') {
    scrollToOtherField();
  }
}

  void _openSphotMultiChoiceMenu({
    required GlobalKey fieldKey,
    required List<String> choices,
    required Set<String> selectedValues,
    required double maxMenuHeight,
    TextEditingController? otherController,
  }) {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;

    final renderBox = fieldKey.currentContext!.findRenderObject() as RenderBox;

    final position = renderBox.localToGlobal(Offset.zero);

    final size = renderBox.size;
    final scrollController = ScrollController();

    void closeMenu() {
      _dropdownOverlay?.remove();
      _dropdownOverlay = null;
    }

    void scrollToOtherField() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) {
          return;
        }

        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, overlaySetState) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: closeMenu,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: position.dx,
                  top: position.dy + size.height - 12,
                  width: size.width,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: BoxConstraints(maxHeight: maxMenuHeight),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.97),
                        border: const Border(
                          left: BorderSide(color: adminColor, width: 1.4),
                          right: BorderSide(color: adminColor, width: 1.4),
                          bottom: BorderSide(color: adminColor, width: 1.4),
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(10),
                          bottomRight: Radius.circular(10),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ScrollbarTheme(
                        data: const ScrollbarThemeData(
                          thumbColor: MaterialStatePropertyAll<Color>(
                            adminColor,
                          ),
                          trackVisibility: MaterialStatePropertyAll<bool>(
                            false,
                          ),
                        ),
                        child: Scrollbar(
                          controller: scrollController,
                          thumbVisibility: true,
                          thickness: 10,
                          radius: const Radius.circular(10),
                          child: ListView.builder(
                            controller: scrollController,
                            primary: false,
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: choices.length,
                            itemBuilder: (context, index) {
                              final choice = choices[index];

                              final selected = selectedValues.contains(choice);

                              final choiceIconPath =
                                  _sphotLabelIconPaths[choice];

                              final displayedChoice =
                                  _sphotLabelDisplayNames[choice] ?? choice;

                              final showOtherField =
                                  choice == 'AUTRE' &&
                                  selected &&
                                  otherController != null;

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      final selectingOther =
                                          choice == 'AUTRE' && !selected;

                                      setState(() {
                                        if (choice == 'AUCUN') {
                                          if (selected) {
                                            selectedValues.clear();
                                          } else {
                                            selectedValues
                                              ..clear()
                                              ..add(choice);
                                          }
                                        } else {
                                          selectedValues.remove('AUCUN');

                                          if (selected) {
                                            selectedValues.remove(choice);

                                            if (choice == 'AUTRE') {
                                              otherController?.clear();
                                            }
                                          } else {
                                            if (_sphotWaterQualityChoices
                                                .contains(choice)) {
                                              selectedValues.removeAll(
                                                _sphotWaterQualityChoices,
                                              );
                                            }

                                            if (_sphotHandiplageChoices
                                                .contains(choice)) {
                                              selectedValues.removeAll(
                                                _sphotHandiplageChoices,
                                              );
                                            }

                                            selectedValues.add(choice);
                                          }
                                        }
                                      });

                                      overlaySetState(() {});

                                      if (selectingOther) {
                                        scrollToOtherField();
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            selected
                                                ? Icons.check_box_rounded
                                                : Icons
                                                      .check_box_outline_blank_rounded,
                                            color: selected
                                                ? redColor
                                                : adminColor,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 10),
                                          if (choiceIconPath != null) ...[
                                            SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: Image.asset(
                                                choiceIconPath,
                                                fit: BoxFit.contain,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return const Icon(
                                                        Icons
                                                            .image_not_supported_outlined,
                                                        color: adminColor,
                                                        size: 20,
                                                      );
                                                    },
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                          ],
                                          Expanded(
                                            child: Text(
                                              displayedChoice,
                                              style: const TextStyle(
                                                color: adminColor,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Le champ est situé dans le menu,
                                  // directement sous AUTRE.
                                  if (showOtherField)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        46,
                                        0,
                                        16,
                                        10,
                                      ),
                                      child: TextField(
                                        controller: otherController,
                                        autofocus: true,
                                        textCapitalization:
                                            TextCapitalization.sentences,
                                        onSubmitted: (_) {
                                          closeMenu();
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Précisez :',
                                          isDense: true,
                                          filled: true,
                                          fillColor: adminColor.withOpacity(
                                            0.035,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 10,
                                              ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            borderSide: BorderSide(
                                              color: adminColor.withOpacity(
                                                0.55,
                                              ),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            borderSide: const BorderSide(
                                              color: adminColor,
                                              width: 1.7,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

  Widget _sphotSectionTitle(int number, String title) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$number',
            style: const TextStyle(color: redColor),
          ),
          TextSpan(
            text: '. $title',
            style: const TextStyle(color: adminColor),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
    );
  }

  Widget _sauveteurSectionTitle(int number, String title) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$number. ',
            style: const TextStyle(color: redColor),
          ),
          TextSpan(
            text: title,
            style: const TextStyle(color: adminColor),
          ),
        ],
      ),
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _sauveteurCiviliteField() {
    return GestureDetector(
      key: _sauveteurCiviliteKey,
      behavior: HitTestBehavior.opaque,
      onTap: _openSauveteurCiviliteMenu,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _sauveteurCivilite == null ? null : 'Civilité',
          labelStyle: const TextStyle(
            color: adminColor,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: adminColor.withOpacity(0.035),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: adminColor, width: 1.6),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _sauveteurCivilite ?? 'Civilité',
                style: const TextStyle(
                  color: adminColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: adminColor,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }

  void _openSauveteurCiviliteMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;

    final fieldContext = _sauveteurCiviliteKey.currentContext;

    if (fieldContext == null) {
      return;
    }

    final renderBox = fieldContext.findRenderObject() as RenderBox;

    final position = renderBox.localToGlobal(Offset.zero);

    final size = renderBox.size;

    const civiliteChoices = <String>['Monsieur', 'Madame'];

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _dropdownOverlay?.remove();
                  _dropdownOverlay = null;
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: position.dx,
              top: position.dy + size.height - 12,
              width: size.width,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.94),
                    border: const Border(
                      left: BorderSide(color: adminColor, width: 1.4),
                      right: BorderSide(color: adminColor, width: 1.4),
                      bottom: BorderSide(color: adminColor, width: 1.4),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: civiliteChoices.map((choice) {
                      final selected = _sauveteurCivilite == choice;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _sauveteurCivilite = choice;
                            if (_editingSauveteurDocId != null) {
                              _sauveteurHasUnsavedChanges = true;
                            }
                          });

                          _dropdownOverlay?.remove();
                          _dropdownOverlay = null;
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  choice,
                                  style: TextStyle(
                                    color: selected ? redColor : adminColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  Icons.check_rounded,
                                  color: redColor,
                                  size: 21,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_dropdownOverlay!);
  }

  Widget _sauveteurEditorField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
    bool forceUppercase = false,
    bool capitalizeFirstLetter = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      textCapitalization: keyboardType == TextInputType.emailAddress
          ? TextCapitalization.none
          : forceUppercase
          ? TextCapitalization.characters
          : TextCapitalization.sentences,
      onChanged: (value) {
        var normalizedValue = value;

        if (forceUppercase) {
          normalizedValue = value.toUpperCase();
        } else if (capitalizeFirstLetter && value.isNotEmpty) {
          normalizedValue =
              value.substring(0, 1).toUpperCase() + value.substring(1);
        }

        if (normalizedValue != value) {
          controller.value = TextEditingValue(
            text: normalizedValue,
            selection: TextSelection.collapsed(offset: normalizedValue.length),
          );
        }

        if (mounted) {
          setState(() {
            if (_editingSauveteurDocId != null) {
              _sauveteurHasUnsavedChanges = true;
            }
          });
        }
      },
      style: const TextStyle(
        color: adminColor,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: maxLines > 1,
        labelStyle: const TextStyle(
          color: adminColor,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: adminColor.withOpacity(0.035),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 13,
        ),
        suffixIcon: onTap == null
            ? null
            : const Icon(Icons.calendar_month_rounded, color: adminColor),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: adminColor.withOpacity(0.55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: adminColor, width: 1.8),
        ),
      ),
    );
  }

  Widget _buildSauveteurFunctionsField() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: adminColor.withOpacity(0.025),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: adminColor.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fonction(s)',
            style: TextStyle(color: adminColor, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Column(
            children: _sauveteurFonctionChoices.map((fonction) {
              final selected = _sauveteurFonctions.contains(fonction);
              return CheckboxListTile(
                dense: true,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: adminColor,
                value: selected,
                title: Text(
                  fonction,
                  style: const TextStyle(
                    color: adminColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _sauveteurFonctions.add(fonction);
                    } else {
                      _sauveteurFonctions.remove(fonction);
                    }
                    if (_editingSauveteurDocId != null) {
                      _sauveteurHasUnsavedChanges = true;
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSauveteurPostesField() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('territoires')
          .doc(_resolvedTerritoireId)
          .collection('spots')
          .where('typeSphot', isEqualTo: '🚨 POSTE DE SECOURS 🚨')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Chargement des postes impossible : ${snapshot.error}',
            style: const TextStyle(color: redColor),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aData = a.data();
            final bData = b.data();
            final aName = _cleanText(
              aData['nomSecours'] ?? aData['nomSphot'] ?? aData['sphotName'],
            );
            final bName = _cleanText(
              bData['nomSecours'] ?? bData['nomSphot'] ?? bData['sphotName'],
            );
            return aName.compareTo(bName);
          });

        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: adminColor.withOpacity(0.45)),
            ),
            child: const Text(
              'Aucun poste de secours disponible.',
              style: TextStyle(color: adminColor, fontWeight: FontWeight.w700),
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: adminColor.withOpacity(0.025),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: adminColor.withOpacity(0.55)),
          ),
          child: Column(
            children: docs.map((doc) {
              final data = doc.data();
              final numeroSphot = _cleanText(data['idSphot'] ?? doc.id);
              final nomPoste = _cleanText(
                data['nomSecours'] ?? data['nomSphot'] ?? data['sphotName'],
              );
              final label = <String>[
                numeroSphot,
                nomPoste,
              ].where((value) => value.isNotEmpty).join(' - ');
              final selected = _sauveteurPostes.contains(doc.id);

              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: selected,
                activeColor: adminColor,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  label.isEmpty ? doc.id : label,
                  style: const TextStyle(
                    color: adminColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _sauveteurPostes.add(doc.id);
                    } else {
                      _sauveteurPostes.remove(doc.id);
                    }
                    if (_editingSauveteurDocId != null) {
                      _sauveteurHasUnsavedChanges = true;
                    }
                  });
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildSauveteurPeriodesField() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('territoires')
          .doc(_resolvedTerritoireId)
          .collection('periodesSurveillance')
          .orderBy('startDate')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Chargement des périodes impossible : ${snapshot.error}',
            style: const TextStyle(
              color: redColor,
              fontWeight: FontWeight.w700,
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final periods = snapshot.data!.docs;

        if (periods.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: adminColor, width: 1.4),
            ),
            child: const Text(
              'Aucune période de surveillance enregistrée.',
              style: TextStyle(color: adminColor, fontWeight: FontWeight.w700),
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: adminColor.withOpacity(0.025),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: adminColor.withOpacity(0.55)),
          ),
          child: Column(
            children: periods.map((periodDocument) {
              final data = periodDocument.data();
              final periodId = periodDocument.id;

              final periodName = (data['name'] ?? 'PÉRIODE SANS NOM')
                  .toString()
                  .toUpperCase();

              final startDateValue = data['startDate'];
              final endDateValue = data['endDate'];

              final startDate = startDateValue is Timestamp
                  ? _formatSurveillanceDate(startDateValue.toDate())
                  : '--/--/----';

              final endDate = endDateValue is Timestamp
                  ? _formatSurveillanceDate(endDateValue.toDate())
                  : '--/--/----';

              final rawStartHour = (data['startHour'] ?? '--:--').toString();

              final rawEndHour = (data['endHour'] ?? '--:--').toString();

              final rawSecondStartHour = (data['secondStartHour'] ?? '')
                  .toString();

              final rawSecondEndHour = (data['secondEndHour'] ?? '').toString();

              final startHour = rawStartHour.replaceFirst(':', 'h');
              final endHour = rawEndHour.replaceFirst(':', 'h');
              final secondStartHour = rawSecondStartHour.replaceFirst(':', 'h');
              final secondEndHour = rawSecondEndHour.replaceFirst(':', 'h');

              final hasSecondSlot =
                  secondStartHour.isNotEmpty && secondEndHour.isNotEmpty;

              final selected = _sauveteurPeriodesSurveillance.contains(
                periodId,
              );

              return Column(
                children: [
                  CheckboxListTile(
                    dense: true,
                    value: selected,
                    activeColor: adminColor,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          periodName,
                          style: const TextStyle(
                            color: redColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'DU $startDate AU $endDate',
                          style: const TextStyle(
                            color: adminColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'DE $startHour À $endHour',
                          style: const TextStyle(
                            color: adminColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (hasSecondSlot) ...[
                          const SizedBox(height: 3),
                          Text(
                            'DE $secondStartHour À '
                            '$secondEndHour',
                            style: const TextStyle(
                              color: adminColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _sauveteurPeriodesSurveillance.add(periodId);
                        } else {
                          _sauveteurPeriodesSurveillance.remove(periodId);
                        }
                        if (_editingSauveteurDocId != null) {
                          _sauveteurHasUnsavedChanges = true;
                        }
                      });
                    },
                  ),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildSurveillancePeriodsPanel() {
    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.45), width: 1.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 6),
                    Transform.translate(
                      offset: const Offset(-12, 0),
                      child: Transform.scale(
                        scale: 1.5,
                        alignment: Alignment.center,
                        child: AdaptiveAssetImage(
                          'data/icons/fire_red_icon.svg',
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'CRÉER UNE PÉRIODE',
                        style: TextStyle(
                          color: adminColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      onPressed: () {
                        setState(() {
                          _showSurveillancePeriodsPanel = false;
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _openSurveillancePeriodDialog();
                    },
                    icon: const Icon(
                      Icons.add_rounded,
                      color: redColor,
                      size: 28,
                    ),
                    label: const Text(
                      'CRÉER UNE PÉRIODE DE SURVEILLANCE',
                      style: TextStyle(
                        color: adminColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: adminColor, width: 1.7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'PÉRIODES DE SURVEILLANCE ENREGISTRÉES',
                  style: TextStyle(
                    color: adminColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('territoires')
                        .doc(_resolvedTerritoireId)
                        .collection('periodesSurveillance')
                        .orderBy('startDate')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Chargement impossible : ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: redColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'Aucune période de surveillance créée.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: adminColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final startDateValue = data['startDate'];
                          final endDateValue = data['endDate'];

                          if (startDateValue is! Timestamp ||
                              endDateValue is! Timestamp) {
                            return const SizedBox.shrink();
                          }

                          final period = _DashboardSurveillancePeriod(
                            id: doc.id,
                            name: _cleanText(data['name']),
                            startDate: startDateValue.toDate(),
                            endDate: endDateValue.toDate(),
                            startHour:
                                _parseSurveillanceTime(data['startHour']) ??
                                const TimeOfDay(hour: 0, minute: 0),
                            endHour:
                                _parseSurveillanceTime(data['endHour']) ??
                                const TimeOfDay(hour: 0, minute: 0),
                            secondStartHour: _parseSurveillanceTime(
                              data['secondStartHour'],
                            ),
                            secondEndHour: _parseSurveillanceTime(
                              data['secondEndHour'],
                            ),
                          );

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: adminColor.withOpacity(0.035),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: adminColor, width: 1.4),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        period.name.toUpperCase(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: redColor,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        'DU ${_formatSurveillanceDate(period.startDate)} '
                                        'AU ${_formatSurveillanceDate(period.endDate)}',
                                        style: const TextStyle(
                                          color: adminColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _formatSurveillancePeriodHours(period),
                                        style: const TextStyle(
                                          color: adminColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Modifier',
                                  onPressed: () {
                                    _openSurveillancePeriodDialog(
                                      period: period,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.edit_rounded,
                                    color: adminColor,
                                    size: 21,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Supprimer',
                                  onPressed: () {
                                    _deleteSurveillancePeriod(period);
                                  },
                                  icon: const Icon(
                                    Icons.delete_rounded,
                                    color: redColor,
                                    size: 21,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<List<String>> _loadSauveteurPostLabels(List<String> posteIds) async {
    final labels = await Future.wait(
      posteIds.map((posteId) async {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('territoires')
              .doc(_resolvedTerritoireId)
              .collection('spots')
              .doc(posteId)
              .get();

          final data = snapshot.data() ?? <String, dynamic>{};
          final numero = _cleanText(data['idSphot'] ?? posteId);
          final nom = _cleanText(
            data['nomSecours'] ?? data['nomSphot'] ?? data['sphotName'],
          );

          return <String>[
            numero,
            nom,
          ].where((value) => value.isNotEmpty).join(' - ');
        } catch (_) {
          return posteId;
        }
      }),
    );

    return labels.where((label) => label.isNotEmpty).toList();
  }

  Future<List<String>> _loadSauveteurPeriodeLabels(
    List<String> periodeIds,
  ) async {
    final labels = await Future.wait(
      periodeIds.map((periodeId) async {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('territoires')
              .doc(_resolvedTerritoireId)
              .collection('periodesSurveillance')
              .doc(periodeId)
              .get();

          final data = snapshot.data() ?? <String, dynamic>{};

          final label = _cleanText(data['label']);
          if (label.isNotEmpty) {
            return label;
          }

          final name = _cleanText(data['name']);
          return name.isNotEmpty ? name : periodeId;
        } catch (_) {
          return periodeId;
        }
      }),
    );

    return labels.where((label) => label.isNotEmpty).toList();
  }

  Widget _buildSauveteursManagementPanel() {
    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.45), width: 1.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.groups_rounded, color: redColor, size: 30),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'GESTION DES SAUVETEURS',
                        style: TextStyle(
                          color: adminColor,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      onPressed: () {
                        setState(() {
                          _showSauveteursManagementPanel = false;
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Modifiez ou supprimez les sauveteurs enregistrés',
                  style: TextStyle(
                    color: adminColor.withOpacity(0.75),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('territoires')
                        .doc(_resolvedTerritoireId)
                        .collection('sauveteurs')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Chargement impossible : '
                            '${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: redColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final documents = [...snapshot.data!.docs];

                      documents.sort((a, b) {
                        final dataA = a.data();
                        final dataB = b.data();
                        final nomA = _cleanText(dataA['nom']).toUpperCase();
                        final nomB = _cleanText(dataB['nom']).toUpperCase();
                        final nomComparison = nomA.compareTo(nomB);

                        if (nomComparison != 0) {
                          return nomComparison;
                        }

                        return _cleanText(
                          dataA['prenom'],
                        ).toUpperCase().compareTo(
                          _cleanText(dataB['prenom']).toUpperCase(),
                        );
                      });

                      if (documents.isEmpty) {
                        return const Center(
                          child: Text(
                            'Aucun sauveteur enregistré.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: adminColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: documents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final document = documents[index];
                          final data = document.data();
                          final nom = _cleanText(data['nom']).toUpperCase();
                          final prenom = _cleanText(data['prenom']);
                          final telephone = _cleanText(data['telephone']);
                          final email = _cleanText(data['email']);
                          final fonctions =
                              (data['fonctions'] as List? ?? const [])
                                  .map((value) => value.toString())
                                  .where((value) => value.isNotEmpty)
                                  .join(' • ');
                          final posteIds =
                              (data['postesAffectes'] as List? ?? const [])
                                  .map((value) => value.toString())
                                  .where((value) => value.isNotEmpty)
                                  .toList();

                          final periodeIds =
                              (data['periodesSurveillance'] as List? ??
                                      const [])
                                  .map((value) => value.toString())
                                  .where((value) => value.isNotEmpty)
                                  .toList();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: adminColor.withOpacity(0.025),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: adminColor.withOpacity(0.65),
                                width: 1.4,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: redColor.withOpacity(0.10),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.person_rounded,
                                    color: redColor,
                                    size: 25,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$nom $prenom'.trim(),
                                        style: const TextStyle(
                                          color: redColor,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      if (telephone.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          telephone,
                                          style: const TextStyle(
                                            color: adminColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                      if (email.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          email,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: adminColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                      if (fonctions.isNotEmpty) ...[
                                        const SizedBox(height: 5),
                                        Text(
                                          fonctions,
                                          style: TextStyle(
                                            color: adminColor.withOpacity(0.72),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 5),
                                      FutureBuilder<List<String>>(
                                        future: _loadSauveteurPostLabels(
                                          posteIds,
                                        ),
                                        builder: (context, postSnapshot) {
                                          if (!postSnapshot.hasData) {
                                            return const Text(
                                              'Chargement des postes...',
                                              style: TextStyle(
                                                color: adminColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            );
                                          }

                                          final labels = postSnapshot.data!;

                                          return Text(
                                            labels.isEmpty
                                                ? 'Aucun poste affecté'
                                                : labels.join('\n'),
                                            style: const TextStyle(
                                              color: adminColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              height: 1.35,
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 6),
                                      FutureBuilder<List<String>>(
                                        future: _loadSauveteurPeriodeLabels(
                                          periodeIds,
                                        ),
                                        builder: (context, periodeSnapshot) {
                                          if (!periodeSnapshot.hasData) {
                                            return const Text(
                                              'Chargement des périodes...',
                                              style: TextStyle(
                                                color: adminColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            );
                                          }

                                          final labels = periodeSnapshot.data!;

                                          if (labels.isEmpty) {
                                            return const Text(
                                              'Aucune période affectée',
                                              style: TextStyle(
                                                color: adminColor,
                                                decoration: TextDecoration.none,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            );
                                          }

                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ...labels.asMap().entries.map((
                                                entry,
                                              ) {
                                                final parts = entry.value.split(
                                                  ' — ',
                                                );

                                                final periodTitle =
                                                    parts.isNotEmpty
                                                    ? parts.first
                                                    : '';

                                                final periodDates =
                                                    parts.length >= 2
                                                    ? parts[1]
                                                    : '';

                                                final periodHours =
                                                    parts.length >= 3
                                                    ? parts.sublist(2)
                                                    : <String>[];

                                                return Padding(
                                                  padding: EdgeInsets.only(
                                                    top: entry.key == 0 ? 0 : 9,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      if (periodTitle
                                                          .isNotEmpty)
                                                        Text(
                                                          periodTitle,
                                                          style: const TextStyle(
                                                            color: adminColor,
                                                            decoration:
                                                                TextDecoration
                                                                    .none,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            height: 1.25,
                                                          ),
                                                        ),

                                                      if (periodDates
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          periodDates,
                                                          style: const TextStyle(
                                                            color: adminColor,
                                                            decoration:
                                                                TextDecoration
                                                                    .none,
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            height: 1.25,
                                                          ),
                                                        ),
                                                      ],

                                                      ...periodHours.map(
                                                        (hours) => Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 2,
                                                              ),
                                                          child: Text(
                                                            hours,
                                                            style: const TextStyle(
                                                              color: adminColor,
                                                              decoration:
                                                                  TextDecoration
                                                                      .none,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              height: 1.25,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                            ],
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Column(
                                  children: [
                                    IconButton(
                                      tooltip: 'Modifier',
                                      onPressed: () {
                                        _openSauveteurForEditing(
                                          document.id,
                                          data,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        color: adminColor,
                                        size: 21,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Supprimer',
                                      onPressed: () {
                                        _deleteSauveteur(document.id, data);
                                      },
                                      icon: const Icon(
                                        Icons.delete_rounded,
                                        color: redColor,
                                        size: 21,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSauveteurEditorPanel() {
    final contactOk =
        _sauveteurTelephoneController.text.trim().isNotEmpty &&
        _sauveteurEmailController.text.trim().contains('@');

    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.45), width: 1.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 6),
                    Transform.translate(
                      offset: const Offset(-12, 0),
                      child: Transform.scale(
                        scale: 1.5,
                        alignment: Alignment.center,
                        child: AdaptiveAssetImage(
                          'data/icons/fire_red_icon.svg',
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _editingSauveteurDocId == null
                            ? 'CRÉER UN SAUVETEUR'
                            : 'MODIFIER LE SAUVETEUR',
                        style: const TextStyle(
                          color: adminColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      onPressed: () {
                        final returnToSummary = _editingSauveteurDocId != null;

                        setState(() {
                          _showSauveteurEditorPanel = false;
                          _showSauveteursManagementPanel = false;

                          _showTrialSummaryPanel = returnToSummary;

                          _trialSummaryPanelFuture = returnToSummary
                              ? _loadTrialSummaryData()
                              : null;

                          _clearSauveteurEditor();
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sauveteurSectionTitle(1, 'IDENTITÉ'),
                        const SizedBox(height: 9),
                        _sauveteurCiviliteField(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _sauveteurEditorField(
                                controller: _sauveteurNomController,
                                label: 'NOM',
                                forceUppercase: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _sauveteurEditorField(
                                controller: _sauveteurPrenomController,
                                label: 'Prénom',
                                capitalizeFirstLetter: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _sauveteurEditorField(
                                controller: _sauveteurDateNaissanceController,
                                label: 'Date de naissance',
                                readOnly: true,
                                onTap: _selectSauveteurBirthDate,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 92,
                              child: _sauveteurEditorField(
                                controller: _sauveteurAgeController,
                                label: 'Âge',
                                readOnly: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _sauveteurSectionTitle(2, 'COORDONNÉES'),
                        const SizedBox(height: 9),
                        _sauveteurEditorField(
                          controller: _sauveteurAdresseController,
                          label: 'Adresse',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 125,
                              child: _sauveteurEditorField(
                                controller: _sauveteurCodePostalController,
                                label: 'Code postal',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _sauveteurEditorField(
                                controller: _sauveteurVilleController,
                                label: 'VILLE',
                                forceUppercase: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _sauveteurEditorField(
                          controller: _sauveteurTelephoneController,
                          label: 'Téléphone',
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            FrenchPhoneNumberFormatter(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _sauveteurEditorField(
                          controller: _sauveteurEmailController,
                          label: 'Email',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 18),
                        _sauveteurSectionTitle(3, 'FONCTION ET EXPÉRIENCE'),
                        const SizedBox(height: 9),
                        _buildSauveteurFunctionsField(),
                        const SizedBox(height: 8),
                        _sauveteurEditorField(
                          controller: _sauveteurExperienceController,
                          label: 'Années d’expérience',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 18),
                        _sauveteurSectionTitle(4, 'POSTE(S) DE SECOURS'),
                        const SizedBox(height: 9),
                        _buildSauveteurPostesField(),
                        const SizedBox(height: 18),

                        _sauveteurSectionTitle(5, 'PÉRIODE(S) DE SURVEILLANCE'),

                        const SizedBox(height: 9),

                        _buildSauveteurPeriodesField(),
                        const SizedBox(height: 18),
                        _sauveteurSectionTitle(6, 'OBSERVATIONS'),
                        const SizedBox(height: 9),
                        _sauveteurEditorField(
                          controller: _sauveteurObservationsController,
                          label: 'Observations',
                          maxLines: 4,
                          inputFormatters: [
                            TextInputFormatter.withFunction((
                              oldValue,
                              newValue,
                            ) {
                              if (newValue.text.isEmpty) {
                                return newValue;
                              }

                              final correctedText =
                                  newValue.text.substring(0, 1).toUpperCase() +
                                  newValue.text.substring(1);

                              return newValue.copyWith(text: correctedText);
                            }),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _sauveteurSectionTitle(7, 'ACCÈS SAUVETEUR'),
                        const SizedBox(height: 9),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: OutlinedButton(
                            onPressed:
                                _isSavingSauveteur ||
                                    (_editingSauveteurDocId != null &&
                                        _sauveteurPasswordRegenerated)
                                ? null
                                : _editingSauveteurDocId != null
                                ? _regenerateSauveteurPassword
                                : _generateSauveteurAccess,
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  (_editingSauveteurDocId != null
                                      ? _sauveteurPasswordRegenerated
                                      : _sauveteurAccessGenerated)
                                  ? Colors.white
                                  : redColor,
                              backgroundColor:
                                  (_editingSauveteurDocId != null
                                      ? _sauveteurPasswordRegenerated
                                      : _sauveteurAccessGenerated)
                                  ? redColor
                                  : Colors.transparent,
                              side: const BorderSide(
                                color: redColor,
                                width: 1.8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              _editingSauveteurDocId != null
                                  ? _sauveteurPasswordRegenerated
                                        ? 'MOT DE PASSE RÉGÉNÉRÉ'
                                        : 'RÉGÉNÉRER LE MOT DE PASSE'
                                  : _sauveteurAccessGenerated
                                  ? 'ACCÈS GÉNÉRÉ'
                                  : 'GÉNÉRER L’ACCÈS',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: adminColor.withOpacity(0.55),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Identifiant : '
                                '${_sauveteurGeneratedLogin.isEmpty ? 'non généré' : _sauveteurGeneratedLogin}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Mot de passe : '
                                '${_sauveteurGeneratedPassword.isEmpty ? 'non généré' : _sauveteurGeneratedPassword}',
                                style: const TextStyle(
                                  color: adminColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_editingSauveteurDocId != null &&
                            _sauveteurPasswordRegenerated) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 42,
                            child: OutlinedButton.icon(
                              onPressed: _sauveteurEmailSent
                                  ? null
                                  : () => _sendSauveteurCredentialsEmail(
                                      isReset: true,
                                    ),
                              icon: Icon(
                                _sauveteurEmailSent
                                    ? Icons.mark_email_read_rounded
                                    : Icons.email_outlined,
                              ),
                              label: Text(
                                _sauveteurEmailSent
                                    ? 'NOUVEAU MOT DE PASSE ENVOYÉ'
                                    : 'ENVOYER LE NOUVEAU MOT DE PASSE',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _sauveteurEmailSent
                                    ? Colors.white
                                    : redColor,
                                backgroundColor: _sauveteurEmailSent
                                    ? redColor
                                    : Colors.transparent,
                                side: const BorderSide(
                                  color: redColor,
                                  width: 1.8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isSavingSauveteur ? null : _saveSauveteur,
                    icon: _isSavingSauveteur
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _isSavingSauveteur
                          ? _editingSauveteurDocId == null
                                ? 'CRÉATION ET ENVOI...'
                                : 'ENREGISTREMENT...'
                          : _editingSauveteurDocId == null
                          ? 'CRÉER UN SAUVETEUR'
                          : 'ENREGISTRER LES MODIFICATIONS',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: ElevatedButton.styleFrom(
                      foregroundColor:
                          _editingSauveteurDocId != null &&
                              _sauveteurHasUnsavedChanges
                          ? Colors.white
                          : redColor,
                      backgroundColor:
                          _editingSauveteurDocId != null &&
                              _sauveteurHasUnsavedChanges
                          ? redColor
                          : Colors.transparent,
                      disabledForegroundColor: Colors.white,
                      disabledBackgroundColor: redColor,
                      elevation: 0,
                      side: const BorderSide(color: redColor, width: 1.8),
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
    );
  }

  Widget _buildSphotEditorPanel() {
    final isEditing = _editingSphotDocId?.trim().isNotEmpty == true;
    final lat = double.tryParse(_sphotLatController.text.trim());
    final lng = double.tryParse(_sphotLngController.text.trim());
    final hasPosition = lat != null && lng != null;
    
    return Container(
      width: 430,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.45), width: 1.5),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 6),
                    Transform.translate(
                      offset: const Offset(-12, 0),
                      child: Transform.scale(
                        scale: 1.5,
                        alignment: Alignment.center,
                        child: AdaptiveAssetImage(
                          'data/icons/fire_red_icon.svg',
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                    const SizedBox(width: 0),
                    Expanded(
                      child: Text(
                        isEditing ? 'MODIFIER LE SPHOT' : 'CRÉER UN SPHOT',
                        style: const TextStyle(
                          color: adminColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      onPressed: () {
                        setState(() {
                          _showSphotEditorPanel = false;
                          _placingSphotOnMap = false;
                          _selectedSpot = null;
                          _clearSphotEditor();
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                _sphotSectionTitle(1, 'EMPLACEMENT'),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _placingSphotOnMap = true;
                      });
                    },
                    icon: AdaptiveAssetImage(
                      'data/icons/fire_red_icon.svg',
                      width: 26,
                      height: 26,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                    label: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          hasPosition
                              ? 'CLIQUEZ ICI PUIS UTILISEZ LA CARTE POUR MODIFIER L’EMPLACEMENT'
                              : 'UTILISEZ LA CARTE POUR L’EMPLACEMENT',
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            color: adminColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),

                    style: OutlinedButton.styleFrom(
                      foregroundColor: adminColor,

                      alignment: Alignment.centerLeft,

                      padding: const EdgeInsets.symmetric(horizontal: 18),

                      side: const BorderSide(color: adminColor, width: 1.6),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _sphotEditorField(
                        controller: _sphotLatController,
                        label: 'Latitude',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _sphotEditorField(
                        controller: _sphotLngController,
                        label: 'Longitude',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _sphotSectionTitle(2, 'IDENTIFICATION'),
                const SizedBox(height: 9),
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: _sphotEditorField(
                        controller: _sphotIdController,
                        label: 'N° SPHOT',
                        inputFormatters: [
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            return newValue.copyWith(
                              text: newValue.text.toUpperCase(),
                              composing: TextRange.empty,
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _sphotEditorField(
                        controller: _sphotNameController,
                        label: 'Nom du SPHOT',
                        inputFormatters: [
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final text = newValue.text;

                            if (text.isEmpty) {
                              return newValue;
                            }

                            final formattedText =
                                text[0].toUpperCase() + text.substring(1);

                            return newValue.copyWith(
                              text: formattedText,
                              composing: TextRange.empty,
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                _sphotSectionTitle(3, 'TYPE'),

                const SizedBox(height: 9),
                Theme(
                  data: Theme.of(context).copyWith(
                    scrollbarTheme: const ScrollbarThemeData(
                      thumbColor: MaterialStatePropertyAll<Color>(adminColor),
                      thumbVisibility: MaterialStatePropertyAll<bool>(true),
                      thickness: MaterialStatePropertyAll<double>(9),
                      radius: Radius.circular(10),
                    ),
                  ),
                  child: GestureDetector(
                    key: _sphotTypeKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: _openSphotTypeMenu,

                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: _selectedSphotType.isEmpty
                            ? null
                            : 'Type de SPHOT',

                        labelStyle: const TextStyle(
                          color: adminColor,
                          fontWeight: FontWeight.w700,
                        ),

                        filled: true,
                        fillColor: Colors.transparent,

                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),

                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: adminColor,
                            width: 1.6,
                          ),
                        ),

                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: adminColor,
                            width: 1.6,
                          ),
                        ),
                      ),

                      child: Row(
                        children: [
                          Expanded(
                            child: _sphotTypeLabel(_selectedSphotType),
                          ),

                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: adminColor,
                            size: 26,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _sphotSectionTitle(4, 'ÉQUIPEMENTS'),

                const SizedBox(height: 5),

                _sphotMultiDropdown(
                  fieldKey: _sphotEquipmentKey,
                  label: 'Équipements du SPHOT',
                  choices: _sphotEquipmentChoices,
                  selectedValues: _selectedSphotEquipments,
                  otherController: _sphotOtherEquipmentController,
                  maxMenuHeight: 240,
                ),

                const SizedBox(height: 14),

                _sphotSectionTitle(5, 'LABELS'),

                const SizedBox(height: 5),

                _sphotMultiDropdown(
                  fieldKey: _sphotLabelKey,
                  label: 'Labels du SPHOT',
                  choices: _sphotLabelChoices,
                  selectedValues: _selectedSphotLabels,
                  otherController: _sphotOtherLabelController,
                  maxMenuHeight: 145,
                ),

                const SizedBox(height: 14),

                _sphotSectionTitle(6, 'WEBCAM'),

                const SizedBox(height: 5),

                _sphotEditorField(
                  controller: _sphotWebcamUrlController,
                  label: 'Adresse internet de la webcam si doté',
                  keyboardType: TextInputType.url,
                ),

                const Spacer(),

                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _isSavingSphot ? null : _saveSphotFromDashboard,

                    icon: _isSavingSphot
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: redColor,
                            ),
                          )
                        : const Icon(Icons.save_rounded),

                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _isSavingSphot
                            ? 'ENREGISTREMENT...'
                            : isEditing
                            ? 'ENREGISTRER LA MODIFICATION DU SPHOT'
                            : 'CRÉER UN SPHOT',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),

                    style: OutlinedButton.styleFrom(
                      foregroundColor: redColor,
                      backgroundColor: Colors.transparent,
                      disabledForegroundColor: redColor.withOpacity(0.55),
                      side: const BorderSide(color: redColor, width: 1.8),
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
    );
  }

  Widget _buildSpotDetailPanel() {
    final spot = _selectedSpot;
    if (spot == null) return const SizedBox.shrink();

    final name = _spotName(spot);
    final type = _cleanText(spot['typeSphot'] ?? 'Non renseigné');
    final nature = _cleanText(spot['natureSphot'] ?? 'Non renseignée');
    final label = _cleanText(spot['labelSphot'] ?? 'Non renseigné');
    final ville = _cleanText(spot['ville'] ?? 'Non renseignée');
    final departement = _cleanText(spot['departement'] ?? 'Non renseigné');
    final region = _cleanText(spot['region'] ?? 'Non renseignée');
    final telephone = _cleanText(spot['telephonePoste'] ?? 'Non renseigné');
    final lat = _toDouble(spot['sphotLat']);
    final lng = _toDouble(spot['sphotLng']);

    return Container(
      width: 420,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(
            color: _spotTypeColor(spot).withOpacity(0.45),
            width: 1.5,
          ),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: _spotTypeColor(spot),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedSpot = null;
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              _spotInfoLine('Type', type),
              _spotInfoLine('Nature', nature),
              _spotInfoLine('Label', label),
              _spotInfoLine('Ville', ville),
              _spotInfoLine('Département', departement),
              _spotInfoLine('Région', region),
              _spotInfoLine('Téléphone', telephone),
              _spotInfoLine('Latitude', lat.toStringAsFixed(6)),
              _spotInfoLine('Longitude', lng.toStringAsFixed(6)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _loadSphotInEditor(spot),
                  icon: const Icon(Icons.edit_location_alt_rounded),
                  label: const Text(
                    'MODIFIER LE SPHOT',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: adminColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvertiserDetailPanel() {
    final advertiser = _selectedAdvertiser;
    if (advertiser == null) return const SizedBox.shrink();

    final companyName = _cleanText(
      advertiser['advertiserName'] ??
          advertiser['companyName'] ??
          advertiser['businessName'] ??
          advertiser['organisation'] ??
          'Annonceur',
    );

    final email = _cleanText(advertiser['email'] ?? 'Non renseigné');
    final phone = _cleanText(advertiser['phone'] ?? 'Non renseigné');
    final websiteUrl = _cleanText(advertiser['websiteUrl'] ?? 'Non renseigné');

    final siret = _cleanText(advertiser['siret'] ?? 'Non renseigné');

    final siren = _cleanText(advertiser['siren'] ?? 'Non renseigné');

    final categoryLabel = _cleanText(
      advertiser['categoryLabel'] ?? 'Non renseignée',
    );

    final durationLabel = _cleanText(
      advertiser['durationLabel'] ?? 'Non renseignée',
    );
    final rawStatus = _cleanText(advertiser['status'] ?? '');

    final campaignStatus = switch (rawStatus.toLowerCase()) {
      'pending' => 'En attente de validation',
      'active' => 'Active',
      'approved' => 'Approuvée',
      'rejected' => 'Refusée',
      'disabled' => 'Désactivée',
      'deleted' => 'Supprimée',
      'finished' => 'Terminée',
      _ => 'Non renseigné',
    };
    final isApproved = rawStatus.toLowerCase() == 'approved';
    final isRejected = rawStatus.toLowerCase() == 'rejected';
    final contactName = _cleanText(
      advertiser['contactName'] ?? 'Non renseigné',
    );

    final offerLabel = _cleanText(
      advertiser['visibilityLabel'] ?? 'Non renseignée',
    );

    final targetCity = _cleanText(advertiser['centerCity'] ?? 'Non renseignée');

    final radiusLabel = advertiser['radiusKm'] != null
        ? AdvertisingPricingConfig.radiusLabel(
            _toDouble(advertiser['radiusKm']),
          )
        : advertiser['broadcastType'] == 'national'
        ? 'National'
        : 'Non renseigné';

    final radiusKm = _toDouble(advertiser['radiusKm']);
    final centerLat = _toDouble(advertiser['centerLat']);
    final centerLng = _toDouble(advertiser['centerLng']);

    int coveredSpots = 0;

    if (radiusKm > 0) {
      for (final doc in _latestSpotDocs) {
        final data = {...doc.data(), '_docId': doc.id};

        final lat = _toDouble(data['sphotLat']);
        final lng = _toDouble(data['sphotLng']);

        if (lat == 0 || lng == 0) continue;

        final distance = _distanceKm(centerLat, centerLng, lat, lng);

        if (distance <= radiusKm) {
          coveredSpots++;
        }
      }
    }

    final price = _toDouble(
      advertiser['totalPriceExclTax'] ?? advertiser['priceExclTax'],
    );

    final bannerUrl = _cleanText(
      advertiser['bannerUrl'] ?? advertiser['imageUrl'],
    );

    return Container(
      width: 420,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.25), width: 1.5),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      companyName,
                      style: const TextStyle(
                        color: adminColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedAdvertiser = null;
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              if (bannerUrl.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    launchUrl(
                      Uri.parse(bannerUrl),
                      webOnlyWindowName: '_blank',
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: adminColor.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: adminColor.withOpacity(0.25)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.image_rounded, color: adminColor, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bannière publicitaire',
                            style: TextStyle(
                              color: adminColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(Icons.open_in_full_rounded, color: adminColor),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 18),

              _spotInfoLine('Responsable', contactName),
              _spotInfoLine('Email', email),
              _spotInfoLine('Téléphone', phone),
              _spotInfoLine(
                'Site internet',
                websiteUrl.isEmpty ? 'Non renseigné' : websiteUrl,
              ),
              _spotInfoLine('SIRET', siret.isEmpty ? 'Non renseigné' : siret),
              _spotInfoLine('SIREN', siren.isEmpty ? 'Non renseigné' : siren),
              _spotInfoLine(
                'Catégorie',
                categoryLabel.isEmpty ? 'Non renseignée' : categoryLabel,
              ),
              _spotInfoLine(
                'Durée',
                durationLabel.isEmpty ? 'Non renseignée' : durationLabel,
              ),
              _spotInfoLine('Ville cible', targetCity),
              _spotInfoLine('Rayon d’action', radiusLabel),
              _spotInfoLine('SPHOTS', '$coveredSpots touchés'),
              _spotInfoLine('Offre choisie', offerLabel),
              _spotInfoLine('Statut', campaignStatus),
              _spotInfoLine(
                'Début',
                _formatDate(advertiser['campaignStartDate']),
              ),
              _spotInfoLine('Fin', _formatDate(advertiser['campaignEndDate'])),
              _spotInfoLine('Prix', '${price.toStringAsFixed(0)} € HT'),

              const SizedBox(height: 22),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedAdvertiser = {
                            ...advertiser,
                            'status': 'approved',
                          };
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isApproved ? redColor : adminColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: Icon(
                        isApproved
                            ? Icons.check_circle_rounded
                            : Icons.check_rounded,
                      ),
                      label: Text(isApproved ? 'Approuvé' : 'Approuver'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedAdvertiser = {
                            ...advertiser,
                            'status': 'rejected',
                          };
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRejected ? redColor : adminColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(99),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: Icon(
                        isRejected ? Icons.cancel_rounded : Icons.close_rounded,
                      ),
                      label: Text(isRejected ? 'Refusé' : 'Refuser'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approveAdminRequest(Map<String, dynamic> adminData) async {
    final requestId = _cleanText(adminData['requestId'] ?? adminData['uid']);

    if (requestId.isEmpty) {
      throw Exception('Identifiant de la demande introuvable.');
    }

    final profile = Map<String, dynamic>.from(adminData['profile'] ?? {});

    final proConnect = Map<String, dynamic>.from(adminData['proConnect'] ?? {});

    final recipientEmail = _cleanText(
      profile['email'] ?? proConnect['email'] ?? adminData['email'],
    );

    if (recipientEmail.isEmpty) {
      throw Exception('Adresse email du demandeur introuvable.');
    }

    final now = FieldValue.serverTimestamp();

    await FirebaseFirestore.instance
        .collection('adminRequests')
        .doc(requestId)
        .set({
          'status': 'approved',
          'accessPhase': 'configuration_access',
          'updatedAt': now,

          'administrativeTracking': {
            'status': 'approved',
            'reviewStartedAt': now,
            'approvedAt': now,
            'rejectedAt': null,
            'rejectionReason': null,
          },

          'commercialTracking': {
            'status': 'configuration_access_opened',
            'configurationAccessOpenedAt': now,
          },

          'setupProgress': {'accessGranted': true, 'updatedAt': now},

          'approvalEmail': {
            'status': 'pending',
            'recipient': recipientEmail,
            'sentAt': null,
            'messageId': null,
            'error': null,
            'updatedAt': now,
          },

          'lastEvent': {
            'type': 'admin_request_approved',
            'category': 'administrative',
            'label': 'Demande administrateur approuvée',
            'createdAt': now,
            'createdByRole': 'super_admin',
          },
        }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() {
      _selectedAdmin = {
        ...adminData,
        'status': 'approved',
        'accessPhase': 'configuration_access',
        'approvalEmail': {'status': 'pending', 'recipient': recipientEmail},
      };
    });
  }

  Future<void> _rejectAdminRequest(
    Map<String, dynamic> adminData,
    String rejectionReason,
  ) async {
    final requestId = _cleanText(adminData['requestId'] ?? adminData['uid']);

    if (requestId.isEmpty) {
      throw Exception('Identifiant de la demande introuvable.');
    }

    final profile = Map<String, dynamic>.from(adminData['profile'] ?? {});

    final proConnect = Map<String, dynamic>.from(adminData['proConnect'] ?? {});

    final recipientEmail = _cleanText(
      profile['email'] ?? proConnect['email'] ?? adminData['email'],
    );

    if (recipientEmail.isEmpty) {
      throw Exception('Adresse email du demandeur introuvable.');
    }

    final administrativeTracking = Map<String, dynamic>.from(
      adminData['administrativeTracking'] ?? {},
    );

    final previousRejectionReason = _cleanText(
      administrativeTracking['rejectionReason'],
    );

    final now = FieldValue.serverTimestamp();

    await FirebaseFirestore.instance
        .collection('adminRequests')
        .doc(requestId)
        .set({
          'status': 'rejected',
          'accessPhase': 'correction_required',
          'updatedAt': now,

          'administrativeTracking': {
            ...administrativeTracking,
            'status': 'rejected',
            'reviewStartedAt': administrativeTracking['reviewStartedAt'] ?? now,
            'rejectedAt': now,
            'rejectionReason': rejectionReason,
            'previousRejectionReason': previousRejectionReason.isEmpty
                ? null
                : previousRejectionReason,
            'approvedAt': null,
          },

          'commercialTracking.status': 'rejected',
          'commercialTracking.configurationAccessOpenedAt': null,

          'setupProgress.accessGranted': false,
          'setupProgress.updatedAt': now,

          'rejectionEmail': {
            'status': 'pending',
            'recipient': recipientEmail,
            'sentAt': null,
            'messageId': null,
            'error': null,
            'updatedAt': now,
          },

          'lastEvent': {
            'type': 'admin_request_rejected',
            'category': 'administrative',
            'label': 'Demande administrateur refusée',
            'comment': rejectionReason,
            'createdAt': now,
            'createdByRole': 'super_admin',
          },
        }, SetOptions(merge: true));

    if (!mounted) return;

    setState(() {
      _selectedAdmin = {
        ...adminData,
        'status': 'rejected',
        'accessPhase': 'correction_required',
        'administrativeTracking': {
          ...administrativeTracking,
          'status': 'rejected',
          'rejectionReason': rejectionReason,
        },
        'rejectionEmail': {'status': 'pending', 'recipient': recipientEmail},
      };
    });
  }

  Future<void> _openAdminRejectionDialog(Map<String, dynamic> adminData) async {
    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        String rejectionReason = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'REFUSER LA DEMANDE',
                style: TextStyle(color: redColor, fontWeight: FontWeight.w900),
              ),
              content: SizedBox(
                width: 430,
                child: TextField(
                  minLines: 4,
                  maxLines: 8,
                  autofocus: true,
                  onChanged: (value) {
                    rejectionReason = value.trim();
                    setDialogState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Motif du refus',
                    hintText:
                        'Indiquez clairement la raison du refus au demandeur.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: adminColor,
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: redColor, width: 2),
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('ANNULER'),
                ),
                ElevatedButton(
                  onPressed: rejectionReason.isEmpty
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(rejectionReason);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: redColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                  ),
                  child: const Text('CONFIRMER LE REFUS'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || reason == null || reason.isEmpty) {
      return;
    }

    await _rejectAdminRequest(adminData, reason);
  }

  Future<void> _openAdminExternalLink(String rawUrl) async {
    final value = rawUrl.trim();

    if (value.isEmpty) {
      return;
    }

    final normalizedUrl =
        value.startsWith('http://') || value.startsWith('https://')
        ? value
        : 'https://$value';

    final uri = Uri.tryParse(normalizedUrl);

    if (uri == null) {
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir ce lien.')),
      );
    }
  }

  Widget _adminDetailLine({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final displayedValue = value.trim().isEmpty
        ? 'Non renseigné'
        : value.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: adminColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: adminColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: adminColor.withOpacity(0.72),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  displayedValue,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminLinkTile({
    required IconData icon,
    required String label,
    required String url,
    VoidCallback? onEdit,
  }) {
    final hasUrl = url.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: hasUrl
            ? adminColor.withOpacity(0.055)
            : Colors.grey.withOpacity(0.055),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasUrl
              ? adminColor.withOpacity(0.30)
              : Colors.grey.withOpacity(0.24),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
        child: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: hasUrl ? Colors.white : Colors.grey.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hasUrl
                      ? adminColor.withOpacity(0.25)
                      : Colors.grey.withOpacity(0.20),
                ),
              ),
              child: Icon(
                icon,
                color: hasUrl ? adminColor : Colors.grey,
                size: 21,
              ),
            ),

            const SizedBox(width: 11),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: hasUrl ? adminColor : Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      hasUrl ? url : 'Non renseigné',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasUrl ? adminColor : Colors.grey,
                        decoration: TextDecoration.none,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (onEdit != null)
              IconButton(
                tooltip: 'Modifier',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, color: redColor, size: 19),
              ),
          ],
        ),
      ),
    );
  }

  Widget _adminPanelSectionTitle({
    required IconData icon,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: adminColor, size: 21),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: adminColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminDetailSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: adminColor.withOpacity(0.045),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: adminColor.withOpacity(0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: redColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _buildAdvertisersList() {
    return const SizedBox.shrink();
  }

  String _legalDocumentIdFromTitle(String title) {
    switch (title) {
      case 'CGU':
        return 'cgu';
      case 'Politique de confidentialité':
      case 'POLITIQUE DE CONFIDENTIALITÉ':
        return 'privacyPolicy';
      case 'RGPD':
        return 'rgpdNotice';
      default:
        return title;
    }
  }

  Future<List<String>> _loadLegalChaptersFromFirebase(
    String documentTitle,
  ) async {
    final documentId = _legalDocumentIdFromTitle(documentTitle);

    final snapshot = await FirebaseFirestore.instance
        .collection('legalDocuments')
        .doc(documentId)
        .collection('chapters')
        .orderBy(FieldPath.documentId)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return (data['title'] ?? data['titre'] ?? doc.id).toString();
    }).toList();
  }

  Future<void> _loadAllLegalChaptersFromFirebase() async {
    final cgu = await _loadLegalChaptersFromFirebase('CGU');
    final privacy = await _loadLegalChaptersFromFirebase(
      'Politique de confidentialité',
    );
    final rgpd = await _loadLegalChaptersFromFirebase('RGPD');

    if (!mounted) return;

    setState(() {
      _documentChapters['CGU'] = cgu;
      _documentChapters['Politique de confidentialité'] = privacy;
      _documentChapters['RGPD'] = rgpd;
    });
  }

  Widget _buildLegalDocumentsPanel() {
    return Container(
      width: 420,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        border: Border(
          left: BorderSide(color: adminColor.withOpacity(0.25), width: 1.5),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'DOCUMENTS JURIDIQUES',
                      style: TextStyle(
                        color: adminColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _showLegalDocumentsPanel = false;
                        _selectedLegalDocument = null;
                        _selectedLegalChapter = null;
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              _legalDocumentTile(
                title: 'CGU',
                subtitle: 'Conditions Générales d’Utilisation',
                chapters: _documentChapters['CGU'] ?? [],
              ),

              const SizedBox(height: 12),

              _legalDocumentTile(
                title: 'POLITIQUE DE CONFIDENTIALITÉ',
                subtitle: 'Données personnelles et confidentialité',
                chapters:
                    _documentChapters['Politique de confidentialité'] ?? [],
              ),

              const SizedBox(height: 12),

              _legalDocumentTile(
                title: 'RGPD',
                subtitle: 'Notice d’information RGPD',
                chapters: _documentChapters['RGPD'] ?? [],
              ),

              const SizedBox(height: 12),

              _buildLegalVersionTile(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalChapterEditor() {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: adminColor, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _legalTitleController,
              decoration: InputDecoration(
                labelText: 'Titre du chapitre',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 14),

            TextField(
              controller: _legalContentController,
              minLines: 10,
              maxLines: 18,
              decoration: InputDecoration(
                labelText: 'Contenu du chapitre',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _isSavingLegalChapter ? null : _saveLegalChapter,
                icon: const Icon(Icons.save_rounded),
                label: const Text('ENREGISTRER'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: adminColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modifiedChaptersBlock(String documentName) {
    if (!_modifiedDocuments.contains(documentName)) {
      return const SizedBox.shrink();
    }

    final chapters = _documentChapters[documentName] ?? [];

    if (chapters.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(left: 12, bottom: 10),
        child: Text(
          'Aucun chapitre disponible.',
          style: TextStyle(
            color: adminColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 12),
      child: Column(
        children: chapters.map((chapter) {
          final selected =
              _modifiedChapters[documentName]?.contains(chapter) ?? false;

          return CheckboxListTile(
            value: selected,
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: adminColor,
            title: Text(
              chapter,
              style: const TextStyle(
                color: adminColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            onChanged: (value) {
              setState(() {
                final set = _modifiedChapters[documentName] ?? <String>{};

                if (value == true) {
                  set.add(chapter);
                  _modifiedDocuments.add(documentName);
                } else {
                  set.remove(chapter);

                  if (set.isEmpty) {
                    _modifiedDocuments.remove(documentName);
                  }
                }

                _modifiedChapters[documentName] = set;
              });
            },
          );
        }).toList(),
      ),
    );
  }

  bool get _canPublishVersion {
    if (_modifiedDocuments.isEmpty) return false;

    if (_legalChangeLogController.text.trim().isEmpty) {
      return false;
    }

    for (final document in _modifiedDocuments) {
      final selectedChapters = _modifiedChapters[document] ?? {};
      if (selectedChapters.isEmpty) {
        return false;
      }
    }

    return true;
  }

  Widget _buildLegalVersionsHistory() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('legalVersions').get(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Erreur historique : ${snapshot.error}',
              style: const TextStyle(
                color: redColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Chargement de l’historique...',
              style: TextStyle(color: adminColor, fontWeight: FontWeight.w700),
            ),
          );
        }

        final versions = snapshot.data!.docs;

        if (versions.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Aucune version enregistrée.',
              style: TextStyle(color: adminColor, fontWeight: FontWeight.w700),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: versions.map((doc) {
            final data = doc.data();

            final version = (data['version'] ?? '').toString();
            final publicationDate =
                (data['publicationDate'] ?? 'Non renseignée').toString();
            final updatedAtText = (data['updatedAtText'] ?? 'Non renseignée')
                .toString();
            final status = (data['status'] ?? 'Non renseigné').toString();

            final summary =
                (data['summary'] ?? data['changeLog'] ?? 'Non renseigné')
                    .toString();

            final documents = List<String>.from(
              data['documentsModified'] ?? [],
            );

            final chaptersRaw = Map<String, dynamic>.from(
              data['chaptersModified'] ?? {},
            );

            return Container(
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border.all(color: adminColor, width: 1.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  iconColor: redColor,
                  collapsedIconColor: redColor,
                  title: Text(
                    'Version $version',
                    style: const TextStyle(
                      color: redColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    'Publiée le $publicationDate • MAJ $updatedAtText',
                    style: const TextStyle(
                      color: adminColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  childrenPadding: const EdgeInsets.all(12),
                  children: [
                    _spotInfoLine('État', status),
                    _spotInfoLine(
                      'Documents',
                      documents.isEmpty
                          ? 'Non renseigné'
                          : documents.join(', '),
                    ),
                    ...chaptersRaw.entries.map((entry) {
                      final chapters = List<String>.from(entry.value ?? []);

                      if (chapters.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return _spotInfoLine(entry.key, chapters.join(', '));
                    }),
                    _spotInfoLine('Résumé', summary),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildLegalVersionTile() {
    return Container(
      decoration: BoxDecoration(
        color: adminColor.withOpacity(0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: adminColor, width: 1.4),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          iconColor: redColor,
          collapsedIconColor: redColor,
          title: const Text(
            'VERSION',
            style: TextStyle(
              color: redColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: const Text(
            'Version, publication et état du document',
            style: TextStyle(
              color: adminColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            TextField(
              controller: _legalVersionController,
              style: const TextStyle(
                color: redColor,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                labelText: 'Version',
                labelStyle: const TextStyle(
                  color: adminColor,
                  fontWeight: FontWeight.w700,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.6),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _legalPublicationDateController,
              readOnly: true,
              onTap: () async {
                final now = DateTime.now();

                final selectedDate = await showDatePicker(
                  context: context,
                  initialDate: now,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: adminColor,
                          onPrimary: Colors.white,
                          secondary: adminColor,
                          surface: Colors.white,
                          onSurface: Colors.black,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );

                if (selectedDate == null) return;

                _legalPublicationDateController.text =
                    '${selectedDate.day.toString().padLeft(2, '0')}/'
                    '${selectedDate.month.toString().padLeft(2, '0')}/'
                    '${selectedDate.year}';
              },
              style: const TextStyle(
                color: redColor,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                labelText: 'Date de publication',
                labelStyle: const TextStyle(
                  color: adminColor,
                  fontWeight: FontWeight.w700,
                ),
                suffixIcon: const Icon(
                  Icons.calendar_month_rounded,
                  color: redColor,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.8),
                ),
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Documents modifiés',
              style: TextStyle(
                color: redColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),

            CheckboxListTile(
              value: _modifiedDocuments.contains('CGU'),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _modifiedDocuments.add('CGU');
                  } else {
                    _modifiedDocuments.remove('CGU');
                    _modifiedChapters['CGU']?.clear();
                  }
                });
              },
              title: const Text(
                'CGU',
                style: TextStyle(
                  color: adminColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              activeColor: adminColor,
              checkColor: Colors.white,
              side: const BorderSide(color: adminColor, width: 1.6),
            ),

            _modifiedChaptersBlock('CGU'),

            CheckboxListTile(
              value: _modifiedDocuments.contains(
                'Politique de confidentialité',
              ),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _modifiedDocuments.add('Politique de confidentialité');
                  } else {
                    _modifiedDocuments.remove('Politique de confidentialité');
                    _modifiedChapters['Politique de confidentialité']?.clear();
                  }
                });
              },
              title: const Text(
                'Politique de confidentialité',
                style: TextStyle(
                  color: adminColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              activeColor: adminColor,
              checkColor: Colors.white,
              side: const BorderSide(color: adminColor, width: 1.6),
            ),

            _modifiedChaptersBlock('Politique de confidentialité'),

            CheckboxListTile(
              value: _modifiedDocuments.contains('RGPD'),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _modifiedDocuments.add('RGPD');
                  } else {
                    _modifiedDocuments.remove('RGPD');
                    _modifiedChapters['RGPD']?.clear();
                  }
                });
              },
              title: const Text(
                'RGPD',
                style: TextStyle(
                  color: adminColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              activeColor: adminColor,
              checkColor: Colors.white,
              side: const BorderSide(color: adminColor, width: 1.6),
            ),

            _modifiedChaptersBlock('RGPD'),

            TextField(
              controller: _legalChangeLogController,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(
                color: adminColor,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                labelText: 'Résumé des modifications',
                alignLabelWithHint: true,
                labelStyle: const TextStyle(
                  color: adminColor,
                  fontWeight: FontWeight.w700,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.6),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              key: _legalStatusKey,
              onTap: _openLegalStatusMenu,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'État',
                  labelStyle: const TextStyle(
                    color: adminColor,
                    fontWeight: FontWeight.w700,
                  ),
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: adminColor, width: 1.6),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: adminColor, width: 1.6),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedLegalStatus,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: redColor,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: redColor,
                      size: 26,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: TextEditingController(text: _legalLastUpdatedText),
              readOnly: true,
              style: const TextStyle(
                color: redColor,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                labelText: 'Dernière mise à jour',
                labelStyle: const TextStyle(
                  color: adminColor,
                  fontWeight: FontWeight.w700,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.6),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: adminColor, width: 1.8),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _legalVersionButtonRed
                    ? null
                    : (_canPublishVersion
                          ? _saveLegalVersionAndTurnButtonRed
                          : null),
                icon: Icon(
                  _legalVersionButtonRed
                      ? Icons.check_circle_rounded
                      : Icons.save_rounded,
                ),
                label: Text(
                  _legalVersionButtonRed ? 'ENREGISTRÉE' : 'ENREGISTRER',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _legalVersionButtonRed
                      ? redColor
                      : adminColor,
                  disabledBackgroundColor: _legalVersionButtonRed
                      ? redColor
                      : Colors.grey.shade300,
                  disabledForegroundColor: _legalVersionButtonRed
                      ? Colors.white
                      : Colors.grey,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Historique des versions',
              style: TextStyle(
                color: redColor,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),

            _buildLegalVersionsHistory(),
          ],
        ),
      ),
    );
  }

  Widget _legalDocumentTile({
    required String title,
    required String subtitle,
    required List<String> chapters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: adminColor.withOpacity(0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: adminColor, width: 1.4),
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: redColor,
          collapsedIconColor: redColor,
          title: Text(
            title,
            style: const TextStyle(
              color: redColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              color: adminColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          children: chapters.map((chapter) {
            final isSelected =
                _selectedLegalDocument == title &&
                _selectedLegalChapter == chapter;

            return Column(
              children: [
                GestureDetector(
                  onTap: () {
                    if (isSelected) {
                      setState(() {
                        _selectedLegalDocument = null;
                        _selectedLegalChapter = null;
                        _legalTitleController.clear();
                        _legalContentController.clear();
                      });
                    } else {
                      _loadLegalChapter(title, chapter);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: adminColor.withOpacity(0.18)),
                      ),
                    ),
                    child: Text(
                      chapter,
                      style: const TextStyle(
                        color: adminColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (isSelected) _buildLegalChapterEditor(),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  String _legalDocumentId(String title) {
    switch (title) {
      case 'CGU':
        return 'cgu';
      case 'POLITIQUE DE CONFIDENTIALITÉ':
        return 'privacyPolicy';
      case 'RGPD':
        return 'rgpdNotice';
      default:
        return 'cgu';
    }
  }

  String _legalChapterId(String chapter) {
    final match = RegExp(r'^(\d+)').firstMatch(chapter);
    final number = match?.group(1) ?? '1';
    return number.padLeft(2, '0');
  }

  String _legalChapterTitle(String chapter) {
    return chapter.replaceFirst(RegExp(r'^\d+\.\s*'), '').trim();
  }

  Future<void> _loadLegalChapter(String documentTitle, String chapter) async {
    print('LOAD : $documentTitle / $chapter');
    final documentId = _legalDocumentId(documentTitle);
    final chapterId = _legalChapterId(chapter);

    _selectedLegalDocument = documentTitle;
    _selectedLegalChapter = chapter;
    _legalTitleController.text = _legalChapterTitle(chapter);
    _legalContentController.clear();

    setState(() {});

    final doc = await FirebaseFirestore.instance
        .collection('legalDocuments')
        .doc(documentId)
        .collection('chapters')
        .doc(chapterId)
        .get();

    final data = doc.data();
    print(data);

    if (data != null) {
      _legalTitleController.text =
          (data['title'] ?? _legalChapterTitle(chapter)).toString();

      _legalContentController.text = (data['content'] ?? '').toString();

      setState(() {});
    }
  }

  Future<void> _saveLegalChapter() async {
    if (_selectedLegalDocument == null || _selectedLegalChapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun chapitre sélectionné.')),
      );
      return;
    }

    final documentId = _legalDocumentId(_selectedLegalDocument!);
    final chapterId = _legalChapterId(_selectedLegalChapter!);
    final order = int.tryParse(chapterId) ?? 1;

    final title = _legalTitleController.text.trim().isEmpty
        ? _legalChapterTitle(_selectedLegalChapter!)
        : _legalTitleController.text.trim();

    final content = _legalContentController.text.trim();

    setState(() {
      _isSavingLegalChapter = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('legalDocuments')
          .doc(documentId)
          .collection('chapters')
          .doc(chapterId)
          .set({
            'order': order,
            'title': title,
            'content': content,
            'isActive': true,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {});
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur Firebase : $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLegalChapter = false;
        });
      }
    }
  }

  void _markLegalVersionModified() {
    if (!_legalVersionButtonRed && !_legalVersionSaved) return;

    setState(() {
      _legalVersionSaved = false;
      _legalVersionButtonRed = false;
    });
  }

  Future<void> _saveLegalVersionAndTurnButtonRed() async {
    setState(() {
      _legalVersionButtonRed = true;
    });

    await _saveLegalVersion();
  }

  Future<void> _saveLegalVersion() async {
    if (!_canPublishVersion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sélectionnez au moins un document, un chapitre modifié et renseignez le résumé des modifications.',
          ),
        ),
      );
      return;
    }

    final now = DateTime.now();

    final version = _legalVersionController.text.trim().isEmpty
        ? '1.0'
        : _legalVersionController.text.trim();

    final versionId = version.replaceAll('.', '_');

    final formattedDate =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year}';

    final publicationDate = _legalPublicationDateController.text.trim().isEmpty
        ? formattedDate
        : _legalPublicationDateController.text.trim();

    final summary = _legalChangeLogController.text.trim();

    try {
      final firestore = FirebaseFirestore.instance;

      Future<Map<String, dynamic>> loadDocumentSnapshot({
        required String label,
        required String documentId,
      }) async {
        final doc = await firestore
            .collection('legalDocuments')
            .doc(documentId)
            .get();

        final chaptersSnapshot = await firestore
            .collection('legalDocuments')
            .doc(documentId)
            .collection('chapters')
            .orderBy(FieldPath.documentId)
            .get();

        final selectedChapters = _modifiedChapters[label] ?? <String>{};

        return {
          'label': label,
          'documentId': documentId,
          'modified': _modifiedDocuments.contains(label),
          'modifiedChapters': selectedChapters.toList(),
          'document': doc.data() ?? {},
          'chapters': chaptersSnapshot.docs.map((chapter) {
            return {'id': chapter.id, ...chapter.data()};
          }).toList(),
        };
      }

      final cguSnapshot = await loadDocumentSnapshot(
        label: 'CGU',
        documentId: 'cgu',
      );

      final privacySnapshot = await loadDocumentSnapshot(
        label: 'Politique de confidentialité',
        documentId: 'privacyPolicy',
      );

      final rgpdSnapshot = await loadDocumentSnapshot(
        label: 'RGPD',
        documentId: 'rgpdNotice',
      );

      final chaptersModified = _modifiedChapters.map(
        (key, value) => MapEntry(key, value.toList()),
      );

      final documentsModified = _modifiedDocuments.toList();

      final versionPayload = {
        'version': version,
        'versionId': versionId,
        'publicationDate': publicationDate,
        'publishedAt': FieldValue.serverTimestamp(),
        'status': _selectedLegalStatus,
        'summary': summary,
        'documentsModified': documentsModified,
        'chaptersModified': chaptersModified,
        'documents': {
          'cgu': cguSnapshot,
          'privacyPolicy': privacySnapshot,
          'rgpdNotice': rgpdSnapshot,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtText': formattedDate,
      };

      await firestore.collection('legalDocuments').doc('metadata').set({
        'version': version,
        'publicationDate': publicationDate,
        'publishedAt': FieldValue.serverTimestamp(),
        'status': _selectedLegalStatus,
        'summary': summary,
        'documentsModified': documentsModified,
        'chaptersModified': chaptersModified,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtText': formattedDate,
      }, SetOptions(merge: true));

      await firestore
          .collection('legalVersions')
          .doc(versionId)
          .set(versionPayload, SetOptions(merge: true));

      if (!mounted) return;

      setState(() {
        _legalLastUpdatedText = formattedDate;
        _legalVersionSaved = true;
        _legalVersionButtonRed = true;

        _modifiedDocuments.clear();
        _modifiedChapters['CGU'] = <String>{};
        _modifiedChapters['Politique de confidentialité'] = <String>{};
        _modifiedChapters['RGPD'] = <String>{};

        _legalChangeLogController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Version SPHOT $version publiée et archivée.')),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur publication version SPHOT : $error')),
      );
    }
  }

  void _openLegalStatusMenu() {
    _dropdownOverlay?.remove();
    _dropdownOverlay = null;

    final renderBox =
        _legalStatusKey.currentContext!.findRenderObject() as RenderBox;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final statuses = ['Brouillon', 'Publié', 'Archivé'];

    _dropdownOverlay = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _dropdownOverlay?.remove();
                  _dropdownOverlay = null;
                },
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: position.dx,
              top: position.dy + size.height - 10,
              width: size.width,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.94),
                    border: const Border(
                      left: BorderSide(color: adminColor, width: 1.4),
                      right: BorderSide(color: adminColor, width: 1.4),
                      bottom: BorderSide(color: adminColor, width: 1.4),
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: statuses.map((status) {
                      final selected = _selectedLegalStatus == status;

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedLegalStatus = status;
                          });

                          _dropdownOverlay?.remove();
                          _dropdownOverlay = null;
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color: selected ? redColor : adminColor,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: selected ? redColor : adminColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_dropdownOverlay!);
  }

  Future<void> _loadAdministratorTerritoryCenter() async {
    try {
      final uid = widget.adminUid.trim();

      if (uid.isEmpty) {
        return;
      }

      final firestore = FirebaseFirestore.instance;

      Map<String, dynamic>? administratorData;

      /*
     * Priorité à adminRequests/{uid}.
     * C'est là que sont enregistrés villeLat, villeLng
     * et logoVille pour cet Admin.
     */
      final requestSnapshot = await firestore
          .collection('adminRequests')
          .doc(uid)
          .get();

      if (requestSnapshot.exists) {
        administratorData = requestSnapshot.data();
      }

      /*
     * Sécurité pour les Admins dont la demande
     * n'est plus disponible.
     */
      if (administratorData == null) {
        final approvedAdminSnapshot = await firestore
            .collection('admins')
            .doc(uid)
            .get();

        if (approvedAdminSnapshot.exists) {
          administratorData = approvedAdminSnapshot.data();
        }
      }

      if (administratorData == null) {
        return;
      }

      final territoire = Map<String, dynamic>.from(
        administratorData['territoire'] ?? <String, dynamic>{},
      );

      /*
     * Le centre est exclusivement celui enregistré
     * dans le document de cet Admin.
     */
      final latitude = _toDouble(territoire['villeLat']);

      final longitude = _toDouble(territoire['villeLng']);

      if (latitude == 0 || longitude == 0) {
        return;
      }

      final territoireId = _cleanText(
        territoire['territoireId'] ??
            administratorData['territoireId'] ??
            administratorData['organisationId'] ??
            widget.territoireId,
      );

      final structure = Map<String, dynamic>.from(
        administratorData['structure'] ?? <String, dynamic>{},
      );

      final organisationName = _cleanText(
        structure['nom'] ??
            administratorData['nomStructure'] ??
            administratorData['organisation'] ??
            territoire['ville'] ??
            'ADMIN',
      );

      final logoVille = _cleanText(
        territoire['logoVille'] ?? administratorData['logoVille'],
      );

      final center = LatLng(latitude, longitude);

      final markerData = <String, dynamic>{
        ...administratorData,
        'uid': uid,
        'territoireId': territoireId,
        'territoire': <String, dynamic>{
          ...territoire,
          'territoireId': territoireId,
          'villeLat': latitude,
          'villeLng': longitude,
          'logoVille': logoVille,
        },
        'structure': <String, dynamic>{...structure, 'nom': organisationName},
        'organisation': organisationName,
      };

      if (!mounted) {
        return;
      }

      setState(() {
        _territoryCenter = center;
        _territoryZoom = 14.0;
        _territoryCenterLoaded = true;
        _administratorTerritoryMarkerData = markerData;
      });
    } catch (error, stackTrace) {
      debugPrint('Erreur chargement position Admin : $error');

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void initState() {
    super.initState();

    _speech = stt.SpeechToText();

    _legalVersionController.addListener(_markLegalVersionModified);

    _legalPublicationDateController.addListener(_markLegalVersionModified);

    _legalChangeLogController.addListener(_markLegalVersionModified);

    _loadAllLegalChaptersFromFirebase();

    _loadAdministratorTerritoryCenter();
  }

  @override
  void dispose() {
    _mapMovementTimer?.cancel();
    _trialEndRefreshTimer?.cancel();

    _sphotHoverExitTimer?.cancel();
    _removeSphotHoverLabel();

    _speech.stop();
    _dropdownOverlay?.remove();

    _legalVersionController.removeListener(_markLegalVersionModified);

    _legalPublicationDateController.removeListener(_markLegalVersionModified);

    _legalChangeLogController.removeListener(_markLegalVersionModified);

    _searchController.dispose();
    _legalTitleController.dispose();
    _legalContentController.dispose();
    _legalVersionController.dispose();
    _legalPublicationDateController.dispose();
    _legalChangeLogController.dispose();
    _sphotIdController.dispose();
    _sphotNameController.dispose();
    _sphotLatController.dispose();
    _sphotLngController.dispose();
    _sphotOtherTypeController.dispose();
    _sphotOtherEquipmentController.dispose();
    _sphotOtherLabelController.dispose();
    _sphotWebcamUrlController.dispose();
    _sauveteurNomController.dispose();
    _sauveteurPrenomController.dispose();
    _sauveteurDateNaissanceController.dispose();
    _sauveteurAgeController.dispose();
    _sauveteurAdresseController.dispose();
    _sauveteurCodePostalController.dispose();
    _sauveteurVilleController.dispose();
    _sauveteurTelephoneController.dispose();
    _sauveteurEmailController.dispose();
    _sauveteurExperienceController.dispose();
    _sauveteurObservationsController.dispose();

    super.dispose();
  }

  void _updateVisibleCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> spots,
  ) {
    final bounds = _mapController.camera.visibleBounds;

    int count = 0;

    for (final doc in spots) {
      final data = doc.data();

      final lat = _toDouble(data['sphotLat']);
      final lng = _toDouble(data['sphotLng']);

      if (lat != 0 && lng != 0 && bounds.contains(LatLng(lat, lng))) {
        count++;
      }
    }

    if (count != _visibleOnMapSpotCount) {
      setState(() {
        _visibleOnMapSpotCount = count;
      });
    }
  }

  Future<void> _updateVisibleSauveteurCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> spots,
  ) async {
    final requestId = ++_sauveteurCountRequestId;
    final bounds = _mapController.camera.visibleBounds;

    int count = 0;

    for (final doc in spots) {
      final data = doc.data();

      final lat = _toDouble(data['sphotLat']);
      final lng = _toDouble(data['sphotLng']);

      if (lat == 0 || lng == 0 || !bounds.contains(LatLng(lat, lng))) {
        continue;
      }

      final snap = await doc.reference.collection('sauveteursAffectes').get();

      count += snap.docs.length;
    }

    if (!mounted || requestId != _sauveteurCountRequestId) return;

    setState(() {
      _visibleOnMapSauveteurCount = count;
    });
  }

  Widget _buildMapSearchBar() {
    return Positioned(
      top: 76,
      left: 12,
      right: 12,
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
            onChanged: (value) {
              setState(() {
                _searchText = value;
                _selectedSpot = null;
                _selectedAdmin = null;
                _selectedAdvertiser = null;
              });
            },
            textInputAction: TextInputAction.search,

            onSubmitted: (value) {
              FocusScope.of(context).unfocus();
              _centerOnFirstCurrentResult();
            },
            decoration: InputDecoration(
              hintText: 'Recherche',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),

              prefixIcon: const Icon(Icons.search, color: Colors.black87),

              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchText.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.black54,
                        size: 20,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchText = '';
                          _selectedSpot = null;
                          _selectedAdmin = null;
                          _selectedAdvertiser = null;
                        });
                      },
                    ),
                  IconButton(
                    onPressed: _startVoiceSearch,
                    icon: const Icon(
                      Icons.keyboard_voice_rounded,
                      color: Color(0xFFDC2626),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecenterButton() {
    return Positioned(
      right: 12,
      bottom: 20,
      child: FloatingActionButton(
        heroTag: 'adminRecenter',
        mini: true,
        backgroundColor: Colors.white,
        foregroundColor: adminColor,
        onPressed: _territoryCenterLoaded
            ? () {
                _mapController.move(_territoryCenter, 14.0);
              }
            : null,
        child: const Icon(Icons.my_location),
      ),
    );
  }

  Widget _buildNorthButton() {
    return Positioned(
      right: 12,
      bottom: 72,
      child: FloatingActionButton(
        heroTag: 'superAdminNorth',
        mini: true,
        backgroundColor: Colors.white,
        foregroundColor: adminColor,
        onPressed: () {
          _mapController.rotate(0);
        },
        child: const Icon(Icons.navigation),
      ),
    );
  }

  Widget _buildMapStyleButton() {
    return Positioned(
      right: 12,
      bottom: 124,
      child: FloatingActionButton(
        heroTag: 'superAdminMapStyle',
        mini: true,
        backgroundColor: Colors.white,
        foregroundColor: adminColor,
        onPressed: () {
          setState(() {
            _selectedTileStyle = (_selectedTileStyle + 1) % _tileStyles.length;
          });
        },
        child: Icon(
          _selectedTileStyle == 0
              ? Icons.map_outlined
              : _selectedTileStyle == 1
              ? Icons.satellite_alt
              : Icons.terrain,
        ),
      ),
    );
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

    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

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

  bool _matchesSearch(Map<String, dynamic> data) {
    final query = _normalizeSearch(_searchText);
    if (query.isEmpty) return true;

    final fields = [
      data['nomSphot'],
      data['nomSecours'],
      data['typeSphot'],
      data['natureSphot'],
      data['labelSphot'],
      data['ville'],
      data['departement'],
    ].map((value) => _normalizeSearch((value ?? '').toString())).toList();

    for (final field in fields) {
      if (field.isEmpty) continue;

      if (field.contains(query)) {
        return true;
      }

      final words = field.split(RegExp(r'\s+'));

      for (final word in words) {
        if (_levenshtein(query, word) <= 2) {
          return true;
        }
      }
    }

    return false;
  }

  void _startVoiceSearch() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        debugPrint('SPEECH STATUS: $status');

        if (status == 'done' || status == 'notListening') {
          if (mounted) {
            setState(() {
              _isListening = false;
            });
          }
        }
      },
      onError: (error) {
        debugPrint('SPEECH ERROR: $error');

        if (mounted) {
          setState(() {
            _isListening = false;
          });
        }
      },
    );

    if (!available) {
      debugPrint('SPEECH NON DISPONIBLE');
      return;
    }

    setState(() {
      _isListening = true;
    });

    await _speech.listen(
      localeId: 'fr_FR',
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      partialResults: true,
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        final text = result.recognizedWords.trim();

        debugPrint('SPEECH TEXT: $text');

        if (text.isEmpty) return;

        final cleanText = text.trim();

        _searchController
          ..clear()
          ..text = cleanText
          ..selection = TextSelection.fromPosition(
            TextPosition(offset: cleanText.length),
          );

        setState(() {
          _searchText = cleanText;
          _selectedSpot = null;
          _selectedAdmin = null;
          _selectedAdvertiser = null;
        });

        if (text.length >= 3) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _centerOnFirstCurrentResult();
          });
        }

        if (result.finalResult) {
          _speech.stop();

          if (mounted) {
            setState(() {
              _isListening = false;
            });
          }
        }
      },
    );
  }

  bool _matchesAdminSearch(Map<String, dynamic> data) {
    final query = _normalizeSearch(_searchText);
    if (query.isEmpty) return true;

    final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});
    final structure = Map<String, dynamic>.from(data['structure'] ?? {});
    final profile = Map<String, dynamic>.from(data['profile'] ?? {});

    final fields = [
      data['nomStructure'],
      data['organisation'],
      data['email'],
      data['siret'],
      data['nomResponsable'],
      data['prenom'],
      structure['nom'],
      structure['siret'],
      profile['email'],
      profile['nomAffiche'],
      territoire['ville'],
      territoire['departement'],
      territoire['region'],
    ].map((value) => _normalizeSearch((value ?? '').toString())).toList();

    for (final field in fields) {
      if (field.isEmpty) continue;

      if (field.contains(query)) {
        return true;
      }

      final words = field.split(RegExp(r'\s+'));

      for (final word in words) {
        if (_levenshtein(query, word) <= 2) {
          return true;
        }
      }
    }

    return false;
  }

  int _searchScore(List<dynamic> values) {
    final query = _normalizeSearch(_searchText);
    if (query.isEmpty) return 0;

    int bestScore = 0;

    for (final value in values) {
      final field = _normalizeSearch((value ?? '').toString());
      if (field.isEmpty) continue;

      if (field == query) bestScore = bestScore < 1000 ? 1000 : bestScore;
      if (field.startsWith(query))
        bestScore = bestScore < 800 ? 800 : bestScore;
      if (field.contains(query)) bestScore = bestScore < 600 ? 600 : bestScore;

      final words = field.split(RegExp(r'\s+'));

      for (final word in words) {
        if (word == query) bestScore = bestScore < 900 ? 900 : bestScore;
        if (word.startsWith(query))
          bestScore = bestScore < 700 ? 700 : bestScore;

        final distance = _levenshtein(query, word);

        if (distance <= 1) bestScore = bestScore < 650 ? 650 : bestScore;
        if (distance == 2) bestScore = bestScore < 450 ? 450 : bestScore;
      }
    }

    return bestScore;
  }

  void _centerOnFirstCurrentResult() {
    final results = <Map<String, dynamic>>[];

    for (final doc in _latestSpotDocs) {
      final data = doc.data();
      final lat = _toDouble(data['sphotLat']);
      final lng = _toDouble(data['sphotLng']);

      final score = _searchScore([
        data['nomSphot'],
        data['nomSecours'],
        data['typeSphot'],
        data['natureSphot'],
        data['labelSphot'],
        data['ville'],
        data['departement'],
      ]);

      if (lat != 0 && lng != 0 && score > 0) {
        results.add({
          'type': 'spot',
          'score': score,
          'data': data,
          'lat': lat,
          'lng': lng,
          'zoom': 16.0,
        });
      }
    }

    for (final doc in _latestAdminDocs) {
      final data = doc.data();
      final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});
      final structure = Map<String, dynamic>.from(data['structure'] ?? {});
      final profile = Map<String, dynamic>.from(data['profile'] ?? {});

      final lat = _toDouble(territoire['villeLat']);
      final lng = _toDouble(territoire['villeLng']);

      final score = _searchScore([
        data['nomStructure'],
        data['organisation'],
        data['email'],
        data['siret'],
        data['nomResponsable'],
        structure['nom'],
        structure['siret'],
        profile['email'],
        profile['nomAffiche'],
        territoire['ville'],
        territoire['departement'],
        territoire['region'],
      ]);

      if (lat != 0 && lng != 0 && score > 0) {
        results.add({
          'type': 'admin',
          'score': score,
          'data': data,
          'lat': lat,
          'lng': lng,
          'zoom': 18.0,
        });
      }
    }

    for (final doc in _latestAdDocs) {
      final data = {...doc.data(), 'id': doc.id};

      final lat = _toDouble(data['centerLat']);
      final lng = _toDouble(data['centerLng']);

      final score = _searchScore([
        data['advertiserName'],
        data['contactName'],
        data['email'],
        data['phone'],
        data['siret'],
        data['city'],
        data['department'],
        data['region'],
        data['status'],
        data['broadcastType'],
        data['visibilityLabel'],
        data['campaignTitle'],
        data['companyName'],
        data['businessName'],
        data['organisation'],
      ]);

      if (lat != 0 && lng != 0 && score > 0) {
        results.add({
          'type': 'advertiser',
          'score': score,
          'data': data,
          'lat': lat,
          'lng': lng,
          'zoom': 16.0,
        });
      }
    }

    if (results.isEmpty) return;

    results.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    final best = results.first;
    final type = best['type'];
    final data = Map<String, dynamic>.from(best['data']);

    if (_showSphotEditorPanel && type == 'spot') {
      _loadSphotInEditor(data);
      return;
    }

    setState(() {
      _showStatisticsPanel = false;
      _selectedSpot = type == 'spot' ? data : null;
      _selectedAdmin = type == 'admin' ? data : null;
      _selectedAdvertiser = type == 'advertiser' ? data : null;
    });

    _mapController.move(
      LatLng(best['lat'] as double, best['lng'] as double),
      best['zoom'] as double,
    );
  }

  Marker _buildAdminMarker(Map<String, dynamic> data) {
    final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});

    final structure = Map<String, dynamic>.from(data['structure'] ?? {});

    final lat = _toDouble(territoire['villeLat']);
    final lng = _toDouble(territoire['villeLng']);

    final organisation = _cleanText(
      structure['nom'] ??
          data['nomStructure'] ??
          data['organisation'] ??
          territoire['ville'] ??
          'ADMIN',
    );

    final logoUrl = _cleanText(
      territoire['logoVille'] ??
          territoire['logoUrl'] ??
          structure['logoVille'] ??
          structure['logoUrl'] ??
          data['logoVille'] ??
          data['logoUrl'],
    );

    return Marker(
      point: LatLng(lat, lng),
      width: 85,
      height: 85,
      alignment: Alignment.topCenter,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() {
              _showStatisticsPanel = false;
              _selectedSpot = null;
              _selectedAdmin = Map<String, dynamic>.from(data);
              _selectedAdvertiser = null;
              _showLegalDocumentsPanel = false;
              _selectedLegalDocument = null;
              _selectedLegalChapter = null;
            });
          },
          child: SizedBox(
            width: 85,
            height: 85,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                AdaptiveAssetImage(
                  'data/icons/fire_red_icon.svg',
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
                      child: logoUrl.isEmpty
                          ? const Icon(
                              Icons.account_balance_rounded,
                              color: adminColor,
                              size: 23,
                            )
                          : IgnorePointer(
                              child: Image.network(
                                logoUrl,
                                key: ValueKey<String>('admin-logo-$logoUrl'),
                                width: 34,
                                height: 34,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                webHtmlElementStrategy:
                                    WebHtmlElementStrategy.prefer,
                                errorBuilder:
                                    (
                                      BuildContext context,
                                      Object error,
                                      StackTrace? stackTrace,
                                    ) {
                                      return const Icon(
                                        Icons.account_balance_rounded,
                                        color: adminColor,
                                        size: 23,
                                      );
                                    },
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
    );
  }

  Color _advertiserMarkerColor(Map<String, dynamic> data) {
    final status = _cleanText(data['status']).toLowerCase();

    if (status == 'active') return const Color(0xFF16A34A);
    if (status == 'disabled') return const Color(0xFF6B7280);
    if (status == 'deleted') return const Color(0xFF111827);
    if (status == 'pending') return const Color(0xFFF59E0B);

    return redColor;
  }

  Marker _buildAdvertiserMarker(Map<String, dynamic> data) {
    final lat = _toDouble(data['centerLat']);
    final lng = _toDouble(data['centerLng']);

    final name = _cleanText(
      data['advertiserName'] ??
          data['companyName'] ??
          data['businessName'] ??
          'Annonceur',
    );

    return Marker(
      point: LatLng(lat, lng),
      width: 34,
      height: 34,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showStatisticsPanel = false;
            _selectedSpot = null;
            _selectedAdmin = null;
            _selectedAdvertiser = data;
          });

          _mapController.move(LatLng(lat, lng), 18);
        },
        child: Tooltip(
          message: name,
          child: Icon(
            Icons.location_on,
            color: _advertiserMarkerColor(data),
            size: 34,
          ),
        ),
      ),
    );
  }

  void _updateVisibleAdminCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> admins,
  ) {
    final bounds = _mapController.camera.visibleBounds;
    int count = 0;

    for (final doc in admins) {
      final data = doc.data();
      final territoire = Map<String, dynamic>.from(data['territoire'] ?? {});

      final lat = _toDouble(territoire['villeLat']);
      final lng = _toDouble(territoire['villeLng']);

      if (lat != 0 && lng != 0 && bounds.contains(LatLng(lat, lng))) {
        count++;
      }
    }

    if (count != _visibleOnMapAdminCount) {
      setState(() {
        _visibleOnMapAdminCount = count;
      });
    }
  }

  void _updateVisibleAdvertiserCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> advertisers,
  ) {
    final bounds = _mapController.camera.visibleBounds;
    int count = 0;

    for (final doc in advertisers) {
      final data = doc.data();

      final lat = _toDouble(data['centerLat']);
      final lng = _toDouble(data['centerLng']);

      if (lat != 0 && lng != 0 && bounds.contains(LatLng(lat, lng))) {
        count++;
      }
    }

    if (count != _visibleAdvertiserCount) {
      setState(() {
        _visibleAdvertiserCount = count;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _spotsStream,
      builder: (context, spotsSnapshot) {
        if (spotsSnapshot.hasError) {
          return Center(
            child: Text('Erreur Dashboard Map : ${spotsSnapshot.error}'),
          );
        }

        if (!spotsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _adminRequestsStream,
          builder: (context, adminsSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _subscriptionsStream,
              builder: (context, subscriptionsSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _adRequestsStream,
                  builder: (context, adsSnapshot) {
                    final docs = spotsSnapshot.data ?? [];
                    _latestSpotDocs = docs;

                    final subscriptionsDocs =
                        subscriptionsSnapshot.data?.docs ?? [];

                    _subscriptionsByUid = {
                      for (final doc in subscriptionsDocs) doc.id: doc.data(),
                    };

                    final adminUid = widget.adminUid.trim();

                    final currentSubscription = _subscriptionsByUid[adminUid];

                    // Recherche de la demande correspondant à l’Admin connecté.
                    Map<String, dynamic>? currentAdminRequest;

                    final adminRequestDocuments =
                        adminsSnapshot.data?.docs ?? [];

                    for (final document in adminRequestDocuments) {
                      final data = document.data();

                      if (document.id == adminUid ||
                          _cleanText(data['uid']) == adminUid) {
                        currentAdminRequest = data;
                        break;
                      }
                    }

                    final rawTrialRequest =
                        currentAdminRequest?['trialRequest'];

                    final trialRequest = rawTrialRequest is Map
                        ? Map<String, dynamic>.from(rawTrialRequest)
                        : <String, dynamic>{};

                    final trialRequestStatus = _cleanText(
                      currentAdminRequest?['trialRequestStatus'] ??
                          trialRequest['status'],
                    ).toLowerCase();

                    final hasAlreadyRequestedTrial =
                        currentAdminRequest?['trialRequestedAt'] != null ||
                        trialRequest['requestedAt'] != null ||
                        trialRequestStatus.isNotEmpty;

                    // Une demande antérieure ou n’importe quel abonnement existant
                    // interdit définitivement une nouvelle période d’essai.
                    final canRequestTrial =
                        !hasAlreadyRequestedTrial &&
                        currentSubscription == null;

                    // Conservation du suivi temporel déjà présent dans le dashboard.
                    final rawTrialEndDate =
                        currentSubscription?['trialEndDate'];

                    final DateTime? trialEndDate = rawTrialEndDate is Timestamp
                        ? rawTrialEndDate.toDate()
                        : rawTrialEndDate is DateTime
                        ? rawTrialEndDate
                        : null;

                    _scheduleTrialEndRefresh(trialEndDate);

                    final validSpots = docs.where((doc) {
                      final data = doc.data();
                      final lat = _toDouble(data['sphotLat']);
                      final lng = _toDouble(data['sphotLng']);

                      return lat != 0 && lng != 0 && _matchesFilter(data);
                    }).toList();

                    final adminDocs = adminsSnapshot.data?.docs ?? [];
                    _latestAdminDocs = adminDocs;

                    final validAdmins = adminDocs.where((doc) {
                      final data = doc.data();
                      final territoire = Map<String, dynamic>.from(
                        data['territoire'] ?? {},
                      );

                      final lat = _toDouble(territoire['villeLat']);
                      final lng = _toDouble(territoire['villeLng']);

                      return lat != 0 && lng != 0 && _matchesAdminFilter(data);
                    }).toList();

                    final adDocs = adsSnapshot.data?.docs ?? [];

                    _latestAdDocs = adDocs;

                    final validAdvertisers = adDocs.where((doc) {
                      final data = doc.data();
                      final lat = _toDouble(data['centerLat']);
                      final lng = _toDouble(data['centerLng']);

                      return lat != 0 &&
                          lng != 0 &&
                          _matchesAdvertiserFilter(data) &&
                          _matchesAdvertiserSearch(data);
                    }).toList();

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _updateVisibleCount(validSpots);
                      _updateVisibleAdminCount(validAdmins);
                      _updateVisibleAdvertiserCount(validAdvertisers);
                      _updateVisibleSauveteurCount(validSpots);
                    });

                    final editedLat = double.tryParse(
                      _sphotLatController.text.trim().replaceAll(',', '.'),
                    );

                    final editedLng = double.tryParse(
                      _sphotLngController.text.trim().replaceAll(',', '.'),
                    );

                    final creationMarkerIconPath = _selectedSphotType.isEmpty
                        ? 'data/icons/fire_red_icon.svg'
                        : _getMarkerIconPath({'typeSphot': _selectedSphotType});

                    final clusteredMarkers = validSpots.map((doc) {
                      final markerData = <String, dynamic>{
                        ...doc.data(),
                        '_docId': doc.id,
                      };

                      final isCurrentlyEditing =
                          _editingSphotDocId?.trim() == doc.id;

                      if (isCurrentlyEditing &&
                          editedLat != null &&
                          editedLng != null) {
                        markerData['sphotLat'] = editedLat;
                        markerData['sphotLng'] = editedLng;
                      }

                      return _buildSpotMarker(markerData);
                    }).toList();

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildRightPanel(
                          visibleSpots: validSpots.length,
                          canRequestTrial: canRequestTrial,
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              FlutterMap(
                                key: ValueKey<String>(
                                  'admin-map-'
                                  '${_territoryCenter.latitude}-'
                                  '${_territoryCenter.longitude}',
                                ),
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: _territoryCenter,
                                  initialZoom: 14.0,
                                  minZoom: 2,
                                  maxZoom: 18,
                                  onTap: (_, point) {
                                    if (_showSphotEditorPanel &&
                                        _placingSphotOnMap) {
                                      _setSphotPosition(point);
                                      return;
                                    }

                                    setState(() {
                                      _showStatisticsPanel = false;
                                      _selectedSpot = null;
                                      _selectedAdmin = null;
                                      _selectedAdvertiser = null;
                                      _showLegalDocumentsPanel = false;
                                      _selectedLegalDocument = null;
                                      _selectedLegalChapter = null;
                                    });
                                  },
                                  onPositionChanged: (_, __) {
                                    _mapMovementTimer?.cancel();

                                    _mapMovementTimer = Timer(
                                      const Duration(milliseconds: 250),
                                      () {
                                        if (!mounted) {
                                          return;
                                        }

                                        _updateVisibleCount(validSpots);
                                        _updateVisibleAdminCount(validAdmins);
                                        _updateVisibleAdvertiserCount(
                                          validAdvertisers,
                                        );
                                        _updateVisibleSauveteurCount(
                                          validSpots,
                                        );
                                      },
                                    );
                                  },
                                ),
                                children: [
                                  TileLayer(
                                    key: ValueKey<String>(
                                      'admin_tile_$_selectedTileStyle',
                                    ),
                                    urlTemplate:
                                        _tileStyles[_selectedTileStyle].url,
                                    subdomains: _tileStyles[_selectedTileStyle]
                                        .subdomains,
                                    maxZoom: _tileStyles[_selectedTileStyle]
                                        .maxZoom
                                        .toDouble(),
                                    maxNativeZoom:
                                        _tileStyles[_selectedTileStyle].maxZoom,
                                    userAgentPackageName: 'com.sylvainra.sphot',
                                  ),

                                  MarkerClusterLayerWidget(
                                    options: MarkerClusterLayerOptions(
                                      markers: clusteredMarkers,
                                      size: const Size(54, 54),
                                      maxClusterRadius: 45,
                                      disableClusteringAtZoom: 15,
                                      builder: (context, clusterMarkers) {
                                        final clusterColor =
                                            _clusterBorderColor(clusterMarkers);

                                        final iconPath = _clusterIconPath(
                                          clusterColor,
                                        );

                                        final count = clusterMarkers.length
                                            .toString();

                                        return SizedBox(
                                          width: 54,
                                          height: 54,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              AdaptiveAssetImage(
                                                iconPath,
                                                width: 54,
                                                height: 54,
                                                fit: BoxFit.contain,
                                                filterQuality:
                                                    FilterQuality.high,
                                              ),
                                              Text(
                                                count,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: count.length >= 3
                                                      ? 13
                                                      : 16,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.black87,
                                                  shadows: const [
                                                    Shadow(
                                                      color: Colors.white70,
                                                      offset: Offset(0.5, 0.5),
                                                      blurRadius: 1,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),

                                  if (_administratorTerritoryMarkerData != null)
                                    MarkerLayer(
                                      markers: [
                                        _buildAdminMarker(
                                          _administratorTerritoryMarkerData!,
                                        ),
                                      ],
                                    ),

                                  if (_showSphotEditorPanel &&
                                      _editingSphotDocId?.trim().isNotEmpty !=
                                          true &&
                                      editedLat != null &&
                                      editedLng != null)
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point: LatLng(editedLat, editedLng),
                                          width: 46,
                                          height: 46,
                                          alignment: const Alignment(0, -0.9),
                                          child: AdaptiveAssetImage(
                                            creationMarkerIconPath,
                                            width: 46,
                                            height: 46,
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.high,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
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

                              _buildMapSearchBar(),
                              _buildRecenterButton(),
                              _buildNorthButton(),
                              _buildMapStyleButton(),

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
                                      border: Border.all(
                                        color: adminColor,
                                        width: 2,
                                      ),
                                    ),
                                    child: IconButton(
                                      onPressed: () {
                                        Navigator.of(
                                          context,
                                        ).pushAndRemoveUntil(
                                          MaterialPageRoute(
                                            builder: (_) => const MapPage(),
                                          ),
                                          (route) => false,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        color: adminColor,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (_selectedAdmin != null) _buildAdminDetailPanel(),

                        if (_showSubscriptionPanel)
                          AdminSubscriptionPanel(
                            adminUid: widget.adminUid,
                            onClose: _closeSubscriptionPanel,
                          )
                        else if (_showBillingDocumentsPanel)
                          _buildBillingDocumentsPanel()
                        else if (_showStatisticsPanel)
                          AdminStatisticsPanel(
                            territoireId: _resolvedTerritoireId,
                            onClose: _closeStatisticsPanel,
                          )
                        else if (_showTrialSummaryPanel)
                          _buildTrialSummaryPanel()
                        else if (_showSauveteursManagementPanel)
                          _buildSauveteursManagementPanel()
                        else if (_showSurveillancePeriodsPanel)
                          _buildSurveillancePeriodsPanel()
                        else if (_showSauveteurEditorPanel)
                          _buildSauveteurEditorPanel()
                        else if (_showSphotEditorPanel)
                          _buildSphotEditorPanel()
                        else if (_selectedSpot != null)
                          _buildSpotDetailPanel(),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class DashboardSpotMarker extends StatelessWidget {
  final Map<String, dynamic> data;
  final String name;
  final String iconPath;
  final Color typeColor;

  const DashboardSpotMarker({
    super.key,
    required this.data,
    required this.name,
    required this.iconPath,
    required this.typeColor,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveAssetImage(
      iconPath,
      width: 46,
      height: 46,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) {
        return Icon(Icons.place, color: typeColor, size: 34);
      },
    );
  }
}

class FrenchPhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }

    final buffer = StringBuffer();

    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && index.isEven) {
        buffer.write(' ');
      }

      buffer.write(digits[index]);
    }

    final formattedNumber = buffer.toString();

    return TextEditingValue(
      text: formattedNumber,
      selection: TextSelection.collapsed(offset: formattedNumber.length),
    );
  }
}

class _DashboardSurveillancePeriod {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final TimeOfDay startHour;
  final TimeOfDay endHour;
  final TimeOfDay? secondStartHour;
  final TimeOfDay? secondEndHour;

  const _DashboardSurveillancePeriod({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.startHour,
    required this.endHour,
    this.secondStartHour,
    this.secondEndHour,
  });

  bool get hasMiddayBreak => secondStartHour != null && secondEndHour != null;
}

class _DashboardSurveillancePeriodDialog extends StatefulWidget {
  final _DashboardSurveillancePeriod? period;

  const _DashboardSurveillancePeriodDialog({this.period});

  @override
  State<_DashboardSurveillancePeriodDialog> createState() =>
      _DashboardSurveillancePeriodDialogState();
}

class _DashboardSurveillancePeriodDialogState
    extends State<_DashboardSurveillancePeriodDialog> {
  static const Color _blue = Color(0xFF1E3A8A);
  static const Color _red = Color(0xFFDC2626);

  late final TextEditingController _nameController;
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startHour;
  TimeOfDay? _endHour;
  TimeOfDay? _secondStartHour;
  TimeOfDay? _secondEndHour;
  bool _hasMiddayBreak = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.period?.name ?? '');
    _startDate = widget.period?.startDate;
    _endDate = widget.period?.endDate;
    _startHour = widget.period?.startHour;
    _endHour = widget.period?.endHour;
    _secondStartHour = widget.period?.secondStartHour;
    _secondEndHour = widget.period?.secondEndHour;
    _hasMiddayBreak = widget.period?.hasMiddayBreak ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return 'Choisir';
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) {
      return 'Choisir';
    }

    return '${time.hour.toString().padLeft(2, '0')}h'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? DateTime.now())
          : (_endDate ?? _startDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _blue,
              onPrimary: Colors.white,
              onSurface: _blue,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
      _errorMessage = '';
    });
  }

  Future<void> _pickTime({
    required bool isStart,
    bool secondSlot = false,
  }) async {
    final currentTime = secondSlot
        ? (isStart ? _secondStartHour : _secondEndHour)
        : (isStart ? _startHour : _endHour);

    final picked = await showTimePicker(
      context: context,
      initialTime:
          currentTime ??
          (secondSlot
              ? (isStart
                    ? const TimeOfDay(hour: 14, minute: 0)
                    : const TimeOfDay(hour: 19, minute: 0))
              : (isStart
                    ? const TimeOfDay(hour: 11, minute: 0)
                    : const TimeOfDay(hour: 13, minute: 0))),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _blue,
              onPrimary: Colors.white,
              onSurface: _blue,
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
      },
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      if (secondSlot && isStart) {
        _secondStartHour = picked;
      } else if (secondSlot) {
        _secondEndHour = picked;
      } else if (isStart) {
        _startHour = picked;
      } else {
        _endHour = picked;
      }
      _errorMessage = '';
    });
  }

  Widget _pickerTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _blue.withOpacity(0.025),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _blue, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: _blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(color: _blue, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    String error = '';

    int minutesOf(TimeOfDay time) {
      return time.hour * 60 + time.minute;
    }

    if (name.isEmpty) {
      error = 'Nom de période manquant';
    } else if (_startDate == null) {
      error = 'Date de début manquante';
    } else if (_endDate == null) {
      error = 'Date de fin manquante';
    } else if (_startHour == null) {
      error = 'Heure de début manquante';
    } else if (_endHour == null) {
      error = 'Heure de fin manquante';
    } else if (_endDate!.isBefore(_startDate!)) {
      error = 'La date de fin doit être postérieure à la date de début';
    } else if (minutesOf(_endHour!) <= minutesOf(_startHour!)) {
      error = 'L’heure de fin doit être postérieure à l’heure de début';
    } else if (_hasMiddayBreak && _secondStartHour == null) {
      error = 'Heure de début du second créneau manquante';
    } else if (_hasMiddayBreak && _secondEndHour == null) {
      error = 'Heure de fin du second créneau manquante';
    } else if (_hasMiddayBreak &&
        minutesOf(_secondEndHour!) <= minutesOf(_secondStartHour!)) {
      error =
          'L’heure de fin du second créneau doit être postérieure à son heure de début';
    } else if (_hasMiddayBreak &&
        minutesOf(_secondStartHour!) <= minutesOf(_endHour!)) {
      error = 'Le second créneau doit commencer après la fin du premier';
    }

    if (error.isNotEmpty) {
      setState(() {
        _errorMessage = error;
      });
      return;
    }

    Navigator.of(context).pop(
      _DashboardSurveillancePeriod(
        id:
            widget.period?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.toUpperCase(),
        startDate: _startDate!,
        endDate: _endDate!,
        startHour: _startHour!,
        endHour: _endHour!,
        secondStartHour: _hasMiddayBreak ? _secondStartHour : null,
        secondEndHour: _hasMiddayBreak ? _secondEndHour : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _blue, width: 1.5),
      ),
      title: Text(
        widget.period == null
            ? 'CRÉER UNE PÉRIODE DE SURVEILLANCE'
            : 'MODIFIER UNE PÉRIODE DE SURVEILLANCE',
        style: const TextStyle(color: _blue, fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 390,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.characters,
                onChanged: (value) {
                  final upperValue = value.toUpperCase();
                  if (upperValue != value) {
                    _nameController.value = TextEditingValue(
                      text: upperValue,
                      selection: TextSelection.collapsed(
                        offset: upperValue.length,
                      ),
                    );
                  }
                },
                style: const TextStyle(
                  color: _red,
                  fontWeight: FontWeight.w900,
                ),
                decoration: InputDecoration(
                  labelText: 'NOM de la période de surveillance',
                  hintText: 'EX : JUILLET - AOÛT 20..',
                  labelStyle: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w700,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _blue),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _blue, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _pickerTile(
                label: 'Date début',
                value: _formatDate(_startDate),
                icon: Icons.calendar_month_rounded,
                onTap: () => _pickDate(isStart: true),
              ),
              const SizedBox(height: 9),
              _pickerTile(
                label: 'Date fin',
                value: _formatDate(_endDate),
                icon: Icons.calendar_month_rounded,
                onTap: () => _pickDate(isStart: false),
              ),
              const SizedBox(height: 9),
              _pickerTile(
                label: _hasMiddayBreak
                    ? 'Heure début — créneau 1'
                    : 'Heure début',
                value: _formatTime(_startHour),
                icon: Icons.access_time_rounded,
                onTap: () => _pickTime(isStart: true),
              ),
              const SizedBox(height: 9),
              _pickerTile(
                label: _hasMiddayBreak ? 'Heure fin — créneau 1' : 'Heure fin',
                value: _formatTime(_endHour),
                icon: Icons.access_time_rounded,
                onTap: () => _pickTime(isStart: false),
              ),
              const SizedBox(height: 9),
              Container(
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.025),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _blue, width: 1.5),
                ),
                child: CheckboxListTile(
                  value: _hasMiddayBreak,
                  activeColor: _blue,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  title: const Text(
                    'PAUSE MÉRIDIENNE — '
                    'AJOUTER UN SECOND CRÉNEAU',
                    style: TextStyle(
                      color: _blue,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _hasMiddayBreak = value == true;

                      if (_hasMiddayBreak) {
                        _secondStartHour ??= const TimeOfDay(
                          hour: 14,
                          minute: 0,
                        );
                        _secondEndHour ??= const TimeOfDay(hour: 19, minute: 0);
                      }

                      _errorMessage = '';
                    });
                  },
                ),
              ),
              if (_hasMiddayBreak) ...[
                const SizedBox(height: 9),
                _pickerTile(
                  label: 'Heure début — créneau 2',
                  value: _formatTime(_secondStartHour),
                  icon: Icons.access_time_rounded,
                  onTap: () => _pickTime(isStart: true, secondSlot: true),
                ),
                const SizedBox(height: 9),
                _pickerTile(
                  label: 'Heure fin — créneau 2',
                  value: _formatTime(_secondEndHour),
                  icon: Icons.access_time_rounded,
                  onTap: () => _pickTime(isStart: false, secondSlot: true),
                ),
              ],
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _red,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,

      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text(
            'RETOUR',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),

        OutlinedButton(
          onPressed: _save,
          style: OutlinedButton.styleFrom(
            foregroundColor: _red,
            side: const BorderSide(color: _red, width: 1.8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            widget.period == null
                ? 'CRÉER UNE PÉRIODE'
                : 'MODIFIER UNE PÉRIODE',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
