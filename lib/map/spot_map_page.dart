import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/spot.dart';
import '../services/spot_service.dart';

class SpotMapPage extends StatelessWidget {
  const SpotMapPage({super.key});

  Color _getMarkerColor(Spot spot) {
    final statut = spot.statut.toLowerCase();

    if (statut.contains('rouge')) return Colors.red;
    if (statut.contains('jaune')) return Colors.orange;
    if (statut.contains('vert')) return Colors.green;
    if (statut.contains('non')) return Colors.red;

    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Spot>>(
      future: SpotService.loadSpots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text('Erreur : ${snapshot.error}'),
            ),
          );
        }

        final spots = snapshot.data ?? [];

        return Scaffold(
          appBar: AppBar(
            title: Text('${spots.length} spots chargés'),
          ),
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(46.4167, -1.5000),
              initialZoom: 11,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bathing_spots_app',
              ),
              MarkerLayer(
                markers: spots
                    .where((spot) => spot.latitude != 0 && spot.longitude != 0)
                    .map(
                      (spot) => Marker(
                        point: LatLng(spot.latitude, spot.longitude),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (_) {
                                return Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        spot.nom,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text('Statut : ${spot.statut}'),
                                      Text('Latitude : ${spot.latitude}'),
                                      Text('Longitude : ${spot.longitude}'),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          child: Icon(
                            Icons.location_on,
                            color: _getMarkerColor(spot),
                            size: 42,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}



