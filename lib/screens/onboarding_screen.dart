import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../router/onboarding_state.dart';

const _globalFeedsUrl =
    'https://raw.githubusercontent.com/DevOpen-io/dondurma-rss-reader/refs/heads/main/remote_data/suggested_feeds.json';
const _trFeedsUrl =
    'https://raw.githubusercontent.com/DevOpen-io/dondurma-rss-reader/refs/heads/main/remote_data/suggested_feed_tr.json';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgController;
  late final AnimationController _entranceController;
  late final TabController _tabController;

  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _contentFade;

  List<Map<String, String>> _globalFeeds = [];
  List<Map<String, String>> _trFeeds = [];
  bool _loadingGlobal = true;
  bool _loadingTr = true;
  bool _errorGlobal = false;
  bool _errorTr = false;

  final Set<String> _selectedGlobal = {};
  final Set<String> _selectedTr = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();

    _headerFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );

    _headerSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    ));

    _contentFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    _tabController = TabController(length: 2, vsync: this);

    _loadGlobalFeeds();
    _loadTrFeeds();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _entranceController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGlobalFeeds() async {
    try {
      final res = await http.get(Uri.parse(_globalFeedsUrl));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as List<dynamic>;
        setState(() {
          _globalFeeds = data
              .map(
                (item) => {
                  'name': item['name'].toString(),
                  'url': item['url'].toString(),
                  'category': item['category'].toString(),
                  'popularity': (item['popularity'] ?? 0).toString(),
                },
              )
              .toList();
          _loadingGlobal = false;
        });
      } else {
        setState(() {
          _loadingGlobal = false;
          _errorGlobal = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingGlobal = false;
          _errorGlobal = true;
        });
      }
    }
  }

  Future<void> _loadTrFeeds() async {
    try {
      final res = await http.get(Uri.parse(_trFeedsUrl));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as List<dynamic>;
        setState(() {
          _trFeeds = data
              .map(
                (item) => {
                  'name': item['name'].toString(),
                  'url': item['url'].toString(),
                  'category': item['category'].toString(),
                  'popularity': (item['popularity'] ?? 0).toString(),
                },
              )
              .toList();
          _loadingTr = false;
        });
      } else {
        setState(() {
          _loadingTr = false;
          _errorTr = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingTr = false;
          _errorTr = true;
        });
      }
    }
  }

  List<String> _categoriesFor(List<Map<String, String>> feeds) {
    final maxPop = <String, int>{};
    for (final f in feeds) {
      final cat = f['category']!;
      final pop = int.tryParse(f['popularity'] ?? '0') ?? 0;
      if (pop > (maxPop[cat] ?? 0)) maxPop[cat] = pop;
    }
    return maxPop.keys.toList()
      ..sort((a, b) => (maxPop[b] ?? 0).compareTo(maxPop[a] ?? 0));
  }

  Map<String, int> _countsFor(List<Map<String, String>> feeds) {
    final counts = <String, int>{};
    for (final f in feeds) {
      counts[f['category']!] = (counts[f['category']!] ?? 0) + 1;
    }
    return counts;
  }

  List<Map<String, String>> _topFeedsFor(
    List<Map<String, String>> feeds,
    String cat,
  ) {
    return (feeds.where((f) => f['category'] == cat).toList()
          ..sort((a, b) => a['name']!.compareTo(b['name']!)))
        .take(5)
        .toList();
  }

  int get _totalSelected => _selectedGlobal.length + _selectedTr.length;
  bool get _canContinue => _totalSelected > 0;
  bool get _bothError => _errorGlobal && _errorTr;

  Future<void> _finish() async {
    setState(() => _isSubmitting = true);
    final subscriptionProvider = context.read<SubscriptionProvider>();
    final feedProvider = context.read<FeedProvider>();

    final toAdd = <({String url, String name, String category})>[];
    for (final cat in _selectedGlobal) {
      for (final feed in _topFeedsFor(_globalFeeds, cat)) {
        toAdd.add((url: feed['url']!, name: feed['name']!, category: feed['category']!));
      }
    }
    for (final cat in _selectedTr) {
      for (final feed in _topFeedsFor(_trFeeds, cat)) {
        toAdd.add((url: feed['url']!, name: feed['name']!, category: feed['category']!));
      }
    }

    await subscriptionProvider.addFeedsBatch(toAdd);
    feedProvider.refreshAll();
    await Hive.box('settings').put('hasSeenOnboarding', true);
    if (mounted) context.go('/');
  }

  Future<void> _skip() async {
    sessionOnboardingBypassed = true;
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) => CustomPaint(
              painter: _BlobPainter(
                t: _bgController.value,
                color: colorScheme.primary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeTransition(
                  opacity: _headerFade,
                  child: SlideTransition(
                    position: _headerSlide,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.rss_feed_rounded,
                              size: 36,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            l10n.onboardingTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.onboardingSubtitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                  height: 1.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FadeTransition(
                  opacity: _headerFade,
                  child: TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(text: l10n.tabGlobal),
                      Tab(text: l10n.tabTurkish),
                    ],
                  ),
                ),
                Expanded(
                  child: FadeTransition(
                    opacity: _contentFade,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildContent(
                          feeds: _globalFeeds,
                          loading: _loadingGlobal,
                          error: _errorGlobal,
                          selected: _selectedGlobal,
                          onToggle: (cat) => setState(() {
                            if (_selectedGlobal.contains(cat)) {
                              _selectedGlobal.remove(cat);
                            } else {
                              _selectedGlobal.add(cat);
                            }
                          }),
                          l10n: l10n,
                          colorScheme: colorScheme,
                        ),
                        _buildContent(
                          feeds: _trFeeds,
                          loading: _loadingTr,
                          error: _errorTr,
                          selected: _selectedTr,
                          onToggle: (cat) => setState(() {
                            if (_selectedTr.contains(cat)) {
                              _selectedTr.remove(cat);
                            } else {
                              _selectedTr.add(cat);
                            }
                          }),
                          l10n: l10n,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _contentFade,
                  child: _buildBottom(l10n, colorScheme),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent({
    required List<Map<String, String>> feeds,
    required bool loading,
    required bool error,
    required Set<String> selected,
    required void Function(String) onToggle,
    required AppLocalizations l10n,
    required ColorScheme colorScheme,
  }) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.onboardingLoadError,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final categories = _categoriesFor(feeds);
    final counts = _countsFor(feeds);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: categories
            .map(
              (cat) => _CategoryChip(
                label: cat,
                count: counts[cat] ?? 0,
                selected: selected.contains(cat),
                colorScheme: colorScheme,
                onTap: () => onToggle(cat),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildBottom(AppLocalizations l10n, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_bothError) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.explore_outlined,
                  size: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l10n.onboardingExploreHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (_bothError)
            TextButton(
              onPressed: _isSubmitting ? null : _skip,
              child: Text(l10n.onboardingSkip),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_canContinue && !_isSubmitting) ? _finish : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: _isSubmitting
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(l10n.onboardingContinue),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? null
              : Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 14, color: colorScheme.onPrimary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.onPrimary.withValues(alpha: 0.25)
                    : colorScheme.onSurface.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  final double t;
  final Color color;

  const _BlobPainter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.07);

    final b1x = size.width * (0.78 + 0.08 * sin(t * 2 * pi));
    final b1y = size.height * (0.1 + 0.05 * cos(t * 2 * pi * 1.3));
    canvas.drawCircle(Offset(b1x, b1y), size.width * 0.42, paint);

    final b2x = size.width * (0.12 + 0.07 * cos(t * 2 * pi * 0.7));
    final b2y = size.height * (0.82 + 0.06 * sin(t * 2 * pi * 0.9));
    canvas.drawCircle(Offset(b2x, b2y), size.width * 0.36, paint);

    final b3x = size.width * (0.5 + 0.06 * sin(t * 2 * pi * 1.1 + pi));
    final b3y = size.height * (0.48 + 0.04 * cos(t * 2 * pi * 0.8));
    canvas.drawCircle(Offset(b3x, b3y), size.width * 0.26, paint);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => old.t != t;
}
