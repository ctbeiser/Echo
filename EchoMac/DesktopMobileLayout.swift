import WebKit

enum DesktopMobileLayout {
    static let twitterScript = WKUserScript(
        source: """
        (() => {
          if (window.top !== window || location.protocol !== 'https:' ||
              !['x.com', 'www.x.com', 'mobile.x.com', 'twitter.com', 'www.twitter.com', 'mobile.twitter.com'].includes(location.hostname)) return;

          // Twitter chooses its phone navigation using screen dimensions.
          // Give this embedded mobile page its viewport as its screen before
          // the site initializes its layout and caches those dimensions.
          Object.defineProperties(window.screen, {
            width: { configurable: true, get: () => window.innerWidth },
            height: { configurable: true, get: () => window.innerHeight },
            availWidth: { configurable: true, get: () => window.innerWidth },
            availHeight: { configurable: true, get: () => window.innerHeight }
          });
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )
}
