import 'package:flutter/foundation.dart';
import '../models/alert.dart';
import '../services/storage_service.dart';
import '../services/price_service.dart';
import '../services/notification_service.dart';
import '../services/database_service.dart';

/// Провайдер для управления состоянием алертов
class AlertProvider with ChangeNotifier {
  final StorageService _storageService = StorageService();
  final PriceService _priceService = PriceService();
  final NotificationService _notificationService = NotificationService();
  final DatabaseService _db = DatabaseService();

  List<Alert> _alerts = [];
  double? _lastPrice;
  bool _isLoading = false;

  List<Alert> get alerts => _alerts;
  List<Alert> get activeAlerts => _alerts.where((a) => a.isActive).toList();
  double? get lastPrice => _lastPrice;
  bool get isLoading => _isLoading;

  /// Загружает все алерты из БД
  Future<void> loadAlerts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final rows = await _db.getAllAlerts();
      _alerts = rows.map((row) {
        return Alert(
          id: row['id'] as int,
          ticker: row['ticker'] as String,
          thresholdPrice: (row['threshold_price'] as num).toDouble(),
          direction: row['direction'] as String,
          initialPrice: (row['initial_price'] as num).toDouble(),
          isActive: (row['is_active'] as int) == 1,
        );
      }).toList();
      
      print('[AlertProvider] Загружено алертов: ${_alerts.length}');
    } catch (e) {
      print('[AlertProvider] Ошибка при загрузке алертов: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Загружает первый активный алерт (для обратной совместимости)
  Alert? get alert => activeAlerts.isNotEmpty ? activeAlerts.first : null;

  /// Сохраняет алерт в БД и возвращает обогащённую версию (с direction/initialPrice)
  Future<Alert> saveAlert(Alert alert) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Определяем направление и начальную цену
      final current = await _priceService.getPrice(alert.ticker);
      if (current == null) {
        throw Exception('Не удалось получить текущую цену для ${alert.ticker}');
      }
      if ((current - alert.thresholdPrice).abs() < 1e-9) {
        throw Exception('Текущая цена равна целевой. Выберите другое значение.');
      }
      final direction = current < alert.thresholdPrice ? 'UP' : 'DOWN';

      // Сохраняем в БД
      await _db.addAlert(
        ticker: alert.ticker.toUpperCase(),
        thresholdPrice: alert.thresholdPrice,
        direction: direction,
        initialPrice: current,
      );
      
      // Перезагружаем список
      await loadAlerts();
      
      print('[AlertProvider] Алерт сохранен в БД');
      return Alert(
        id: null,
        ticker: alert.ticker.toUpperCase(),
        thresholdPrice: alert.thresholdPrice,
        direction: direction,
        initialPrice: current,
        isActive: true,
      );
    } catch (e) {
      print('[AlertProvider] Ошибка при сохранении алерта: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Удаляет алерт
  Future<void> deleteAlert(int alertId) async {
    await _db.deleteAlert(alertId);
    await loadAlerts();
  }

  /// Проверяет все активные алерты
  Future<void> checkPrice() async {
    final active = activeAlerts;
    if (active.isEmpty) {
      print('[AlertProvider] Нет активных алертов');
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Группируем алерты по тикерам для оптимизации запросов
      final tickers = active.map((a) => a.ticker).toSet();
      
      for (final ticker in tickers) {
        print('[AlertProvider] Проверка цены для $ticker...');
        
        final price = await _priceService.getPrice(ticker);
        if (price == null) {
          print('[AlertProvider] Не удалось получить цену для $ticker');
          continue;
        }

        _lastPrice = price;
        await _storageService.saveLastPrice(price);

        // Логируем факт проверки цены в PriceHistory для актива, если он существует
        final assetId = await _db.getAssetIdByTicker(ticker);
        if (assetId != null) {
          await _db.addPriceHistory(assetId: assetId, price: price, timestamp: DateTime.now().millisecondsSinceEpoch);
        }

        // Проверяем все алерты для этого тикера
        final tickerAlerts = active.where((a) => a.ticker == ticker);
        for (final alert in tickerAlerts) {
          final shouldTrigger = (alert.direction == 'UP' && price >= alert.thresholdPrice) ||
              (alert.direction == 'DOWN' && price <= alert.thresholdPrice);
          
          if (shouldTrigger) {
            print('[AlertProvider] ✅ Пороговая цена достигнута для ${alert.ticker} @ \$${alert.thresholdPrice}!');
            
            // Отправляем уведомление
            final arrow = alert.direction == 'UP' ? '↑' : '↓';
            final verb = alert.direction == 'UP' ? 'достиг' : 'упал до';
            await _notificationService.showNotification(
              '🎯 Умный алерт',
              '${alert.ticker} $verb \$${alert.thresholdPrice.toStringAsFixed(2)} $arrow (текущая: \$${price.toStringAsFixed(2)})',
            );

            // Логируем алерт в БД
            await _db.logAlert(
              assetId: assetId,
              ticker: alert.ticker,
              price: price,
              targetPrice: alert.thresholdPrice,
              triggeredAt: DateTime.now().millisecondsSinceEpoch,
              direction: alert.direction,
            );

            // Деактивируем алерт в БД
            if (alert.id != null) {
              await _db.deactivateAlert(alert.id!);
            }
          }
        }
      }

      // Перезагружаем алерты после проверки
      await loadAlerts();
      
      print('[AlertProvider] Проверка завершена');
    } catch (e) {
      print('[AlertProvider] Ошибка при проверке цены: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
