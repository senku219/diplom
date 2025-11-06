import 'package:flutter/material.dart';
import '../utils/app_info.dart';
import '../widgets/feature_card.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    AppInfo.getVersion().then((v) => setState(() => _version = v));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.show_chart, size: 40, color: scheme.primary),
                  ),
                  const SizedBox(height: 12),
                  const Text('CryptoWatcher', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Версия: ${_version.isEmpty ? '—' : _version}', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverList.separated(
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final features = [
                  const FeatureCard(
                    icon: Icons.account_balance_wallet,
                    title: 'Отслеживание портфеля',
                    description: 'Управляйте активами, считайте P&L и стоимость позиций.',
                  ),
                  const FeatureCard(
                    icon: Icons.notifications_active,
                    title: 'Уведомления о ценах',
                    description: 'Получайте push при достижении целевых уровней.',
                  ),
                  const FeatureCard(
                    icon: Icons.history,
                    title: 'История изменений',
                    description: 'Архив всех проверок цен и срабатываний алертов.',
                  ),
                  const FeatureCard(
                    icon: Icons.api_outlined,
                    title: 'API CoinGecko',
                    description: 'Актуальные цены из надежного источника.',
                  ),
                ];
                return features[index];
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: scheme.primary, size: 20),
                          const SizedBox(width: 8),
                          const Text('Цель проекта', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'CryptoWatcher — это дипломный проект, разработанный для отслеживания криптовалютных активов и получения уведомлений о достижении целевых цен. Приложение демонстрирует использование современных технологий Flutter, локальной базы данных SQLite и интеграции с внешними API для создания полнофункционального мобильного приложения.',
                        style: TextStyle(color: Colors.grey, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverToBoxAdapter(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Разработчик', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text('hsiddq'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: AppInfo.openTelegram,
                            icon: const Icon(Icons.send),
                            label: const Text('Написать разработчику'),
                          ),
                          OutlinedButton.icon(
                            onPressed: AppInfo.openGithub,
                            icon: const Icon(Icons.code),
                            label: const Text('GitHub'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverToBoxAdapter(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Информация', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Лицензия: ${AppInfo.license}'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: AppInfo.openGithub,
                        child: const Text('Репозиторий GitHub', style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: AppInfo.rateApp,
                        icon: const Icon(Icons.star_rate_outlined),
                        label: const Text('Оценить приложение'),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


