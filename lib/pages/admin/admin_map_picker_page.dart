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

  LatLng? selectedPoint;

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
    color: Color(0xFF1E3A8A),
    width: 2,
  ),
),
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
  color: Color(0xFFDC2626),
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
      color: Color(0xFF1E3A8A),
      width: 1.5,
    ),
  ),
  child: Text(
    'Latitude : ${selectedPoint!.latitude.toStringAsFixed(6)}\n'
    'Longitude : ${selectedPoint!.longitude.toStringAsFixed(6)}',
    textAlign: TextAlign.center,
    style: const TextStyle(
      color: Color(0xFF1E3A8A),
      fontWeight: FontWeight.w800,
    ),
  ),
),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(
  Icons.close_rounded,
  color: Color(0xFF1E3A8A),
),
                          label: const Text(
  'ANNULER',
  style: TextStyle(
    color: Color(0xFF1E3A8A),
    fontWeight: FontWeight.w900,
  ),
),
                          style: ElevatedButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: const Color(0xFF1E3A8A),
  elevation: 0,
  side: const BorderSide(
    color: Color(0xFF1E3A8A),
    width: 2,
  ),
),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: selectedPoint == null
                              ? null
                              : () {
                                  Navigator.of(context).pop(selectedPoint);
                                },
                          icon: const Icon(Icons.check_rounded),
                          label: const Text(
                            'VALIDER',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
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