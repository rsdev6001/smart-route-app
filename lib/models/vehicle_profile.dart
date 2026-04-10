class VehicleProfile {
  const VehicleProfile({
    required this.label,
    required this.rangeKm,
  });

  final String label;
  final double rangeKm;

  @override
  String toString() => label;
}

const vehicleProfiles = <VehicleProfile>[
  VehicleProfile(label: "Standard Car (Toyota Prius)", rangeKm: 700),
  VehicleProfile(label: "EV/Hybrid", rangeKm: 320),
  VehicleProfile(label: "Motorbike", rangeKm: 280),
  VehicleProfile(label: "Bicycle", rangeKm: 70),
  VehicleProfile(label: "Public Transport (Bus/Tube)", rangeKm: 1000),
  VehicleProfile(label: "Walk", rangeKm: 20),
];
