import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'price_service.dart';
import 'storage_service.dart';

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

      // Загружаем сохраненный алерт
      final alert = await storageService.loadAlert();

      if (alert == null) {
        print('[BackgroundService] Алерт не найден, задача пропущена');
        return Future.value(true);
      }

      print('[BackgroundService] Проверка цены для ${alert.ticker}...');

      // Получаем текущую цену
      final currentPrice = await priceService.getPrice(alert.ticker);

      if (currentPrice == null) {
        print('[BackgroundService] Не удалось получить цену');
        return Future.value(true);
      }

      print('[BackgroundService] Текущая цена ${alert.ticker}: \$$currentPrice');
      print('[BackgroundService] Пороговая цена: \$${alert.thresholdPrice}');

      // Сохраняем последнюю проверенную цену
      await storageService.saveLastPrice(currentPrice);

      // Проверяем, достигнута ли пороговая цена
      if (priceService.isThresholdReached(currentPrice, alert.thresholdPrice)) {
        print('[BackgroundService] ✅ Пороговая цена достигнута!');

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

        await localNotifications.show(
          0,
          '🎯 Цена достигнута!',
          '${alert.ticker} достиг цены \$${currentPrice.toStringAsFixed(2)} (порог: \$${alert.thresholdPrice.toStringAsFixed(2)})',
          notificationDetails,
        );

        print('[BackgroundService] Уведомление отправлено');
      } else {
        print('[BackgroundService] Пороговая цена еще не достигнута');
      }

      return Future.value(true);
    } catch (e) {
      print('[BackgroundService] Ошибка при выполнении задачи: $e');
      return Future.value(false);
    }
  });
}
