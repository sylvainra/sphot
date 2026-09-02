import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'web/advertiser/web_advertiser_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final FirebaseOptions defaultOptions =
      DefaultFirebaseOptions.currentPlatform;

  final FirebaseOptions advertiserOptions = FirebaseOptions(
    apiKey: defaultOptions.apiKey,
    appId: defaultOptions.appId,
    messagingSenderId: defaultOptions.messagingSenderId,
    projectId: defaultOptions.projectId,
    authDomain: 'sphot-advertiser-test.firebaseapp.com',
    storageBucket: defaultOptions.storageBucket,
    measurementId: defaultOptions.measurementId,
  );

  await Firebase.initializeApp(options: advertiserOptions);

  runApp(const WebAdvertiserApp());
}