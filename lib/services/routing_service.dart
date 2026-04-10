import "dart:convert";

import "package:http/http.dart" as http;
import "package:latlong2/latlong.dart";

class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
  });

  final List<LatLng> points;
  final double distanceKm;
  final double durationMinutes;
}

class RoutingService {
  RoutingService({required this.apiKey});

  final String apiKey;

  Future<RouteResult> fetchRoute({
    required LatLng start,
    required LatLng end,
  }) async {
    final uri = Uri.https(
      "api.openrouteservice.org",
      "/v2/directions/driving-car/geojson",
    );

    final body = <String, dynamic>{
      "coordinates": <List<double>>[
        <double>[start.longitude, start.latitude],
        <double>[end.longitude, end.latitude],
      ],
    };

    final response = await http.post(
      uri,
      headers: <String, String>{
        "Authorization": apiKey,
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception("Routing failed (${response.statusCode}): ${response.body}");
    }

    final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> features = json["features"] as List<dynamic>;
    final Map<String, dynamic> feature = features.first as Map<String, dynamic>;
    final Map<String, dynamic> geometry = feature["geometry"] as Map<String, dynamic>;
    final List<dynamic> coordinates = geometry["coordinates"] as List<dynamic>;

    final List<LatLng> points = coordinates
        .map((dynamic c) => c as List<dynamic>)
        .map((List<dynamic> c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    final Map<String, dynamic> properties = feature["properties"] as Map<String, dynamic>;
    final Map<String, dynamic> summary = properties["summary"] as Map<String, dynamic>;
    return RouteResult(
      points: points,
      distanceKm: ((summary["distance"] as num).toDouble()) / 1000,
      durationMinutes: ((summary["duration"] as num).toDouble()) / 60,
    );
  }
}
