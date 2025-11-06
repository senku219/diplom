import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppInfo {
  static const String appName = 'CryptoWatcher';
  static const String developerName = 'hsiddq';
  static const String telegramHandle = 'hsiddq';
  static const String githubRepo = 'https://github.com/senku219/diplom.git';
  static const String license = 'MIT License';

  static Future<String> getVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
    }

  static Future<void> openTelegram() async {
    final uri = Uri.parse('https://t.me/$telegramHandle');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> openGithub() async {
    final uri = Uri.parse(githubRepo);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> rateApp() async {
    // Заглушка: можно открыть маркетплейс при наличии ID пакета
    final uri = Uri.parse('https://example.com/rate');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}


