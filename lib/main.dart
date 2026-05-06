import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'map/map_page.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

await FMTC.instance('mapStore').manage.create();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SPHOT',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MapPage(), // ⚠️ PAS de const ici
    );
  }
}