import "dart:convert";

import "package:http/http.dart" as http;
import "package:latlong2/latlong.dart";

class GeocodingService {
  GeocodingService({required this.userAgent});

  final String userAgent;

  Future<LatLng> geocodePlace(String query) async {
    final uri = Uri.https("nominatim.openstreetmap.org", "/search", <String, String>{
      "q": query,
      "format": "jsonv2",
      "limit": "1",
    });

    final response = await http.get(uri, headers: <String, String>{"User-Agent": userAgent});
    if (response.statusCode != 200) {
      throw Exception("Geocoding failed (${response.statusCode})");
    }

    final List<dynamic> json = jsonDecode(response.body) as List<dynamic>;
    if (json.isEmpty) {
      throw Exception("No location found for '$query'");
    }

    final Map<String, dynamic> first = json.first as Map<String, dynamic>;
    return LatLng(
      double.parse(first["lat"].toString()),
      double.parse(first["lon"].toString()),
    );
  }
}
