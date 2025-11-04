import 'package:flutter/foundation.dart';
import '../models/alert.dart';
import '../services/storage_service.dart';
import '../services/price_service.dart';
import '../services/notification_service.dart';

/// Провайдер для управления состоянием алерта
class AlertProvider with ChangeNotifier {
  final StorageService _storageService = StorageService();
  final PriceService _priceService = PriceService();
  final NotificationService _notificationService = NotificationService();

  Alert? _alert;
  double? _lastPrice;
  bool _isLoading = false;

  Alert? get alert => _alert;
  double? get lastPrice => _lastPrice;
  bool get isLoading => _isLoading;

  /// Загружает сохраненный алерт из хранилища
  Future<void> loadAlert() async {
    _isLoading = true;
    notifyListeners();

    try {
      _alert = await _storageService.loadAlert();
      _lastPrice = await _storageService.getLastPrice();
      
      print('[AlertProvider] Алерт загружен: $_alert');
      print('[AlertProvider] Последняя цена: $_lastPrice');
    } catch (e) {
      print('[AlertProvider] Ошибка при загрузке алерта: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Сохраняет алерт в хранилище
  Future<void> saveAlert(Alert alert) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _storageService.saveAlert(alert);
      _alert = alert;
      
      print('[AlertProvider] Алерт сохранен: $alert');
    } catch (e) {
      print('[AlertProvider] Ошибка при сохранении алерта: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Проверяет текущую цену криптовалюты
  Future<void> checkPrice() async {
    if (_alert == null) {
      print('[AlertProvider] Алерт не установлен, проверка пропущена');
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      print('[AlertProvider] Проверка цены для ${_alert!.ticker}...');
      
      final price = await _priceService.getPrice(_alert!.ticker);

      if (price != null) {
        _lastPrice = price;
        await _storageService.saveLastPrice(price);

        // Проверяем, достигнута ли пороговая цена
        if (_priceService.isThresholdReached(price, _alert!.thresholdPrice)) {
          print('[AlertProvider] ✅ Пороговая цена достигнута!');
          
          // Отправляем уведомление
          await _notificationService.showNotification(
            '🎯 Цена достигнута!',
            '${_alert!.ticker} достиг цены \$${price.toStringAsFixed(2)} (порог: \$${_alert!.thresholdPrice.toStringAsFixed(2)})',
          );
        }

        print('[AlertProvider] Текущая цена: \$$price');
      } else {
        print('[AlertProvider] Не удалось получить цену');
      }
    } catch (e) {
      print('[AlertProvider] Ошибка при проверке цены: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
