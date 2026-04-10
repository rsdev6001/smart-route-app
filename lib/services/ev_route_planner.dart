import "dart:math";

import "package:latlong2/latlong.dart";
import "package:smart_route/models/route_plan.dart";
import "package:smart_route/models/vehicle_profile.dart";
import "package:smart_route/services/charging_service.dart";
import "package:smart_route/services/geocoding_service.dart";
import "package:smart_route/services/routing_service.dart";

class EvRoutePlanner {
  EvRoutePlanner({
    required this.geocodingService,
    required this.routingService,
    required this.chargingService,
  });

  final GeocodingService geocodingService;
  final RoutingService routingService;
  final ChargingService chargingService;
  final Distance _distance = const Distance();

  Future<RoutePlan> buildPlan({
    required String originQuery,
    required String destinationQuery,
    required VehicleProfile vehicle,
  }) async {
    final LatLng origin = await geocodingService.geocodePlace(originQuery);
    final LatLng destination = await geocodingService.geocodePlace(destinationQuery);
    final RouteResult route = await routingService.fetchRoute(start: origin, end: destination);

    final List<ChargingStation> stops = <ChargingStation>[];
    final double maxLegKm = vehicle.rangeKm * 0.8;

    if (route.distanceKm > maxLegKm) {
      stops.addAll(await _selectChargingStops(route.points, maxLegKm));
    }

    return RoutePlan(
      routePoints: route.points,
      distanceKm: route.distanceKm,
      durationMinutes: route.durationMinutes,
      chargingStops: stops,
      originLabel: originQuery,
      destinationLabel: destinationQuery,
    );
  }

  Future<List<ChargingStation>> _selectChargingStops(
    List<LatLng> routePoints,
    double maxLegKm,
  ) async {
    if (routePoints.isEmpty) return <ChargingStation>[];

    final List<double> cumulativeKm = _buildCumulativeDistances(routePoints);
    final double totalKm = cumulativeKm.last;

    final Set<String> seenIds = <String>{};
    final List<ChargingStation> candidateStations = <ChargingStation>[];

    for (double sampleAt = maxLegKm * 0.75; sampleAt < totalKm; sampleAt += maxLegKm * 0.75) {
      final int sampleIndex = _indexAtDistance(cumulativeKm, sampleAt);
      final LatLng samplePoint = routePoints[sampleIndex];
      final List<ChargingStation> around = await chargingService.fetchStationsNear(
        center: samplePoint,
        distanceKm: 20,
        maxResults: 40,
      );
      for (final ChargingStation station in around) {
        if (seenIds.add(station.id)) {
          candidateStations.add(station);
        }
      }
    }

    final List<_ProjectedStation> projected = candidateStations
        .map((ChargingStation station) => _projectToRoute(station, routePoints, cumulativeKm))
        .whereType<_ProjectedStation>()
        .toList()
      ..sort((a, b) => a.kmAlongRoute.compareTo(b.kmAlongRoute));

    return _greedyStopSelection(projected, maxLegKm, totalKm);
  }

  List<ChargingStation> _greedyStopSelection(
    List<_ProjectedStation> projected,
    double maxLegKm,
    double totalKm,
  ) {
    final List<ChargingStation> result = <ChargingStation>[];
    double currentKm = 0;
    int guard = 0;

    while ((totalKm - currentKm) > maxLegKm && guard < 20) {
      guard++;
      _ProjectedStation? best;
      for (final _ProjectedStation station in projected) {
        final double legKm = station.kmAlongRoute - currentKm;
        if (legKm > 1 && legKm <= maxLegKm) {
          if (best == null || station.kmAlongRoute > best.kmAlongRoute) {
            best = station;
          }
        }
      }
      if (best == null) {
        break;
      }
      result.add(best.station);
      currentKm = best.kmAlongRoute;
    }

    return result;
  }

  _ProjectedStation? _projectToRoute(
    ChargingStation station,
    List<LatLng> routePoints,
    List<double> cumulativeKm,
  ) {
    double? bestDistanceMeters;
    int bestIndex = -1;
    for (int i = 0; i < routePoints.length; i++) {
      final double meters = _distance.as(
        LengthUnit.Meter,
        station.location,
        routePoints[i],
      );
      if (bestDistanceMeters == null || meters < bestDistanceMeters) {
        bestDistanceMeters = meters;
        bestIndex = i;
      }
    }
    if (bestIndex == -1 || (bestDistanceMeters ?? 999999) > 2500) {
      return null;
    }

    return _ProjectedStation(
      station: station,
      kmAlongRoute: cumulativeKm[bestIndex],
    );
  }

  List<double> _buildCumulativeDistances(List<LatLng> points) {
    final List<double> out = List<double>.filled(points.length, 0);
    for (int i = 1; i < points.length; i++) {
      out[i] = out[i - 1] + _distance.as(LengthUnit.Kilometer, points[i - 1], points[i]);
    }
    return out;
  }

  int _indexAtDistance(List<double> cumulative, double km) {
    for (int i = 0; i < cumulative.length; i++) {
      if (cumulative[i] >= km) return i;
    }
    return max(0, cumulative.length - 1);
  }
}

class _ProjectedStation {
  const _ProjectedStation({
    required this.station,
    required this.kmAlongRoute,
  });

  final ChargingStation station;
  final double kmAlongRoute;
}
