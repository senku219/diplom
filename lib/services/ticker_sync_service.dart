import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

class TickerSyncService {
  static const String baseUrl = 'https://api.coingecko.com/api/v3';
  static const int perPage = 250; // Максимум для CoinGecko
  static const int totalCoins = 1000; // Топ-1000

  // Загрузка топ-1000 монет по рыночной капитализации
  static Future<void> syncTop1000Coins(Database db) async {
    print('[TickerSync] Начинаем загрузку топ-1000 криптовалют...');

    try {
      final int totalPages = (totalCoins / perPage).ceil(); // 4 страницы по 250
      final List<Map<String, dynamic>> allCoins = [];

      // Загружаем по страницам (4 запроса по 250 монет)
      for (int page = 1; page <= totalPages; page++) {
        print('[TickerSync] Загружаем страницу $page из $totalPages...');

        final url = '$baseUrl/coins/markets'
            '?vs_currency=usd'
            '&order=market_cap_desc'
            '&per_page=$perPage'
            '&page=$page'
            '&sparkline=false';

        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final List<dynamic> coins = json.decode(response.body) as List<dynamic>;

          for (final coin in coins) {
            allCoins.add({
              'ticker': (coin as Map<String, dynamic>)['symbol']?.toUpperCase() ?? '',
              'name': coin['name'] ?? '',
              'coingecko_id': coin['id'] ?? '',
            });
          }

          // Задержка между запросами чтобы не превысить rate limit
          if (page < totalPages) {
            await Future.delayed(const Duration(seconds: 2));
          }
        } else if (response.statusCode == 429) {
          // Rate limit - ждем и повторяем
          print('[TickerSync] Rate limit, ждем 60 секунд...');
          await Future.delayed(const Duration(seconds: 60));
          page--; // Повторим эту страницу
          continue;
        } else {
          print('[TickerSync] Ошибка загрузки страницы $page: ${response.statusCode}');
        }
      }

      // Сохраняем в БД с использованием batch для производительности
      if (allCoins.isNotEmpty) {
        await _saveTickersToDb(db, allCoins);
        print('[TickerSync] Успешно загружено ${allCoins.length} монет');
      }
    } catch (e) {
      print('[TickerSync] Ошибка синхронизации: $e');
      rethrow;
    }
  }

  // Сохранение в БД пачками
  static Future<void> _saveTickersToDb(Database db, List<Map<String, dynamic>> tickers) async {
    final Batch batch = db.batch();

    for (final ticker in tickers) {
      // INSERT OR REPLACE чтобы обновлять существующие
      batch.rawInsert('''
        INSERT OR REPLACE INTO Tickers (ticker, name, coingecko_id)
        VALUES (?, ?, ?)
      ''', [ticker['ticker'], ticker['name'], ticker['coingecko_id']]);
    }

    await batch.commit(noResult: true);
    print('[TickerSync] Сохранено в БД: ${tickers.length} записей');
  }

  // Ленивая загрузка неизвестного тикера
  static Future<Map<String, dynamic>?> searchAndCacheTicker(Database db, String query) async {
    try {
      print('[TickerSync] Поиск монеты: $query');

      // Сначала проверяем в БД
      final existing = await db.query(
        'Tickers',
        where: 'ticker = ? OR name LIKE ?',
        whereArgs: [query.toUpperCase(), '%$query%'],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        return existing.first;
      }

      // Если не нашли - ищем в API
      final url = '$baseUrl/search?query=$query';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final coins = (data['coins'] as List).cast<Map<String, dynamic>>();

        if (coins.isNotEmpty) {
          final coin = coins.first;

          // Получаем детальную информацию с тикером
          final detailUrl = '$baseUrl/coins/${coin['id']}?localization=false&tickers=false&market_data=true';
          final detailResponse = await http.get(Uri.parse(detailUrl));

          if (detailResponse.statusCode == 200) {
            final details = json.decode(detailResponse.body) as Map<String, dynamic>;

            final tickerData = {
              'ticker': (details['symbol'] as String?)?.toUpperCase() ?? query.toUpperCase(),
              'name': (details['name'] as String?) ?? (coin['name'] as String? ?? query),
              'coingecko_id': coin['id'],
            };

            // Сохраняем в БД
            await db.insert('Tickers', tickerData, conflictAlgorithm: ConflictAlgorithm.replace);
            print('[TickerSync] Добавлена новая монета: ${tickerData['ticker']}');

            return tickerData;
          }
        }
      }
    } catch (e) {
      print('[TickerSync] Ошибка поиска: $e');
    }

    return null;
  }

  // Проверка, когда последний раз обновляли (MVP: проверяем наличие записей)
  static Future<bool> needsUpdate(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM Tickers'),
    );
    return count == null || count < 100; // Если меньше 100 записей - нужно обновить
  }

  // Получить все тикеры для автокомплита
  static Future<List<Map<String, dynamic>>> getAllTickers(Database db) async {
    return await db.query(
      'Tickers',
      orderBy: 'ticker ASC',
    );
  }

  // Поиск тикеров для автокомплита
  static Future<List<Map<String, dynamic>>> searchTickers(Database db, String query) async {
    if (query.isEmpty) return [];

    return await db.query(
      'Tickers',
      where: 'ticker LIKE ? OR name LIKE ?',
      whereArgs: ['%${query.toUpperCase()}%', '%$query%'],
      orderBy: 'ticker ASC',
      limit: 20,
    );
  }
}


