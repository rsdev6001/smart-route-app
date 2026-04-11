import "dart:convert";

import "package:http/http.dart" as http;
import "package:latlong2/latlong.dart";
import "package:smart_route/models/route_plan.dart";

class ChargingService {
  Future<List<ChargingStation>> fetchStationsNear({
    required LatLng center,
    required double distanceKm,
    int maxResults = 25,
  }) async {
    final uri = Uri.https(
      "api.openchargemap.io",
      "/v3/poi/",
      <String, String>{
        "key": "ef1ca54f-14d2-410f-8ceb-a5ad7d73ac3f",
        "output": "json",
        "latitude": center.latitude.toString(),
        "longitude": center.longitude.toString(),
        "distance": distanceKm.toString(),
        "distanceunit": "KM",
        "maxresults": maxResults.toString(),
        "compact": "true",
        "verbose": "false",
      },
    );

    final response =
        await http.get(uri, headers: const <String, String>{"X-API-Key": ""});
    if (response.statusCode != 200) {
      throw Exception(
          "Charging stations fetch failed (${response.statusCode})");
    }

    final List<dynamic> items = jsonDecode(response.body) as List<dynamic>;
    return items.map((dynamic item) {
      final Map<String, dynamic> p = item as Map<String, dynamic>;
      final Map<String, dynamic> info =
          p["AddressInfo"] as Map<String, dynamic>;
      final List<dynamic>? connections = p["Connections"] as List<dynamic>?;

      final String connectionInfo = (connections == null || connections.isEmpty)
          ? "Connector details unavailable"
          : (connections.first as Map<String, dynamic>)["ConnectionType"]
                      ?["Title"]
                  ?.toString() ??
              "Connector details unavailable";

      return ChargingStation(
        id: p["ID"].toString(),
        name: info["Title"]?.toString() ?? "Charging Station",
        location: LatLng(
          (info["Latitude"] as num).toDouble(),
          (info["Longitude"] as num).toDouble(),
        ),
        address: info["AddressLine1"]?.toString() ?? "Address unavailable",
        connectionInfo: connectionInfo,
      );
    }).toList();
  }
}
