import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  final String _apiKey = 'VOTRE_CLE_API'; // Remplacez par votre clé API OpenWeatherMap
  final String _baseUrl = 'https://api.openweathermap.org/data/2.5/weather';

  Future<Map<String, dynamic>?> fetchWeather(double latitude, double longitude) async {
    final url = '$_baseUrl?lat=$latitude&lon=$longitude&appid=$_apiKey&units=metric';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Erreur lors de la récupération des données météo : ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception : $e');
      return null;
    }
  }
}