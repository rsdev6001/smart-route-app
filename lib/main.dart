import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_map/flutter_map.dart";
import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:geolocator/geolocator.dart";
import "package:latlong2/latlong.dart";
import "package:smart_route/config/app_config.dart";
import "package:smart_route/models/route_plan.dart";
import "package:smart_route/models/vehicle_profile.dart";
import "package:smart_route/services/charging_service.dart";
import "package:smart_route/services/ev_route_planner.dart";
import "package:smart_route/services/geocoding_service.dart";
import "package:smart_route/services/routing_service.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await dotenv.load(fileName: ".env");
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: "SF Pro Display",
      ),
      home: const SmartRouteHomePage(),
    );
  }
}

// ── Colour constants ──────────────────────────────────────────────────────────
const Color _kSurface = Color(0xFF0F1923);
const Color _kCard = Color(0xFF1A2535);
const Color _kBlue = Color(0xFF3B82F6);
const Color _kBlueLight = Color(0xFF93C5FD);
const Color _kGreen = Color(0xFF10B981);
const Color _kTextPri = Color(0xFFE2E8F0);
const Color _kTextMut = Color(0xFF94A3B8);
const Color _kBorder = Color(0x1AFFFFFF);

class SmartRouteHomePage extends StatefulWidget {
  const SmartRouteHomePage({super.key});

  @override
  State<SmartRouteHomePage> createState() => _SmartRouteHomePageState();
}

class _SmartRouteHomePageState extends State<SmartRouteHomePage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  List<PlaceSuggestion> _originSuggestions = [];
  List<PlaceSuggestion> _destinationSuggestions = [];
  PlaceSuggestion? _selectedOriginSuggestion;
  PlaceSuggestion? _selectedDestinationSuggestion;

  VehicleProfile _selectedVehicle = vehicleProfiles[1];
  RoutePlan? _routePlan;
  bool _isLoading = false;
  bool _isOriginAutocompleteLoading = false;
  bool _isDestinationAutocompleteLoading = false;
  String? _error;

  late final EvRoutePlanner _planner = EvRoutePlanner(
    geocodingService: GeocodingService(
      userAgent: AppConfig.userAgent,
      orsApiKey: AppConfig.orsApiKey,
    ),
    routingService: RoutingService(apiKey: AppConfig.orsApiKey),
    chargingService: ChargingService(),
  );

  static const LatLng _defaultCenter = LatLng(51.5074, -0.1278);
  late final MapController _mapController = MapController();

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
    _sheetController.dispose();
    super.dispose();
  }

  // ── Location ─────────────────────────────────────────────────────────────
  Future<void> _tryUseCurrentLocation() async {
    final bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

    final Position pos = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _originController.text =
          "${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}";
    });
  }

  // ── Route planning ────────────────────────────────────────────────────────
  Future<void> _planRoute() async {
    if (!AppConfig.isConfigured) {
      _setError("Missing ORS_API_KEY.");
      return;
    }
    if (_originController.text.trim().isEmpty ||
        _destinationController.text.trim().isEmpty) {
      _setError("Enter both origin and destination.");
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final plan = await _planner.buildPlan(
        originQuery: _queryForRouting(
            _originController.text.trim(), _selectedOriginSuggestion),
        destinationQuery: _queryForRouting(
            _destinationController.text.trim(), _selectedDestinationSuggestion),
        vehicle: _selectedVehicle,
      );
      if (!mounted) return;
      setState(() {
        _routePlan = plan;
      });

      // Collapse sheet after successful route
      _sheetController.animateTo(
        0.18,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );

      // Fit map to route bounds
      if (plan.routePoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(plan.routePoints);
        _mapController.fitCamera(
          CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.fromLTRB(40, 100, 40, 260)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _setError(e.toString());
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setError(String msg) => setState(() => _error = msg);

  String _queryForRouting(String text, PlaceSuggestion? sel) {
    if (sel == null || text != sel.name) return text;
    return "${sel.location.latitude}, ${sel.location.longitude}";
  }

  // ── Autocomplete ──────────────────────────────────────────────────────────
  Future<void> _handleOriginChanged(String value) async {
    _selectedOriginSuggestion = null;
    if (!value.endsWith(" ")) {
      if (_originSuggestions.isNotEmpty)
        setState(() => _originSuggestions = []);
      return;
    }
    await _loadSuggestions(value, isOrigin: true);
  }

  Future<void> _handleDestinationChanged(String value) async {
    _selectedDestinationSuggestion = null;
    if (!value.endsWith(" ")) {
      if (_destinationSuggestions.isNotEmpty)
        setState(() => _destinationSuggestions = []);
      return;
    }
    await _loadSuggestions(value, isOrigin: false);
  }

  Future<void> _loadSuggestions(String query, {required bool isOrigin}) async {
    setState(() {
      if (isOrigin)
        _isOriginAutocompleteLoading = true;
      else
        _isDestinationAutocompleteLoading = true;
    });
    try {
      final results = await _planner.geocodingService.autocompletePlaces(query);
      if (!mounted) return;
      setState(() {
        if (isOrigin)
          _originSuggestions = results;
        else
          _destinationSuggestions = results;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (isOrigin)
          _originSuggestions = [];
        else
          _destinationSuggestions = [];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        if (isOrigin)
          _isOriginAutocompleteLoading = false;
        else
          _isDestinationAutocompleteLoading = false;
      });
    }
  }

  void _chooseOriginSuggestion(PlaceSuggestion s) => setState(() {
        _selectedOriginSuggestion = s;
        _originController.text = s.name;
        _originSuggestions = [];
      });

  void _chooseDestinationSuggestion(PlaceSuggestion s) => setState(() {
        _selectedDestinationSuggestion = s;
        _destinationController.text = s.name;
        _destinationSuggestions = [];
      });

  // ── Markers ───────────────────────────────────────────────────────────────
  List<Marker> _buildMarkers() {
    final plan = _routePlan;
    if (plan == null || plan.routePoints.isEmpty) return [];

    return [
      _buildMarker(plan.routePoints.first, child: _PulsingDot(color: _kBlue)),
      _buildMarker(plan.routePoints.last,
          child: const _PinMarker(color: Color(0xFFEF4444))),
      ...plan.chargingStops.map((s) => _buildMarker(s.location,
          child: Tooltip(
            message: "${s.name}\n${s.connectionInfo}",
            child: const _ChargingMarker(),
          ))),
    ];
  }

  Marker _buildMarker(LatLng point, {required Widget child}) =>
      Marker(point: point, width: 48, height: 48, child: child);

  // ── Suggestion overlay ────────────────────────────────────────────────────
  Widget _suggestionList({
    required List<PlaceSuggestion> suggestions,
    required bool isLoading,
    required ValueChanged<PlaceSuggestion> onTap,
  }) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: LinearProgressIndicator(
          minHeight: 2,
          color: _kBlue,
          backgroundColor: _kCard,
        ),
      );
    }
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(maxHeight: 180),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: _kBorder),
          itemBuilder: (_, i) {
            final s = suggestions[i];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined,
                  size: 18, color: _kBlueLight),
              title: Text(s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _kTextPri, fontSize: 13)),
              onTap: () => onTap(s),
            );
          },
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final routePoints = _routePlan?.routePoints ?? [];
    final mapCenter =
        routePoints.isNotEmpty ? routePoints.first : _defaultCenter;

    return Scaffold(
      backgroundColor: _kSurface,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Full-screen map ─────────────────────────────────────────────
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mapCenter,
                initialZoom: 12,
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: "com.example.smartroute",
                ),
                if (routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        color: _kBlue,
                        strokeWidth: 5,
                        borderColor: Colors.white.withOpacity(0.3),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                MarkerLayer(markers: _buildMarkers()),
              ],
            ),
          ),

          // ── Top gradient scrim ──────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _kSurface.withOpacity(0.85),
                    _kSurface.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),

          // ── App bar ─────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const Text(
                    "SmartRoute",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  // Location recenter
                  _MapFab(
                    icon: Icons.my_location_outlined,
                    onTap: _tryUseCurrentLocation,
                  ),
                ],
              ),
            ),
          ),

          // ── Zoom controls (right side) ──────────────────────────────────
          Positioned(
            right: 16,
            bottom: 220,
            child: Column(
              children: [
                _MapFab(
                  icon: Icons.add,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 8),
                _MapFab(
                  icon: Icons.remove,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                ),
              ],
            ),
          ),

          // ── Route summary pill ──────────────────────────────────────────
          if (_routePlan != null)
            Positioned(
              bottom: 220,
              left: 16,
              right: 72,
              child: _RouteSummaryPill(plan: _routePlan!),
            ),

          // ── Bottom sheet ────────────────────────────────────────────────
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.38,
            minChildSize: 0.18,
            maxChildSize: 0.72,
            snap: true,
            snapSizes: const [0.18, 0.38, 0.72],
            builder: (context, scrollController) => _BottomSheetPanel(
              scrollController: scrollController,
              originController: _originController,
              destinationController: _destinationController,
              originSuggestions: _originSuggestions,
              destinationSuggestions: _destinationSuggestions,
              isOriginLoading: _isOriginAutocompleteLoading,
              isDestinationLoading: _isDestinationAutocompleteLoading,
              selectedVehicle: _selectedVehicle,
              isLoading: _isLoading,
              error: _error,
              onOriginChanged: _handleOriginChanged,
              onDestinationChanged: _handleDestinationChanged,
              onOriginSuggestionTap: _chooseOriginSuggestion,
              onDestinationSuggestionTap: _chooseDestinationSuggestion,
              onVehicleChanged: (v) {
                if (v != null) setState(() => _selectedVehicle = v);
              },
              onGetDirections: _isLoading ? null : _planRoute,
              suggestionListBuilder: _suggestionList,
              onSwapLocations: () {
                final tmp = _originController.text;
                _originController.text = _destinationController.text;
                _destinationController.text = tmp;
                final tmpSel = _selectedOriginSuggestion;
                _selectedOriginSuggestion = _selectedDestinationSuggestion;
                _selectedDestinationSuggestion = tmpSel;
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Supporting widgets
// ═══════════════════════════════════════════════════════════════════════════

class _MapFab extends StatelessWidget {
  const _MapFab({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _kCard.withOpacity(0.92),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
          ),
          child: Icon(icon, color: _kBlueLight, size: 20),
        ),
      );
}

// ── Route summary pill ──────────────────────────────────────────────────────
class _RouteSummaryPill extends StatelessWidget {
  const _RouteSummaryPill({required this.plan});
  final RoutePlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _kCard.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBlue.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          _PillStat(
            label: "DISTANCE",
            value: "${plan.distanceKm.toStringAsFixed(1)} km",
            color: _kTextPri,
          ),
          _pillDivider(),
          _PillStat(
            label: "ETA",
            value: "${plan.durationMinutes.toStringAsFixed(0)} min",
            color: _kTextPri,
          ),
          _pillDivider(),
          _PillStat(
            label: "STOPS",
            value: "${plan.chargingStops.length} ⚡",
            color: _kGreen,
          ),
        ],
      ),
    );
  }

  Widget _pillDivider() => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: _kBorder,
      );
}

class _PillStat extends StatelessWidget {
  const _PillStat(
      {required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 9, color: _kTextMut, letterSpacing: 0.8)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        ],
      );
}

// ── Bottom sheet panel ──────────────────────────────────────────────────────
class _BottomSheetPanel extends StatelessWidget {
  const _BottomSheetPanel({
    required this.scrollController,
    required this.originController,
    required this.destinationController,
    required this.originSuggestions,
    required this.destinationSuggestions,
    required this.isOriginLoading,
    required this.isDestinationLoading,
    required this.selectedVehicle,
    required this.isLoading,
    required this.error,
    required this.onOriginChanged,
    required this.onDestinationChanged,
    required this.onOriginSuggestionTap,
    required this.onDestinationSuggestionTap,
    required this.onVehicleChanged,
    required this.onGetDirections,
    required this.suggestionListBuilder,
    required this.onSwapLocations,
  });

  final ScrollController scrollController;
  final TextEditingController originController;
  final TextEditingController destinationController;
  final List<PlaceSuggestion> originSuggestions;
  final List<PlaceSuggestion> destinationSuggestions;
  final bool isOriginLoading, isDestinationLoading, isLoading;
  final VehicleProfile selectedVehicle;
  final String? error;
  final ValueChanged<String> onOriginChanged;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<PlaceSuggestion> onOriginSuggestionTap;
  final ValueChanged<PlaceSuggestion> onDestinationSuggestionTap;
  final ValueChanged<VehicleProfile?> onVehicleChanged;
  final VoidCallback? onGetDirections;
  final VoidCallback onSwapLocations;
  final Widget Function({
    required List<PlaceSuggestion> suggestions,
    required bool isLoading,
    required ValueChanged<PlaceSuggestion> onTap,
  }) suggestionListBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: _kBorder),
          left: BorderSide(color: _kBorder),
          right: BorderSide(color: _kBorder),
        ),
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const Text(
                "Plan your route",
                style: TextStyle(
                  color: _kTextPri,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // Origin + swap + destination stacked
              Stack(
                children: [
                  Column(
                    children: [
                      _LocationField(
                        controller: originController,
                        hint: "Your location",
                        icon: Icons.circle,
                        iconColor: _kBlue,
                        onChanged: onOriginChanged,
                        hasFocusBorder: true,
                      ),
                      suggestionListBuilder(
                        suggestions: originSuggestions,
                        isLoading: isOriginLoading,
                        onTap: onOriginSuggestionTap,
                      ),
                      const SizedBox(height: 8),
                      _LocationField(
                        controller: destinationController,
                        hint: "Destination",
                        icon: Icons.location_on,
                        iconColor: const Color(0xFFEF4444),
                        onChanged: onDestinationChanged,
                        hasFocusBorder: false,
                      ),
                      suggestionListBuilder(
                        suggestions: destinationSuggestions,
                        isLoading: isDestinationLoading,
                        onTap: onDestinationSuggestionTap,
                      ),
                    ],
                  ),
                  // Swap button
                  Positioned(
                    right: 0,
                    top: 32,
                    child: GestureDetector(
                      onTap: onSwapLocations,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _kCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kBorder),
                        ),
                        child: const Icon(Icons.swap_vert,
                            color: _kBlueLight, size: 18),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Vehicle selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<VehicleProfile>(
                    value: selectedVehicle,
                    dropdownColor: _kCard,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down,
                        color: _kBlueLight, size: 20),
                    items: vehicleProfiles
                        .map(
                          (v) => DropdownMenuItem<VehicleProfile>(
                            value: v,
                            child: Row(
                              children: [
                                const Icon(Icons.electric_car,
                                    color: _kBlue, size: 18),
                                const SizedBox(width: 8),
                                Text(v.label,
                                    style: const TextStyle(
                                        color: _kTextPri, fontSize: 14)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: onVehicleChanged,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Error
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B1515),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFEF4444).withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Color(0xFFEF4444), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(error!,
                              style: const TextStyle(
                                  color: Color(0xFFFCA5A5), fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ),

              // Get Directions button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: onGetDirections,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kBlue,
                    disabledBackgroundColor: _kBlue.withOpacity(0.4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.alt_route, size: 20),
                            SizedBox(width: 8),
                            Text("Get Directions",
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Location text field ─────────────────────────────────────────────────────
class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.iconColor,
    required this.onChanged,
    required this.hasFocusBorder,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final ValueChanged<String> onChanged;
  final bool hasFocusBorder;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: _kTextPri, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _kTextMut, fontSize: 14),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 40, minHeight: 0),
          filled: true,
          fillColor: _kCard,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: hasFocusBorder ? _kBlue : const Color(0xFFEF4444),
              width: 1.5,
            ),
          ),
        ),
      );
}

// ── Custom markers ──────────────────────────────────────────────────────────
class _PulsingDot extends StatelessWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      );
}

class _PinMarker extends StatelessWidget {
  const _PinMarker({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Icon(
        Icons.location_on,
        color: color,
        size: 40,
        shadows: [
          Shadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 6,
              offset: const Offset(0, 3)),
        ],
      );
}

class _ChargingMarker extends StatelessWidget {
  const _ChargingMarker();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _kGreen,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        child: const Icon(Icons.ev_station, color: Colors.white, size: 22),
      );
}
