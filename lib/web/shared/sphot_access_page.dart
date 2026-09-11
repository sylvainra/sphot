import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

const sphotAccessBlue = Color(0xFF1E3A8A);

class SphotAccessPage extends StatelessWidget {
  const SphotAccessPage({
    super.key,
    required this.title,
    required this.child,
    required this.onBack,
    this.onBackgroundTap,
  });

  final String title;
  final Widget child;
  final VoidCallback onBack;
  final VoidCallback? onBackgroundTap;

  @override
  Widget build(BuildContext context) {
    return TooltipVisibility(
      visible: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          onTap: onBackgroundTap ?? () => FocusScope.of(context).unfocus(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('data/images/map_background.jpg', fit: BoxFit.cover),
              IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) => FlutterMap(
                    options: MapOptions(
                      initialCenter: const LatLng(46.3893825, -1.4942598),
                      initialZoom: constraints.maxWidth / constraints.maxHeight >= 1.2
                          ? 17.35
                          : 16.2,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                      backgroundColor: Colors.transparent,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        maxZoom: 19,
                        maxNativeZoom: 19,
                        userAgentPackageName: 'com.sylvainra.sphot',
                        keepBuffer: 5,
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 78, bottom: 98),
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: sphotAccessBlue, width: 2.5),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SvgPicture.asset(
                                          'data/icons/fire_red_icon.svg',
                                          width: 42,
                                          height: 58,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          title,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: sphotAccessBlue,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        child,
                                      ],
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
                ),
              ),
              SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: 68,
                    child: Stack(
                      children: [
                        Positioned(
                          top: -5,
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
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: sphotAccessBlue, width: 2),
                      ),
                      child: IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back, color: sphotAccessBlue, size: 28),
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

class SphotAccessButton extends StatelessWidget {
  const SphotAccessButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: ButtonStyle(
        foregroundColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.disabled)
                ? sphotAccessBlue.withOpacity(0.55)
                : sphotAccessBlue),
        backgroundColor: MaterialStateProperty.all(Colors.transparent),
        overlayColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.pressed)) {
            return sphotAccessBlue.withOpacity(0.14);
          }
          if (states.contains(MaterialState.hovered) ||
              states.contains(MaterialState.focused)) {
            return sphotAccessBlue.withOpacity(0.08);
          }
          return Colors.transparent;
        }),
        elevation: MaterialStateProperty.all(0),
        side: MaterialStateProperty.resolveWith((states) => BorderSide(
          color: states.contains(MaterialState.disabled)
              ? sphotAccessBlue.withOpacity(0.55)
              : sphotAccessBlue,
          width: 2,
        )),
        shape: MaterialStateProperty.all(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        )),
      ),
      child: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: sphotAccessBlue),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    )),
                  ),
                ),
              ],
            ),
    ),
  );
}
