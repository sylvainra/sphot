import 'package:flutter/material.dart';

class AdService {
  // Exemple de méthode pour afficher une publicité
  Widget displayAd(String adContent) {
    return Card(
      margin: const EdgeInsets.all(10.0),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Publicité',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(adContent),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                // Logique pour acheter l'espace publicitaire
              },
              child: const Text('Acheter cet espace publicitaire'),
            ),
          ],
        ),
      ),
    );
  }
}