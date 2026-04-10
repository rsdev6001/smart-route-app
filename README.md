# SmartRoute (Flutter Android App)

SmartRoute helps EV owners find the best route to a destination with charging stops available along the way.

## API Strategy (Best Approach)

- **Routing engine:** [OpenRouteService](https://openrouteservice.org/)  
  - Returns route geometry, distance, and ETA.
  - Free tier available and easy Flutter integration.
- **Charging station data:** [OpenChargeMap](https://openchargemap.org/site/develop/api)  
  - Open EV charging POI dataset.
  - Used to discover stations near route segments.
- **Geocoding:** [Nominatim (OpenStreetMap)](https://nominatim.org/release-docs/develop/api/Search/)  
  - Converts user-entered place names into coordinates.
- **Map rendering:** OpenStreetMap tiles via `flutter_map`  
  - No lock-in to proprietary SDKs.

## How EV Routing Works Here

1. Geocode source and destination.
2. Fetch route line + summary from OpenRouteService.
3. Compute safe driving leg based on selected vehicle range (`80%` usable range).
4. Sample points along the route, fetch nearby chargers from OpenChargeMap.
5. Project chargers onto route and greedily pick stop points so every leg stays within range.
6. Render route polyline + start/end + charging markers on map.

## Project Setup

This folder was initialized with app source files directly. If Flutter template files are missing on your machine, run:

```bash
flutter create .
```

Then keep `lib/`, `pubspec.yaml`, and `android/app/src/main/AndroidManifest.xml` from this project.

## Run

1. Install Flutter SDK.
2. Create an OpenRouteService API key.
3. Install dependencies:

```bash
flutter pub get
```

4. Run Android build:

```bash
flutter run --dart-define=ORS_API_KEY=your_openrouteservice_key --dart-define=SMARTROUTE_USER_AGENT="SmartRoute/1.0 (contact:you@example.com)"
```

## Key Files

- `lib/main.dart` - UI + map + user flow.
- `lib/services/ev_route_planner.dart` - EV-aware charger stop planner.
- `lib/services/routing_service.dart` - OpenRouteService client.
- `lib/services/charging_service.dart` - OpenChargeMap client.
- `lib/services/geocoding_service.dart` - Nominatim geocoding.

## Next Improvements

- Charger compatibility filter (CCS/Type2/CHAdeMO) based on user vehicle connector type.
- Charger availability status (if provider supports real-time status).
- Multi-alternative routes and scoring (time vs charging convenience).
- Offline caching of recent routes/stations.
