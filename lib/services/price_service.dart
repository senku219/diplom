import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import 'ticker_sync_service.dart';

/// Сервис для работы с CoinGecko API
/// Получает актуальную цену криптовалюты в USD
class PriceService {
  // Базовый URL CoinGecko API
  static const String baseUrl = 'https://api.coingecko.com/api/v3';

  /// Получить CoinGecko id для тикера из БД (с ленивым кэшированием)
  static Future<String?> getCoinGeckoId(String ticker) async {
    final Database db = await DatabaseService().database;
    final upper = ticker.toUpperCase();

    final res = await db.query(
      'Tickers',
      columns: ['coingecko_id'],
      where: 'ticker = ?',
      whereArgs: [upper],
      limit: 1,
    );
    if (res.isNotEmpty) {
      return res.first['coingecko_id'] as String?;
    }

    // Ленивая подгрузка
    print('[PriceService] Тикер $ticker не найден в БД, ищем в API...');
    final found = await TickerSyncService.searchAndCacheTicker(db, upper);
    if (found != null) return found['coingecko_id'] as String?;

    print('[PriceService] Тикер $ticker не найден ни в БД, ни в API');
    return null;
  }

  // Простой кэш цен на 60 секунд: TICKER -> (price, timestampMs)
  static final Map<String, Map<String, dynamic>> _priceCache = {};
  static const int _cacheTtlMs = 60 * 1000;

  /// Получает текущую цену криптовалюты по тикеру
  /// 
  /// [ticker] - тикер криптовалюты (например: BTC, ETH, SOL)
  /// Возвращает цену в USD или null, если произошла ошибка
  Future<double?> getPrice(String ticker) async {
    try {
      final coinId = await getCoinGeckoId(ticker);
      if (coinId == null) {
        print('[PriceService] Неизвестный тикер: $ticker');
        return null;
      }

      // Формируем URL запроса
      final url = Uri.parse(
        '$baseUrl/simple/price?ids=$coinId&vs_currencies=usd',
      );

      print('[PriceService] URL: $url');

      // Выполняем HTTP запрос
      final response = await http.get(url);

      print('[PriceService] Статус ответа: ${response.statusCode}');
      print('[PriceService] Тело ответа: ${response.body}');

      if (response.statusCode == 200) {
        // Парсим JSON ответ
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Проверяем, есть ли данные для запрошенной монеты
        if (data.containsKey(coinId)) {
          final coinData = data[coinId] as Map<String, dynamic>;
          final price = (coinData['usd'] as num).toDouble();
          print('[PriceService] Получена цена: \$$price для $ticker');
          return price;
        } else {
          print('[PriceService] Ошибка: Монета $ticker не найдена в ответе');
          return null;
        }
      } else {
        print('[PriceService] Ошибка HTTP: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('[PriceService] Исключение при получении цены: $e');
      return null;
    }
  }

  /// Проверяет, достигнута ли пороговая цена
  /// 
  /// [currentPrice] - текущая цена
  /// [thresholdPrice] - пороговая цена
  /// Возвращает true, если текущая цена >= пороговой
  bool isThresholdReached(double currentPrice, double thresholdPrice) {
    return currentPrice >= thresholdPrice;
  }

  /// Получает цены нескольких тикеров одним запросом с кэшированием (60 сек)
  /// Возвращает мапу: TICKER -> price
  Future<Map<String, double>> getMultiplePrices(List<String> tickers) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final upperTickers = tickers.map((t) => t.toUpperCase()).toSet().toList();

    // Разделим на: что можно взять из кэша и что нужно запросить
    final Map<String, double> result = {};
    final List<String> toFetch = [];

    for (final t in upperTickers) {
      final cached = _priceCache[t];
      if (cached != null && now - (cached['ts'] as int) < _cacheTtlMs) {
        result[t] = cached['price'] as double;
      } else {
        toFetch.add(t);
      }
    }

    if (toFetch.isEmpty) {
      return result;
    }

    // Получить CoinGecko ids из БД / лениво из API
    final Database db = await DatabaseService().database;
    final Map<String, String> tickerToId = {};
    // Сначала пробуем из БД одним запросом IN
    final placeholders = List.filled(toFetch.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT ticker, coingecko_id FROM Tickers WHERE ticker IN ($placeholders)',
      toFetch,
    );
    for (final r in rows) {
      tickerToId[(r['ticker'] as String).toUpperCase()] = r['coingecko_id'] as String;
    }
    // Для отсутствующих делаем ленивый поиск
    for (final t in toFetch) {
      if (!tickerToId.containsKey(t)) {
        final found = await TickerSyncService.searchAndCacheTicker(db, t);
        if (found != null) {
          tickerToId[t] = found['coingecko_id'] as String;
        }
      }
    }

    final ids = tickerToId.values.toSet().join(',');
    if (ids.isEmpty) return result;

    final url = Uri.parse('$baseUrl/simple/price?ids=$ids&vs_currencies=usd');
    print('[PriceService] Batch URL: $url');

    try {
      final response = await http.get(url);
      print('[PriceService] Batch status: ${response.statusCode}');
      if (response.statusCode != 200) {
        return result; // вернем то, что было из кэша
      }
      final data = json.decode(response.body) as Map<String, dynamic>;

      // Обратное соответствие id->ticker(верхний)
      final Map<String, String> idToTicker = {
        for (final e in tickerToId.entries) e.value: e.key
      };

      for (final entry in data.entries) {
        final id = entry.key;
        final coinData = entry.value as Map<String, dynamic>;
        if (coinData.containsKey('usd')) {
          final price = (coinData['usd'] as num).toDouble();
          final ticker = idToTicker[id] ?? id.toUpperCase();
          result[ticker] = price;
          _priceCache[ticker] = {'price': price, 'ts': now};
        }
      }
    } catch (e) {
      print('[PriceService] Batch exception: $e');
    }

    return result;
  }
}
