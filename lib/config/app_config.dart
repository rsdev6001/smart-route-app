import "package:flutter_dotenv/flutter_dotenv.dart";

class AppConfig {
  static String get orsApiKey =>
      dotenv.env["ORS_API_KEY"] ?? const String.fromEnvironment("ORS_API_KEY");

  static String get userAgent =>
      dotenv.env["SMARTROUTE_USER_AGENT"] ??
      const String.fromEnvironment(
        "SMARTROUTE_USER_AGENT",
        defaultValue: "SmartRoute/1.0 (contact: your-email@example.com)",
      );

  static bool get isConfigured => orsApiKey.trim().isNotEmpty;
}
