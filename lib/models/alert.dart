/// Модель данных для уведомления о достижении цены
class Alert {
  final int? id;              // ID из БД (null для новых алертов)
  final String ticker;        // Тикер криптовалюты (BTC, ETH, SOL и т.д.)
  final double thresholdPrice; // Пороговая цена в USD
  final String direction;     // 'UP' или 'DOWN'
  final double initialPrice;  // Цена на момент создания алерта
  final bool isActive;        // Активен ли алерт

  Alert({
    this.id,
    required this.ticker,
    required this.thresholdPrice,
    required this.direction,
    required this.initialPrice,
    required this.isActive,
  });

  // Преобразование в JSON для сохранения
  Map<String, dynamic> toJson() {
    return {
      'ticker': ticker.toUpperCase(),
      'thresholdPrice': thresholdPrice,
      'direction': direction,
      'initialPrice': initialPrice,
      'isActive': isActive,
    };
  }

  // Создание из JSON
  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      ticker: json['ticker'] as String,
      thresholdPrice: json['thresholdPrice'] as double,
      direction: json['direction'] as String,
      initialPrice: (json['initialPrice'] as num).toDouble(),
      isActive: (json['isActive'] as bool?) ?? true,
    );
  }
}
