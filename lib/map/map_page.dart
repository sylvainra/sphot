import 'dart:math';
import 'dart:ui' as ui;
import 'dart:async';
import 'lifeguard_login_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

import '../models/flag_state.dart';
import '../services/firestore_service.dart';
import 'flag_marker.dart';

enum SpotFilter {
  all,
  secours,
  accesPlage,
  eauBleue,
  eauVerte,
  lagon,
  naturisme,
  autre,
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final FirestoreService _firestoreService = FirestoreService();
  SpotFilter _selectedFilter = SpotFilter.all;

  bool _showFlagForZoom(double zoom) => zoom >= 12.5;
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

  String _getMarkerIconPath(SpotFlagState spot) {
    final type = spot.normalizedType;

    if (spot.isNaturisme) return 'data/icons/fire_icon.png';
    if (type.contains('ACCES PLAGE')) return 'data/icons/fire_orange_icon.png';

    if (type.contains('LAC') ||
        type.contains('BARRAGE') ||
        type.contains('CASCADE')) {
      return 'data/icons/fire_blue_icon.png';
    }

    if (type.contains('FLEUVE') || type.contains('RIVIERE')) {
      return 'data/icons/fire_green_icon.png';
    }

    if (type.contains('LAGON') || type.contains('PISCINE NATURELLE')) {
      return 'data/icons/fire_cyan_icon.png';
    }

    return 'data/icons/fire_orange_icon.png';
  }

  Color _typeColor(SpotFlagState spot) {
    final type = spot.normalizedType;

    if (spot.isPosteSecours) return const Color(0xFFFF0000);
    if (spot.isNaturisme) return const Color(0xFFD87A5C);
    if (type.contains('ACCES PLAGE')) return const Color(0xFFFF7F00);

    if (type.contains('LAC') ||
        type.contains('BARRAGE') ||
        type.contains('CASCADE')) {
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

  bool _matchesFilter(SpotFlagState spot) {
    final type = spot.normalizedType;

    switch (_selectedFilter) {
      case SpotFilter.all:
        return true;
      case SpotFilter.secours:
        return spot.isPosteSecours;
      case SpotFilter.accesPlage:
        return type.contains('ACCES PLAGE');
      case SpotFilter.eauBleue:
        return type.contains('LAC') ||
            type.contains('CASCADE') ||
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

  String _filterLabel(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
        return 'SPHOTS';
      case SpotFilter.secours:
        return 'SPHOT\nPoste de secours';
      case SpotFilter.accesPlage:
        return 'SPHOT\nAccès plage';
      case SpotFilter.eauBleue:
        return 'SPHOT\nLac\nCascade\nBarrage';
      case SpotFilter.eauVerte:
        return 'SPHOT\nFleuve\nRivière';
      case SpotFilter.lagon:
        return 'SPHOT\nLagon\nPiscine naturelle';
      case SpotFilter.naturisme:
        return 'SPHOT\nNaturisme';
      case SpotFilter.autre:
        return 'SPHOT\nAutre\nNon renseigné';
    }
  }

  Color _filterColor(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
        return Colors.black87;
      case SpotFilter.secours:
        return const Color(0xFFFF0000);
      case SpotFilter.accesPlage:
        return const Color(0xFFFF7F00);
      case SpotFilter.eauBleue:
        return const Color(0xFF1E3A8A);
      case SpotFilter.eauVerte:
        return const Color(0xFF2E7D32);
      case SpotFilter.lagon:
        return const Color(0xFF00ACC1);
      case SpotFilter.naturisme:
        return const Color(0xFFD87A5C);
      case SpotFilter.autre:
        return Colors.black87;
    }
  }

  Widget _drawerAssetIcon(String path) {
    return Image.asset(path, width: 40, height: 40, fit: BoxFit.contain);
  }

  Widget _filterIcon(SpotFilter filter) {
    switch (filter) {
      case SpotFilter.all:
  return const _SphotSpinnerIcon();
      case SpotFilter.secours:
        return const _DrawerFlagIcon();
      case SpotFilter.accesPlage:
        return _drawerAssetIcon('data/icons/fire_orange_icon.png');
      case SpotFilter.eauBleue:
        return _drawerAssetIcon('data/icons/fire_blue_icon.png');
      case SpotFilter.eauVerte:
        return _drawerAssetIcon('data/icons/fire_green_icon.png');
      case SpotFilter.lagon:
        return _drawerAssetIcon('data/icons/fire_cyan_icon.png');
      case SpotFilter.naturisme:
        return _drawerAssetIcon('data/icons/fire_icon.png');
      case SpotFilter.autre:
        return _drawerAssetIcon('data/icons/fire_black_icon.png');
    }
  }

Marker _buildOtherSpotMarker(
  SpotFlagState spot,
  bool showText,
  double zoom,
  double rotation,
) {
  return Marker(
    point: LatLng(spot.lat, spot.lng),
    width: 56,
    height: 56,
    alignment: Alignment.center,
    child: _OtherSpotMarker(
      spot: spot,
      iconPath: _getMarkerIconPath(spot),
      showTextAllowed: showText,
      zoom: zoom,
      rotation: rotation,
      labelOpacity: _labelOpacity(zoom),
      typeTextColor: _typeColor(spot),
    ),
  );
}

  Marker _buildSecoursMarker(
  SpotFlagState spot,
  bool showFlag,
  bool showText,
  double zoom,
  double rotation,
) {
  if (!showFlag) {
    return Marker(
      point: LatLng(spot.lat, spot.lng),
      width: 18,
      height: 18,
      alignment: Alignment.center,
      child: _SimplePostePoint(spot: spot),
    );
  }

  return Marker(
    point: LatLng(spot.lat, spot.lng),
    width: 70,
    height: 95,
    alignment: Alignment.center,
    child: _HoverMarker(
      spot: spot,
      showTextAllowed: showText,
      zoom: zoom,
      rotation: rotation,
      labelOpacity: _labelOpacity(zoom),
    ),
  );
}

  List<Marker> _buildMarkers(
  List<SpotFlagState> spots,
  double zoom,
  double rotation,
) {
  final showFlag = _showFlagForZoom(zoom);
  final showText = _showTextForZoom(zoom);

  return spots.where(_matchesFilter).map((spot) {
    if (spot.isPosteSecours) {
      return _buildSecoursMarker(spot, showFlag, showText, zoom, rotation);
    }
    return _buildOtherSpotMarker(spot, showText, zoom, rotation);
  }).toList();
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
                            setState(() => _selectedFilter = filter);
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
      final child = marker.child;
      if (child is _OtherSpotMarker) {
        colors.add(child.typeTextColor);
      } else if (child is _SimplePostePoint || child is _HoverMarker) {
        colors.add(const Color(0xFFFF0000));
      }
    }

    return colors.length == 1 ? colors.first : Colors.black;
  }

  Widget _buildCluster(BuildContext context, List<Marker> markers) {
    final borderColor = _clusterBorderColor(markers);

    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(color: borderColor, width: 2.2),
      ),
      child: Transform.rotate(
  angle: -MapCamera.of(context).rotation * pi / 180,
  alignment: Alignment.center,
  child: Text(
    markers.length.toString(),
    style: _mapLabelStyle(
      fontSize: 13,
      fontWeight: FontWeight.w900,
      color: borderColor,
    ),
  ),
),
    );
  }

  PreferredSizeWidget _buildAppBar() {
  return AppBar(
    primary: false,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    toolbarHeight: 70,

    // 👉 MENU À GAUCHE
    leading: Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.only(left: 14),
        child: IconButton(
          tooltip: 'Menu',
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          icon: const _ColoredHamburgerIcon(size: 25),
        ),
      ),
    ),

    // 👉 LOGO SPHOT CENTRE
    title: Image.asset(
      'data/icons/title.png',
      height: 90,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    ),

    // 👉 LOGO SAUVETEUR À DROITE
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 14),
        child: IconButton(
          tooltip: 'Connexion sauveteurs',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const LifeguardLoginPage(),
              ),
            );
          },
          icon: Image.asset(
            'data/icons/lifeguard_logo.png',
            width: 50,
            height: 50,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  key: _scaffoldKey, // 👈 AJOUT
  drawerScrimColor: Colors.transparent,
  backgroundColor: Colors.transparent,
  extendBodyBehindAppBar: true,
  appBar: _buildAppBar(),

  endDrawer: _buildDrawer(), // 👈 CHANGEMENT ICI
      body: StreamBuilder<List<SpotFlagState>>(
        stream: _firestoreService.getSpotsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final spots = snapshot.data!;

          return FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(46.4006176, -1.5064563),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.sphot',
              ),
              Builder(
                builder: (context) {
                  final zoom = MapCamera.of(context).zoom;
                  final rotation = MapCamera.of(context).rotation;
                  final markers = _buildMarkers(spots, zoom, rotation);

                  return MarkerClusterLayerWidget(
                    options: MarkerClusterLayerOptions(
                      markers: markers,
                      size: const Size(42, 42),
                      maxClusterRadius: 45,
                      builder: _buildCluster,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
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
            ).createShader(Rect.fromLTWH(0, 0, 120, 20)),
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
                ),
              ),
            ),
      ],
    );
  }
}

class _ColoredHamburgerIcon extends StatelessWidget {
  final double size;

  const _ColoredHamburgerIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    final lineHeight = size * 0.12;

    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _line(size, lineHeight, const Color(0xFFFF0000)),
          SizedBox(height: size * 0.15),
          _line(size, lineHeight, const Color(0xFFFFFF00)),
          SizedBox(height: size * 0.15),
          _line(size, lineHeight, const Color(0xFFFF0000)),
        ],
      ),
    );
  }

  Widget _line(double width, double height, Color color) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.black.withOpacity(0.25), width: 0.3),
      ),
    );
  }
}

class _SphotSpinnerIcon extends StatefulWidget {
  const _SphotSpinnerIcon();

  @override
  State<_SphotSpinnerIcon> createState() => _SphotSpinnerIconState();
}

class _SphotSpinnerIconState extends State<_SphotSpinnerIcon> {
  late final Timer _timer;
  int _step = 0;

  static const List<String> _icons = [
    'data/icons/fire_orange_icon.png',
    'data/icons/fire_blue_icon.png',
    'data/icons/fire_green_icon.png',
    'data/icons/fire_cyan_icon.png',
    'data/icons/fire_icon.png',
    'data/icons/fire_black_icon.png',
  ];

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!mounted) return;
      setState(() => _step = _step + 1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 42.0;
    const iconSize = 22.0;
    const radius = 10.0;
    const count = 6;

    final angles = List.generate(
      count,
      (i) => -pi / 2 + (2 * pi * i / count),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(count, (index) {
          final angle = angles[index];
          final path = _icons[index % _icons.length];

          final activeIndex = _step % count;
          final isActive = index == activeIndex;

          return Positioned(
            left: size / 2 + cos(angle) * radius - iconSize / 2,
            top: size / 2 + sin(angle) * radius - iconSize / 2,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: isActive ? 1.0 : 0.18,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale: isActive ? 1.18 : 0.78,
                child: Transform.rotate(
                  angle: angle + pi / 2,
                  child: Image.asset(
                    path,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          );
        }),
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
      final wave = sin(phase + t * pi * 1.8) * amplitude;

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

class _OtherSpotMarker extends StatefulWidget {
  final SpotFlagState spot;
  final String iconPath;
  final bool showTextAllowed;
  final double zoom;
  final double rotation;
  final double labelOpacity;
  final Color typeTextColor;

  const _OtherSpotMarker({
    required this.spot,
    required this.iconPath,
    required this.showTextAllowed,
    required this.zoom,
    required this.rotation,
    required this.labelOpacity,
    required this.typeTextColor,
  });

  @override
  State<_OtherSpotMarker> createState() => _OtherSpotMarkerState();
}

class _OtherSpotMarkerState extends State<_OtherSpotMarker> {
  bool isHovering = false;

  double _labelSize(double base) {
    if (widget.zoom >= 16) return base + 2;
    if (widget.zoom >= 15) return base + 1.5;
    if (widget.zoom >= 14) return base + 1;
    if (widget.zoom >= 13) return base;
    return base - 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;

    final isTouchDevice =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    final showText =
        widget.showTextAllowed && (isTouchDevice || isHovering);

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
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
              Image.asset(
                widget.iconPath,
                width: spot.isNaturisme ? 52 : 48,
                height: spot.isNaturisme ? 52 : 48,
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${spot.name} - ${spot.nomSphot}',
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(11),
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            spot.typeSphot,
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(10),
                              fontWeight: FontWeight.w700,
                              color: widget.typeTextColor,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '⚠️ BAIGNADE NON SURVEILLÉE',
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(10),
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFFF0000),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '⚠️ BAIGNADE À VOS RISQUES ET PÉRILS',
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(10),
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFFF0000),
                            ),
                          ),
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

class _SimplePostePoint extends StatelessWidget {
  final SpotFlagState spot;

  const _SimplePostePoint({required this.spot});

  Color _getColor() {
    switch (spot.flagColor) {
      case FlagColor.green:
        return const Color(0xFF22C55E);
      case FlagColor.yellow:
        return const Color(0xFFFDE047);
      case FlagColor.red:
        return const Color(0xFFEF4444);
      case FlagColor.violet:
        return const Color(0xFFD946EF);
      case FlagColor.none:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFlag = spot.hasValidFlag;

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: hasFlag ? _getColor() : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: hasFlag ? Colors.white : Colors.black,
          width: 2,
        ),
      ),
    );
  }
}

class _HoverMarker extends StatefulWidget {
  final SpotFlagState spot;
  final bool showTextAllowed;
  final double zoom;
  final double rotation;
  final double labelOpacity;

  const _HoverMarker({
    required this.spot,
    required this.showTextAllowed,
    required this.zoom,
    required this.rotation,
    required this.labelOpacity,
  });

  @override
  State<_HoverMarker> createState() => _HoverMarkerState();
}

class _HoverMarkerState extends State<_HoverMarker> {
  bool isHovering = false;

  double _labelSize(double base) {
    if (widget.zoom >= 16) return base + 2;
    if (widget.zoom >= 15) return base + 1.5;
    if (widget.zoom >= 14) return base + 1;
    if (widget.zoom >= 13) return base;
    return base - 0.5;
  }

  Widget _warningLine(String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: _labelSize(18),
          color: const Color(0xFFFF0000),
          shadows: const [Shadow(color: Colors.white, blurRadius: 2)],
        ),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: _mapLabelStyle(
              fontSize: _labelSize(10),
              fontWeight: FontWeight.w900,
              color: const Color(0xFFFF0000),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;

    final isTouchDevice =
        Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;

    final showText =
        widget.showTextAllowed && (isTouchDevice || isHovering);

    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: SizedBox(
        width: 70,
        height: 95,
        child: Transform.rotate(
          angle: -widget.rotation * pi / 180,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                offset: const Offset(0, -47.5),
                child: FlagMarker(spot: spot),
              ),

              if (showText)
                Positioned(
                  top: 54,
                  left: -175,
                  child: Opacity(
                    opacity: widget.labelOpacity,
                    child: SizedBox(
                      width: 420,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${spot.name} - ${spot.nomSphot}',
                            textAlign: TextAlign.center,
                            style: _mapLabelStyle(
                              fontSize: _labelSize(11),
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: _mapLabelStyle(
                                fontSize: _labelSize(10),
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                              children: [
                                const TextSpan(
                                  text: '🚨 POSTE DE SECOURS 🚨',
                                  style: TextStyle(
                                    color: Color(0xFFFF0000),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (spot.phone.trim().isNotEmpty)
                                  TextSpan(text: ' - 📞 ${spot.phone}'),
                                if (spot.heureDebut.trim().isNotEmpty &&
                                    spot.heureFin.trim().isNotEmpty)
                                  TextSpan(
                                    text:
                                        ' - 🕘 ${spot.heureDebut} - ${spot.heureFin}',
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (spot.isMissingFlagColorDuringSurveillance) ...[
                            _warningLine('COULEUR DE LA FLAMME NON RENSEIGNÉE'),
                            _warningLine('BAIGNADE À VOS RISQUES ET PÉRILS'),
                          ] else
                            Text(
                              spot.displayStatut,
                              textAlign: TextAlign.center,
                              style: _mapLabelStyle(
                                fontSize: _labelSize(10),
                                fontWeight: FontWeight.w900,
                                color: Color(spot.statutColor),
                              ),
                            ),
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

TextStyle _mapLabelStyle({
  required double fontSize,
  required FontWeight fontWeight,
  required Color color,
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: 1.1,
    letterSpacing: -0.1,
    shadows: const [
      Shadow(color: Colors.white, offset: Offset(0, 0), blurRadius: 2),
      Shadow(color: Colors.white, offset: Offset(1, 0), blurRadius: 1),
      Shadow(color: Colors.white, offset: Offset(-1, 0), blurRadius: 1),
      Shadow(color: Colors.white, offset: Offset(0, 1), blurRadius: 1),
      Shadow(color: Colors.white, offset: Offset(0, -1), blurRadius: 1),
    ],
  );
}