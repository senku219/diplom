import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseService {
  static const int _dbVersion = 3;
  static const String _dbName = 'cryptowatcher.db';

  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);
    return await openDatabase(
      fullPath,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // На Android PRAGMA лучше вызывать через rawQuery
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _migrate(db, oldVersion, newVersion);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    // Справочник тикеров (опционально)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Tickers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticker TEXT NOT NULL UNIQUE,
        name TEXT,
        coingecko_id TEXT
      );
    ''');

    // Активы
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Assets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticker TEXT NOT NULL CHECK (length(ticker) > 0),
        amount REAL NOT NULL DEFAULT 0 CHECK (amount >= 0),
        entry_price REAL NOT NULL DEFAULT 0 CHECK (entry_price >= 0),
        note TEXT,
        updated_at INTEGER NOT NULL,
        UNIQUE (ticker)
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_assets_ticker ON Assets(ticker);
    ''');

    // История цен (все проверки)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS PriceHistory (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_id INTEGER NOT NULL,
        price REAL NOT NULL CHECK (price >= 0),
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (asset_id) REFERENCES Assets(id) ON DELETE CASCADE
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ph_asset_time ON PriceHistory(asset_id, timestamp DESC);
    ''');

    // Таблица алертов
    await db.execute('''
      CREATE TABLE IF NOT EXISTS Alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticker TEXT NOT NULL CHECK (length(ticker) > 0),
        threshold_price REAL NOT NULL CHECK (threshold_price > 0),
        direction TEXT NOT NULL CHECK (direction IN ('UP', 'DOWN')),
        initial_price REAL NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        created_at INTEGER NOT NULL
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_alerts_ticker_active ON Alerts(ticker, is_active);
    ''');

    // Лог срабатываний уведомлений
    await db.execute('''
      CREATE TABLE IF NOT EXISTS AlertsLog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_id INTEGER,
        ticker TEXT,
        price REAL NOT NULL,
        target_price REAL NOT NULL,
        triggered_at INTEGER NOT NULL,
        direction TEXT,
        FOREIGN KEY (asset_id) REFERENCES Assets(id) ON DELETE SET NULL
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_alerts_asset_time ON AlertsLog(asset_id, triggered_at DESC);
    ''');
  }

  Future<void> _migrate(Database db, int from, int to) async {
    // Миграции на будущие версии
    if (from < 2) {
      await db.execute('ALTER TABLE AlertsLog ADD COLUMN direction TEXT');
      from = 2;
    }
    if (from < 3) {
      // Создаём таблицу Alerts
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Alerts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          ticker TEXT NOT NULL CHECK (length(ticker) > 0),
          threshold_price REAL NOT NULL CHECK (threshold_price > 0),
          direction TEXT NOT NULL CHECK (direction IN ('UP', 'DOWN')),
          initial_price REAL NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
          created_at INTEGER NOT NULL
        );
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_alerts_ticker_active ON Alerts(ticker, is_active);
      ''');
      // Обновляем AlertsLog для поддержки ticker и direction (если колонок еще нет)
      try {
        // Проверяем наличие колонки ticker
        final columns = await db.rawQuery('PRAGMA table_info(AlertsLog)');
        final hasTicker = columns.any((c) => c['name'] == 'ticker');
        if (!hasTicker) {
          await db.execute('ALTER TABLE AlertsLog ADD COLUMN ticker TEXT');
        }
      } catch (_) {}
      try {
        // Проверяем наличие колонки direction
        final columns = await db.rawQuery('PRAGMA table_info(AlertsLog)');
        final hasDirection = columns.any((c) => c['name'] == 'direction');
        if (!hasDirection) {
          await db.execute('ALTER TABLE AlertsLog ADD COLUMN direction TEXT');
        }
      } catch (_) {}
      from = 3;
    }
  }

  // Публичный alias для инициализации (по требованию ТЗ)
  Future<void> initDatabase() async {
    await database;
  }

  Future<int> addAsset(String ticker, double amount, double entryPrice, String? note) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return await upsertAsset(
      ticker: ticker,
      amount: amount,
      entryPrice: entryPrice,
      note: note,
      updatedAt: now,
    );
  }

  Future<List<Map<String, Object?>>> getAssets() async {
    final db = await database;
    // Возвращаем активы c последней ценой через подзапрос
    final rows = await db.rawQuery('''
      SELECT a.id, a.ticker, a.amount, a.entry_price, a.note, a.updated_at,
             (
               SELECT ph.price FROM PriceHistory ph
               WHERE ph.asset_id = a.id
               ORDER BY ph.timestamp DESC
               LIMIT 1
             ) AS last_price
      FROM Assets a
      ORDER BY a.ticker ASC
    ''');
    return rows;
  }

  Future<void> deleteAsset(int id) async {
    await deleteAssetById(id);
  }

  Future<void> updateAssetPrice(int id, double currentPrice) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await database;
    await addPriceHistory(assetId: id, price: currentPrice, timestamp: now);
    await db.update('Assets', {'updated_at': now}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int?> getAssetIdByTicker(String ticker) async {
    final db = await database;
    final rows = await db.query('Assets', columns: ['id'], where: 'ticker = ?', whereArgs: [ticker.toUpperCase()], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['id'] as int;
  }

  Future<void> updateAssetFields({
    required int id,
    double? amount,
    double? entryPrice,
    String? note,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final data = <String, Object?>{'updated_at': now};
    if (amount != null) data['amount'] = amount;
    if (entryPrice != null) data['entry_price'] = entryPrice;
    if (note != null) data['note'] = note;
    await db.update('Assets', data, where: 'id = ?', whereArgs: [id]);
  }
  // Утилиты для часто используемых запросов
  Future<int> upsertAsset({
    required String ticker,
    required double amount,
    required double entryPrice,
    String? note,
    required int updatedAt,
  }) async {
    final db = await database;
    // Тикер в верхний регистр для уникальности
    final upper = ticker.toUpperCase();
    return await db.insert(
      'Assets',
      {
        'ticker': upper,
        'amount': amount,
        'entry_price': entryPrice,
        'note': note,
        'updated_at': updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAssetById(int assetId) async {
    final db = await database;
    await db.delete('Assets', where: 'id = ?', whereArgs: [assetId]);
  }

  Future<void> addPriceHistory({
    required int assetId,
    required double price,
    required int timestamp,
  }) async {
    final db = await database;
    await db.insert('PriceHistory', {
      'asset_id': assetId,
      'price': price,
      'timestamp': timestamp,
    });
  }

  Future<void> logAlert({
    int? assetId,
    String? ticker,
    required double price,
    required double targetPrice,
    required int triggeredAt,
    required String direction,
  }) async {
    final db = await database;
    await db.insert('AlertsLog', {
      'asset_id': assetId,
      'ticker': ticker?.toUpperCase(),
      'price': price,
      'target_price': targetPrice,
      'triggered_at': triggeredAt,
      'direction': direction,
    });
  }

  Future<double?> getLastPriceForAsset(int assetId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT price FROM PriceHistory WHERE asset_id = ? ORDER BY timestamp DESC LIMIT 1',
      [assetId],
    );
    if (rows.isEmpty) return null;
    return rows.first['price'] as double?;
  }

  // История цен с опциональным фильтром по тикеру, пагинацией
  Future<List<Map<String, Object?>>> getPriceHistory({
    required int limit,
    required int offset,
    String? ticker,
  }) async {
    final db = await database;
    if (ticker != null && ticker.isNotEmpty) {
      return await db.rawQuery('''
        SELECT ph.id, ph.asset_id, a.ticker, ph.price, ph.timestamp
        FROM PriceHistory ph
        JOIN Assets a ON a.id = ph.asset_id
        WHERE a.ticker = ?
        ORDER BY ph.timestamp DESC
        LIMIT ? OFFSET ?
      ''', [ticker.toUpperCase(), limit, offset]);
    } else {
      return await db.rawQuery('''
        SELECT ph.id, ph.asset_id, a.ticker, ph.price, ph.timestamp
        FROM PriceHistory ph
        JOIN Assets a ON a.id = ph.asset_id
        ORDER BY ph.timestamp DESC
        LIMIT ? OFFSET ?
      ''', [limit, offset]);
    }
  }

  // Лог уведомлений, пагинация
  Future<List<Map<String, Object?>>> getAlertsLog({
    required int limit,
    required int offset,
  }) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT al.id, al.asset_id, 
             COALESCE(a.ticker, al.ticker) as ticker, 
             al.price, al.target_price, al.triggered_at, al.direction
      FROM AlertsLog al
      LEFT JOIN Assets a ON a.id = al.asset_id
      ORDER BY al.triggered_at DESC
      LIMIT ? OFFSET ?
    ''', [limit, offset]);
  }

  // Очистка истории старше порога времени (unix ms)
  Future<int> clearHistory({required int olderThan}) async {
    final db = await database;
    final deletedPrices = await db.delete('PriceHistory', where: 'timestamp < ?', whereArgs: [olderThan]);
    final deletedAlerts = await db.delete('AlertsLog', where: 'triggered_at < ?', whereArgs: [olderThan]);
    return deletedPrices + deletedAlerts;
  }

  // ========== Методы для работы с алертами ==========

  Future<int> addAlert({
    required String ticker,
    required double thresholdPrice,
    required String direction,
    required double initialPrice,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return await db.insert('Alerts', {
      'ticker': ticker.toUpperCase(),
      'threshold_price': thresholdPrice,
      'direction': direction,
      'initial_price': initialPrice,
      'is_active': 1,
      'created_at': now,
    });
  }

  Future<List<Map<String, Object?>>> getActiveAlerts() async {
    final db = await database;
    return await db.query(
      'Alerts',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, Object?>>> getAllAlerts() async {
    final db = await database;
    return await db.query(
      'Alerts',
      orderBy: 'created_at DESC',
    );
  }

  Future<void> deactivateAlert(int alertId) async {
    final db = await database;
    await db.update('Alerts', {'is_active': 0}, where: 'id = ?', whereArgs: [alertId]);
  }

  Future<void> deleteAlert(int alertId) async {
    final db = await database;
    await db.delete('Alerts', where: 'id = ?', whereArgs: [alertId]);
  }

  Future<void> deleteAllAlerts() async {
    final db = await database;
    await db.delete('Alerts');
  }
}


