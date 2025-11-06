import 'package:flutter/material.dart';
import '../models/asset.dart';
import '../services/database_service.dart';
import '../services/price_service.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final DatabaseService _db = DatabaseService();
  final PriceService _price = PriceService();

  bool _loading = true;
  List<Asset> _assets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.getAssets();
    final assets = rows.map((r) => Asset.fromRow(r)).toList();
    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  Future<void> _refreshPrices() async {
    // Последовательно обновляем цены и историю
    for (final a in _assets) {
      final price = await _price.getPrice(a.ticker);
      if (price != null) {
        await _db.updateAssetPrice(a.id, price);
      }
    }
    await _load();
  }

  Future<void> _addAssetDialog() async {
    final formKey = GlobalKey<FormState>();
    final tickerCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final entryCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Добавить актив'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: tickerCtrl,
                    decoration: const InputDecoration(labelText: 'Тикер'),
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите тикер' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(labelText: 'Количество'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n < 0) return 'Введите корректное количество';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: entryCtrl,
                    decoration: const InputDecoration(labelText: 'Цена покупки (USD)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n < 0) return 'Введите корректную цену';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Заметка'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final ticker = tickerCtrl.text.trim().toUpperCase();
                final amount = double.parse(amountCtrl.text.trim());
                final entry = double.parse(entryCtrl.text.trim());
                final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();
                await _db.addAsset(ticker, amount, entry, note);
                if (!mounted) return;
                Navigator.of(context).pop(true);
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await _load();
      // Мгновенно подтянуть цены для нового актива
      await _refreshPrices();
    }
  }

  Future<void> _deleteAsset(Asset a) async {
    await _db.deleteAsset(a.id);
    await _load();
  }

  Future<void> _editAssetDialog(Asset a) async {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController(text: a.amount.toString());
    final entryCtrl = TextEditingController(text: a.entryPrice.toString());
    final noteCtrl = TextEditingController(text: a.note ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Редактировать ${a.ticker}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(labelText: 'Количество'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n < 0) return 'Введите корректное количество';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: entryCtrl,
                    decoration: const InputDecoration(labelText: 'Цена покупки (USD)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').trim());
                      if (n == null || n < 0) return 'Введите корректную цену';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(labelText: 'Заметка'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final amount = double.parse(amountCtrl.text.trim());
                final entry = double.parse(entryCtrl.text.trim());
                final note = noteCtrl.text.trim();
                await _db.updateAssetFields(id: a.id, amount: amount, entryPrice: entry, note: note);
                if (!mounted) return;
                Navigator.pop(context, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _load();
      await _refreshPrices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final green = const Color(0xFF4CAF50);
    final red = const Color(0xFFF44336);

    final totalValue = _assets.fold<double>(0, (s, a) => s + a.positionValue);
    final totalInvested = _assets.fold<double>(0, (s, a) => s + a.investedValue);
    final totalPnl = totalValue - totalInvested;
    final totalPct = totalInvested == 0 ? 0 : (totalPnl / totalInvested) * 100;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои активы'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAssetDialog,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshPrices,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Итоги портфеля
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Итого портфель', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text('Стоимость: \$${totalValue.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text('P&L: \$${totalPnl.toStringAsFixed(2)}',
                                  style: TextStyle(fontSize: 16, color: totalPnl >= 0 ? green : red, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Text('(${totalPct.toStringAsFixed(2)}%)',
                                  style: TextStyle(fontSize: 16, color: totalPnl >= 0 ? green : red)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Список активов
                  for (final a in _assets)
                    Dismissible(
                      key: ValueKey('asset-${a.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        color: red.withOpacity(0.1),
                        child: Icon(Icons.delete_outline, color: red),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Удалить актив?'),
                                content: Text('Удалить ${a.ticker}?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
                                ],
                              ),
                            ) ??
                            false;
                      },
                      onDismissed: (_) => _deleteAsset(a),
                      child: InkWell(
                        onLongPress: () => _editAssetDialog(a),
                        child: _AssetCard(asset: a, green: green, red: red),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  final Asset asset;
  final Color green;
  final Color red;
  const _AssetCard({required this.asset, required this.green, required this.red});

  @override
  Widget build(BuildContext context) {
    final pnl = asset.profitUsd;
    final pct = asset.profitPercent;
    final color = pnl >= 0 ? green : red;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(asset.ticker, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          asset.lastPrice == null ? '-' : '\$${asset.lastPrice!.toStringAsFixed(2)}',
                          key: ValueKey(asset.lastPrice),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Кол-во: ${asset.amount.toStringAsFixed(6)}'),
                  Text('Цена покупки: \$${asset.entryPrice.toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Стоимость: \$${asset.positionValue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('P&L', style: TextStyle(color: Colors.grey[600])),
                Text('\$${pnl.toStringAsFixed(2)}', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                Text('(${pct.toStringAsFixed(2)}%)', style: TextStyle(color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


