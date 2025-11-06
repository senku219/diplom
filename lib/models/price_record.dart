class PriceRecord {
  final int id;
  final int assetId;
  final String ticker;
  final double price;
  final int timestamp; // unix ms

  const PriceRecord({
    required this.id,
    required this.assetId,
    required this.ticker,
    required this.price,
    required this.timestamp,
  });

  factory PriceRecord.fromRow(Map<String, Object?> row) {
    return PriceRecord(
      id: row['id'] as int,
      assetId: row['asset_id'] as int,
      ticker: row['ticker'] as String,
      price: (row['price'] as num).toDouble(),
      timestamp: row['timestamp'] as int,
    );
  }
}


