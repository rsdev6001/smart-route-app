import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:geolocator/geolocator.dart";
import "package:latlong2/latlong.dart";
import "package:smart_route/config/app_config.dart";
import "package:smart_route/models/route_plan.dart";
import "package:smart_route/models/vehicle_profile.dart";
import "package:smart_route/services/charging_service.dart";
import "package:smart_route/services/ev_route_planner.dart";
import "package:smart_route/services/geocoding_service.dart";
import "package:smart_route/services/routing_service.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartRouteApp());
}

class SmartRouteApp extends StatelessWidget {
  const SmartRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "SmartRoute",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E67D6)),
        useMaterial3: true,
      ),
      home: const SmartRouteHomePage(),
    );
  }
}

class SmartRouteHomePage extends StatefulWidget {
  const SmartRouteHomePage({super.key});

  @override
  State<SmartRouteHomePage> createState() => _SmartRouteHomePageState();
}

class _SmartRouteHomePageState extends State<SmartRouteHomePage> {
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  VehicleProfile _selectedVehicle = vehicleProfiles[1];
  RoutePlan? _routePlan;
  bool _isLoading = false;
  String? _error;

  late final EvRoutePlanner _planner = EvRoutePlanner(
    geocodingService: GeocodingService(userAgent: AppConfig.userAgent),
    routingService: RoutingService(apiKey: AppConfig.orsApiKey),
    chargingService: ChargingService(),
  );

  static const LatLng _defaultCenter = LatLng(51.5074, -0.1278);

  @override
  void initState() {
    super.initState();
    _originController.text = "Waterloo Station, London";
    _destinationController.text = "The British Museum, London";
    _tryUseCurrentLocation();
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _tryUseCurrentLocation() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return;
    }

    final Position pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _originController.text = "${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}";
    });
  }

  Future<void> _planRoute() async {
    if (!AppConfig.isConfigured) {
      setState(() {
        _error = "Missing ORS_API_KEY. Run with --dart-define=ORS_API_KEY=your_key";
      });
      return;
    }
    if (_originController.text.trim().isEmpty || _destinationController.text.trim().isEmpty) {
      setState(() {
        _error = "Enter both origin and destination.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final RoutePlan plan = await _planner.buildPlan(
        originQuery: _originController.text.trim(),
        destinationQuery: _destinationController.text.trim(),
        vehicle: _selectedVehicle,
      );
      if (!mounted) return;
      setState(() {
        _routePlan = plan;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Marker> _buildMarkers() {
    final RoutePlan? plan = _routePlan;
    if (plan == null || plan.routePoints.isEmpty) return <Marker>[];

    final List<Marker> markers = <Marker>[
      Marker(
        point: plan.routePoints.first,
        width: 50,
        height: 50,
        child: const Icon(Icons.my_location, color: Colors.blue, size: 34),
      ),
      Marker(
        point: plan.routePoints.last,
        width: 50,
        height: 50,
        child: const Icon(Icons.location_on, color: Colors.red, size: 36),
      ),
    ];

    for (final ChargingStation s in plan.chargingStops) {
      markers.add(
        Marker(
          point: s.location,
          width: 50,
          height: 50,
          child: Tooltip(
            message: "${s.name}\n${s.connectionInfo}",
            child: const Icon(Icons.ev_station, color: Colors.green, size: 34),
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final List<LatLng> routePoints = _routePlan?.routePoints ?? <LatLng>[];
    final LatLng mapCenter = routePoints.isNotEmpty ? routePoints.first : _defaultCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Text("SmartRoute"),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _originController,
                      decoration: const InputDecoration(
                        labelText: "Your location",
                        prefixIcon: Icon(Icons.near_me),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _destinationController,
                      decoration: const InputDecoration(
                        labelText: "Destination",
                        prefixIcon: Icon(Icons.place_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<VehicleProfile>(
                      value: _selectedVehicle,
                      items: vehicleProfiles
                          .map((VehicleProfile v) => DropdownMenuItem<VehicleProfile>(
                                value: v,
                                child: Text(v.label),
                              ))
                          .toList(),
                      onChanged: (VehicleProfile? value) {
                        if (value == null) return;
                        setState(() {
                          _selectedVehicle = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: "Select Vehicle type",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _planRoute,
                        icon: const Icon(Icons.alt_route),
                        label: Text(_isLoading ? "Finding..." : "Get Directions"),
                      ),
                    ),
                    if (_routePlan != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Distance: ${_routePlan!.distanceKm.toStringAsFixed(1)} km | ETA: ${_routePlan!.durationMinutes.toStringAsFixed(0)} min | Charging stops: ${_routePlan!.chargingStops.length}",
                        ),
                      ),
                    ],
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: mapCenter,
                initialZoom: 12,
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: "com.example.smartroute",
                ),
                if (routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: <Polyline>[
                      Polyline(
                        points: routePoints,
                        color: const Color(0xFF1E67D6),
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                MarkerLayer(markers: _buildMarkers()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
