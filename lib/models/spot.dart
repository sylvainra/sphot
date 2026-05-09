class Spot {
  final String nom;
  final double latitude;
  final double longitude;
  final String statut;

  Spot({
    required this.nom,
    required this.latitude,
    required this.longitude,
    required this.statut,
  });

  factory Spot.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0;
      return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
    }

    return Spot(
      nom: json['nom'] ??
          json['Nom'] ??
          json['name'] ??
          json['Name'] ??
          json['spot'] ??
          json['Spot'] ??
          'Spot sans nom',
      latitude: parseDouble(
        json['latitude'] ?? json['Latitude'] ?? json['lat'] ?? json['Lat'],
      ),
      longitude: parseDouble(
        json['longitude'] ?? json['Longitude'] ?? json['lng'] ?? json['Lon'],
      ),
      statut: json['statut'] ?? json['Statut'] ?? json['status'] ?? '',
    );
  }
}