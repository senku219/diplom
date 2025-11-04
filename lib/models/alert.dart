/// Модель данных для уведомления о достижении цены
class Alert {
  final String ticker;        // Тикер криптовалюты (BTC, ETH, SOL и т.д.)
  final double thresholdPrice; // Пороговая цена в USD

  Alert({
    required this.ticker,
    required this.thresholdPrice,
  });

  // Преобразование в JSON для сохранения
  Map<String, dynamic> toJson() {
    return {
      'ticker': ticker.toUpperCase(),
      'thresholdPrice': thresholdPrice,
    };
  }

  // Создание из JSON
  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      ticker: json['ticker'] as String,
      thresholdPrice: json['thresholdPrice'] as double,
    );
  }
}
