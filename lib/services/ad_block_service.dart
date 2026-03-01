/// Built-in ad-blocking utility for the in-app browser.
///
/// Uses two complementary strategies:
/// 1. **Domain-level blocking** — [shouldBlockUrl] checks whether a
///    navigation request targets a known ad/tracker domain.
/// 2. **Element-level hiding** — [adBlockScript] is a JavaScript snippet
///    injected after page load that hides common ad containers via CSS and
///    a `MutationObserver` for dynamically inserted ads.
class AdBlockService {
  AdBlockService._();

  // ---------------------------------------------------------------------------
  // Blocked ad / tracker domains
  // ---------------------------------------------------------------------------

  /// Common advertising and tracking domains.
  ///
  /// Entries are matched against the **host** portion of a URL. A host matches
  /// if it equals or ends with `.<domain>`.
  static const Set<String> _blockedDomains = {
    // Google Ads & Analytics
    'pagead2.googlesyndication.com',
    'googleads.g.doubleclick.net',
    'ad.doubleclick.net',
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'google-analytics.com',
    'googletagmanager.com',
    'googletagservices.com',
    'adservice.google.com',
    'pagead2.googleadservices.com',

    // Facebook / Meta
    'connect.facebook.net',
    'pixel.facebook.com',
    'an.facebook.com',

    // Amazon Ads
    'aax.amazon-adsystem.com',
    'amazon-adsystem.com',
    'assoc-amazon.com',

    // Major ad networks
    'ads.pubmatic.com',
    'pubmatic.com',
    'openx.net',
    'casalemedia.com',
    'contextweb.com',
    'rubiconproject.com',
    'indexww.com',
    'bidswitch.net',
    'smartadserver.com',
    'adnxs.com',
    'adsrvr.org',
    'criteo.com',
    'criteo.net',
    'outbrain.com',
    'widgets.outbrain.com',
    'taboola.com',
    'cdn.taboola.com',
    'trc.taboola.com',
    'revjet.com',
    'revcontent.com',
    'mgid.com',
    'zergnet.com',
    'adroll.com',

    // Tracking / analytics
    'scorecardresearch.com',
    'quantserve.com',
    'bluekai.com',
    'addthis.com',
    'adsymptotic.com',
    'adform.net',
    'moatads.com',
    'serving-sys.com',
    'media.net',
    'amplitude.com',
    'mixpanel.com',
    'segment.io',
    'hotjar.com',
    'mouseflow.com',
    'fullstory.com',

    // Pop-up / pop-under networks
    'propellerads.com',
    'popcash.net',
    'popads.net',
    'clickadu.com',
    'exoclick.com',

    // Miscellaneous
    'adcolony.com',
    'unity3d.com',
    'applovin.com',
    'inmobi.com',
    'smaato.net',
    'mopub.com',
    'chartboost.com',
    'vungle.com',
    'fyber.com',
    'ironsrc.com',
  };

  /// Returns `true` when the [url] should be blocked because its host belongs
  /// to a known ad or tracker domain.
  static bool shouldBlockUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;

    for (final domain in _blockedDomains) {
      if (host == domain || host.endsWith('.$domain')) {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Element-hiding JavaScript + CSS
  // ---------------------------------------------------------------------------

  /// JavaScript snippet to inject after page load.
  ///
  /// 1. Creates a `<style>` tag that hides the most common ad selectors.
  /// 2. Sets up a `MutationObserver` to re-hide ads that are loaded lazily
  ///    or injected after DOMContentLoaded.
  static const String adBlockScript = r'''
(function() {
  // 1. Inject CSS to hide common ad elements
  var style = document.createElement('style');
  style.type = 'text/css';
  style.textContent = [
    /* Google Ads */
    '.adsbygoogle',
    'ins.adsbygoogle',
    '[id^="google_ads"]',
    '[id^="div-gpt-ad"]',
    '[class*="google-ad"]',
    'iframe[src*="doubleclick.net"]',
    'iframe[src*="googlesyndication"]',
    'iframe[src*="googleads"]',
    /* Generic ad containers */
    '[class*="ad-container"]',
    '[class*="ad-wrapper"]',
    '[class*="ad-banner"]',
    '[class*="ad-slot"]',
    '[class*="ad-unit"]',
    '[class*="ad-block"]',
    '[class*="ad-placement"]',
    '[class*="advertisement"]',
    '[id*="ad-container"]',
    '[id*="ad-wrapper"]',
    '[id*="ad-banner"]',
    '[id*="advertisement"]',
    '[data-ad]',
    '[data-ad-slot]',
    '[data-ad-client]',
    '[data-google-query-id]',
    /* Taboola, Outbrain, Revcontent */
    '.taboola-container',
    '[id^="taboola-"]',
    '.OUTBRAIN',
    '[data-widget-id*="outbrain"]',
    '.rc-cta-widget',
    /* Popup / overlay ads */
    '[class*="popup-ad"]',
    '[class*="modal-ad"]',
    '[class*="interstitial"]',
    '[class*="overlay-ad"]',
    /* Sponsored content */
    '[class*="sponsored"]',
    '[class*="promoted-content"]',
    '[class*="native-ad"]'
  ].join(', ') + ' { display: none !important; visibility: hidden !important; height: 0 !important; overflow: hidden !important; }';
  document.head.appendChild(style);

  // 2. MutationObserver for dynamically injected ads
  var selectors = [
    '.adsbygoogle', 'ins.adsbygoogle', '[id^="google_ads"]',
    '[id^="div-gpt-ad"]', '[class*="ad-container"]', '[class*="ad-wrapper"]',
    '[class*="ad-banner"]', '[class*="ad-slot"]', '[class*="advertisement"]',
    '[data-ad]', '[data-ad-slot]', '.taboola-container', '[id^="taboola-"]',
    '.OUTBRAIN', '[class*="sponsored"]', '[class*="native-ad"]',
    'iframe[src*="doubleclick"]', 'iframe[src*="googlesyndication"]'
  ].join(', ');

  function hideAds() {
    var ads = document.querySelectorAll(selectors);
    for (var i = 0; i < ads.length; i++) {
      ads[i].style.display = 'none';
      ads[i].style.visibility = 'hidden';
    }
  }

  hideAds();

  var observer = new MutationObserver(function(mutations) {
    hideAds();
  });
  observer.observe(document.body || document.documentElement, {
    childList: true,
    subtree: true
  });
})();
''';
}
