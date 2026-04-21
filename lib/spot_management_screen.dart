import 'package:flutter/material.dart';

class SpotManagementScreen extends StatelessWidget {
  const SpotManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Spots de Baignade'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.pool),
            title: const Text('Plage de Longeville-sur-Mer'),
            subtitle: const Text('Type: Océan / Mer\nSurveillé: Oui'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              // Naviguer vers les détails du spot
            },
          ),
          // Ajouter d'autres spots ici
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Ajouter un nouveau spot
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}