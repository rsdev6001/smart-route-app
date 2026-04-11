import "dart:convert";

import "package:http/http.dart" as http;
import "package:latlong2/latlong.dart";

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.name,
    required this.location,
  });

  final String name;
  final LatLng location;
}

class GeocodingService {
  GeocodingService({
    required this.userAgent,
    required this.orsApiKey,
  });

  final String userAgent;
  final String orsApiKey;

  Future<List<PlaceSuggestion>> autocompletePlaces(String query) async {
    final String trimmed = "${query.trim()} India";
    if (trimmed.isEmpty || orsApiKey.trim().isEmpty) return <PlaceSuggestion>[];

    final uri = Uri.https(
      "api.openrouteservice.org",
      "/geocode/autocomplete",
      <String, String>{
        "api_key": orsApiKey,
        "text": trimmed,
        "size": "5",
        "layers": "venue",
      },
    );

    final response =
        await http.get(uri, headers: <String, String>{"User-Agent": userAgent});
    if (response.statusCode != 200) {
      throw Exception("Autocomplete failed (${response.statusCode})");
    }

    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> features =
        json["features"] as List<dynamic>? ?? <dynamic>[];
    return features.map((dynamic item) {
      final Map<String, dynamic> feature = item as Map<String, dynamic>;
      final Map<String, dynamic> geometry =
          feature["geometry"] as Map<String, dynamic>;
      final List<dynamic> coordinates =
          geometry["coordinates"] as List<dynamic>;
      final Map<String, dynamic> properties =
          feature["properties"] as Map<String, dynamic>;
      final String name = properties["name"]?.toString() ?? "Unknown place";
      final double lon = (coordinates[0] as num).toDouble();
      final double lat = (coordinates[1] as num).toDouble();

      return PlaceSuggestion(
        name: name,
        location: LatLng(lat, lon),
      );
    }).toList();
  }

  Future<LatLng> geocodePlace(String query) async {
    final uri =
        Uri.https("nominatim.openstreetmap.org", "/search", <String, String>{
      "q": query,
      "format": "jsonv2",
      "limit": "1",
    });

    final response =
        await http.get(uri, headers: <String, String>{"User-Agent": userAgent});
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
