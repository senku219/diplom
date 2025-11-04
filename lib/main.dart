import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'providers/alert_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart' as notification_service;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация Firebase
  print('[Main] Инициализация Firebase...');
  await Firebase.initializeApp();
  print('[Main] Firebase инициализирован');

  // Настройка обработчика фоновых уведомлений
  FirebaseMessaging.onBackgroundMessage(
    notification_service.firebaseMessagingBackgroundHandler,
  );

  // Инициализация сервиса уведомлений
  print('[Main] Инициализация NotificationService...');
  await NotificationService().initialize();
  print('[Main] NotificationService инициализирован');

  // Инициализация фоновых задач
  print('[Main] Инициализация BackgroundService...');
  await BackgroundService.initialize();
  print('[Main] BackgroundService инициализирован');

  // Запуск приложения
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AlertProvider(),
      child: MaterialApp(
        title: 'CryptoWatcher',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
