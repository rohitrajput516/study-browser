import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StudyBrowserApp());
}

class StudyBrowserApp extends StatelessWidget {
  const StudyBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Study Browser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF12151C),
        primaryColor: const Color(0xFFA8C7FA),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFA8C7FA),
          secondary: Color(0xFF8AB4F8),
          surface: Color(0xFF1E232E),
        ),
        dividerColor: const Color(0xFF2D3343),
      ),
      home: const BrowserHomeScreen(),
    );
  }
}

class LockGroup {
  String id;
  String name;
  List<String> domains;
  String passwordHash;
  bool isLocked;
  int tempUnlockUntil;

  LockGroup({
    required this.id,
    required this.name,
    required this.domains,
    required this.passwordHash,
    required this.isLocked,
    this.tempUnlockUntil = 0,
  });

  bool get isCurrentlyActive {
    if (!isLocked) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (tempUnlockUntil > now) return false;
    return true;
  }

  int get remainingTempSeconds {
    final diff = tempUnlockUntil - DateTime.now().millisecondsSinceEpoch;
    return diff > 0 ? (diff ~/ 1000) : 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': id.isEmpty ? 'group' : name,
        'domains': domains,
        'passwordHash': passwordHash,
        'isLocked': isLocked,
        'tempUnlockUntil': tempUnlockUntil,
      };

  factory LockGroup.fromJson(Map<String, dynamic> json) => LockGroup(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? 'Group').toString(),
        domains: List<String>.from(json['domains'] ?? []),
        passwordHash: (json['passwordHash'] ?? '').toString(),
        isLocked: json['isLocked'] == true,
        tempUnlockUntil: (json['tempUnlockUntil'] ?? 0) as int,
      );
}

class BookmarkItem {
  String title;
  String url;

  BookmarkItem({required this.title, required this.url});

  Map<String, dynamic> toJson() => {'title': title, 'url': url};

  factory BookmarkItem.fromJson(Map<String, dynamic> json) => BookmarkItem(
        title: (json['title'] ?? 'Bookmark').toString(),
        url: (json['url'] ?? 'https://www.google.com').toString(),
      );
}

class HistoryItem {
  String title;
  String url;
  String timestamp;

  HistoryItem({
    required this.title,
    required this.url,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'timestamp': timestamp,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        title: (json['title'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        timestamp: (json['timestamp'] ?? '').toString(),
      );
}

class BrowserTab {
  String id;
  String title;
  String url;
  bool isIncognito;
  bool isDesktop;

  BrowserTab({
    required this.id,
    required this.title,
    required this.url,
    this.isIncognito = false,
    this.isDesktop = false,
  });
}

class BrowserHomeScreen extends StatefulWidget {
  const BrowserHomeScreen({super.key});

  @override
  State<BrowserHomeScreen> createState() => _BrowserHomeScreenState();
}

class _BrowserHomeScreenState extends State<BrowserHomeScreen> {
  static const MethodChannel _intentChannel =
      MethodChannel('study_browser/intent');

  static const String _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; RMX3395) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
  static const String _desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  late final WebViewController _webController;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _findController = TextEditingController();

  Timer? _lockEnforcementTimer;
  bool _webViewReady = false;

  int _loadingProgress = 0;
  String _currentUrl = 'https://www.google.com';
  String _pageTitle = 'Google';

  // Browser Enhancements State
  bool _isDesktopMode = false;
  bool _isIncognito = false;
  bool _isReadingMode = false;
  bool _showFindBar = false;
  bool _showZoomBar = false;
  int _zoomPercent = 100;

  List<BrowserTab> _tabs = [];
  int _activeTabIndex = 0;

  // Focus & Feature Locks State
  bool _blockYtShorts = true;
  bool _hideYtFeed = false;
  bool _blockIgReels = true;
  bool _whitelistMode = false;
  String _featurePassHash = '';
  int _featureTempUnlockUntil = 0;

  List<String> _whitelistedDomains = [
    'google.com',
    'google.co.in',
    'youtube.com',
    'wikipedia.org',
    'ncert.nic.in',
    'upsc.gov.in',
    'github.com',
    'vercel.app',
  ];

  List<LockGroup> _lockGroups = [];
  List<BookmarkItem> _bookmarks = [];
  List<HistoryItem> _history = [];
  List<String> _downloads = [];

  // Blocked Overlay State
  bool _isPageBlocked = false;
  String _blockedUrl = '';
  String _blockedReason = '';
  LockGroup? _blockingGroup;

  static const String _focusFilterJs = r'''
    (function() {
      function applyRules() {
        var host = (window.location.hostname || '').toLowerCase();
        var path = window.location.pathname || '';

        // Desktop Viewport Enforcement
        var vpMeta = document.querySelector('meta[name="viewport"]');
        if (window.__SB_DESKTOP_MODE) {
          if (!vpMeta) {
            vpMeta = document.createElement('meta');
            vpMeta.name = 'viewport';
            document.head.appendChild(vpMeta);
          }
          if (vpMeta.getAttribute('content') !== 'width=1280, initial-scale=0.35, user-scalable=yes') {
            vpMeta.setAttribute('content', 'width=1280, initial-scale=0.35, user-scalable=yes');
          }
        } else {
          if (vpMeta && vpMeta.getAttribute('content') && vpMeta.getAttribute('content').includes('width=1280')) {
            vpMeta.setAttribute('content', 'width=device-width, initial-scale=1.0');
          }
        }

        // Page Zoom Enforcement
        if (document.body && window.__SB_ZOOM_PERCENT) {
          document.body.style.zoom = window.__SB_ZOOM_PERCENT + '%';
        }

        // 1. YouTube Shorts & Feed Control
        if (host.includes('youtube.com')) {
          if (window.__SB_YT_SHORTS) {
            if (path.startsWith('/shorts')) {
              window.location.replace('https://m.youtube.com');
              return;
            }
            var styleId = 'sb-yt-shorts-style';
            if (!document.getElementById(styleId)) {
              var style = document.createElement('style');
              style.id = styleId;
              style.innerHTML = `
                ytm-reel-shelf-renderer,
                ytd-reel-shelf-renderer,
                ytd-rich-shelf-renderer[is-shorts],
                ytm-shorts-lockup-view-model,
                ytm-shorts-lockup-view-model-v2,
                [is-shorts],
                a[href^="/shorts"],
                a[href*="/shorts/"],
                ytm-pivot-bar-item-renderer:nth-child(2),
                ytd-mini-guide-entry-renderer[aria-label="Shorts"],
                ytd-guide-entry-renderer a[title="Shorts"] {
                  display: none !important;
                }
              `;
              document.head.appendChild(style);
            }
          } else {
            var el = document.getElementById('sb-yt-shorts-style');
            if (el) el.remove();
          }

          if (window.__SB_YT_FEED) {
            var feedStyleId = 'sb-yt-feed-style';
            if (!document.getElementById(feedStyleId)) {
              var style2 = document.createElement('style');
              style2.id = feedStyleId;
              style2.innerHTML = `
                ytm-browse[page-subtype="home"],
                div.tab-content[tab-identifier="FEwhat_to_watch"],
                ytd-browse[page-subtype="home"] #contents {
                  display: none !important;
                }
              `;
              document.head.appendChild(style2);
            }
          } else {
            var el2 = document.getElementById('sb-yt-feed-style');
            if (el2) el2.remove();
          }
        }

        // 2. Instagram Reels & Explore Control
        if (host.includes('instagram.com')) {
          if (window.__SB_IG_REELS) {
            if (path.startsWith('/reels') || path.startsWith('/reel/') || path.startsWith('/explore')) {
              window.location.replace('https://www.instagram.com/direct/inbox/');
              return;
            }
            var igStyleId = 'sb-ig-reels-style';
            if (!document.getElementById(igStyleId)) {
              var igStyle = document.createElement('style');
              igStyle.id = igStyleId;
              igStyle.innerHTML = `
                a[href*="/reels/"],
                a[href="/reels/"],
                a[href*="/explore/"],
                a[href="/explore/"] {
                  display: none !important;
                }
              `;
              document.head.appendChild(igStyle);
            }
          } else {
            var igEl = document.getElementById('sb-ig-reels-style');
            if (igEl) igEl.remove();
          }
        }
      }

      if (!window.__SB_INTERVAL_SET) {
        window.__SB_INTERVAL_SET = true;
        setInterval(applyRules, 400);
      }
      applyRules();
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _tabs = [
      BrowserTab(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'New Tab',
        url: 'https://www.google.com',
      ),
    ];
    _setupWebViewController();
    _setupIntentListener();
    _bootBrowser();
    _startLockEnforcementTimer();
  }

  @override
  void dispose() {
    _lockEnforcementTimer?.cancel();
    _urlController.dispose();
    _findController.dispose();
    super.dispose();
  }

  void _startLockEnforcementTimer() {
    // हर 2 सेकंड में चेक करता है कि 10-मिनट अनलॉक खत्म हुआ या नहीं
    _lockEnforcementTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_webViewReady) return;
      if (!_isPageBlocked && _currentUrl.isNotEmpty) {
        final allowed = _evaluateUrl(_currentUrl, showOverlayOnBlock: true);
        if (!allowed) {
          _webController.loadRequest(Uri.parse('about:blank'));
        }
      }
    });
  }

  void _setupIntentListener() {
    // जब ऐप बैकग्राउंड में खुला हो और WhatsApp आदि से किसी लिंक पर क्लिक हो
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNewIntentUrl') {
        final String? incoming = call.arguments as String?;
        if (incoming != null && incoming.trim().isNotEmpty) {
          _loadFromSearchBar(incoming.trim());
        }
      }
    });
  }

  Future<void> _bootBrowser() async {
    await _loadSavedData();
    String? initialExternalUrl;
    try {
      initialExternalUrl =
          await _intentChannel.invokeMethod<String>('getInitialUrl');
    } catch (_) {}

    if (initialExternalUrl != null && initialExternalUrl.trim().isNotEmpty) {
      // बाहर से लिंक क्लिक होने पर सीधा वही लिंक लोड होगा (Lock चेक के साथ)
      _loadFromSearchBar(initialExternalUrl.trim());
    } else {
      // सामान्य तरीके से ऐप खोलने पर Google लोड होगा
      _loadFromSearchBar('https://www.google.com');
    }
  }

  String _hashPassword(String input) {
    final bytes = utf8.encode(input.trim());
    return sha256.convert(bytes).toString();
  }

  String _generateRandomPassword() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%&*';
    final rnd = Random.secure();
    return List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  bool get _isFeatureLockActive {
    if (_featurePassHash.isEmpty) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return _featureTempUnlockUntil <= now;
  }

  int get _featureRemainingTempSeconds {
    final diff = _featureTempUnlockUntil - DateTime.now().millisecondsSinceEpoch;
    return diff > 0 ? (diff ~/ 1000) : 0;
  }

  String _formatSeconds(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _blockYtShorts = prefs.getBool('blockYtShorts') ?? true;
      _hideYtFeed = prefs.getBool('hideYtFeed') ?? false;
      _blockIgReels = prefs.getBool('blockIgReels') ?? true;
      _whitelistMode = prefs.getBool('whitelistMode') ?? false;
      _featurePassHash = prefs.getString('featurePassHash') ?? '';
      _featureTempUnlockUntil = prefs.getInt('featureTempUnlockUntil') ?? 0;

      final savedWhitelist = prefs.getStringList('whitelistedDomains');
      if (savedWhitelist != null && savedWhitelist.isNotEmpty) {
        _whitelistedDomains = savedWhitelist;
      }

      final groupsJson = prefs.getString('lockGroups');
      if (groupsJson != null) {
        final List decoded = jsonDecode(groupsJson);
        _lockGroups = decoded
            .map((e) => LockGroup.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } else {
        _lockGroups = [
          LockGroup(
            id: 'distraction',
            name: 'Distraction',
            domains: ['facebook.com', 'x.com', 'twitter.com', 'reddit.com'],
            passwordHash: '',
            isLocked: false,
          ),
          LockGroup(
            id: 'shopping',
            name: 'Shopping',
            domains: ['amazon.in', 'flipkart.com', 'myntra.com', 'meesho.com'],
            passwordHash: '',
            isLocked: false,
          ),
        ];
      }

      final bmJson = prefs.getString('bookmarks');
      if (bmJson != null) {
        final List decoded = jsonDecode(bmJson);
        _bookmarks = decoded
            .map((e) =>
                BookmarkItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } else {
        _bookmarks = [
          BookmarkItem(title: 'Google Search', url: 'https://www.google.com'),
          BookmarkItem(title: 'YouTube Study', url: 'https://m.youtube.com'),
          BookmarkItem(title: 'NCERT Portal', url: 'https://ncert.nic.in'),
        ];
      }

      final histJson = prefs.getString('historyItems');
      if (histJson != null) {
        final List decoded = jsonDecode(histJson);
        _history = decoded
            .map((e) =>
                HistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      final savedDownloads = prefs.getStringList('downloadsList');
      if (savedDownloads != null) {
        _downloads = savedDownloads;
      }
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('blockYtShorts', _blockYtShorts);
    await prefs.setBool('hideYtFeed', _hideYtFeed);
    await prefs.setBool('blockIgReels', _blockIgReels);
    await prefs.setBool('whitelistMode', _whitelistMode);
    await prefs.setString('featurePassHash', _featurePassHash);
    await prefs.setInt('featureTempUnlockUntil', _featureTempUnlockUntil);
    await prefs.setStringList('whitelistedDomains', _whitelistedDomains);
    await prefs.setString(
      'lockGroups',
      jsonEncode(_lockGroups.map((g) => g.toJson()).toList()),
    );
    await prefs.setString(
      'bookmarks',
      jsonEncode(_bookmarks.map((b) => b.toJson()).toList()),
    );
    await prefs.setString(
      'historyItems',
      jsonEncode(_history.map((h) => h.toJson()).toList()),
    );
    await prefs.setStringList('downloadsList', _downloads);
  }

  void _setupWebViewController() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF12151C))
      ..setUserAgent(_mobileUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _loadingProgress = progress);
            }
            _injectFocusScripts();
          },
          onPageStarted: (url) {
            if (url == 'about:blank') return;
            final allowed = _evaluateUrl(url, showOverlayOnBlock: true);
            if (!allowed) {
              _webController.loadRequest(Uri.parse('about:blank'));
              return;
            }
            if (mounted) {
              setState(() {
                _currentUrl = url;
                _urlController.text = url;
                _syncActiveTab(url: url);
              });
            }
            _injectFocusScripts();
          },
          onPageFinished: (url) async {
            if (url == 'about:blank') return;
            _injectFocusScripts();
            try {
              final titleObj = await _webController
                  .runJavaScriptReturningResult('document.title');
              final cleanTitle =
                  titleObj.toString().replaceAll('"', '').trim();
              if (mounted && cleanTitle.isNotEmpty) {
                setState(() {
                  _pageTitle = cleanTitle;
                  _syncActiveTab(title: cleanTitle, url: url);
                });
              }
              _recordHistory(cleanTitle.isEmpty ? url : cleanTitle, url);
            } catch (_) {
              _recordHistory(url, url);
            }
          },
          onUrlChange: (change) {
            final newUrl = change.url ?? '';
            if (newUrl.isEmpty || newUrl == 'about:blank') return;
            final allowed = _evaluateUrl(newUrl, showOverlayOnBlock: true);
            if (!allowed) {
              _webController.loadRequest(Uri.parse('about:blank'));
              return;
            }
            if (mounted) {
              setState(() {
                _currentUrl = newUrl;
                _urlController.text = newUrl;
                _syncActiveTab(url: newUrl);
              });
            }
            _injectFocusScripts();
          },
          onNavigationRequest: (request) {
            final reqUrl = request.url;
            if (reqUrl == 'about:blank') return NavigationDecision.navigate;

            // डाउनलोड होने वाली फ़ाइलों को पहचानना
            final lower = reqUrl.toLowerCase().split('?').first;
            if (lower.endsWith('.pdf') ||
                lower.endsWith('.zip') ||
                lower.endsWith('.apk') ||
                lower.endsWith('.doc') ||
                lower.endsWith('.docx') ||
                lower.endsWith('.mp3') ||
                lower.endsWith('.mp4')) {
              if (!_downloads.contains(reqUrl)) {
                setState(() => _downloads.insert(0, reqUrl));
                _saveData();
                _showToast('📥 फ़ाइल लिंक Downloads में सेव किया गया');
              }
            }

            final allowed = _evaluateUrl(reqUrl, showOverlayOnBlock: true);
            if (!allowed) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    _webViewReady = true;
  }

  void _syncActiveTab({String? title, String? url}) {
    if (_tabs.isEmpty || _activeTabIndex >= _tabs.length) return;
    final tab = _tabs[_activeTabIndex];
    if (title != null && title.isNotEmpty) tab.title = title;
    if (url != null && url.isNotEmpty) tab.url = url;
    tab.isDesktop = _isDesktopMode;
    tab.isIncognito = _isIncognito;
  }

  void _recordHistory(String title, String url) {
    // Incognito मोड में हिस्ट्री सेव नहीं होगी, लेकिन सारे Locks काम करेंगे
    if (_isIncognito) return;
    if (url.isEmpty || url == 'about:blank') return;
    if (_history.isNotEmpty && _history.first.url == url) return;

    final now = DateTime.now();
    final timeStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _history.insert(
        0,
        HistoryItem(title: title, url: url, timestamp: timeStr),
      );
      if (_history.length > 100) {
        _history.removeLast();
      }
    });
    _saveData();
  }

  Future<void> _injectFocusScripts() async {
    if (!_webViewReady) return;
    try {
      final bool shortsActive =
          _blockYtShorts && (_featurePassHash.isEmpty || _isFeatureLockActive);
      final bool feedActive =
          _hideYtFeed && (_featurePassHash.isEmpty || _isFeatureLockActive);
      final bool igActive =
          _blockIgReels && (_featurePassHash.isEmpty || _isFeatureLockActive);

      final flagsJs = '''
        window.__SB_YT_SHORTS = $shortsActive;
        window.__SB_YT_FEED = $feedActive;
        window.__SB_IG_REELS = $igActive;
        window.__SB_DESKTOP_MODE = $_isDesktopMode;
        window.__SB_ZOOM_PERCENT = $_zoomPercent;
      ''';
      await _webController.runJavaScript(flagsJs);
      await _webController.runJavaScript(_focusFilterJs);
    } catch (_) {}
  }

  bool _domainMatches(String host, String fullUrl, String ruleDomain) {
    final cleanRule = ruleDomain
        .toLowerCase()
        .replaceAll('https://', '')
        .replaceAll('http://', '')
        .replaceAll('www.', '')
        .replaceAll('m.', '')
        .split('/')
        .first
        .trim();
    if (cleanRule.isEmpty) return false;

    final cleanHost =
        host.toLowerCase().replaceAll('www.', '').replaceAll('m.', '');
    if (cleanHost == cleanRule || cleanHost.endsWith('.$cleanRule')) {
      return true;
    }
    final cleanRuleHyphen = cleanRule.replaceAll('.', '-');
    if (fullUrl.toLowerCase().contains(cleanRule) ||
        cleanHost.contains(cleanRuleHyphen)) {
      return true;
    }
    return false;
  }

  bool _evaluateUrl(String url, {bool showOverlayOnBlock = true}) {
    if (url == 'about:blank') return true;
    final uri = Uri.tryParse(url);
    if (uri == null) return true;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final featureEnforced = _featurePassHash.isEmpty || _isFeatureLockActive;

    // 1. Feature Locks (YouTube Shorts & Instagram Reels)
    if (featureEnforced) {
      if (_blockYtShorts &&
          host.contains('youtube.com') &&
          path.startsWith('/shorts')) {
        _showToast('YouTube Shorts लॉक है — केवल स्टडी वीडियो अनुमत हैं');
        return false;
      }
      if (_blockIgReels &&
          host.contains('instagram.com') &&
          (path.startsWith('/reels') ||
              path.startsWith('/reel/') ||
              path.startsWith('/explore'))) {
        _showToast('Instagram Reels और Explore लॉक है');
        return false;
      }
    }

    // 2. Custom Lock Groups Check
    for (final group in _lockGroups) {
      if (group.isCurrentlyActive) {
        for (final domain in group.domains) {
          if (_domainMatches(host, url, domain)) {
            if (showOverlayOnBlock && mounted) {
              setState(() {
                _isPageBlocked = true;
                _blockedUrl = url;
                _blockedReason = 'Lock Group: ${group.name}';
                _blockingGroup = group;
              });
            }
            return false;
          }
        }
      }
    }

    // 3. Exam Whitelist Mode Check
    if (_whitelistMode && featureEnforced) {
      bool allowed = false;
      for (final wDomain in _whitelistedDomains) {
        if (_domainMatches(host, url, wDomain)) {
          allowed = true;
          break;
        }
      }
      if (!allowed) {
        if (showOverlayOnBlock && mounted) {
          setState(() {
            _isPageBlocked = true;
            _blockedUrl = url;
            _blockedReason = 'Exam Whitelist Mode सक्रिय है';
            _blockingGroup = null;
          });
        }
        return false;
      }
    }

    if (_isPageBlocked && showOverlayOnBlock && mounted) {
      setState(() => _isPageBlocked = false);
    }
    return true;
  }

  String _normalizeUrlForMode(String rawUrl) {
    var target = rawUrl;
    if (_isDesktopMode) {
      if (target.contains('://m.youtube.com')) {
        target = target.replaceFirst('://m.youtube.com', '://www.youtube.com');
        if (!target.contains('app=desktop')) {
          target += target.contains('?') ? '&app=desktop' : '?app=desktop';
        }
      } else if (target.contains('.m.wikipedia.org')) {
        target = target.replaceFirst('.m.wikipedia.org', '.wikipedia.org');
      }
    } else {
      if (target.contains('app=desktop')) {
        target = target
            .replaceAll('?app=desktop', '')
            .replaceAll('&app=desktop', '');
      }
    }
    return target;
  }

  void _loadFromSearchBar(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    String targetUrl;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      targetUrl = trimmed;
    } else if (trimmed.contains('.') && !trimmed.contains(' ')) {
      targetUrl = 'https://$trimmed';
    } else {
      targetUrl =
          'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
    }

    targetUrl = _normalizeUrlForMode(targetUrl);

    setState(() {
      _currentUrl = targetUrl;
      _urlController.text = targetUrl;
      _isReadingMode = false;
      _syncActiveTab(url: targetUrl);
    });

    // लिंक लोड करने से पहले Lock चेक करना (बाहरी और अंदरूनी दोनों लिंक्स के लिए)
    final allowed = _evaluateUrl(targetUrl, showOverlayOnBlock: true);
    if (!allowed) {
      _webController.loadRequest(Uri.parse('about:blank'));
      return;
    }

    setState(() => _isPageBlocked = false);
    _webController.loadRequest(Uri.parse(targetUrl));
  }

  Future<void> _toggleDesktopMode() async {
    setState(() {
      _isDesktopMode = !_isDesktopMode;
      _syncActiveTab();
    });
    await _webController.setUserAgent(
      _isDesktopMode ? _desktopUserAgent : _mobileUserAgent,
    );
    final updatedUrl = _normalizeUrlForMode(_currentUrl);
    _showToast(_isDesktopMode
        ? 'Desktop site मोड चालू किया गया'
        : 'Mobile site मोड चालू किया गया');
    _loadFromSearchBar(updatedUrl);
  }

  Future<void> _toggleReadingMode() async {
    setState(() => _isReadingMode = !_isReadingMode);
    if (_isReadingMode) {
      await _webController.runJavaScript(r'''
        (function() {
          if (document.getElementById('sb-reader-overlay')) return;
          var title = document.title || '';
          var paragraphs = Array.from(document.querySelectorAll('article p, main p, p'))
            .map(function(p) { return p.innerText.trim(); })
            .filter(function(t) { return t.length > 40; });
          var contentHtml = paragraphs.length > 0
            ? paragraphs.map(function(p) { return '<p style="margin-bottom:16px;line-height:1.75;font-size:18px;color:#E2E8F0;">' + p + '</p>'; }).join('')
            : '<p style="color:#94A3B8;">इस पेज पर रीडिंग मोड के लिए लंबा टेक्स्ट उपलब्ध नहीं है।</p>';
          var overlay = document.createElement('div');
          overlay.id = 'sb-reader-overlay';
          overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#0F141C;color:#F8FAFC;overflow-y:auto;padding:24px 20px 80px 20px;font-family:sans-serif;';
          overlay.innerHTML = '<div style="max-width:680px;margin:0 auto;"><h1 style="font-size:24px;line-height:1.4;margin-bottom:20px;color:#A8C7FA;border-bottom:1px solid #262F40;padding-bottom:12px;">' + title + '</h1>' + contentHtml + '</div>';
          document.body.appendChild(overlay);
        })();
      ''');
      _showToast('Reading mode चालू किया गया');
    } else {
      await _webController.runJavaScript(r'''
        var el = document.getElementById('sb-reader-overlay');
        if (el) el.remove();
      ''');
      _showToast('Reading mode बंद किया गया');
    }
  }

  void _translateCurrentPage() {
    if (_currentUrl.isEmpty || _currentUrl.startsWith('about:')) return;
    final translateUrl =
        'https://translate.google.com/translate?sl=auto&tl=hi&u=${Uri.encodeComponent(_currentUrl)}';
    _loadFromSearchBar(translateUrl);
    _showToast('पेज को हिंदी में अनुवाद किया जा रहा है...');
  }

  Future<void> _performFindInPage(String query) async {
    if (query.trim().isEmpty) return;
    final safeQuery = query.replaceAll("'", "\\'");
    await _webController.runJavaScript("window.find('$safeQuery');");
  }

  void _createNewTab({bool incognito = false, String? url}) {
    final target = url ?? 'https://www.google.com';
    final newTab = BrowserTab(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: incognito ? 'Incognito Tab' : 'New Tab',
      url: target,
      isIncognito: incognito,
      isDesktop: _isDesktopMode,
    );
    setState(() {
      _tabs.add(newTab);
      _activeTabIndex = _tabs.length - 1;
      _isIncognito = incognito;
    });
    _loadFromSearchBar(target);
    _showToast(incognito
        ? 'New Incognito tab (सभी Focus Locks सक्रिय हैं)'
        : 'New tab खोला गया');
  }

  void _switchToTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    setState(() {
      _activeTabIndex = index;
      _isIncognito = tab.isIncognito;
      _isDesktopMode = tab.isDesktop;
    });
    _webController.setUserAgent(
      _isDesktopMode ? _desktopUserAgent : _mobileUserAgent,
    );
    _loadFromSearchBar(tab.url);
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      _loadFromSearchBar('https://www.google.com');
      return;
    }
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
    _switchToTab(_activeTabIndex);
  }

  bool get _isCurrentPageBookmarked =>
      _bookmarks.any((b) => b.url == _currentUrl);

  Future<void> _toggleCurrentBookmark() async {
    setState(() {
      if (_isCurrentPageBookmarked) {
        _bookmarks.removeWhere((b) => b.url == _currentUrl);
        _showToast('Bookmark हटाया गया');
      } else {
        final uri = Uri.tryParse(_currentUrl);
        final title = _pageTitle.isNotEmpty
            ? _pageTitle
            : (uri?.host.isNotEmpty == true ? uri!.host : 'Saved Page');
        _bookmarks.insert(0, BookmarkItem(title: title, url: _currentUrl));
        _showToast('Bookmark सेव हो गया');
      }
    });
    await _saveData();
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 13.5),
        ),
        backgroundColor: const Color(0xFF1E232E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ===========================================================================
  // CHROME-STYLE 3-DOT POPUP MENU (Screenshots 2 & 3 Layout)
  // ===========================================================================
  void _openChromeStyleMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Browser Menu',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, anim1, anim2) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 52, right: 10),
              child: Material(
                color: const Color(0xFF1E232E),
                elevation: 14,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFF2E3646), width: 1),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints.tightFor(
                      width: 285,
                      )
                    maxHeight: MediaQuery.of(context).size.height * 0.82,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // TOP 5 CHROME ACTION ICONS ROW
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFF2D3343)),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildTopMenuIconButton(
                              icon: Icons.arrow_back,
                              tooltip: 'Back',
                              onTap: () async {
                                Navigator.pop(ctx);
                                if (await _webController.canGoBack()) {
                                  await _webController.goBack();
                                }
                              },
                            ),
                            _buildTopMenuIconButton(
                              icon: Icons.arrow_forward,
                              tooltip: 'Forward',
                              onTap: () async {
                                Navigator.pop(ctx);
                                if (await _webController.canGoForward()) {
                                  await _webController.goForward();
                                }
                              },
                            ),
                            _buildTopMenuIconButton(
                              icon: _isCurrentPageBookmarked
                                  ? Icons.star
                                  : Icons.star_border,
                              iconColor: _isCurrentPageBookmarked
                                  ? const Color(0xFFA8C7FA)
                                  : Colors.white,
                              tooltip: 'Bookmark',
                              onTap: () {
                                Navigator.pop(ctx);
                                _toggleCurrentBookmark();
                              },
                            ),
                            _buildTopMenuIconButton(
                              icon: Icons.download_outlined,
                              tooltip: 'Save Page Link',
                              onTap: () {
                                Navigator.pop(ctx);
                                if (!_downloads.contains(_currentUrl)) {
                                  setState(
                                      () => _downloads.insert(0, _currentUrl));
                                  _saveData();
                                }
                                _showToast('पेज Downloads में जोड़ा गया');
                              },
                            ),
                            _buildTopMenuIconButton(
                              icon: Icons.refresh,
                              tooltip: 'Reload',
                              onTap: () {
                                Navigator.pop(ctx);
                                _webController.reload();
                              },
                            ),
                          ],
                        ),
                      ),

                      // SCROLLABLE MENU ITEMS
                      Flexible(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          children: [
                            _buildChromeMenuItem(
                              icon: Icons.add_box_outlined,
                              title: 'New tab',
                              onTap: () {
                                Navigator.pop(ctx);
                                _createNewTab(incognito: false);
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.visibility_off_outlined,
                              title: 'New Incognito tab',
                              onTap: () {
                                Navigator.pop(ctx);
                                _createNewTab(incognito: true);
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.layers_outlined,
                              title: 'Recent tabs (${_tabs.length})',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openTabsSwitcherSheet();
                              },
                            ),
                            const Divider(height: 12),
                            _buildChromeMenuItem(
                              icon: Icons.history,
                              title: 'History',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openHistorySheet();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.delete_outline,
                              title: 'Delete browsing data',
                              onTap: () {
                                Navigator.pop(ctx);
                                _confirmClearBrowsingData();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.tune,
                              title: 'Site controls',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openSiteControlsDialog();
                              },
                            ),
                            const Divider(height: 12),
                            _buildChromeMenuItem(
                              icon: Icons.download_done_outlined,
                              title: 'Downloads',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openDownloadsSheet();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.bookmarks_outlined,
                              title: 'Bookmarks',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openBookmarksSheet();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.zoom_in,
                              title: 'Zoom ($_zoomPercent%)',
                              onTap: () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _showZoomBar = true;
                                  _showFindBar = false;
                                });
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.share_outlined,
                              title: 'Share...',
                              onTap: () {
                                Navigator.pop(ctx);
                                Clipboard.setData(
                                    ClipboardData(text: _currentUrl));
                                _showToast('लिंक क्लिपबोर्ड पर कॉपी हो गया');
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.find_in_page_outlined,
                              title: 'Find in page',
                              onTap: () {
                                Navigator.pop(ctx);
                                setState(() {
                                  _showFindBar = true;
                                  _showZoomBar = false;
                                });
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.translate,
                              title: 'Translate...',
                              onTap: () {
                                Navigator.pop(ctx);
                                _translateCurrentPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.menu_book_outlined,
                              title: _isReadingMode
                                  ? 'Hide Reading mode'
                                  : 'Show Reading mode',
                              onTap: () {
                                Navigator.pop(ctx);
                                _toggleReadingMode();
                              },
                            ),
                            // DESKTOP SITE WITH CHECKBOX
                            InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                _toggleDesktopMode();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.desktop_windows_outlined,
                                        size: 21, color: Color(0xFFE2E8F0)),
                                    const SizedBox(width: 16),
                                    const Expanded(
                                      child: Text(
                                        'Desktop site',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Color(0xFFE2E8F0),
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: Checkbox(
                                        value: _isDesktopMode,
                                        activeColor: const Color(0xFFA8C7FA),
                                        checkColor: const Color(0xFF0F141C),
                                        onChanged: (_) {
                                          Navigator.pop(ctx);
                                          _toggleDesktopMode();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 12),
                            _buildChromeMenuItem(
                              icon: Icons.shield_outlined,
                              title: 'Focus & Lock Settings',
                              iconColor: const Color(0xFFA8C7FA),
                              onTap: () {
                                Navigator.pop(ctx);
                                _openLockManagerSheet();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopMenuIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF282F3D),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }

  Widget _buildChromeMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFFE2E8F0),
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 21, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TABS, HISTORY, DOWNLOADS, SITE CONTROLS & CLEAR DATA SHEETS
  // ===========================================================================
  void _openTabsSwitcherSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setTabSheet) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Open Tabs (${_tabs.length})',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.visibility_off_outlined,
                            size: 17),
                        label: const Text('Incognito'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _createNewTab(incognito: true);
                        },
                      ),
                      const SizedBox(width: 6),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('New Tab'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _createNewTab(incognito: false);
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 20),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _tabs.length,
                  itemBuilder: (_, i) {
                    final tab = _tabs[i];
                    final isSelected = i == _activeTabIndex;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF263147)
                            : const Color(0xFF12151C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFA8C7FA)
                              : const Color(0xFF2D3343),
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          tab.isIncognito
                              ? Icons.visibility_off_outlined
                              : Icons.public,
                          color: tab.isIncognito
                              ? const Color(0xFFC4B5FD)
                              : const Color(0xFFA8C7FA),
                        ),
                        title: Text(
                          tab.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          tab.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white60),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _closeTab(i);
                            setTabSheet(() {});
                            if (_tabs.length == 1) Navigator.pop(ctx);
                          },
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _switchToTab(i);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setHistState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Browsing History',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  if (_history.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Clear All'),
                      onPressed: () async {
                        setState(() => _history.clear());
                        setHistState(() {});
                        await _saveData();
                      },
                    ),
                ],
              ),
              const Divider(height: 18),
              if (_history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'अभी कोई ब्राउज़िंग हिस्ट्री नहीं है',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _history.length,
                    itemBuilder: (_, i) {
                      final item = _history[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history,
                            size: 20, color: Color(0xFFA8C7FA)),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.timestamp} • ${item.url}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _loadFromSearchBar(item.url);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDownloadsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Saved & Downloaded Links',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  if (_downloads.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        setState(() => _downloads.clear());
                        setDlState(() {});
                        await _saveData();
                      },
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const Divider(height: 18),
              if (_downloads.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'कोई सेव किया गया लिंक या फ़ाइल नहीं है',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _downloads.length,
                    itemBuilder: (_, i) {
                      final link = _downloads[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined,
                            color: Color(0xFFA8C7FA)),
                        title: Text(
                          link.split('/').last.isEmpty
                              ? link
                              : link.split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          link,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: link));
                            _showToast('लिंक कॉपी किया गया');
                          },
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _loadFromSearchBar(link);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearBrowsingData() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232E),
        title: const Text('Delete browsing data?'),
        content: const Text(
          'इससे ब्राउज़िंग हिस्ट्री, कैश और लोकल स्टोरेज साफ़ हो जाएगा।\n\n(आपके बनाए हुए Focus Locks और Passwords सुरक्षित रहेंगे)',
          style: TextStyle(fontSize: 13.5, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _history.clear());
              await _saveData();
              await _webController.clearCache();
              await _webController.clearLocalStorage();
              _showToast('Browsing data साफ़ कर दिया गया');
            },
            child: const Text('Delete data'),
          ),
        ],
      ),
    );
  }

  void _openSiteControlsDialog() {
    final uri = Uri.tryParse(_currentUrl);
    final host = uri?.host ?? _currentUrl;
    final isSecure = _currentUrl.startsWith('https://');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232E),
        title: Row(
          children: [
            Icon(
              isSecure ? Icons.lock_outline : Icons.info_outline,
              color: isSecure ? const Color(0xFF86EFAC) : Colors.amber,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                host.isEmpty ? 'Site Controls' : host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSecure
                  ? 'Connection is secure (HTTPS)'
                  : 'Unencrypted connection (HTTP)',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Mode: ${_isDesktopMode ? "Desktop Site" : "Mobile Site"} • Zoom: $_zoomPercent%',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const Divider(height: 20),
            if (host.isNotEmpty && _lockGroups.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.block, size: 17),
                  label: Text('${_lockGroups.first.name} ग्रुप में यह साइट डालें'),
                  onPressed: () async {
                    final group = _lockGroups.first;
                    final clean = host.replaceAll('www.', '');
                    if (!group.domains.contains(clean)) {
                      setState(() => group.domains.add(clean));
                      await _saveData();
                      _showToast('$clean को ${group.name} में जोड़ा गया');
                    }
                    if (mounted) Navigator.pop(ctx);
                    _loadFromSearchBar(_currentUrl);
                  },
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // PASSWORD DIALOGS (Time-Vault Compatible)
  // ===========================================================================
  Future<String?> _promptPasswordVerification({
    required String title,
    required String expectedHash,
    bool allowTempUnlock = true,
  }) async {
    final passCtrl = TextEditingController();
    String? errorText;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E232E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E3646)),
          ),
          title: Text(title, style: const TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'अनलॉक करने के लिए अपना पासवर्ड (Time-Vault से) दर्ज करें:',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'पासवर्ड पेस्ट करें',
                  errorText: errorText,
                  filled: true,
                  fillColor: const Color(0xFF12151C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            if (allowTempUnlock)
              FilledButton.tonal(
                onPressed: () {
                  if (_hashPassword(passCtrl.text) == expectedHash) {
                    Navigator.pop(ctx, 'TEMP_10');
                  } else {
                    setDialogState(() => errorText = 'गलत पासवर्ड!');
                  }
                },
                child: const Text('10 Min Unlock'),
              ),
            FilledButton(
              onPressed: () {
                if (_hashPassword(passCtrl.text) == expectedHash) {
                  Navigator.pop(ctx, 'FULL');
                } else {
                  setDialogState(() => errorText = 'गलत पासवर्ड!');
                }
              },
              child: const Text('Permanent Unlock'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptSetNewPassword(String label) async {
    final passCtrl = TextEditingController();
    bool obscure = false;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E232E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E3646)),
          ),
          title: Text('$label पर लॉक सेट करें',
              style: const TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'पासवर्ड लिखें या रैंडम पासवर्ड जनरेट करके अपने Time-Vault में लॉक कर दें:',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'कम से कम 4 अक्षर का पासवर्ड',
                  filled: true,
                  fillColor: const Color(0xFF12151C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () =>
                        setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('Random Password बनाएं और Copy करें'),
                  onPressed: () {
                    final rndPass = _generateRandomPassword();
                    setDialogState(() {
                      passCtrl.text = rndPass;
                      obscure = true;
                    });
                    Clipboard.setData(ClipboardData(text: rndPass));
                    _showToast(
                        'रैंडम पासवर्ड Copy हो गया! अब इसे Time-Vault में सेव करें');
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (passCtrl.text.trim().length < 4) {
                  _showToast('कम से कम 4 अक्षर का पासवर्ड रखें');
                  return;
                }
                Clipboard.setData(ClipboardData(text: passCtrl.text.trim()));
                Navigator.pop(ctx, _hashPassword(passCtrl.text));
              },
              child: const Text('Enable Lock'),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // CLEAN & PROFESSIONAL FOCUS & LOCK MANAGER (2-TAB DESIGN)
  // ===========================================================================
  void _openLockManagerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        maxChildSize: 0.94,
        builder: (_, scrollCtrl) => DefaultTabController(
          length: 2,
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              Future<void> toggleFeature({
                required bool currentValue,
                required Function(bool) onChanged,
              }) async {
                if (!currentValue) {
                  setState(() => onChanged(true));
                  setSheetState(() {});
                  await _saveData();
                  _injectFocusScripts();
                  _loadFromSearchBar(_currentUrl);
                  return;
                }
                if (_isFeatureLockActive) {
                  final res = await _promptPasswordVerification(
                    title: 'Focus Controls अनलॉक करें',
                    expectedHash: _featurePassHash,
                  );
                  if (res == 'FULL') {
                    setState(() => onChanged(false));
                  } else if (res == 'TEMP_10') {
                    setState(() {
                      _featureTempUnlockUntil = DateTime.now()
                          .add(const Duration(minutes: 10))
                          .millisecondsSinceEpoch;
                    });
                    _showToast('10 मिनट के लिए अस्थायी अनलॉक किया गया');
                  }
                } else {
                  setState(() => onChanged(false));
                }
                setSheetState(() {});
                await _saveData();
                _injectFocusScripts();
                _loadFromSearchBar(_currentUrl);
              }

              return Column(
                children: [
                  // HEADER
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shield_outlined,
                                color: Color(0xFFA8C7FA), size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Focus & Lock Manager',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // CLEAN 2-TAB BAR
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E232E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2D3343)),
                    ),
                    child: const TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Color(0xFF0F141C),
                      unselectedLabelColor: Color(0xFFCBD5E1),
                      indicator: BoxDecoration(
                        color: Color(0xFFA8C7FA),
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      tabs: [
                        Tab(text: 'Focus Controls'),
                        Tab(text: 'Site Lock Groups'),
                      ],
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      children: [
                        // TAB 1: FOCUS CONTROLS (YOUTUBE, INSTA, WHITELIST)
                        ListView(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          children: [
                            // Password Status Banner
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E232E),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: const Color(0xFF2E3646)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _featurePassHash.isNotEmpty
                                        ? Icons.lock_outline
                                        : Icons.lock_open_outlined,
                                    color: _featurePassHash.isNotEmpty
                                        ? const Color(0xFF86EFAC)
                                        : const Color(0xFF94A3B8),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _featurePassHash.isEmpty
                                              ? 'Controls Unlocked'
                                              : (_isFeatureLockActive
                                                  ? 'Password Protected'
                                                  : 'Unlocked (${_formatSeconds(_featureRemainingTempSeconds)} left)'),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'लॉक ऑन करने के बाद बिना पासवर्ड कोई नियम बंद नहीं होगा',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_featurePassHash.isEmpty)
                                    FilledButton.tonalIcon(
                                      icon: const Icon(Icons.key_outlined,
                                          size: 16),
                                      label: const Text('Set Lock'),
                                      onPressed: () async {
                                        final hash = await _promptSetNewPassword(
                                            'Focus Controls');
                                        if (hash != null) {
                                          setState(() {
                                            _featurePassHash = hash;
                                            _featureTempUnlockUntil = 0;
                                          });
                                          setSheetState(() {});
                                          await _saveData();
                                        }
                                      },
                                    )
                                  else
                                    OutlinedButton(
                                      onPressed: () async {
                                        final res =
                                            await _promptPasswordVerification(
                                          title: 'Focus Lock पासवर्ड हटाएं',
                                          expectedHash: _featurePassHash,
                                          allowTempUnlock: false,
                                        );
                                        if (res == 'FULL') {
                                          setState(() => _featurePassHash = '');
                                          setSheetState(() {});
                                          await _saveData();
                                          _showToast('पासवर्ड हटा दिया गया');
                                        }
                                      },
                                      child: const Text('Reset'),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Switches Card
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E232E),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: const Color(0xFF2E3646)),
                              ),
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    title: const Text('Block YouTube Shorts',
                                        style: TextStyle(fontSize: 14.5)),
                                    subtitle: const Text(
                                      'क्लासेस और लेक्चर चलेंगे, Shorts टैब और रील्स ब्लॉक रहेंगे',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.white60),
                                    ),
                                    value: _blockYtShorts,
                                    onChanged: (_) => toggleFeature(
                                      currentValue: _blockYtShorts,
                                      onChanged: (v) => _blockYtShorts = v,
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  SwitchListTile(
                                    title: const Text(
                                        'YouTube Search-Only Mode',
                                        style: TextStyle(fontSize: 14.5)),
                                    subtitle: const Text(
                                      'YouTube होमपेज फीड छिपाएं ताकि केवल सर्च काम करे',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.white60),
                                    ),
                                    value: _hideYtFeed,
                                    onChanged: (_) => toggleFeature(
                                      currentValue: _hideYtFeed,
                                      onChanged: (v) => _hideYtFeed = v,
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  SwitchListTile(
                                    title: const Text(
                                        'Block Instagram Reels & Explore',
                                        style: TextStyle(fontSize: 14.5)),
                                    subtitle: const Text(
                                      'केवल DM/चैट चलेगा, Reels और Explore पेज बंद रहेंगे',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.white60),
                                    ),
                                    value: _blockIgReels,
                                    onChanged: (_) => toggleFeature(
                                      currentValue: _blockIgReels,
                                      onChanged: (v) => _blockIgReels = v,
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  SwitchListTile(
                                    title: const Text('Strict Whitelist Mode',
                                        style: TextStyle(fontSize: 14.5)),
                                    subtitle: Text(
                                      'केवल नीचे दी गई ${_whitelistedDomains.length} स्टडी वेबसाइट्स ही खुलेंगी',
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white60),
                                    ),
                                    value: _whitelistMode,
                                    onChanged: (_) => toggleFeature(
                                      currentValue: _whitelistMode,
                                      onChanged: (v) => _whitelistMode = v,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Visible Whitelist Domains Card
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E232E),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: const Color(0xFF2E3646)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Allowed Study Domains (Whitelist)',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextButton.icon(
                                        icon: const Icon(Icons.add, size: 17),
                                        label: const Text('Add Site'),
                                        onPressed: () =>
                                            _promptAddWhitelistDomain(
                                                setSheetState),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _whitelistedDomains.map((domain) {
                                      return Chip(
                                        label: Text(domain,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                        backgroundColor:
                                            const Color(0xFF12151C),
                                        side: const BorderSide(
                                            color: Color(0xFF2E3646)),
                                        deleteIcon:
                                            const Icon(Icons.close, size: 14),
                                        onDeleted: () async {
                                          if (_whitelistMode &&
                                              _isFeatureLockActive) {
                                            _showToast(
                                                'Whitelist लॉक सक्रिय होने पर साइट हटाई नहीं जा सकती');
                                            return;
                                          }
                                          setState(() => _whitelistedDomains
                                              .remove(domain));
                                          setSheetState(() {});
                                          await _saveData();
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // TAB 2: CUSTOM SITE LOCK GROUPS
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Custom Block Groups',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('New Group'),
                                  onPressed: () =>
                                      _promptCreateNewGroup(setSheetState),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._lockGroups.map((group) {
                              final active = group.isCurrentlyActive;
                              final tempLeft = group.remainingTempSeconds;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E232E),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: active
                                        ? const Color(0xFFA8C7FA)
                                            .withOpacity(0.45)
                                        : const Color(0xFF2E3646),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              active
                                                  ? Icons.lock_outline
                                                  : Icons.lock_open_outlined,
                                              size: 19,
                                              color: active
                                                  ? const Color(0xFFA8C7FA)
                                                  : Colors.white54,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              group.name,
                                              style: const TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            if (!group.isLocked)
                                              FilledButton.tonal(
                                                onPressed: () async {
                                                  if (group.domains.isEmpty) {
                                                    _showToast(
                                                        'पहले इस ग्रुप में कम से कम 1 डोमेन जोड़ें');
                                                    return;
                                                  }
                                                  final hash =
                                                      await _promptSetNewPassword(
                                                          group.name);
                                                  if (hash != null) {
                                                    setState(() {
                                                      group.passwordHash = hash;
                                                      group.isLocked = true;
                                                      group.tempUnlockUntil = 0;
                                                    });
                                                    setSheetState(() {});
                                                    await _saveData();
                                                    _loadFromSearchBar(
                                                        _currentUrl);
                                                  }
                                                },
                                                child: const Text('Lock Group'),
                                              )
                                            else
                                              OutlinedButton(
                                                onPressed: () async {
                                                  final res =
                                                      await _promptPasswordVerification(
                                                    title:
                                                        '${group.name} अनलॉक करें',
                                                    expectedHash:
                                                        group.passwordHash,
                                                  );
                                                  if (res == 'FULL') {
                                                    setState(() {
                                                      group.isLocked = false;
                                                      group.passwordHash = '';
                                                    });
                                                    _showToast(
                                                        '${group.name} अनलॉक हो गया');
                                                  } else if (res == 'TEMP_10') {
                                                    setState(() {
                                                      group.tempUnlockUntil =
                                                          DateTime.now()
                                                              .add(const Duration(
                                                                  minutes: 10))
                                                              .millisecondsSinceEpoch;
                                                    });
                                                    _showToast(
                                                        '${group.name} 10 मिनट के लिए अनलॉक किया गया');
                                                  }
                                                  setSheetState(() {});
                                                  await _saveData();
                                                  _loadFromSearchBar(
                                                      _currentUrl);
                                                },
                                                child: Text(
                                                  active
                                                      ? 'Unlock'
                                                      : 'Open (${_formatSeconds(tempLeft)})',
                                                ),
                                              ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 19,
                                                  color: Colors.white54),
                                              onPressed: () async {
                                                if (group.isCurrentlyActive) {
                                                  _showToast(
                                                      'लॉक ग्रुप को डिलीट करने से पहले अनलॉक करें');
                                                  return;
                                                }
                                                setState(() =>
                                                    _lockGroups.remove(group));
                                                setSheetState(() {});
                                                await _saveData();
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        ...group.domains.map(
                                          (domain) => Chip(
                                            label: Text(domain,
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                            backgroundColor:
                                                const Color(0xFF12151C),
                                            side: const BorderSide(
                                                color: Color(0xFF2E3646)),
                                            deleteIcon: const Icon(Icons.close,
                                                size: 14),
                                            onDeleted: () async {
                                              if (group.isCurrentlyActive) {
                                                _showToast(
                                                    'लॉक ग्रुप से साइट हटाने के लिए पहले अनलॉक करें');
                                                return;
                                              }
                                              setState(() => group.domains
                                                  .remove(domain));
                                              setSheetState(() {});
                                              await _saveData();
                                            },
                                          ),
                                        ),
                                        ActionChip(
                                          avatar:
                                              const Icon(Icons.add, size: 15),
                                          label: const Text('Add Domain',
                                              style: TextStyle(fontSize: 12)),
                                          backgroundColor:
                                              const Color(0xFF263147),
                                          side: BorderSide.none,
                                          onPressed: () =>
                                              _promptAddDomainToGroup(
                                                  group, setSheetState),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _promptAddWhitelistDomain(StateSetter setSheetState) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232E),
        title: const Text('स्टडी वेबसाइट जोड़ें',
            style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'उदाहरण: pw.live या khanacademy.org',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final d = ctrl.text
                  .trim()
                  .toLowerCase()
                  .replaceAll('https://', '')
                  .replaceAll('http://', '')
                  .replaceAll('www.', '')
                  .split('/')
                  .first;
              if (d.isNotEmpty && !_whitelistedDomains.contains(d)) {
                setState(() => _whitelistedDomains.add(d));
                setSheetState(() {});
                await _saveData();
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _promptCreateNewGroup(StateSetter setSheetState) async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232E),
        title:
            const Text('नया Lock Group बनाएं', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            hintText: 'ग्रुप का नाम (जैसे: Gaming, Social)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _lockGroups.add(
                    LockGroup(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: name,
                      domains: [],
                      passwordHash: '',
                      isLocked: false,
                    ),
                  );
                });
                setSheetState(() {});
                await _saveData();
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _promptAddDomainToGroup(
      LockGroup group, StateSetter setSheetState) async {
    final domainCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232E),
        title: Text('${group.name} में डोमेन जोड़ें',
            style: const TextStyle(fontSize: 17)),
        content: TextField(
          controller: domainCtrl,
          decoration: const InputDecoration(
            hintText: 'उदाहरण: instagram.com या netflix.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = domainCtrl.text
                  .trim()
                  .toLowerCase()
                  .replaceAll('https://', '')
                  .replaceAll('http://', '')
                  .replaceAll('www.', '')
                  .split('/')
                  .first;
              if (raw.isNotEmpty && !group.domains.contains(raw)) {
                setState(() => group.domains.add(raw));
                setSheetState(() {});
                await _saveData();
                _loadFromSearchBar(_currentUrl);
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Add Domain'),
          ),
        ],
      ),
    );
  }

  void _openBookmarksSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F29),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBmState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Bookmarks',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                    label: const Text('Add Current Page'),
                    onPressed: () async {
                      await _toggleCurrentBookmark();
                      setBmState(() {});
                    },
                  ),
                ],
              ),
              const Divider(height: 18),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _bookmarks.length,
                  itemBuilder: (_, i) {
                    final bm = _bookmarks[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bookmark_border,
                          color: Color(0xFFA8C7FA)),
                      title: Text(bm.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        bm.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 19),
                        onPressed: () async {
                          setState(() => _bookmarks.removeAt(i));
                          setBmState(() {});
                          await _saveData();
                        },
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _loadFromSearchBar(bm.url);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // MAIN SCAFFOLD & CHROME-STYLE TOP BAR
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_showFindBar || _showZoomBar) {
          setState(() {
            _showFindBar = false;
            _showZoomBar = false;
          });
          return false;
        }
        if (_isReadingMode) {
          await _toggleReadingMode();
          return false;
        }
        if (_isPageBlocked) {
          setState(() => _isPageBlocked = false);
          _loadFromSearchBar('https://www.google.com');
          return false;
        }
        if (await _webController.canGoBack()) {
          await _webController.goBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // TOP CHROME-STYLE BAR
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: _isIncognito
                      ? const Color(0xFF1F1A2C)
                      : const Color(0xFF1A1F29),
                  border: const Border(
                    bottom: BorderSide(color: Color(0xFF282F3D), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.home_outlined, size: 22),
                      tooltip: 'Home',
                      onPressed: () =>
                          _loadFromSearchBar('https://www.google.com'),
                    ),
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF12151C),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFF2D3444)),
                        ),
                        child: TextField(
                          controller: _urlController,
                          textInputAction: TextInputAction.go,
                          onSubmitted: _loadFromSearchBar,
                          style: const TextStyle(fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText: 'Search or type URL',
                            prefixIcon: Icon(
                              _isIncognito
                                  ? Icons.visibility_off_outlined
                                  : Icons.lock_outline,
                              size: 16,
                              color: _isIncognito
                                  ? const Color(0xFFC4B5FD)
                                  : const Color(0xFFA8C7FA),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => _urlController.clear(),
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Tab Counter Button (Chrome style [1])
                    InkWell(
                      onTap: _openTabsSwitcherSheet,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFFE2E8F0), width: 1.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_tabs.length}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    // Shield Button (Focus & Lock Manager)
                    IconButton(
                      icon: const Icon(Icons.shield_outlined,
                          size: 21, color: Color(0xFFA8C7FA)),
                      tooltip: 'Focus & Lock Manager',
                      onPressed: _openLockManagerSheet,
                    ),
                    // Chrome 3-Dot Menu Button
                    IconButton(
                      icon: const Icon(Icons.more_vert, size: 22),
                      tooltip: 'More options',
                      onPressed: _openChromeStyleMenu,
                    ),
                  ],
                ),
              ),

              // OPTIONAL FIND IN PAGE BAR
              if (_showFindBar)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: const Color(0xFF1E232E),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          size: 18, color: Color(0xFFA8C7FA)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _findController,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _performFindInPage,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Find in page...',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            _performFindInPage(_findController.text),
                        child: const Text('Find Next'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _showFindBar = false),
                      ),
                    ],
                  ),
                ),

              // OPTIONAL ZOOM CONTROL BAR
              if (_showZoomBar)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  color: const Color(0xFF1E232E),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Page Zoom: $_zoomPercent%',
                          style: const TextStyle(fontSize: 13.5)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 20),
                            onPressed: () {
                              setState(() {
                                _zoomPercent = (_zoomPercent - 15).clamp(50, 200);
                              });
                              _injectFocusScripts();
                            },
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _zoomPercent = 100);
                              _injectFocusScripts();
                            },
                            child: const Text('Reset'),
                          ),
                          IconButton(
                            icon:
                                const Icon(Icons.add_circle_outline, size: 20),
                            onPressed: () {
                              setState(() {
                                _zoomPercent = (_zoomPercent + 15).clamp(50, 200);
                              });
                              _injectFocusScripts();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                setState(() => _showZoomBar = false),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              if (_loadingProgress < 100)
                LinearProgressIndicator(
                  value: _loadingProgress / 100.0,
                  minHeight: 2,
                  color: const Color(0xFFA8C7FA),
                  backgroundColor: Colors.transparent,
                ),

              // MAIN WEBVIEW OR BLOCKED OVERLAY
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _webController),
                    if (_isPageBlocked) _buildBlockedOverlay(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedOverlay() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF12151C),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF1E232E),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2E3646)),
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 46,
              color: Color(0xFFA8C7FA),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Access Restricted',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            _blockedReason,
            style: const TextStyle(fontSize: 14.5, color: Color(0xFFA8C7FA)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _blockedUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(230, 44),
            ),
            icon: const Icon(Icons.school_outlined, size: 19),
            label: const Text('Back to Study (Google)'),
            onPressed: () {
              setState(() => _isPageBlocked = false);
              _loadFromSearchBar('https://www.google.com');
            },
          ),
          const SizedBox(height: 12),
          if (_blockingGroup != null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(230, 44),
              ),
              icon: const Icon(Icons.key_outlined, size: 18),
              label: Text('Unlock ${_blockingGroup!.name}'),
              onPressed: () async {
                final group = _blockingGroup!;
                final res = await _promptPasswordVerification(
                  title: '${group.name} अनलॉक करें',
                  expectedHash: group.passwordHash,
                );
                if (res == 'FULL') {
                  setState(() {
                    group.isLocked = false;
                    group.passwordHash = '';
                    _isPageBlocked = false;
                  });
                } else if (res == 'TEMP_10') {
                  setState(() {
                    group.tempUnlockUntil = DateTime.now()
                        .add(const Duration(minutes: 10))
                        .millisecondsSinceEpoch;
                    _isPageBlocked = false;
                  });
                }
                await _saveData();
                if (!_isPageBlocked) {
                  _loadFromSearchBar(_blockedUrl);
                }
              },
            ),
        ],
      ),
    );
  }
}
