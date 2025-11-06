import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'providers/alert_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart' as notification_service;
import 'services/ticker_sync_service.dart';
import 'services/database_service.dart';
import 'screens/portfolio_screen.dart';
import 'screens/history_screen.dart';

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

  // Инициализация локальной БД
  print('[Main] Инициализация DatabaseService...');
  final dbService = DatabaseService();
  final db = await dbService.database;
  print('[Main] DatabaseService инициализирован');

  // Проверяем необходимость первичной синхронизации тикеров
  if (await TickerSyncService.needsUpdate(db)) {
    print('[Main] Первый запуск — загружаем список криптовалют...');
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: SyncSplashScreen(databaseService: dbService),
    ));
  } else {
    // Инициализация фоновых задач и обычный запуск
    print('[Main] Инициализация BackgroundService...');
    await BackgroundService.initialize();
    print('[Main] BackgroundService инициализирован');
    runApp(const MyApp());
  }
}

class SyncSplashScreen extends StatefulWidget {
  final DatabaseService databaseService;
  const SyncSplashScreen({super.key, required this.databaseService});

  @override
  State<SyncSplashScreen> createState() => _SyncSplashScreenState();
}

class _SyncSplashScreenState extends State<SyncSplashScreen> {
  String _status = 'Подготовка...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _runSync();
  }

  Future<void> _runSync() async {
    try {
      setState(() => _status = 'Загрузка списка криптовалют (топ-1000)...');
      final db = await widget.databaseService.database;
      await TickerSyncService.syncTop1000Coins(db);
      print('[SyncSplash] Синхронизация завершена');

      // После синхронизации стартуем фоновые задачи и приложение
      await BackgroundService.initialize();
      if (!mounted) return;
      runApp(const MyApp());
    } catch (e) {
      setState(() => _error = 'Ошибка синхронизации: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
        routes: {
          '/portfolio': (_) => const PortfolioScreen(),
          '/history': (_) => const HistoryScreen(),
        },
      ),
    );
  }
}
