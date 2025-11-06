import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'price_service.dart';
import 'storage_service.dart';
import 'database_service.dart';

/// Сервис для фоновой проверки цен
class BackgroundService {
  static const String taskName = 'checkPriceTask';
  static const Duration checkInterval = Duration(minutes: 15);

  /// Инициализация фоновых задач
  static Future<void> initialize() async {
    print('[BackgroundService] Инициализация Workmanager...');

    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true, // Включаем логирование для отладки
    );

    print('[BackgroundService] Workmanager инициализирован');
  }

  /// Регистрирует периодическую задачу проверки цен
  static Future<void> registerPeriodicTask() async {
    print('[BackgroundService] Регистрация периодической задачи...');

    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: checkInterval,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

    print('[BackgroundService] Периодическая задача зарегистрирована (каждые 15 минут)');
  }

  /// Отменяет периодическую задачу
  static Future<void> cancelTask() async {
    print('[BackgroundService] Отмена задачи...');
    await Workmanager().cancelByUniqueName(taskName);
    print('[BackgroundService] Задача отменена');
  }
}

/// Callback функция для фоновых задач (должна быть top-level)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('[BackgroundService] Выполняется фоновая задача: $task');

    try {
      // Инициализируем сервисы
      final storageService = StorageService();
      final priceService = PriceService();

      // Инициализируем локальные уведомления для фонового режима
      final FlutterLocalNotificationsPlugin localNotifications =
          FlutterLocalNotificationsPlugin();
      
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings =
          InitializationSettings(android: androidSettings);
      
      await localNotifications.initialize(initSettings);

      // Инициализируем DatabaseService для работы с алертами
      final db = DatabaseService();
      await db.initDatabase();

      // Загружаем все активные алерты из БД
      final activeAlertsRows = await db.getActiveAlerts();

      if (activeAlertsRows.isEmpty) {
        print('[BackgroundService] Нет активных алертов, задача пропущена');
        return Future.value(true);
      }

      print('[BackgroundService] Найдено активных алертов: ${activeAlertsRows.length}');

      // Группируем по тикерам для оптимизации
      final tickers = activeAlertsRows.map((r) => r['ticker'] as String).toSet();
      int notificationId = 0;

      for (final ticker in tickers) {
        print('[BackgroundService] Проверка цены для $ticker...');

        final currentPrice = await priceService.getPrice(ticker);
        if (currentPrice == null) {
          print('[BackgroundService] Не удалось получить цену для $ticker');
          continue;
        }

        print('[BackgroundService] Текущая цена $ticker: \$$currentPrice');

        // Сохраняем последнюю проверенную цену
        await storageService.saveLastPrice(currentPrice);

        // Проверяем все алерты для этого тикера
        final tickerAlerts = activeAlertsRows.where((r) => r['ticker'] == ticker);
        for (final alertRow in tickerAlerts) {
          final direction = alertRow['direction'] as String;
          final thresholdPrice = (alertRow['threshold_price'] as num).toDouble();
          final alertId = alertRow['id'] as int;

          final shouldTrigger = (direction == 'UP' && currentPrice >= thresholdPrice) ||
              (direction == 'DOWN' && currentPrice <= thresholdPrice);

          if (shouldTrigger) {
            print('[BackgroundService] ✅ Пороговая цена достигнута для $ticker @ \$$thresholdPrice!');

            // Отправляем локальное уведомление
            const AndroidNotificationDetails androidDetails =
                AndroidNotificationDetails(
              'price_alerts',
              'Уведомления о ценах',
              channelDescription: 'Уведомления о достижении пороговой цены',
              importance: Importance.high,
              priority: Priority.high,
              showWhen: true,
            );

            const NotificationDetails notificationDetails =
                NotificationDetails(android: androidDetails);

            final arrow = direction == 'UP' ? '↑' : '↓';
            final verb = direction == 'UP' ? 'достиг' : 'упал до';

            await localNotifications.show(
              notificationId++,
              '🎯 Умный алерт',
              '$ticker $verb \$${thresholdPrice.toStringAsFixed(2)} $arrow (текущая: \$${currentPrice.toStringAsFixed(2)})',
              notificationDetails,
            );

            print('[BackgroundService] Уведомление отправлено');

            // Деактивируем алерт в БД
            await db.deactivateAlert(alertId);

            // Логируем в AlertsLog
            final assetId = await db.getAssetIdByTicker(ticker);
            await db.logAlert(
              assetId: assetId,
              ticker: ticker,
              price: currentPrice,
              targetPrice: thresholdPrice,
              triggeredAt: DateTime.now().millisecondsSinceEpoch,
              direction: direction,
            );
          }
        }
      }

      return Future.value(true);
    } catch (e) {
      print('[BackgroundService] Ошибка при выполнении задачи: $e');
      return Future.value(false);
    }
  });
}
