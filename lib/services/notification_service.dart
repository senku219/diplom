import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Сервис для отправки push-уведомлений
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Инициализация сервиса уведомлений
  Future<void> initialize() async {
    if (_initialized) {
      print('[NotificationService] Уже инициализирован');
      return;
    }

    try {
      print('[NotificationService] Инициализация...');

      // Запрос разрешений на уведомления
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      print('[NotificationService] Статус разрешений: ${settings.authorizationStatus}');

      // Инициализация локальных уведомлений
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initSettings =
          InitializationSettings(android: androidSettings);

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Обработка уведомлений, когда приложение в foreground
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Обработка уведомлений при нажатии (когда приложение в background)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessageOpened);

      _initialized = true;
      print('[NotificationService] Инициализация завершена');
    } catch (e) {
      print('[NotificationService] Ошибка при инициализации: $e');
    }
  }

  /// Отправляет локальное уведомление
  /// 
  /// [title] - заголовок уведомления
  /// [body] - текст уведомления
  Future<void> showNotification(String title, String body) async {
    try {
      print('[NotificationService] Отправка уведомления: $title - $body');

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'price_alerts', // канал уведомлений
        'Уведомления о ценах',
        channelDescription: 'Уведомления о достижении пороговой цены',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const NotificationDetails notificationDetails =
          NotificationDetails(android: androidDetails);

      await _localNotifications.show(
        0, // ID уведомления
        title,
        body,
        notificationDetails,
      );

      print('[NotificationService] Уведомление отправлено');
    } catch (e) {
      print('[NotificationService] Ошибка при отправке уведомления: $e');
    }
  }

  /// Обработчик нажатия на уведомление
  void _onNotificationTapped(NotificationResponse response) {
    print('[NotificationService] Уведомление нажато: ${response.payload}');
  }

  /// Обработка уведомлений в foreground
  void _handleForegroundMessage(RemoteMessage message) {
    print('[NotificationService] Сообщение в foreground: ${message.notification?.title}');
    
    if (message.notification != null) {
      showNotification(
        message.notification!.title ?? 'Уведомление',
        message.notification!.body ?? '',
      );
    }
  }

  /// Обработка нажатия на уведомление в background
  void _handleBackgroundMessageOpened(RemoteMessage message) {
    print('[NotificationService] Сообщение открыто из background: ${message.notification?.title}');
  }

  /// Получает FCM токен (для отправки уведомлений через сервер, если нужно)
  Future<String?> getToken() async {
    try {
      final token = await _firebaseMessaging.getToken();
      print('[NotificationService] FCM Token: $token');
      return token;
    } catch (e) {
      print('[NotificationService] Ошибка при получении токена: $e');
      return null;
    }
  }
}

/// Обработчик уведомлений в background (должен быть top-level функцией)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('[BackgroundHandler] Получено сообщение: ${message.messageId}');
  print('[BackgroundHandler] Заголовок: ${message.notification?.title}');
  print('[BackgroundHandler] Текст: ${message.notification?.body}');
}
