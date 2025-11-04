import 'dart:convert';
import 'package:http/http.dart' as http;

/// Сервис для работы с CoinGecko API
/// Получает актуальную цену криптовалюты в USD
class PriceService {
  // Базовый URL CoinGecko API
  static const String baseUrl = 'https://api.coingecko.com/api/v3';

  /// Маппинг популярных тикеров в ID CoinGecko
  static const Map<String, String> _tickerToId = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'SOL': 'solana',
    'BNB': 'binancecoin',
    'XRP': 'ripple',
    'ADA': 'cardano',
    'DOGE': 'dogecoin',
    'DOT': 'polkadot',
    'MATIC': 'matic-network',
    'LINK': 'chainlink',
    'AVAX': 'avalanche-2',
    'ATOM': 'cosmos',
    'UNI': 'uniswap',
    'LTC': 'litecoin',
    'ETC': 'ethereum-classic',
  };

  /// Получает текущую цену криптовалюты по тикеру
  /// 
  /// [ticker] - тикер криптовалюты (например: BTC, ETH, SOL)
  /// Возвращает цену в USD или null, если произошла ошибка
  Future<double?> getPrice(String ticker) async {
    try {
      print('[PriceService] Запрос цены для $ticker');

      // Преобразуем тикер в ID CoinGecko
      final coinId = _tickerToId[ticker.toUpperCase()] ?? ticker.toLowerCase();

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
}
