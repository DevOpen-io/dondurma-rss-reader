import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'RSS Reader'**
  String get appTitle;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Dondurma Rss Reader'**
  String get appName;

  /// No description provided for @feedsTab.
  ///
  /// In en, this message translates to:
  /// **'Feeds'**
  String get feedsTab;

  /// No description provided for @foldersTab.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get foldersTab;

  /// No description provided for @bookmarksTab.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarksTab;

  /// No description provided for @settingsTab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTab;

  /// No description provided for @myFeeds.
  ///
  /// In en, this message translates to:
  /// **'My Feeds'**
  String get myFeeds;

  /// No description provided for @searchFeeds.
  ///
  /// In en, this message translates to:
  /// **'Search feeds...'**
  String get searchFeeds;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'YESTERDAY'**
  String get yesterday;

  /// No description provided for @older.
  ///
  /// In en, this message translates to:
  /// **'OLDER'**
  String get older;

  /// No description provided for @subscribedOnly.
  ///
  /// In en, this message translates to:
  /// **'Subscribed Only'**
  String get subscribedOnly;

  /// No description provided for @noFeedsFound.
  ///
  /// In en, this message translates to:
  /// **'No feeds found. Add a new feed using the + button.'**
  String get noFeedsFound;

  /// No description provided for @noFeedsInCategory.
  ///
  /// In en, this message translates to:
  /// **'No feeds found in {category}.'**
  String noFeedsInCategory(String category);

  /// No description provided for @noFeedsMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'No feeds match your current filter.'**
  String get noFeedsMatchFilter;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — showing cached articles.'**
  String get offlineBanner;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @allCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up ✓'**
  String get allCaughtUp;

  /// No description provided for @noBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarked articles yet.'**
  String get noBookmarks;

  /// No description provided for @noFolders.
  ///
  /// In en, this message translates to:
  /// **'No folders yet. Categories will appear here.'**
  String get noFolders;

  /// No description provided for @renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename Folder'**
  String get renameFolder;

  /// No description provided for @folderName.
  ///
  /// In en, this message translates to:
  /// **'Folder Name'**
  String get folderName;

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete Folder'**
  String get deleteFolder;

  /// No description provided for @deleteFolderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the folder \"{categoryName}\"?\n\nThis will permanently remove all {feedCount} RSS feeds inside it from your subscriptions.'**
  String deleteFolderConfirm(String categoryName, int feedCount);

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete All'**
  String get deleteAll;

  /// No description provided for @editFeed.
  ///
  /// In en, this message translates to:
  /// **'Edit Feed'**
  String get editFeed;

  /// No description provided for @feedName.
  ///
  /// In en, this message translates to:
  /// **'Feed Name'**
  String get feedName;

  /// No description provided for @feedUrl.
  ///
  /// In en, this message translates to:
  /// **'Feed URL'**
  String get feedUrl;

  /// No description provided for @deleteFeed.
  ///
  /// In en, this message translates to:
  /// **'Delete Feed'**
  String get deleteFeed;

  /// No description provided for @deleteFeedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to completely remove \"{feedName}\" from your subscriptions?'**
  String deleteFeedConfirm(String feedName);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @addRssFeed.
  ///
  /// In en, this message translates to:
  /// **'Add RSS Feed'**
  String get addRssFeed;

  /// No description provided for @feedUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Feed URL'**
  String get feedUrlLabel;

  /// No description provided for @feedUrlHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://techcrunch.com/feed/'**
  String get feedUrlHint;

  /// No description provided for @siteNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Site Name'**
  String get siteNameLabel;

  /// No description provided for @categoryOptional.
  ///
  /// In en, this message translates to:
  /// **'Category (Optional)'**
  String get categoryOptional;

  /// No description provided for @categoryHint.
  ///
  /// In en, this message translates to:
  /// **'Technology, News, etc.'**
  String get categoryHint;

  /// No description provided for @pleaseEnterUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter a URL'**
  String get pleaseEnterUrl;

  /// No description provided for @pleaseEnterValidUrl.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL'**
  String get pleaseEnterValidUrl;

  /// No description provided for @pleaseEnterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get pleaseEnterName;

  /// No description provided for @saveFeed.
  ///
  /// In en, this message translates to:
  /// **'Save Feed'**
  String get saveFeed;

  /// No description provided for @errorAddingFeed.
  ///
  /// In en, this message translates to:
  /// **'Error adding feed: {error}'**
  String errorAddingFeed(String error);

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'CATEGORIES'**
  String get categories;

  /// No description provided for @allNews.
  ///
  /// In en, this message translates to:
  /// **'All News'**
  String get allNews;

  /// No description provided for @uncategorized.
  ///
  /// In en, this message translates to:
  /// **'UNCATEGORIZED'**
  String get uncategorized;

  /// No description provided for @randomBlogs.
  ///
  /// In en, this message translates to:
  /// **'Random Blogs'**
  String get randomBlogs;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'DISCOVER'**
  String get discover;

  /// No description provided for @suggestedFeeds.
  ///
  /// In en, this message translates to:
  /// **'Suggested Feeds'**
  String get suggestedFeeds;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @noFeedsInThisCategory.
  ///
  /// In en, this message translates to:
  /// **'No feeds in this category'**
  String get noFeedsInThisCategory;

  /// No description provided for @addSubscription.
  ///
  /// In en, this message translates to:
  /// **'Add Subscription'**
  String get addSubscription;

  /// No description provided for @addSubscriptionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to add \"{name}\" to your feed list?'**
  String addSubscriptionConfirm(String name);

  /// No description provided for @addSource.
  ///
  /// In en, this message translates to:
  /// **'Add Source'**
  String get addSource;

  /// No description provided for @addedSubscription.
  ///
  /// In en, this message translates to:
  /// **'Added {name} to your subscriptions!'**
  String addedSubscription(String name);

  /// No description provided for @suggestedFeedsWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning: Some RSS sources may be broken or no longer work.'**
  String get suggestedFeedsWarning;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @selectAppStyle.
  ///
  /// In en, this message translates to:
  /// **'Select application style'**
  String get selectAppStyle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @changeAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change the app language'**
  String get changeAppLanguage;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @turkish.
  ///
  /// In en, this message translates to:
  /// **'Türkçe'**
  String get turkish;

  /// No description provided for @dataAndStorage.
  ///
  /// In en, this message translates to:
  /// **'Data & Storage'**
  String get dataAndStorage;

  /// No description provided for @offlineCacheLimit.
  ///
  /// In en, this message translates to:
  /// **'Offline Cache Limit'**
  String get offlineCacheLimit;

  /// No description provided for @offlineCacheLimitDesc.
  ///
  /// In en, this message translates to:
  /// **'Recent articles kept for offline reading'**
  String get offlineCacheLimitDesc;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @autoRefreshFeeds.
  ///
  /// In en, this message translates to:
  /// **'Auto Refresh Feeds'**
  String get autoRefreshFeeds;

  /// No description provided for @autoRefreshFeedsDesc.
  ///
  /// In en, this message translates to:
  /// **'How often feeds sync in background'**
  String get autoRefreshFeedsDesc;

  /// No description provided for @thirtySeconds.
  ///
  /// In en, this message translates to:
  /// **'30 Seconds'**
  String get thirtySeconds;

  /// No description provided for @oneMinute.
  ///
  /// In en, this message translates to:
  /// **'1 Minute'**
  String get oneMinute;

  /// No description provided for @fiveMinutes.
  ///
  /// In en, this message translates to:
  /// **'5 Minutes'**
  String get fiveMinutes;

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get clearCache;

  /// No description provided for @clearCacheDesc.
  ///
  /// In en, this message translates to:
  /// **'Remove downloaded articles to free up space'**
  String get clearCacheDesc;

  /// No description provided for @cacheClearedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared successfully.'**
  String get cacheClearedSuccess;

  /// No description provided for @syncBackground.
  ///
  /// In en, this message translates to:
  /// **'Sync Background'**
  String get syncBackground;

  /// No description provided for @syncBackgroundDesc.
  ///
  /// In en, this message translates to:
  /// **'Fetch new articles while app is open'**
  String get syncBackgroundDesc;

  /// No description provided for @exportSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Export Subscriptions (OPML)'**
  String get exportSubscriptions;

  /// No description provided for @exportSubscriptionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Backup your feeds to a file'**
  String get exportSubscriptionsDesc;

  /// No description provided for @noSubscriptionsToExport.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions to export.'**
  String get noSubscriptionsToExport;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions exported successfully.'**
  String get exportSuccess;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed. Please try again.'**
  String get exportFailed;

  /// No description provided for @importSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Import Subscriptions (OPML)'**
  String get importSubscriptions;

  /// No description provided for @importSubscriptionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Restore feeds from an OPML file'**
  String get importSubscriptionsDesc;

  /// No description provided for @noFeedsFoundOrCancelled.
  ///
  /// In en, this message translates to:
  /// **'No feeds found or import was cancelled.'**
  String get noFeedsFoundOrCancelled;

  /// No description provided for @importedFeeds.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} new feed{count, plural, =1{} other{s}}.'**
  String importedFeeds(int count);

  /// No description provided for @allFeedsExist.
  ///
  /// In en, this message translates to:
  /// **'All feeds already exist — nothing new imported.'**
  String get allFeedsExist;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @versionDesc.
  ///
  /// In en, this message translates to:
  /// **'Current build of Dondurma Rss Reader'**
  String get versionDesc;

  /// No description provided for @rateTheApp.
  ///
  /// In en, this message translates to:
  /// **'Rate the App'**
  String get rateTheApp;

  /// No description provided for @rateTheAppDesc.
  ///
  /// In en, this message translates to:
  /// **'Support the development on the App Store'**
  String get rateTheAppDesc;

  /// No description provided for @displayAndReadability.
  ///
  /// In en, this message translates to:
  /// **'Display & Readability'**
  String get displayAndReadability;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get fontSize;

  /// No description provided for @fontSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get fontSizeMedium;

  /// No description provided for @fontSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fontSizeLarge;

  /// No description provided for @fontSizeXl.
  ///
  /// In en, this message translates to:
  /// **'Extra Large'**
  String get fontSizeXl;

  /// No description provided for @typeface.
  ///
  /// In en, this message translates to:
  /// **'Typeface'**
  String get typeface;

  /// No description provided for @typefaceDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get typefaceDefault;

  /// No description provided for @typefaceSerif.
  ///
  /// In en, this message translates to:
  /// **'Serif'**
  String get typefaceSerif;

  /// No description provided for @typefaceSansSerif.
  ///
  /// In en, this message translates to:
  /// **'Sans-Serif'**
  String get typefaceSansSerif;

  /// No description provided for @typefaceMono.
  ///
  /// In en, this message translates to:
  /// **'Monospace'**
  String get typefaceMono;

  /// No description provided for @lineSpacing.
  ///
  /// In en, this message translates to:
  /// **'Line Spacing'**
  String get lineSpacing;

  /// No description provided for @lineSpacingTight.
  ///
  /// In en, this message translates to:
  /// **'Tight'**
  String get lineSpacingTight;

  /// No description provided for @lineSpacingNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get lineSpacingNormal;

  /// No description provided for @lineSpacingRelaxed.
  ///
  /// In en, this message translates to:
  /// **'Relaxed'**
  String get lineSpacingRelaxed;

  /// No description provided for @contentFiltering.
  ///
  /// In en, this message translates to:
  /// **'Content Filtering'**
  String get contentFiltering;

  /// No description provided for @globalExcludedKeywords.
  ///
  /// In en, this message translates to:
  /// **'Global Excluded Keywords'**
  String get globalExcludedKeywords;

  /// No description provided for @globalExcludedKeywordsDesc.
  ///
  /// In en, this message translates to:
  /// **'Hide articles containing these words across all feeds'**
  String get globalExcludedKeywordsDesc;

  /// No description provided for @excludedKeywords.
  ///
  /// In en, this message translates to:
  /// **'Excluded Keywords'**
  String get excludedKeywords;

  /// No description provided for @excludedKeywordsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. ad, sponsor, spoiler'**
  String get excludedKeywordsHint;

  /// No description provided for @commaSeparated.
  ///
  /// In en, this message translates to:
  /// **'Comma separated'**
  String get commaSeparated;

  /// No description provided for @addKeyword.
  ///
  /// In en, this message translates to:
  /// **'Add Keyword'**
  String get addKeyword;

  /// No description provided for @noKeywordsAdded.
  ///
  /// In en, this message translates to:
  /// **'No keywords added yet.'**
  String get noKeywordsAdded;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in Browser'**
  String get openInBrowser;

  /// No description provided for @readOnOriginalWebpage.
  ///
  /// In en, this message translates to:
  /// **'Read on Original Webpage'**
  String get readOnOriginalWebpage;

  /// No description provided for @invalidUrlFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid URL format'**
  String get invalidUrlFormat;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @openInExternalBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in External Browser'**
  String get openInExternalBrowser;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @themeSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get themeSystemDefault;

  /// No description provided for @themeLightClassic.
  ///
  /// In en, this message translates to:
  /// **'Light (Classic)'**
  String get themeLightClassic;

  /// No description provided for @themeDarkClassic.
  ///
  /// In en, this message translates to:
  /// **'Dark (Classic)'**
  String get themeDarkClassic;

  /// No description provided for @themeLatte.
  ///
  /// In en, this message translates to:
  /// **'Latte (Light)'**
  String get themeLatte;

  /// No description provided for @themeFrappe.
  ///
  /// In en, this message translates to:
  /// **'Frappé (Dark)'**
  String get themeFrappe;

  /// No description provided for @themeMacchiato.
  ///
  /// In en, this message translates to:
  /// **'Macchiato (Dark)'**
  String get themeMacchiato;

  /// No description provided for @themeMocha.
  ///
  /// In en, this message translates to:
  /// **'Mocha (Dark)'**
  String get themeMocha;

  /// No description provided for @manageFeeds.
  ///
  /// In en, this message translates to:
  /// **'Manage Feeds'**
  String get manageFeeds;

  /// No description provided for @noFeedsSubscribed.
  ///
  /// In en, this message translates to:
  /// **'No feeds subscribed.\nAdd one from the Home Screen.'**
  String get noFeedsSubscribed;

  /// No description provided for @removeFeed.
  ///
  /// In en, this message translates to:
  /// **'Remove Feed'**
  String get removeFeed;

  /// No description provided for @removeFeedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to stop following \"{name}\"?'**
  String removeFeedConfirm(String name);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @addFolder.
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
  String get addFolder;

  /// No description provided for @newFolderName.
  ///
  /// In en, this message translates to:
  /// **'New Folder Name'**
  String get newFolderName;

  /// No description provided for @folderAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A folder with this name already exists.'**
  String get folderAlreadyExists;

  /// No description provided for @pleaseEnterFolderName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a folder name'**
  String get pleaseEnterFolderName;

  /// No description provided for @moveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to Folder'**
  String get moveToFolder;

  /// No description provided for @moveFeed.
  ///
  /// In en, this message translates to:
  /// **'Move Feed'**
  String get moveFeed;

  /// No description provided for @feedMovedToFolder.
  ///
  /// In en, this message translates to:
  /// **'\"{feedName}\" moved to \"{folderName}\"'**
  String feedMovedToFolder(String feedName, String folderName);

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @enableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable Notifications'**
  String get enableNotifications;

  /// No description provided for @enableNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Get notified about new articles'**
  String get enableNotificationsDesc;

  /// No description provided for @digestMode.
  ///
  /// In en, this message translates to:
  /// **'Notification Mode'**
  String get digestMode;

  /// No description provided for @digestModeDesc.
  ///
  /// In en, this message translates to:
  /// **'How you receive notifications'**
  String get digestModeDesc;

  /// No description provided for @digestInstant.
  ///
  /// In en, this message translates to:
  /// **'Instant'**
  String get digestInstant;

  /// No description provided for @digestDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily Summary'**
  String get digestDaily;

  /// No description provided for @digestWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly Summary'**
  String get digestWeekly;

  /// No description provided for @quietHours.
  ///
  /// In en, this message translates to:
  /// **'Quiet Hours'**
  String get quietHours;

  /// No description provided for @quietHoursDesc.
  ///
  /// In en, this message translates to:
  /// **'Mute notifications during these hours'**
  String get quietHoursDesc;

  /// No description provided for @quietHoursFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get quietHoursFrom;

  /// No description provided for @quietHoursTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get quietHoursTo;

  /// No description provided for @newArticlesNotification.
  ///
  /// In en, this message translates to:
  /// **'{count} new articles'**
  String newArticlesNotification(int count);

  /// No description provided for @feedNotifications.
  ///
  /// In en, this message translates to:
  /// **'Feed Notifications'**
  String get feedNotifications;

  /// No description provided for @notificationsNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Notifications are not supported on this platform'**
  String get notificationsNotSupported;

  /// No description provided for @notificationsSupportedPlatforms.
  ///
  /// In en, this message translates to:
  /// **'Supported platforms: Android, iOS'**
  String get notificationsSupportedPlatforms;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
