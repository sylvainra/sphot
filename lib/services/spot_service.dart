import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/spot.dart';

class SpotService {
  static Future<List<Spot>> loadSpots() async {
    final String jsonString =
        await rootBundle.loadString('assets/data/spots.json');

    final List<dynamic> jsonData = json.decode(jsonString);

    return jsonData.map((e) => Spot.fromJson(e)).toList();
  }
}
