class AppConfig {
  static const String orsApiKey = String.fromEnvironment("ORS_API_KEY");
  static const String userAgent = String.fromEnvironment(
    "SMARTROUTE_USER_AGENT",
    defaultValue: "SmartRoute/1.0 (contact: your-email@example.com)",
  );

  static bool get isConfigured => orsApiKey.isNotEmpty;
}
