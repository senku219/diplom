import 'package:shared_preferences/shared_preferences.dart';
import '../models/alert.dart';

/// Сервис для локального хранения настроек алерта
class StorageService {
  // Ключи для сохранения данных
  static const String _keyTicker = 'alert_ticker';
  static const String _keyThresholdPrice = 'alert_threshold_price';
  static const String _keyLastPrice = 'last_checked_price';
  static const String _keyDirection = 'alert_direction';
  static const String _keyInitialPrice = 'alert_initial_price';
  static const String _keyIsActive = 'alert_is_active';

  /// Сохраняет настройки алерта
  Future<void> saveAlert(Alert alert) async {
    try {
      print('[StorageService] Сохранение алерта: ${alert.ticker} @ \$${alert.thresholdPrice}');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTicker, alert.ticker.toUpperCase());
      await prefs.setDouble(_keyThresholdPrice, alert.thresholdPrice);
      await prefs.setString(_keyDirection, alert.direction);
      await prefs.setDouble(_keyInitialPrice, alert.initialPrice);
      await prefs.setBool(_keyIsActive, alert.isActive);
      
      print('[StorageService] Алерт успешно сохранен');
    } catch (e) {
      print('[StorageService] Ошибка при сохранении: $e');
    }
  }

  /// Загружает сохраненный алерт
  /// Возвращает null, если алерт не найден
  Future<Alert?> loadAlert() async {
    try {
      print('[StorageService] Загрузка алерта...');
      
      final prefs = await SharedPreferences.getInstance();
      final ticker = prefs.getString(_keyTicker);
      final thresholdPrice = prefs.getDouble(_keyThresholdPrice);
      final direction = prefs.getString(_keyDirection);
      final initialPrice = prefs.getDouble(_keyInitialPrice);
      final isActive = prefs.getBool(_keyIsActive) ?? true;

      if (ticker != null && thresholdPrice != null && direction != null && initialPrice != null) {
        final alert = Alert(
          ticker: ticker,
          thresholdPrice: thresholdPrice,
          direction: direction,
          initialPrice: initialPrice,
          isActive: isActive,
        );
        print('[StorageService] Алерт загружен: ${alert.ticker} @ \$${alert.thresholdPrice}');
        return alert;
      }

      print('[StorageService] Алерт не найден');
      return null;
    } catch (e) {
      print('[StorageService] Ошибка при загрузке: $e');
      return null;
    }
  }

  /// Сохраняет последнюю проверенную цену
  Future<void> saveLastPrice(double price) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyLastPrice, price);
      print('[StorageService] Последняя цена сохранена: \$$price');
    } catch (e) {
      print('[StorageService] Ошибка при сохранении последней цены: $e');
    }
  }

  /// Загружает последнюю проверенную цену
  Future<double?> getLastPrice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final price = prefs.getDouble(_keyLastPrice);
      return price;
    } catch (e) {
      print('[StorageService] Ошибка при загрузке последней цены: $e');
      return null;
    }
  }

  /// Очищает все сохраненные данные
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyTicker);
      await prefs.remove(_keyThresholdPrice);
      await prefs.remove(_keyLastPrice);
      await prefs.remove(_keyDirection);
      await prefs.remove(_keyInitialPrice);
      await prefs.remove(_keyIsActive);
      print('[StorageService] Все данные очищены');
    } catch (e) {
      print('[StorageService] Ошибка при очистке: $e');
    }
  }
}
