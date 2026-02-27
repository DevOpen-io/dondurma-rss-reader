// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'RSS Reader';

  @override
  String get appName => 'Ice Cream Reader';

  @override
  String get feedsTab => 'Feeds';

  @override
  String get foldersTab => 'Folders';

  @override
  String get bookmarksTab => 'Bookmarks';

  @override
  String get settingsTab => 'Settings';

  @override
  String get myFeeds => 'My Feeds';

  @override
  String get searchFeeds => 'Search feeds...';

  @override
  String get today => 'TODAY';

  @override
  String get yesterday => 'YESTERDAY';

  @override
  String get older => 'OLDER';

  @override
  String get subscribedOnly => 'Subscribed Only';

  @override
  String get noFeedsFound =>
      'No feeds found. Add a new feed using the + button.';

  @override
  String noFeedsInCategory(String category) {
    return 'No feeds found in $category.';
  }

  @override
  String get noFeedsMatchFilter => 'No feeds match your current filter.';

  @override
  String get offlineBanner => 'You\'re offline — showing cached articles.';

  @override
  String get loadMore => 'Load more';

  @override
  String get allCaughtUp => 'You\'re all caught up ✓';

  @override
  String get noBookmarks => 'No bookmarked articles yet.';

  @override
  String get noFolders => 'No folders yet. Categories will appear here.';

  @override
  String get renameFolder => 'Rename Folder';

  @override
  String get folderName => 'Folder Name';

  @override
  String get deleteFolder => 'Delete Folder';

  @override
  String deleteFolderConfirm(String categoryName, int feedCount) {
    return 'Are you sure you want to delete the folder \"$categoryName\"?\n\nThis will permanently remove all $feedCount RSS feeds inside it from your subscriptions.';
  }

  @override
  String get deleteAll => 'Delete All';

  @override
  String get editFeed => 'Edit Feed';

  @override
  String get feedName => 'Feed Name';

  @override
  String get feedUrl => 'Feed URL';

  @override
  String get deleteFeed => 'Delete Feed';

  @override
  String deleteFeedConfirm(String feedName) {
    return 'Are you sure you want to completely remove \"$feedName\" from your subscriptions?';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get addRssFeed => 'Add RSS Feed';

  @override
  String get feedUrlLabel => 'Feed URL';

  @override
  String get feedUrlHint => 'e.g. https://techcrunch.com/feed/';

  @override
  String get siteNameLabel => 'Site Name';

  @override
  String get categoryOptional => 'Category (Optional)';

  @override
  String get categoryHint => 'Technology, News, etc.';

  @override
  String get pleaseEnterUrl => 'Please enter a URL';

  @override
  String get pleaseEnterValidUrl => 'Please enter a valid URL';

  @override
  String get pleaseEnterName => 'Please enter a name';

  @override
  String get saveFeed => 'Save Feed';

  @override
  String errorAddingFeed(String error) {
    return 'Error adding feed: $error';
  }

  @override
  String get categories => 'CATEGORIES';

  @override
  String get allNews => 'All News';

  @override
  String get uncategorized => 'UNCATEGORIZED';

  @override
  String get randomBlogs => 'Random Blogs';

  @override
  String get discover => 'DISCOVER';

  @override
  String get suggestedFeeds => 'Suggested Feeds';

  @override
  String get all => 'All';

  @override
  String get noFeedsInThisCategory => 'No feeds in this category';

  @override
  String get addSubscription => 'Add Subscription';

  @override
  String addSubscriptionConfirm(String name) {
    return 'Do you want to add \"$name\" to your feed list?';
  }

  @override
  String get addSource => 'Add Source';

  @override
  String addedSubscription(String name) {
    return 'Added $name to your subscriptions!';
  }

  @override
  String get suggestedFeedsWarning =>
      'Warning: Some RSS sources may be broken or no longer work.';

  @override
  String get general => 'General';

  @override
  String get theme => 'Theme';

  @override
  String get selectAppStyle => 'Select application style';

  @override
  String get language => 'Language';

  @override
  String get changeAppLanguage => 'Change the app language';

  @override
  String get english => 'English';

  @override
  String get turkish => 'Türkçe';

  @override
  String get dataAndStorage => 'Data & Storage';

  @override
  String get offlineCacheLimit => 'Offline Cache Limit';

  @override
  String get offlineCacheLimitDesc =>
      'Recent articles kept for offline reading';

  @override
  String get none => 'None';

  @override
  String get autoRefreshFeeds => 'Auto Refresh Feeds';

  @override
  String get autoRefreshFeedsDesc => 'How often feeds sync in background';

  @override
  String get thirtySeconds => '30 Seconds';

  @override
  String get oneMinute => '1 Minute';

  @override
  String get fiveMinutes => '5 Minutes';

  @override
  String get clearCache => 'Clear Cache';

  @override
  String get clearCacheDesc => 'Remove downloaded articles to free up space';

  @override
  String get cacheClearedSuccess => 'Cache cleared successfully.';

  @override
  String get syncBackground => 'Sync Background';

  @override
  String get syncBackgroundDesc => 'Fetch new articles while app is open';

  @override
  String get exportSubscriptions => 'Export Subscriptions (OPML)';

  @override
  String get exportSubscriptionsDesc => 'Backup your feeds to a file';

  @override
  String get noSubscriptionsToExport => 'No subscriptions to export.';

  @override
  String get exportSuccess => 'Subscriptions exported successfully.';

  @override
  String get exportFailed => 'Export failed. Please try again.';

  @override
  String get importSubscriptions => 'Import Subscriptions (OPML)';

  @override
  String get importSubscriptionsDesc => 'Restore feeds from an OPML file';

  @override
  String get noFeedsFoundOrCancelled =>
      'No feeds found or import was cancelled.';

  @override
  String importedFeeds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 's',
      one: '',
    );
    return 'Imported $count new feed$_temp0.';
  }

  @override
  String get allFeedsExist => 'All feeds already exist — nothing new imported.';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get versionDesc => 'Current build of Ice Cream Reader';

  @override
  String get rateTheApp => 'Rate the App';

  @override
  String get rateTheAppDesc => 'Support the development on the App Store';

  @override
  String get openInBrowser => 'Open in Browser';

  @override
  String get readOnOriginalWebpage => 'Read on Original Webpage';

  @override
  String get invalidUrlFormat => 'Invalid URL format';

  @override
  String get close => 'Close';

  @override
  String get openInExternalBrowser => 'Open in External Browser';

  @override
  String get back => 'Back';

  @override
  String get forward => 'Forward';

  @override
  String get refresh => 'Refresh';

  @override
  String get themeSystemDefault => 'System Default';

  @override
  String get themeLightClassic => 'Light (Classic)';

  @override
  String get themeDarkClassic => 'Dark (Classic)';

  @override
  String get themeLatte => 'Latte (Light)';

  @override
  String get themeFrappe => 'Frappé (Dark)';

  @override
  String get themeMacchiato => 'Macchiato (Dark)';

  @override
  String get themeMocha => 'Mocha (Dark)';

  @override
  String get manageFeeds => 'Manage Feeds';

  @override
  String get noFeedsSubscribed =>
      'No feeds subscribed.\nAdd one from the Home Screen.';

  @override
  String get removeFeed => 'Remove Feed';

  @override
  String removeFeedConfirm(String name) {
    return 'Are you sure you want to stop following \"$name\"?';
  }

  @override
  String get remove => 'Remove';

  @override
  String get addFolder => 'Add Folder';

  @override
  String get newFolderName => 'New Folder Name';

  @override
  String get folderAlreadyExists => 'A folder with this name already exists.';

  @override
  String get pleaseEnterFolderName => 'Please enter a folder name';

  @override
  String get moveToFolder => 'Move to Folder';

  @override
  String get moveFeed => 'Move Feed';

  @override
  String feedMovedToFolder(String feedName, String folderName) {
    return '\"$feedName\" moved to \"$folderName\"';
  }
}
