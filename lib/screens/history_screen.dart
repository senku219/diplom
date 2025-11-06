import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/price_record.dart';
import '../models/alert_record.dart';
import '../services/database_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  final _limit = 50;
  late TabController _tabController;

  // Проверки цен
  final ScrollController _checksCtrl = ScrollController();
  final List<PriceRecord> _checks = [];
  bool _loadingChecks = false;
  bool _hasMoreChecks = true;
  String? _tickerFilter; // null = все

  // Уведомления
  final ScrollController _alertsCtrl = ScrollController();
  final List<AlertRecord> _alerts = [];
  bool _loadingAlerts = false;
  bool _hasMoreAlerts = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checksCtrl.addListener(_onChecksScroll);
    _alertsCtrl.addListener(_onAlertsScroll);
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    await Future.wait([
      _loadMoreChecks(reset: true),
      _loadMoreAlerts(reset: true),
    ]);
  }

  void _onChecksScroll() {
    if (_checksCtrl.position.pixels >= _checksCtrl.position.maxScrollExtent - 200) {
      _loadMoreChecks();
    }
  }

  void _onAlertsScroll() {
    if (_alertsCtrl.position.pixels >= _alertsCtrl.position.maxScrollExtent - 200) {
      _loadMoreAlerts();
    }
  }

  Future<void> _loadMoreChecks({bool reset = false}) async {
    if (_loadingChecks) return;
    setState(() => _loadingChecks = true);
    if (reset) {
      _checks.clear();
      _hasMoreChecks = true;
    }
    final rows = await _db.getPriceHistory(limit: _limit, offset: _checks.length, ticker: _tickerFilter);
    final items = rows.map((r) => PriceRecord.fromRow(r)).toList();
    setState(() {
      _checks.addAll(items);
      _hasMoreChecks = items.length == _limit;
      _loadingChecks = false;
    });
  }

  Future<void> _loadMoreAlerts({bool reset = false}) async {
    if (_loadingAlerts) return;
    setState(() => _loadingAlerts = true);
    if (reset) {
      _alerts.clear();
      _hasMoreAlerts = true;
    }
    final rows = await _db.getAlertsLog(limit: _limit, offset: _alerts.length);
    final items = rows.map((r) => AlertRecord.fromRow(r)).toList();
    setState(() {
      _alerts.addAll(items);
      _hasMoreAlerts = items.length == _limit;
      _loadingAlerts = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text('Это действие удалит старые записи истории проверок и уведомлений.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Очистить')),
        ],
      ),
    );
    if (confirm == true) {
      // По умолчанию очищаем всё старше 10 лет назад
      final threshold = DateTime.now().subtract(const Duration(days: 3650)).millisecondsSinceEpoch;
      await _db.clearHistory(olderThan: threshold);
      await _loadInitial();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _checksCtrl.dispose();
    _alertsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Проверки цен'),
            Tab(text: 'Уведомления'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Очистить историю',
            onPressed: _clearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
          )
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChecksTab(),
          _buildAlertsTab(),
        ],
      ),
    );
  }

  Widget _buildChecksTab() {
    final dfDate = DateFormat('d MMM yyyy');
    final dfTime = DateFormat('HH:mm');

    if (_checks.isEmpty && !_loadingChecks) {
      return _emptyState('Нет данных проверок', Icons.trending_up);
    }

    // Группировка по датам
    final Map<String, List<PriceRecord>> byDate = {};
    for (final r in _checks) {
      final day = dfDate.format(DateTime.fromMillisecondsSinceEpoch(r.timestamp));
      byDate.putIfAbsent(day, () => []).add(r);
    }

    final dates = byDate.keys.toList();

    return Column(
      children: [
        // Фильтр по тикеру
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              const Text('Фильтр:'),
              const SizedBox(width: 12),
              DropdownButton<String?>(
                value: _tickerFilter,
                hint: const Text('Все тикеры'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Все тикеры')),
                  ...{
                    for (final r in _checks) r.ticker
                  }.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))).toList(),
                ],
                onChanged: (v) async {
                  _tickerFilter = v;
                  await _loadMoreChecks(reset: true);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadMoreChecks(reset: true),
            child: ListView.builder(
              controller: _checksCtrl,
              itemCount: dates.length + (_hasMoreChecks ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= dates.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final day = dates[index];
                final items = byDate[day]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    for (int i = 0; i < items.length; i++)
                      _CheckTile(
                        record: items[i],
                        prev: i + 1 < items.length ? items[i + 1] : null,
                        dfTime: dfTime,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertsTab() {
    final df = DateFormat('d MMM yyyy, HH:mm');
    if (_alerts.isEmpty && !_loadingAlerts) {
      return _emptyState('Нет уведомлений', Icons.notifications_none);
    }
    return RefreshIndicator(
      onRefresh: () => _loadMoreAlerts(reset: true),
      child: ListView.builder(
        controller: _alertsCtrl,
        itemCount: _alerts.length + (_hasMoreAlerts ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _alerts.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final r = _alerts[index];
          final above = r.price >= r.targetPrice;
          final color = above ? const Color(0xFF4CAF50) : const Color(0xFFF44336);
          return ListTile(
            leading: Icon(Icons.notifications_active_outlined, color: color),
            title: Text(r.ticker, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Достигнута цена \$${r.price.toStringAsFixed(2)} (цель: \$${r.targetPrice.toStringAsFixed(2)})'),
            trailing: Text(df.format(DateTime.fromMillisecondsSinceEpoch(r.triggeredAt))),
          );
        },
      ),
    );
  }

  Widget _emptyState(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final PriceRecord record;
  final PriceRecord? prev;
  final DateFormat dfTime;
  const _CheckTile({required this.record, required this.prev, required this.dfTime});

  @override
  Widget build(BuildContext context) {
    double? diff;
    if (prev != null && prev!.ticker == record.ticker) {
      diff = record.price - prev!.price;
    }
    Icon? arrow;
    if (diff != null && diff != 0) {
      arrow = diff > 0
          ? const Icon(Icons.arrow_drop_up, color: Color(0xFF4CAF50))
          : const Icon(Icons.arrow_drop_down, color: Color(0xFFF44336));
    }
    return ListTile(
      leading: Text(dfTime.format(DateTime.fromMillisecondsSinceEpoch(record.timestamp)), style: const TextStyle(fontFeatures: [])),
      title: Text(record.ticker, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (arrow != null) arrow,
          Text('\$${record.price.toStringAsFixed(2)}'),
        ],
      ),
    );
  }
}


