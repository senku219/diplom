import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alert.dart';
import '../services/storage_service.dart';
import '../services/price_service.dart';
import '../services/background_service.dart';
import '../providers/alert_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSavedAlert();
  }

  /// Загружает сохраненный алерт при открытии экрана
  Future<void> _loadSavedAlert() async {
    final provider = Provider.of<AlertProvider>(context, listen: false);
    await provider.loadAlert();

    // Если алерт загружен, заполняем поля
    if (provider.alert != null) {
      _tickerController.text = provider.alert!.ticker;
      _priceController.text = provider.alert!.thresholdPrice.toStringAsFixed(2);
    }
  }

  /// Сохраняет алерт и запускает фоновую проверку
  Future<void> _saveAlert() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      final ticker = _tickerController.text.trim().toUpperCase();
      final thresholdPrice = double.parse(_priceController.text.trim());

      final alert = Alert(
        ticker: ticker,
        thresholdPrice: thresholdPrice,
      );

      final provider = Provider.of<AlertProvider>(context, listen: false);
      await provider.saveAlert(alert);

      // Регистрируем фоновую задачу
      await BackgroundService.registerPeriodicTask();

      // Показываем сообщение об успехе
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Алерт сохранен! Проверка цен каждые 15 минут.'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('CryptoWatcher'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<AlertProvider>(
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

                  // Поле для ввода тикера
                  TextFormField(
                    controller: _tickerController,
                    decoration: const InputDecoration(
                      labelText: 'Тикер криптовалюты',
                      hintText: 'BTC, ETH, SOL...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.currency_bitcoin),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Введите тикер криптовалюты';
                      }
                      return null;
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

                  // Кнопка ручной проверки цены
                  OutlinedButton(
                    onPressed: provider.isLoading ? null : _checkPriceManually,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Проверить цену сейчас'),
                  ),

                  const SizedBox(height: 40),

                  // Информация о последней проверенной цене
                  if (provider.alert != null) ...[
                    Card(
                      color: Colors.grey[100],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Текущий алерт:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${provider.alert!.ticker}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Порог: \$${provider.alert!.thresholdPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                  ],

                  // Последняя проверенная цена
                  if (provider.lastPrice != null) ...[
                    Card(
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Последняя проверенная цена:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '\$${provider.lastPrice!.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[900],
                              ),
                            ),
                            if (provider.alert != null &&
                                provider.lastPrice! >= provider.alert!.thresholdPrice)
                              const SizedBox(height: 8),
                            if (provider.alert != null &&
                                provider.lastPrice! >= provider.alert!.thresholdPrice)
                              Text(
                                '✅ Пороговая цена достигнута!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (provider.alert != null) ...[
                    Card(
                      color: Colors.grey[100],
                      child: const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Цена еще не проверена',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
