import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alert.dart';
import '../services/storage_service.dart';
import '../services/price_service.dart';
import '../services/background_service.dart';
import '../providers/alert_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'portfolio_screen.dart';
import 'history_screen.dart';
import 'about_screen.dart';
import '../services/ticker_sync_service.dart';
import '../services/database_service.dart';

/// Главный экран приложения
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _tickerController = TextEditingController();
  final _priceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  int _currentIndex = 0;
  bool _initializedIndex = false;
  final PriceService _priceService = PriceService();
  Map<String, double> _alertPrices = {};
  bool _pricesLoading = false;
  Set<String> _lastTickers = <String>{};
  
  Future<bool> _checkIfTickerInDatabase(String ticker) async {
    final db = await DatabaseService().database;
    final res = await db.query(
      'Tickers',
      where: 'ticker = ?',
      whereArgs: [ticker.toUpperCase()],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restoreSelectedTab();
      await _maybeShowAboutOnFirstRun();
      await _loadSavedAlert();
      await _loadAlertPrices(force: true);
    });
  }

  Future<void> _loadAlertPrices({bool force = false}) async {
    final provider = Provider.of<AlertProvider>(context, listen: false);
    final tickers = provider.activeAlerts.map((a) => a.ticker.toUpperCase()).toSet().toList();
    if (tickers.isEmpty) {
      setState(() => _alertPrices = {});
      return;
    }
    // Если состав тикеров не изменился и не принудительно — не дергаем API
    final currentSet = tickers.toSet();
    if (!force && currentSet.length == _lastTickers.length && currentSet.containsAll(_lastTickers)) {
      return;
    }
    _lastTickers = currentSet;
    setState(() => _pricesLoading = true);
    try {
      final prices = await _priceService.getMultiplePrices(tickers);
      if (mounted) {
        setState(() => _alertPrices = prices);
      }
    } finally {
      if (mounted) setState(() => _pricesLoading = false);
    }
  }
  Future<void> _restoreSelectedTab() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentIndex = prefs.getInt('home_selected_tab') ?? 0;
      _initializedIndex = true;
    });
  }

  Future<void> _saveSelectedTab(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('home_selected_tab', index);
  }

  Future<void> _maybeShowAboutOnFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('about_seen') ?? false;
    if (!seen) {
      await prefs.setBool('about_seen', true);
      if (mounted) {
        setState(() {
          _currentIndex = 3; // О проекте
        });
      }
    }
  }


  /// Загружает сохраненные алерты при открытии экрана
  Future<void> _loadSavedAlert() async {
    final provider = Provider.of<AlertProvider>(context, listen: false);
    await provider.loadAlerts();
  }

  /// Сохраняет алерт и запускает фоновую проверку
  Future<void> _saveAlert() async {
    // Ручная валидация, так как поле тикера теперь кастомное
    final rawTicker = _tickerController.text.trim();
    if (rawTicker.isEmpty || !RegExp(r'^[A-Za-z0-9]{1,15}$').hasMatch(rawTicker)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите корректный тикер (латиница/цифры).')),
        );
      }
      return;
    }
    if (_priceController.text.trim().isEmpty || double.tryParse(_priceController.text.trim()) == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите корректную пороговую цену.')),
        );
      }
      return;
    }

    try {
      final ticker = rawTicker.toUpperCase();
      final thresholdPrice = double.parse(_priceController.text.trim());

      final alert = Alert(
        ticker: ticker,
        thresholdPrice: thresholdPrice,
        direction: 'UP', // временно, будет пересчитано в saveAlert
        initialPrice: 0,
        isActive: true,
      );

      final provider = Provider.of<AlertProvider>(context, listen: false);
      final savedAlert = await provider.saveAlert(alert);
      // После сохранения алерта сразу подгружаем цены (исправляет зависание на лоадере)
      await _loadAlertPrices(force: true);

      // Очищаем поля формы
      _tickerController.clear();
      _priceController.clear();

      // Регистрируем фоновую задачу
      await BackgroundService.registerPeriodicTask();

      // Показываем сообщение об успехе с направлением
      if (mounted) {
        final dirText = savedAlert.direction == 'UP' ? 'поднимется выше' : 'упадет ниже';
        final msg = 'Уведомлю, когда ${savedAlert.ticker} $dirText ${savedAlert.thresholdPrice.toStringAsFixed(2)}\$';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Обновляем цену сразу после сохранения
      await provider.checkPrice();
    } catch (e) {
      print('[HomeScreen] Ошибка при сохранении: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Проверяет цену вручную
  Future<void> _checkPriceManually() async {
    final provider = Provider.of<AlertProvider>(context, listen: false);
    await provider.checkPrice();
  }

  @override
  void dispose() {
    _tickerController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      KeyedSubtree(key: const ValueKey('alerts'), child: _buildAlertsTab()),
      const KeyedSubtree(key: ValueKey('portfolio'), child: PortfolioScreen()),
      const KeyedSubtree(key: ValueKey('history'), child: HistoryScreen()),
      const KeyedSubtree(key: ValueKey('about'), child: AboutScreen()),
    ];

    if (!_initializedIndex) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
        child: pages[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        height: 70,
        elevation: 8,
        onDestinationSelected: (i) async {
          setState(() => _currentIndex = i);
          await _saveSelectedTab(i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.notifications_active_outlined), selectedIcon: Icon(Icons.notifications_active), label: 'Алерты'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Активы'),
          NavigationDestination(icon: Icon(Icons.history), label: 'История'),
          NavigationDestination(icon: Icon(Icons.info_outline), selectedIcon: Icon(Icons.info), label: 'О проекте'),
        ],
      ),
    );
  }

  Widget _buildAlertsTab() {
    return Consumer<AlertProvider>(
        builder: (context, provider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  
                  // Заголовок
                  const Text(
                    'Настройка уведомления о цене',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 40),

                  // Поле ввода тикера с автокомплитом
                  Autocomplete<Map<String, dynamic>>(
                    displayStringForOption: (o) => '${o['ticker']} - ${o['name']}',
                    optionsBuilder: (TextEditingValue tev) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      // Игнорируем внутренний controller Autocomplete и используем общий _tickerController,
                      // чтобы _saveAlert всегда читал актуальное значение
                      return TextField(
                        controller: _tickerController,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Тикер криптовалюты',
                          hintText: 'Например: BTC, ETH, SOL',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _tickerController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _tickerController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (value) async {
                          // подгружаем подсказки из БД (и лениво из API)
                          final db = await DatabaseService().database;
                          final list = await TickerSyncService.searchTickers(db, value);
                          // Хак: пересоздаём Autocomplete с новыми options через setState+key
                          setState(() {
                            // ничего, перерисуем и optionsViewBuilder увидит новые данные
                          });
                        },
                        onSubmitted: (_) => onFieldSubmitted(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      // Пере-запрос подсказок в момент показа
                      final text = _tickerController.text;
                      return FutureBuilder<List<Map<String, dynamic>>>(
                        future: () async {
                          if (text.isEmpty) return <Map<String, dynamic>>[];
                          final db = await DatabaseService().database;
                          return await TickerSyncService.searchTickers(db, text);
                        }(),
                        builder: (context, snapshot) {
                          final items = snapshot.data ?? [];
                          if (items.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width - 32,
                                height: 200,
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  itemCount: items.length,
                                  itemBuilder: (ctx, i) {
                                    final option = items[i];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                        child: Text(option['ticker'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                      title: Text(option['ticker'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text(option['name'], overflow: TextOverflow.ellipsis),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    onSelected: (selection) async {
                      _tickerController.text = (selection['ticker'] as String?)?.toUpperCase() ?? '';
                      setState(() {});
                      FocusScope.of(context).unfocus();
                    },
                  ),

                  const SizedBox(height: 8),

                  // Индикация: из топ-1000 или делаем поиск
                  if (_tickerController.text.isNotEmpty)
                    FutureBuilder<bool>(
                      future: _checkIfTickerInDatabase(_tickerController.text),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          if (snapshot.data!) {
                            return Chip(
                              avatar: const Icon(Icons.check_circle, size: 16, color: Colors.green),
                              label: const Text('Из топ-1000', style: TextStyle(fontSize: 12)),
                              backgroundColor: Colors.green.withOpacity(0.1),
                            );
                          } else {
                            return Chip(
                              avatar: const Icon(Icons.search, size: 16, color: Colors.orange),
                              label: const Text('Поиск в API', style: TextStyle(fontSize: 12)),
                              backgroundColor: Colors.orange.withOpacity(0.1),
                            );
                          }
                        }
                        return const SizedBox.shrink();
                      },
                    ),

                  const SizedBox(height: 20),

                  // Поле для ввода пороговой цены
                  TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(
                      labelText: 'Пороговая цена (USD)',
                      hintText: '50000.00',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Введите пороговую цену';
                      }
                      final price = double.tryParse(value.trim());
                      if (price == null || price <= 0) {
                        return 'Введите корректную цену';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 30),

                  // Кнопка сохранения
                  ElevatedButton(
                    onPressed: provider.isLoading ? null : _saveAlert,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: provider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Сохранить алерт',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),

                  const SizedBox(height: 20),

                  const SizedBox(height: 16),

                  // Список активных алертов с pull-to-refresh
                  if (provider.activeAlerts.isNotEmpty) ...[
                    const Text(
                      'Активные алерты:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    RefreshIndicator(
                      onRefresh: () => _loadAlertPrices(force: true),
                      child: Column(
                        children: provider.activeAlerts.map((alert) {
                          final dirText = alert.direction == 'UP' ? '↑' : '↓';
                          final dirColor = alert.direction == 'UP' ? Colors.green : Colors.red;
                          final key = alert.ticker.toUpperCase();
                          final hasPrice = _alertPrices.containsKey(key);
                          final currentPrice = _alertPrices[key];
                          final diff = hasPrice ? (alert.thresholdPrice - (currentPrice!)).abs() : null;
                          final pct = hasPrice && currentPrice! > 0 ? (diff! / currentPrice * 100) : null;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                        child: Text(alert.ticker, style: const TextStyle(fontSize: 12)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(alert.ticker, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                            if (hasPrice) ...[
                                              AnimatedSwitcher(
                                                duration: const Duration(milliseconds: 250),
                                                child: Text(
                                                  'Текущая цена: \$${currentPrice!.toStringAsFixed(2)}',
                                                  key: ValueKey(currentPrice.toStringAsFixed(2)),
                                                  style: const TextStyle(fontSize: 16, color: Colors.blue),
                                                ),
                                              ),
                                              Text(
                                                'Цель: \$${alert.thresholdPrice.toStringAsFixed(2)} $dirText',
                                                style: const TextStyle(fontSize: 14),
                                              ),
                                              if (diff != null && pct != null)
                                                Text(
                                                  'До цели: \$${diff.toStringAsFixed(2)} (${pct.toStringAsFixed(1)}%)',
                                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                ),
                                            ] else ...[
                                              Row(
                                                children: const [
                                                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                                                  SizedBox(width: 8),
                                                  Text('Загрузка цены...'),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        onPressed: () async {
                                          if (alert.id != null) {
                                            await provider.deleteAlert(alert.id!);
                                            await _loadAlertPrices(force: true);
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Алерт удален'), backgroundColor: Colors.green),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    Card(
                      color: Colors.grey[100],
                      child: const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Нет активных алертов',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Убрали блок последней проверенной цены
                ],
              ),
            ),
          );
        },
      );
  }
}
