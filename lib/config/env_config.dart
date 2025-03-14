class EnvConfig {
  static const String ENV = String.fromEnvironment('ENV', defaultValue: 'dev');
  static bool get isDev => ENV == 'dev';
  static bool get isProd => ENV == 'prod';
} 