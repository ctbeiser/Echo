// Runs only in the background settings page, never in the visible browser.
// Read the websites' own badge results. Only counts cross the bridge.
const hosts = service === 'x'
    ? ['x.com', 'www.x.com', 'twitter.com', 'www.twitter.com', 'mobile.x.com', 'mobile.twitter.com']
    : ['cope.works', 'www.cope.works'];
if (location.protocol !== 'https:' || !hosts.includes(location.hostname)) return;

const originalFetch = window.fetch.bind(window);
let requestVersion = 0;
let blueskyCountPending = false;
let lastNetworkCountAt = 0;
let networkFailed = false;
let retryAfter = 0;
let lastReport = '';
let lastDOMBadge = '';
const startedAt = Date.now();

if (service === 'bluesky') {
    // Let the neutral page run its normal badge initialization. This changes
    // only this monitor document; WebKit still suspends it between samples,
    // and no native window is shown or activated.
    for (const [key, value] of [
        ['visibilityState', 'visible'], ['hidden', false],
        ['webkitVisibilityState', 'visible'], ['webkitHidden', false]
    ]) {
        Object.defineProperty(document, key, {configurable: true, get: () => value});
    }
    if (window.BroadcastChannel) {
        const postMessage = BroadcastChannel.prototype.postMessage;
        BroadcastChannel.prototype.postMessage = function(data) {
            const result = postMessage.call(this, data);
            if (this.name === 'NOTIFS_BROADCAST_CHANNEL' && blueskyCountPending && !networkFailed &&
                typeof data?.event === 'string') {
                const badge = data.event === '' ? {value: 0, lowerBound: false} : parseBadge(data.event);
                if (badge) {
                    blueskyCountPending = false;
                    lastNetworkCountAt = Date.now();
                    report('count', badge.value, badge.lowerBound);
                }
            }
            return result;
        };
    }
}

function report(state, count = null, lowerBound = false, retryAfterSeconds = null) {
    const body = JSON.stringify({state, count, lowerBound, retryAfterSeconds});
    if (body === lastReport && state !== 'count') return;
    lastReport = body;
    window.webkit.messageHandlers.echoNotificationCount.postMessage(body);
}

function validCount(value) {
    return Number.isSafeInteger(value) && value >= 0 && value <= 1000000;
}

function isCountURL(url) {
    if (service === 'x') {
        return hosts.includes(url.hostname) && /\/badge_count(?:\/badge_count)?\.json$/.test(url.pathname);
    }
    return url.pathname === '/xrpc/app.bsky.notification.listNotifications';
}

function acceptResponse(response, version) {
    if (version !== requestVersion) return false;
    if (response.status === 429) {
        const header = response.headers.get('retry-after');
        const seconds = Number(header);
        const date = Date.parse(header || '');
        retryAfter = Date.now() + Math.max(60000,
            Number.isFinite(seconds) ? seconds * 1000 : (date - Date.now()) || 60000);
        networkFailed = true;
        report('rateLimited', null, false, Math.min(31536000, Math.ceil((retryAfter - Date.now()) / 1000)));
        return false;
    }
    if (response.status === 401 || response.status === 403) {
        lastNetworkCountAt = 0;
        networkFailed = true;
        report('unavailable');
        return false;
    }
    if (!response.ok) {
        networkFailed = true;
        report('unavailable');
        return false;
    }
    return true;
}

async function consumeResponse(response, version) {
    if (!acceptResponse(response, version)) return;
    try {
        const body = await response.json();
        if (version !== requestVersion) return;
        const count = body.ntab_unread_count;
        if (validCount(count)) {
            lastNetworkCountAt = Date.now();
            networkFailed = false;
            report('count', count);
        }
    } catch {
        // A site response can change shape. The notification-link badge is a fallback.
    }
}

function isReadMutation(method, url) {
    return method.toUpperCase() !== 'GET' && (
        url.pathname === '/xrpc/app.bsky.notification.updateSeen' ||
        service === 'x' && hosts.includes(url.hostname) && /\/notifications\//.test(url.pathname)
    );
}

window.fetch = function(input, init) {
    const method = init?.method || (input instanceof Request ? input.method : 'GET');
    const url = new URL(input instanceof Request ? input.url : input, location.href);
    if (isReadMutation(method, url)) return Promise.reject(new Error('Echo monitors do not mark notifications read'));
    // Do not clone/consume login or other state-changing request bodies.
    if (method.toUpperCase() !== 'GET') return originalFetch(input, init);
    let request;
    try {
        request = new Request(input instanceof Request ? input.clone() : input, init);
    } catch {
        return originalFetch(input, init);
    }
    // A badge broadcast is fresh only after the website's authenticated,
    // first-page request for all notification types succeeds. The website
    // then applies its own moderation/mute rules and includes repost activity.
    const isBlueskyBadgeRequest = service === 'bluesky' && url.protocol === 'https:' && isCountURL(url) &&
        !url.searchParams.has('cursor') && !url.searchParams.getAll('reasons').some(Boolean) &&
        /^Bearer\s/i.test(request.headers.get('authorization') || '');
    if (isBlueskyBadgeRequest) {
        requestVersion += 1;
        blueskyCountPending = false;
    }
    const version = requestVersion;
    const result = originalFetch(input, init);
    if (service === 'x' && isCountURL(new URL(request.url))) {
        void result.then(response => consumeResponse(response.clone(), version)).catch(() => {});
    } else if (isBlueskyBadgeRequest) {
        void result.then(response => {
            if (acceptResponse(response, version)) {
                networkFailed = false;
                blueskyCountPending = true;
            }
        }).catch(() => {
            if (version === requestVersion) {
                networkFailed = true;
                report('unavailable');
            }
        });
    }
    return result;
};

// X also uses XMLHttpRequest. Observe its normal notification-count response.
const xhrOpen = XMLHttpRequest.prototype.open;
const xhrSetHeader = XMLHttpRequest.prototype.setRequestHeader;
const xhrSend = XMLHttpRequest.prototype.send;
const requests = new WeakMap();
XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    requests.set(this, {method, url: new URL(url, location.href), headers: new Headers()});
    return xhrOpen.call(this, method, url, ...rest);
};
XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
    requests.get(this)?.headers.append(name, value);
    return xhrSetHeader.call(this, name, value);
};
XMLHttpRequest.prototype.send = function(...args) {
    const info = requests.get(this);
    if (info && isReadMutation(info.method, info.url)) {
        this.abort();
        return;
    }
    if (info && info.method.toUpperCase() === 'GET') {
        const version = requestVersion;
        if (service === 'x' && isCountURL(info.url)) {
            this.addEventListener('load', () => {
                const body = this.responseType === 'json' ? JSON.stringify(this.response) :
                    this.responseType === '' || this.responseType === 'text' ? this.responseText : null;
                if (body !== null && this.status >= 200) {
                    void consumeResponse(new Response(body, {
                        status: this.status,
                        headers: {'retry-after': this.getResponseHeader('retry-after') || ''}
                    }), version);
                }
            }, {once: true});
        }
    }
    return xhrSend.apply(this, args);
};

function parseBadge(text) {
    const match = text.trim().match(/^(\d[\d,\s]*)(\+)?$/);
    if (!match) return null;
    const value = Number(match[1].replace(/[,\s]/g, ''));
    return validCount(value) ? {value, lowerBound: Boolean(match[2])} : null;
}

function readBadge(allowSettledZero = false) {
    if (networkFailed || lastNetworkCountAt > 0) return;
    const links = [...document.querySelectorAll(
        'a[data-testid="AppTabBar_Notifications_Link"], a[href="/notifications"], a[href="/notifications/"]'
    )];
    if (!links.length) {
        const loginRoute = /\/(?:i\/flow\/login|login|signin)(?:\/|$)/.test(location.pathname);
        if (loginRoute && document.querySelector('input[autocomplete="username"], input[type="password"], [data-testid="loginButton"]')) {
            report('signedOut');
        }
        return;
    }
    // Bluesky's initial empty badge and DOM updates aren't completion signals.
    // Wait for its fresh, filtered count broadcast, including for a known zero.
    if (service === 'bluesky') return;
    for (const link of links) {
        for (const element of link.querySelectorAll('*')) {
            // Ignore message badges and all other numbers elsewhere on the page.
            if (element.children.length === 0) {
                const badge = parseBadge(element.textContent || '');
                if (badge) {
                    reportBadge(badge);
                    return;
                }
            }
        }
        const label = link.getAttribute('aria-label') || '';
        const match = label.match(/(\d[\d,]*\+?)\s+(?:unread|new)\s+notification/i);
        const badge = match && parseBadge(match[1]);
        if (badge) {
            reportBadge(badge);
            return;
        }
    }
    // X can omit its count request in a hidden tab. After the signed-in shell
    // has settled, its notification link without a badge represents zero in the
    // site's UI. Never infer zero from a missing link or a login/loading page.
    if (service === 'x' && allowSettledZero && Date.now() - startedAt >= 10000 &&
        document.readyState === 'complete' &&
        document.querySelector('[data-testid="SideNav_AccountSwitcher_Button"]') &&
        links.every(link => !/[\p{Number}]|unread|new notification/iu.test(
            `${link.textContent || ''} ${link.getAttribute('aria-label') || ''}`
        ))) {
        reportBadge({value: 0, lowerBound: false});
    }
}

function reportBadge(badge) {
    const signature = JSON.stringify(badge);
    if (signature === lastDOMBadge) return;
    lastDOMBadge = signature;
    report('count', badge.value, badge.lowerBound);
}

window.echoRefreshNotificationCount = function() {
    if (Date.now() < retryAfter) return;
    readBadge(true);
};

// Native navigation policy handles document loads; also keep SPA history changes
// on a neutral page. A hidden monitor must never visit the notifications timeline.
for (const method of ['pushState', 'replaceState']) {
    const original = history[method].bind(history);
    history[method] = function(state, unused, target) {
        if (target != null) {
            const url = new URL(target, location.href);
            if (hosts.includes(url.hostname) && /^\/(notifications(?:\/|$)|home(?:\/|$)|i\/timeline(?:\/|$))/.test(url.pathname)) {
                target = '/settings';
            }
        }
        return original(state, unused, target);
    };
}

let badgeReadScheduled = false;
const observer = new MutationObserver(() => {
    if (badgeReadScheduled) return;
    badgeReadScheduled = true;
    setTimeout(() => {
        badgeReadScheduled = false;
        readBadge();
    }, 300);
});
observer.observe(document, {childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['aria-label']});
