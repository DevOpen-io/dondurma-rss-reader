import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/suggested_feed.dart';
import '../providers/feed_provider.dart';
import '../providers/subscription_provider.dart';
import '../router/onboarding_state.dart';
import '../services/suggested_feeds_service.dart';
import '../utils/motion.dart';
import '../utils/platform_caps.dart';
import '../widgets/constrained_width.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final TabController _tabController;

  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _contentFade;

  final _service = SuggestedFeedsService();
  List<SuggestedFeed> _globalFeeds = [];
  List<SuggestedFeed> _trFeeds = [];
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

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();

    _headerFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );

    _headerSlide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
          ),
        );

    _contentFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
    );

    _tabController = TabController(length: 2, vsync: this);

    _loadGlobalFeeds();
    _loadTrFeeds();
  }

  bool _motionPreferenceApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionPreferenceApplied) return;
    _motionPreferenceApplied = true;
    // Reduced motion: jump the entrance animation straight to its end
    // state instead of animating content in.
    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGlobalFeeds() async {
    try {
      final feeds = await _service.fetchGlobal();
      if (!mounted) return;
      setState(() {
        _globalFeeds = feeds;
        _loadingGlobal = false;
      });
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
      final feeds = await _service.fetchTurkish();
      if (!mounted) return;
      setState(() {
        _trFeeds = feeds;
        _loadingTr = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingTr = false;
          _errorTr = true;
        });
      }
    }
  }

  /// Most popular first; categories without any popular feed are not
  /// offered.
  List<String> _categoriesFor(List<SuggestedFeed> feeds) {
    final maxPop = SuggestedFeed.categoryPopularity(feeds);
    return maxPop.keys.toList()
      ..sort((a, b) => (maxPop[b] ?? 0).compareTo(maxPop[a] ?? 0));
  }

  List<SuggestedFeed> _topFeedsFor(List<SuggestedFeed> feeds, String cat) {
    return (feeds.where((f) => f.category == cat).toList()
          ..sort((a, b) => a.name.compareTo(b.name)))
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
        toAdd.add((url: feed.url, name: feed.name, category: feed.category));
      }
    }
    for (final cat in _selectedTr) {
      for (final feed in _topFeedsFor(_trFeeds, cat)) {
        toAdd.add((url: feed.url, name: feed.name, category: feed.category));
      }
    }

    await subscriptionProvider.addFeedsBatch(toAdd);
    feedProvider.refreshAll();
    await Hive.box('settings').put('hasSeenOnboarding', true);
    if (mounted) context.go('/');
  }

  Future<void> _skip() async {
    sessionOnboardingBypassed = true;
    await Hive.box('settings').put('hasSeenOnboarding', true);
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final isDesktop = PlatformCaps.isDesktop;

    return Scaffold(
      body: SafeArea(
        child: ConstrainedWidth(
          // Desktop gets a wide but bounded column; mobile keeps 600.
          maxWidth: isDesktop ? 880 : 600,
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
                          width: isDesktop ? 72 : 64,
                          height: isDesktop ? 72 : 64,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.rss_feed_rounded,
                            size: isDesktop ? 40 : 36,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.onboardingTitle,
                          textAlign: TextAlign.center,
                          style: (isDesktop
                                  ? Theme.of(
                                      context,
                                    ).textTheme.headlineMedium
                                  : Theme.of(
                                      context,
                                    ).textTheme.headlineSmall)
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.onboardingSubtitle,
                          textAlign: TextAlign.center,
                          style: (isDesktop
                                  ? Theme.of(context).textTheme.bodyLarge
                                  : Theme.of(
                                      context,
                                    ).textTheme.bodyMedium)
                              ?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
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
                        onRetry: () {
                          setState(() {
                            _loadingGlobal = true;
                            _errorGlobal = false;
                          });
                          _loadGlobalFeeds();
                        },
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
                        onRetry: () {
                          setState(() {
                            _loadingTr = true;
                            _errorTr = false;
                          });
                          _loadTrFeeds();
                        },
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
      ),
    );
  }

  Widget _buildContent({
    required List<SuggestedFeed> feeds,
    required bool loading,
    required bool error,
    required Set<String> selected,
    required void Function(String) onToggle,
    required VoidCallback onRetry,
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
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    final categories = _categoriesFor(feeds);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: categories
            .map(
              (cat) => _CategoryChip(
                label: cat,
                selected: selected.contains(cat),
                colorScheme: colorScheme,
                desktop: PlatformCaps.isDesktop,
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
          if (!_bothError) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _isSubmitting ? null : _skip,
              child: Text(l10n.onboardingSkip),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ColorScheme colorScheme;
  final bool desktop;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.colorScheme,
    required this.onTap,
    this.desktop = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: motionDuration(context, const Duration(milliseconds: 200)),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: desktop ? 18 : 14,
          vertical: desktop ? 13 : 10,
        ),
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
              Icon(
                Icons.check_rounded,
                size: desktop ? 16 : 14,
                color: colorScheme.onPrimary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: desktop ? 14.5 : 13,
                fontWeight: FontWeight.w600,
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
