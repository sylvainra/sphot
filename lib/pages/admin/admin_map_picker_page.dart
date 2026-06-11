import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AdminMapPickerPage extends StatefulWidget {
  final String title;
  final double? initialLat;
  final double? initialLng;

  const AdminMapPickerPage({
    super.key,
    required this.title,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<AdminMapPickerPage> createState() => _AdminMapPickerPageState();
}

class _AdminMapPickerPageState extends State<AdminMapPickerPage> {
  static const Color adminColor = Color(0xFF1E3A8A);
  static const Color redColor = Color(0xFFDC2626);

  LatLng? selectedPoint;
  bool _saved = false;

  @override
  void initState() {
    super.initState();

    if (widget.initialLat != null &&
        widget.initialLng != null &&
        widget.initialLat != 0.0 &&
        widget.initialLng != 0.0) {
      selectedPoint = LatLng(widget.initialLat!, widget.initialLng!);
    }
  }

  void _savePosition() {
    if (selectedPoint == null) return;

    setState(() {
      _saved = true;
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      Navigator.of(context).pop(selectedPoint);
    });
  }

  @override
  Widget build(BuildContext context) {
    final LatLng startPoint =
        selectedPoint ?? const LatLng(46.4167, -1.4833);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: startPoint,
              initialZoom: selectedPoint == null ? 11 : 16,
              onTap: (tapPosition, point) {
                setState(() {
                  selectedPoint = point;
                  _saved = false;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.sphot.app',
              ),
              if (selectedPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: selectedPoint!,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Colors.red,
                        size: 46,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: adminColor,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: redColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),

                  const Spacer(),

                  if (selectedPoint != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: adminColor,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        'Latitude : ${selectedPoint!.latitude.toStringAsFixed(6)}\n'
                        'Longitude : ${selectedPoint!.longitude.toStringAsFixed(6)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: adminColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saved
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: adminColor,
                          ),
                          label: const Text(
                            'ANNULER',
                            style: TextStyle(
                              color: adminColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            foregroundColor: adminColor,
                            disabledForegroundColor: adminColor,
                            elevation: 0,
                            side: const BorderSide(
                              color: adminColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              selectedPoint == null || _saved
                                  ? null
                                  : _savePosition,
                          style: OutlinedButton.styleFrom(
                            backgroundColor:
                                _saved ? redColor : Colors.transparent,
                            disabledBackgroundColor:
                                _saved ? redColor : Colors.transparent,
                            foregroundColor:
                                _saved ? Colors.white : redColor,
                            disabledForegroundColor:
                                _saved ? Colors.white : Colors.grey,
                            side: BorderSide(
                              color: selectedPoint == null
                                  ? Colors.grey
                                  : redColor,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            _saved ? 'ENREGISTRÉ' : 'ENREGISTRER',
                            style: TextStyle(
                              color: _saved
                                  ? Colors.white
                                  : selectedPoint == null
                                      ? Colors.grey
                                      : redColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
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