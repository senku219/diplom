class AlertRecord {
  final int id;
  final int assetId;
  final String ticker;
  final double price;
  final double targetPrice;
  final int triggeredAt; // unix ms

  const AlertRecord({
    required this.id,
    required this.assetId,
    required this.ticker,
    required this.price,
    required this.targetPrice,
    required this.triggeredAt,
  });

  factory AlertRecord.fromRow(Map<String, Object?> row) {
    return AlertRecord(
      id: row['id'] as int,
      assetId: row['asset_id'] as int,
      ticker: row['ticker'] as String,
      price: (row['price'] as num).toDouble(),
      targetPrice: (row['target_price'] as num).toDouble(),
      triggeredAt: row['triggered_at'] as int,
    );
  }
}


