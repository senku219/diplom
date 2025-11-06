class Asset {
  final int id;
  final String ticker;
  final double amount;
  final double entryPrice;
  final String? note;
  final int updatedAt;
  final double? lastPrice;

  const Asset({
    required this.id,
    required this.ticker,
    required this.amount,
    required this.entryPrice,
    required this.note,
    required this.updatedAt,
    required this.lastPrice,
  });

  double get positionValue => (lastPrice ?? 0) * amount;
  double get investedValue => entryPrice * amount;
  double get profitUsd => positionValue - investedValue;
  double get profitPercent => investedValue == 0 ? 0 : (profitUsd / investedValue) * 100;

  factory Asset.fromRow(Map<String, Object?> row) {
    return Asset(
      id: (row['id'] as int),
      ticker: (row['ticker'] as String),
      amount: (row['amount'] as num).toDouble(),
      entryPrice: (row['entry_price'] as num).toDouble(),
      note: row['note'] as String?,
      updatedAt: (row['updated_at'] as int),
      lastPrice: row['last_price'] == null ? null : (row['last_price'] as num).toDouble(),
    );
  }
}


