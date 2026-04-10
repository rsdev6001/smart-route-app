import "package:latlong2/latlong.dart";

class ChargingStation {
  const ChargingStation({
    required this.id,
    required this.name,
    required this.location,
    required this.address,
    required this.connectionInfo,
  });

  final String id;
  final String name;
  final LatLng location;
  final String address;
  final String connectionInfo;
}

class RoutePlan {
  const RoutePlan({
    required this.routePoints,
    required this.distanceKm,
    required this.durationMinutes,
    required this.chargingStops,
    required this.originLabel,
    required this.destinationLabel,
  });

  final List<LatLng> routePoints;
  final double distanceKm;
  final double durationMinutes;
  final List<ChargingStation> chargingStops;
  final String originLabel;
  final String destinationLabel;
}
