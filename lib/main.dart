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

// =============================================================================
// DATA MODELS
// =============================================================================
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
        'name': name,
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
  String dateGroup;

  HistoryItem({
    required this.title,
    required this.url,
    required this.timestamp,
    required this.dateGroup,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'timestamp': timestamp,
        'dateGroup': dateGroup,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        title: (json['title'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        timestamp: (json['timestamp'] ?? '').toString(),
        dateGroup: (json['dateGroup'] ?? 'Today').toString(),
      );
}

class DownloadEntry {
  String id;
  String title;
  String url;
  String filePath;
  String sizeLabel;
  String category; // Pages, Videos, Images, Other
  String dateLabel;

  DownloadEntry({
    required this.id,
    required this.title,
    required this.url,
    required this.filePath,
    required this.sizeLabel,
    required this.category,
    required this.dateLabel,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'filePath': filePath,
        'sizeLabel': sizeLabel,
        'category': category,
        'dateLabel': dateLabel,
      };

  factory DownloadEntry.fromJson(Map<String, dynamic> json) => DownloadEntry(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? 'Downloaded File').toString(),
        url: (json['url'] ?? '').toString(),
        filePath: (json['filePath'] ?? '').toString(),
        sizeLabel: (json['sizeLabel'] ?? '1.12 MB').toString(),
        category: (json['category'] ?? 'Other').toString(),
        dateLabel: (json['dateLabel'] ?? 'Today').toString(),
      );
}

class BrowserTab {
  String id;
  String title;
  String url;
  bool isIncognito;
  bool isDesktop;
  String? groupId;

  BrowserTab({
    required this.id,
    required this.title,
    required this.url,
    this.isIncognito = false,
    this.isDesktop = false,
    this.groupId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'isIncognito': isIncognito,
        'isDesktop': isDesktop,
        'groupId': groupId,
      };

  factory BrowserTab.fromJson(Map<String, dynamic> json) => BrowserTab(
        id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString())
            .toString(),
        title: (json['title'] ?? 'New Tab').toString(),
        url: (json['url'] ?? 'https://www.google.com').toString(),
        isIncognito: json['isIncognito'] == true,
        isDesktop: json['isDesktop'] == true,
        groupId: json['groupId']?.toString(),
      );
}

class BrowserTabGroup {
  String id;
  String title;
  int colorValue;

  BrowserTabGroup({
    required this.id,
    required this.title,
    required this.colorValue,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'colorValue': colorValue,
      };

  factory BrowserTabGroup.fromJson(Map<String, dynamic> json) =>
      BrowserTabGroup(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] ?? 'Study Group').toString(),
        colorValue: (json['colorValue'] ?? 0xFF3B82F6) as int,
      );
}

// =============================================================================
// MAIN BROWSER SCREEN
// =============================================================================
class BrowserHomeScreen extends StatefulWidget {
  const BrowserHomeScreen({super.key});

  @override
  State<BrowserHomeScreen> createState() => _BrowserHomeScreenState();
}

class _BrowserHomeScreenState extends State<BrowserHomeScreen> {
  static const MethodChannel _intentChannel =
      MethodChannel('study_browser/intent');

  static const String _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; RMX3395) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';
  static const String _desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  late final WebViewController _webController;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _findController = TextEditingController();

  Timer? _lockEnforcementTimer;
  Timer? _zoomAutoHideTimer;
  bool _webViewReady = false;

  int _loadingProgress = 0;
  String _currentUrl = 'https://www.google.com';
  String _pageTitle = 'Google';

  // Browser States
  bool _isDesktopMode = false;
  bool _isIncognito = false;
  bool _isReadingMode = false;
  bool _showFindBar = false;
  bool _showZoomBar = false;
  int _zoomPercent = 100;
  String _searchEngineUrl = 'https://www.google.com/search?q=';
  String _homepageUrl = 'https://www.google.com';

  List<BrowserTab> _tabs = [];
  List<BrowserTabGroup> _tabGroups = [];
  List<BrowserTab> _recentlyClosedTabs = [];
  int _activeTabIndex = 0;

  // Focus & Lock States
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
  List<DownloadEntry> _downloads = [];

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

        // 1. REAL DESKTOP SITE VIEWPORT & SCALING
        var vpMeta = document.querySelector('meta[name="viewport"]');
        if (window.__SB_DESKTOP_MODE) {
          var screenW = window.screen.width || 360;
          var targetScale = (screenW / 1280.0).toFixed(3);
          var desiredContent = 'width=1280, initial-scale=' + targetScale + ', minimum-scale=0.1, maximum-scale=5.0, user-scalable=yes';
          if (!vpMeta) {
            vpMeta = document.createElement('meta');
            vpMeta.name = 'viewport';
            document.head.appendChild(vpMeta);
          }
          if (vpMeta.getAttribute('content') !== desiredContent) {
            vpMeta.setAttribute('content', desiredContent);
          }
          // Fallback if WebView layout width is still narrow
          if (window.innerWidth > 0 && window.innerWidth < 980 && document.documentElement) {
            document.documentElement.style.minWidth = '1280px';
          }
        } else {
          if (vpMeta && vpMeta.getAttribute('content') && vpMeta.getAttribute('content').includes('width=1280')) {
            vpMeta.setAttribute('content', 'width=device-width, initial-scale=1.0');
          }
          if (document.documentElement && document.documentElement.style.minWidth === '1280px') {
            document.documentElement.style.minWidth = '';
          }
        }

        // 2. PAGE ZOOM CONTROL
        if (document.body && window.__SB_ZOOM_PERCENT) {
          if (window.__SB_ZOOM_PERCENT !== 100) {
            document.body.style.zoom = window.__SB_ZOOM_PERCENT + '%';
          } else if (document.body.style.zoom) {
            document.body.style.zoom = '';
          }
        }

        // 3. YOUTUBE SHORTS & FEED BLOCKER
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

        // 4. INSTAGRAM REELS & EXPLORE BLOCKER
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
        setInterval(applyRules, 350);
      }
      applyRules();
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _setupWebViewController();
    _setupIntentListener();
    _bootBrowser();
    _startLockEnforcementTimer();
  }

  @override
  void dispose() {
    _lockEnforcementTimer?.cancel();
    _zoomAutoHideTimer?.cancel();
    _urlController.dispose();
    _findController.dispose();
    super.dispose();
  }

  void _startLockEnforcementTimer() {
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
    _intentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNewIntentUrl') {
        final String? incoming = call.arguments as String?;
        if (incoming != null && incoming.trim().isNotEmpty) {
          _createNewTab(incognito: false, url: incoming.trim());
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
      _createNewTab(incognito: false, url: initialExternalUrl.trim());
    } else {
      if (_tabs.isEmpty) {
        _tabs = [
          BrowserTab(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: 'Google',
            url: _homepageUrl,
          ),
        ];
        _activeTabIndex = 0;
      }
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
      final activeTab = _tabs[_activeTabIndex];
      _isDesktopMode = activeTab.isDesktop;
      _isIncognito = activeTab.isIncognito;
      await _applyNativeDesktopViewport(_isDesktopMode);
      _loadFromSearchBar(activeTab.url);
    }
  }

  Future<void> _applyNativeDesktopViewport(bool isDesktop) async {
    await _webController.setUserAgent(
      isDesktop ? _desktopUserAgent : _mobileUserAgent,
    );
    try {
      await _intentChannel.invokeMethod('setDesktopViewport', {
        'isDesktop': isDesktop,
      });
    } catch (_) {}
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

  String _todayLabel() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return 'Today - ${now.day} ${months[now.month - 1]} ${now.year}';
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
      _homepageUrl =
          prefs.getString('homepageUrl') ?? 'https://www.google.com';
      _searchEngineUrl = prefs.getString('searchEngineUrl') ??
          'https://www.google.com/search?q=';

      final savedWhitelist = prefs.getStringList('whitelistedDomains');
      if (savedWhitelist != null && savedWhitelist.isNotEmpty) {
        _whitelistedDomains = savedWhitelist;
      }

      // Restore Saved Open Tabs & Tab Groups (So refreshing/killing app never loses tabs!)
      final savedTabsJson = prefs.getString('savedBrowserTabs');
      if (savedTabsJson != null) {
        try {
          final List decoded = jsonDecode(savedTabsJson);
          _tabs = decoded
              .map((e) =>
                  BrowserTab.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        } catch (_) {}
      }
      if (_tabs.isEmpty) {
        _tabs = [
          BrowserTab(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: 'Google',
            url: _homepageUrl,
          ),
        ];
      }
      _activeTabIndex =
          (prefs.getInt('savedActiveTabIndex') ?? 0).clamp(0, _tabs.length - 1);

      final savedTabGroupsJson = prefs.getString('savedTabGroups');
      if (savedTabGroupsJson != null) {
        try {
          final List decoded = jsonDecode(savedTabGroupsJson);
          _tabGroups = decoded
              .map((e) => BrowserTabGroup.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList();
        } catch (_) {}
      }

      final savedClosedJson = prefs.getString('savedRecentlyClosed');
      if (savedClosedJson != null) {
        try {
          final List decoded = jsonDecode(savedClosedJson);
          _recentlyClosedTabs = decoded
              .map((e) =>
                  BrowserTab.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        } catch (_) {}
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
          BookmarkItem(
              title: 'GD Practice Hub',
              url: 'https://gd-practice-hub.vercel.app'),
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

      final dlJson = prefs.getString('downloadEntriesV2');
      if (dlJson != null) {
        try {
          final List decoded = jsonDecode(dlJson);
          _downloads = decoded
              .map((e) =>
                  DownloadEntry.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        } catch (_) {}
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
    await prefs.setString('homepageUrl', _homepageUrl);
    await prefs.setString('searchEngineUrl', _searchEngineUrl);
    await prefs.setStringList('whitelistedDomains', _whitelistedDomains);
    await prefs.setString(
      'savedBrowserTabs',
      jsonEncode(_tabs.map((t) => t.toJson()).toList()),
    );
    await prefs.setInt('savedActiveTabIndex', _activeTabIndex);
    await prefs.setString(
      'savedTabGroups',
      jsonEncode(_tabGroups.map((g) => g.toJson()).toList()),
    );
    await prefs.setString(
      'savedRecentlyClosed',
      jsonEncode(_recentlyClosedTabs.map((t) => t.toJson()).toList()),
    );
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
    await prefs.setString(
      'downloadEntriesV2',
      jsonEncode(_downloads.map((d) => d.toJson()).toList()),
    );
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
            _applyNativeDesktopViewport(_isDesktopMode);
            _injectFocusScripts();
          },
          onPageFinished: (url) async {
            if (url == 'about:blank') return;
            await _applyNativeDesktopViewport(_isDesktopMode);
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

            final allowed = _evaluateUrl(reqUrl, showOverlayOnBlock: true);
            if (!allowed) {
              return NavigationDecision.prevent;
            }

            // Detect direct downloadable files (.pdf, .zip, .apk, video, image, etc.)
            final lower = reqUrl.toLowerCase().split('?').first;
            if (lower.endsWith('.pdf') ||
                lower.endsWith('.zip') ||
                lower.endsWith('.apk') ||
                lower.endsWith('.doc') ||
                lower.endsWith('.docx') ||
                lower.endsWith('.mp3') ||
                lower.endsWith('.mp4') ||
                lower.endsWith('.jpg') ||
                lower.endsWith('.png')) {
              _triggerRealFileDownload(reqUrl);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );
    _webViewReady = true;
  }

  String _detectDownloadCategory(String nameOrUrl) {
    final lower = nameOrUrl.toLowerCase().split('?').first;
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm')) {
      return 'Videos';
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp')) {
      return 'Images';
    }
    if (lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.mhtml')) {
      return 'Pages';
    }
    return 'Other';
  }

  Future<void> _triggerRealFileDownload(String url) async {
    try {
      final res = await _intentChannel.invokeMethod('downloadFile', {
        'url': url,
      });
      String fileName = url.split('/').last.split('?').first;
      if (fileName.isEmpty) fileName = 'Downloaded_File';
      String filePath = '/storage/emulated/0/Download/$fileName';
      String sizeLabel = 'Downloaded';

      if (res is Map) {
        fileName = (res['fileName'] ?? fileName).toString();
        filePath = (res['filePath'] ?? filePath).toString();
        sizeLabel = (res['sizeLabel'] ?? 'Saved in Downloads').toString();
      }

      final entry = DownloadEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: fileName,
        url: url,
        filePath: filePath,
        sizeLabel: sizeLabel,
        category: _detectDownloadCategory(fileName),
        dateLabel: _todayLabel(),
      );

      setState(() => _downloads.insert(0, entry));
      await _saveData();
      _showDownloadBanner(entry);
    } catch (_) {}
  }

  Future<void> _downloadCurrentPageOffline() async {
    // Chrome-style confirmation or immediate offline page save
    try {
      final rawHtmlObj = await _webController.runJavaScriptReturningResult(
          'document.documentElement.outerHTML');
      String htmlString = rawHtmlObj.toString();
      if (htmlString.startsWith('"') && htmlString.endsWith('"')) {
        try {
          htmlString = jsonDecode(htmlString).toString();
        } catch (_) {}
      }

      final titleToSave = _pageTitle.isNotEmpty ? _pageTitle : 'Web_Page';
      final res = await _intentChannel.invokeMethod('saveOfflinePage', {
        'title': titleToSave,
        'html': htmlString,
      });

      if (res is Map) {
        final fileName = (res['fileName'] ?? '$titleToSave.html').toString();
        final filePath = (res['filePath'] ?? '').toString();
        final sizeLabel = (res['sizeLabel'] ?? '1.12 MB').toString();

        final entry = DownloadEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: titleToSave,
          url: _currentUrl,
          filePath: filePath,
          sizeLabel: sizeLabel,
          category: 'Pages',
          dateLabel: _todayLabel(),
        );

        setState(() => _downloads.insert(0, entry));
        await _saveData();
        _showDownloadBanner(entry);
      } else {
        _showToast('पेज ऑफलाइन सेव कर लिया गया');
      }
    } catch (_) {
      _triggerRealFileDownload(_currentUrl);
    }
  }

  void _showDownloadBanner(DownloadEntry entry) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E232E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.download_done, color: Color(0xFFA8C7FA), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'File downloaded',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5),
                  ),
                  Text(
                    '(${entry.sizeLabel}) ${entry.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Open',
          textColor: const Color(0xFFA8C7FA),
          onPressed: () => _openDownloadEntry(entry),
        ),
      ),
    );
  }

  Future<void> _openDownloadEntry(DownloadEntry entry) async {
    final lowerPath = entry.filePath.toLowerCase();
    final lowerUrl = entry.url.toLowerCase().split('?').first;

    // If it's a ZIP, APK, PDF, Video, Audio, or physical file, trigger Android's native "Open with" chooser!
    if (lowerPath.endsWith('.zip') ||
        lowerPath.endsWith('.apk') ||
        lowerPath.endsWith('.pdf') ||
        lowerUrl.endsWith('.zip') ||
        lowerUrl.endsWith('.apk') ||
        lowerUrl.endsWith('.pdf')) {
      final ok = await _intentChannel.invokeMethod<bool>('openWithSystem', {
        'filePath': entry.filePath,
        'url': entry.url,
      });
      if (ok != true && entry.url.isNotEmpty) {
        _loadFromSearchBar(entry.url);
      }
      return;
    }

    // If it's a saved web page, offer to open in browser or system viewer
    if (entry.category == 'Pages' && entry.url.isNotEmpty) {
      _loadFromSearchBar(entry.url);
      _showToast('Viewing saved page: ${entry.title}');
      return;
    }

    await _intentChannel.invokeMethod('openWithSystem', {
      'filePath': entry.filePath,
      'url': entry.url,
    });
  }

  void _syncActiveTab({String? title, String? url}) {
    if (_tabs.isEmpty || _activeTabIndex >= _tabs.length) return;
    final tab = _tabs[_activeTabIndex];
    if (title != null && title.isNotEmpty) tab.title = title;
    if (url != null && url.isNotEmpty) tab.url = url;
    tab.isDesktop = _isDesktopMode;
    tab.isIncognito = _isIncognito;
    _saveData();
  }

  void _recordHistory(String title, String url) {
    if (_isIncognito) return;
    if (url.isEmpty || url == 'about:blank') return;
    if (_history.isNotEmpty && _history.first.url == url) return;

    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _history.insert(
        0,
        HistoryItem(
          title: title,
          url: url,
          timestamp: timeStr,
          dateGroup: _todayLabel(),
        ),
      );
      if (_history.length > 150) {
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
      targetUrl = '$_searchEngineUrl${Uri.encodeComponent(trimmed)}';
    }

    targetUrl = _normalizeUrlForMode(targetUrl);

    setState(() {
      _currentUrl = targetUrl;
      _urlController.text = targetUrl;
      _isReadingMode = false;
      _syncActiveTab(url: targetUrl);
    });

    final allowed = _evaluateUrl(targetUrl, showOverlayOnBlock: true);
    if (!allowed) {
      _webController.loadRequest(Uri.parse('about:blank'));
      return;
    }

    setState(() => _isPageBlocked = false);
    _applyNativeDesktopViewport(_isDesktopMode);
    _webController.loadRequest(Uri.parse(targetUrl));
  }

  Future<void> _toggleDesktopMode() async {
    setState(() {
      _isDesktopMode = !_isDesktopMode;
      _syncActiveTab();
    });
    await _applyNativeDesktopViewport(_isDesktopMode);
    final updatedUrl = _normalizeUrlForMode(_currentUrl);
    _showToast(_isDesktopMode
        ? 'Desktop site चालू किया गया'
        : 'Mobile site चालू किया गया');
    _loadFromSearchBar(updatedUrl);
  }

  void _openZoomControlsWithAutoHide() {
    setState(() {
      _showZoomBar = true;
      _showFindBar = false;
    });
    _scheduleZoomAutoHide();
  }

  void _scheduleZoomAutoHide() {
    _zoomAutoHideTimer?.cancel();
    _zoomAutoHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showZoomBar) {
        setState(() => _showZoomBar = false);
      }
    });
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

  void _createNewTab({bool incognito = false, String? url, String? groupId}) {
    final target = url ?? _homepageUrl;
    final newTab = BrowserTab(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: incognito ? 'Incognito Tab' : 'New Tab',
      url: target,
      isIncognito: incognito,
      isDesktop: _isDesktopMode,
      groupId: groupId,
    );
    setState(() {
      _tabs.add(newTab);
      _activeTabIndex = _tabs.length - 1;
      _isIncognito = incognito;
    });
    _saveData();
    _loadFromSearchBar(target);
  }

  void _switchToTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    setState(() {
      _activeTabIndex = index;
      _isIncognito = tab.isIncognito;
      _isDesktopMode = tab.isDesktop;
    });
    _saveData();
    _applyNativeDesktopViewport(_isDesktopMode);
    _loadFromSearchBar(tab.url);
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final removedTab = _tabs[index];
    if (!removedTab.isIncognito) {
      _recentlyClosedTabs.insert(0, removedTab);
      if (_recentlyClosedTabs.length > 30) {
        _recentlyClosedTabs.removeLast();
      }
    }
    if (_tabs.length <= 1) {
      setState(() {
        _tabs[0] = BrowserTab(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'New Tab',
          url: _homepageUrl,
        );
        _activeTabIndex = 0;
        _isIncognito = false;
      });
      _saveData();
      _loadFromSearchBar(_homepageUrl);
      return;
    }
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
    _saveData();
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
  // CHROME-STYLE 3-DOT POPUP MENU
  // ===========================================================================
  void _openChromeStyleMenu() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Browser Menu',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim1, anim2) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 52, right: 10),
              child: Material(
                color: const Color(0xFF1E232E),
                elevation: 16,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFF2E3646), width: 1),
                ),
                child: SizedBox(
                  width: 286,
                  height: MediaQuery.of(context).size.height * 0.84,
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
                              tooltip: 'Download offline page',
                              onTap: () {
                                Navigator.pop(ctx);
                                _downloadCurrentPageOffline();
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

                      // FULL CHROME MENU ITEMS LIST
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 6),
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
                              icon: Icons.grid_view_outlined,
                              title: 'Add tab to new group',
                              onTap: () {
                                Navigator.pop(ctx);
                                _promptCreateTabGroupForCurrentTab();
                              },
                            ),
                            const Divider(height: 12),
                            _buildChromeMenuItem(
                              icon: Icons.history,
                              title: 'History',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenHistoryPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.delete_outline,
                              title: 'Delete browsing data',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openDeleteBrowsingDataDialog();
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
                                _openFullScreenDownloadsPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.star_border,
                              title: 'Bookmarks',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenBookmarksPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.devices_outlined,
                              title: 'Recent tabs',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenRecentTabsPage();
                              },
                            ),
                            const Divider(height: 12),
                            _buildChromeMenuItem(
                              icon: Icons.zoom_in,
                              title: 'Zoom',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openZoomControlsWithAutoHide();
                              },
                            ),
                            // SHARE ROW WITH DIRECT TELEGRAM QUICK ICON
                            InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                _openChromeShareSheet();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    const Icon(Icons.share_outlined,
                                        size: 21, color: Color(0xFFE2E8F0)),
                                    const SizedBox(width: 16),
                                    const Expanded(
                                      child: Text(
                                        'Share...',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Color(0xFFE2E8F0),
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _intentChannel
                                            .invokeMethod('shareLink', {
                                          'url': _currentUrl,
                                          'title': _pageTitle,
                                          'package': 'org.telegram.messenger',
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF2AABEE),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.send,
                                          size: 15,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
                              icon: Icons.g_translate,
                              title: 'Translate...',
                              onTap: () {
                                Navigator.pop(ctx);
                                _translateCurrentPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.chrome_reader_mode_outlined,
                              title: _isReadingMode
                                  ? 'Hide Reading mode'
                                  : 'Show Reading mode',
                              onTap: () {
                                Navigator.pop(ctx);
                                _toggleReadingMode();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.add_to_home_screen,
                              title: 'Install and create shortcut',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openInstallAndCreateShortcutSheet();
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
                            _buildChromeMenuItem(
                              icon: Icons.settings_outlined,
                              title: 'Settings',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenSettingsPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              icon: Icons.help_outline,
                              title: 'Help and feedback',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenHelpPage();
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
  // INSTALL AND CREATE SHORTCUT (Video 2: 01:34 - 01:59)
  // ===========================================================================
  void _openInstallAndCreateShortcutSheet() {
    final defaultTitle = _pageTitle.isNotEmpty
        ? _pageTitle
        : (Uri.tryParse(_currentUrl)?.host ?? 'Study Shortcut');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Install and create shortcut',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141821),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2D3343)),
              ),
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF263147),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.apps, color: Color(0xFFA8C7FA)),
                ),
                title: const Text('Install page as app',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(defaultTitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _promptConfirmPinShortcut(defaultTitle);
                },
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF141821),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2D3343)),
              ),
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF263147),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_to_home_screen,
                      color: Color(0xFFA8C7FA)),
                ),
                title: const Text('Create shortcut',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                subtitle: const Text('Shortcuts open in Study Browser'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _promptConfirmPinShortcut(defaultTitle);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _promptConfirmPinShortcut(String initialTitle) {
    final nameCtrl = TextEditingController(text: initialTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Add to Home screen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Touch and hold the icon or tap Add to place it on your Home screen:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Shortcut Title',
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _intentChannel.invokeMethod('createHomeShortcut', {
                'title': nameCtrl.text.trim(),
                'url': _currentUrl,
              });
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CHROME-STYLE SHARE SHEET (Video 2: 01:07 - 01:28)
  // ===========================================================================
  void _openChromeShareSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                const Text(
                  'Share link',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            // Link Preview Box with Copy Button
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141821),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2D3343)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF263147),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.public, color: Color(0xFFA8C7FA)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pageTitle.isNotEmpty ? _pageTitle : 'Web Page',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        Text(
                          _currentUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xFFA8C7FA), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy link',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _currentUrl));
                      Navigator.pop(ctx);
                      _showToast('लिंक कॉपी कर लिया गया');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Action Chips Row (Print, Send to device, QR Code, Save Offline)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.print_outlined, size: 17),
                    label: const Text('Print'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _intentChannel.invokeMethod('printPage', {
                        'title': _pageTitle,
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.qr_code, size: 17),
                    label: const Text('QR Code'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showQrCodeDialog();
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.download_outlined, size: 17),
                    label: const Text('Save Offline'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _downloadCurrentPageOffline();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Direct App Share Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildShareAppCircle(
                  label: 'WhatsApp',
                  icon: Icons.chat_bubble_outline,
                  color: const Color(0xFF25D366),
                  onTap: () {
                    Navigator.pop(ctx);
                    _intentChannel.invokeMethod('shareLink', {
                      'url': _currentUrl,
                      'title': _pageTitle,
                      'package': 'com.whatsapp',
                    });
                  },
                ),
                _buildShareAppCircle(
                  label: 'Telegram',
                  icon: Icons.send,
                  color: const Color(0xFF2AABEE),
                  onTap: () {
                    Navigator.pop(ctx);
                    _intentChannel.invokeMethod('shareLink', {
                      'url': _currentUrl,
                      'title': _pageTitle,
                      'package': 'org.telegram.messenger',
                    });
                  },
                ),
                _buildShareAppCircle(
                  label: 'Copy Link',
                  icon: Icons.link,
                  color: const Color(0xFF64748B),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: _currentUrl));
                    _showToast('लिंक कॉपी हो गया');
                  },
                ),
                _buildShareAppCircle(
                  label: 'More Apps',
                  icon: Icons.more_horiz,
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.pop(ctx);
                    _intentChannel.invokeMethod('shareLink', {
                      'url': _currentUrl,
                      'title': _pageTitle,
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareAppCircle({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _showQrCodeDialog() {
    final qrImageUrl =
        'https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=${Uri.encodeComponent(_currentUrl)}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232E),
        title: const Text('Scan QR Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.network(
                qrImageUrl,
                width: 200,
                height: 200,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 200,
                  height: 200,
                  child: Center(
                    child: Text('QR Preview requires internet',
                        style: TextStyle(color: Colors.black)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _currentUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
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
  // FULL-SCREEN CHROME GRID TAB SWITCHER & TAB GROUPS (Video 1: 01:51 - 02:24)
  // ===========================================================================
  void _openFullScreenTabSwitcher() {
    String searchQuery = '';
    bool showIncognitoOnly = _isIncognito;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setGridState) {
            final filteredTabs = _tabs.where((t) {
              if (t.isIncognito != showIncognitoOnly) return false;
              if (searchQuery.trim().isNotEmpty) {
                final q = searchQuery.toLowerCase();
                return t.title.toLowerCase().contains(q) ||
                    t.url.toLowerCase().contains(q);
              }
              return true;
            }).toList();

            // Separate ungrouped tabs and tab groups
            final ungroupedTabs = filteredTabs
                .where((t) =>
                    t.groupId == null ||
                    !_tabGroups.any((g) => g.id == t.groupId))
                .toList();

            return Scaffold(
              backgroundColor: const Color(0xFF12151C),
              appBar: AppBar(
                backgroundColor: const Color(0xFF12151C),
                elevation: 0,
                automaticallyImplyLeading: false,
                titleSpacing: 12,
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Blue + New Tab Button (Chrome Left)
                    InkWell(
                      onTap: () {
                        Navigator.pop(pageCtx);
                        _createNewTab(incognito: showIncognitoOnly);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ),

                    // Center Segmented Switcher ([ count ] | [ Incognito ])
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E232E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF2D3343)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () =>
                                setGridState(() => showIncognitoOnly = false),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: !showIncognitoOnly
                                    ? const Color(0xFF2E384D)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_tabs.where((t) => !t.isIncognito).length}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () =>
                                setGridState(() => showIncognitoOnly = true),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: showIncognitoOnly
                                    ? const Color(0xFF2E384D)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.visibility_off_outlined,
                                  size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Right 3-Dot Menu in Tab Switcher
                    PopupMenuButton<String>(
                      color: const Color(0xFF1E232E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      onSelected: (val) {
                        if (val == 'new_tab') {
                          Navigator.pop(pageCtx);
                          _createNewTab(incognito: false);
                        } else if (val == 'new_incognito') {
                          Navigator.pop(pageCtx);
                          _createNewTab(incognito: true);
                        } else if (val == 'new_group') {
                          _promptCreateNewTabGroupDialog(setGridState);
                        } else if (val == 'close_all') {
                          setState(() {
                            _tabs = [
                              BrowserTab(
                                id: DateTime.now()
                                    .millisecondsSinceEpoch
                                    .toString(),
                                title: 'New Tab',
                                url: _homepageUrl,
                              )
                            ];
                            _activeTabIndex = 0;
                            _isIncognito = false;
                          });
                          _saveData();
                          Navigator.pop(pageCtx);
                          _loadFromSearchBar(_homepageUrl);
                        } else if (val == 'clear_data') {
                          Navigator.pop(pageCtx);
                          _openDeleteBrowsingDataDialog();
                        } else if (val == 'settings') {
                          Navigator.pop(pageCtx);
                          _openFullScreenSettingsPage();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'new_tab',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.add_box_outlined),
                            title: Text('New tab'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'new_incognito',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.visibility_off_outlined),
                            title: Text('New Incognito tab'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'new_group',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.grid_view_outlined),
                            title: Text('New tab group'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'close_all',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.close_fullscreen),
                            title: Text('Close all tabs'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'clear_data',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.delete_outline),
                            title: Text('Delete browsing data'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'settings',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.settings_outlined),
                            title: Text('Settings'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              body: Column(
                children: [
                  // Search Your Tabs Bar
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E232E),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        onChanged: (v) => setGridState(() => searchQuery = v),
                        decoration: const InputDecoration(
                          hintText: 'Search your tabs',
                          prefixIcon: Icon(Icons.search, size: 20),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ),

                  // 2-COLUMN SYMMETRICAL CARD GRID (Tab Groups + Individual Tabs)
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: (!showIncognitoOnly ? _tabGroups.length : 0) +
                          ungroupedTabs.length,
                      itemBuilder: (_, idx) {
                        final groupCount =
                            !showIncognitoOnly ? _tabGroups.length : 0;
                        if (idx < groupCount) {
                          final group = _tabGroups[idx];
                          final groupTabs = _tabs
                              .where((t) => t.groupId == group.id)
                              .toList();
                          return _buildTabGroupGridCard(
                            group: group,
                            groupTabs: groupTabs,
                            pageCtx: pageCtx,
                            setGridState: setGridState,
                          );
                        }
                        final tab = ungroupedTabs[idx - groupCount];
                        final realIndex = _tabs.indexOf(tab);
                        return _buildSingleTabGridCard(
                          tab: tab,
                          realIndex: realIndex,
                          pageCtx: pageCtx,
                          setGridState: setGridState,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSingleTabGridCard({
    required BrowserTab tab,
    required int realIndex,
    required BuildContext pageCtx,
    required StateSetter setGridState,
  }) {
    final isSelected = realIndex == _activeTabIndex;
    final host = Uri.tryParse(tab.url)?.host.replaceAll('www.', '') ?? tab.url;

    return GestureDetector(
      onTap: () {
        Navigator.pop(pageCtx);
        _switchToTab(realIndex);
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E232E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFA8C7FA)
                : const Color(0xFF2E3646),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // Card Header
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
              child: Row(
                children: [
                  Icon(
                    tab.isIncognito ? Icons.visibility_off : Icons.public,
                    size: 16,
                    color: const Color(0xFFA8C7FA),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_vert, size: 16),
                    onSelected: (val) {
                      if (val == 'group') {
                        _promptMoveTabToGroup(tab, setGridState);
                      } else if (val == 'share') {
                        _intentChannel.invokeMethod('shareLink', {
                          'url': tab.url,
                          'title': tab.title,
                        });
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'group',
                        child: Text('Add tab to group'),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Text('Share'),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () {
                      _closeTab(realIndex);
                      setGridState(() {});
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 17),
                    ),
                  ),
                ],
              ),
            ),
            // Card Preview Body
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF12151C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFF263147),
                      child: Text(
                        host.isNotEmpty ? host[0].toUpperCase() : 'W',
                        style: const TextStyle(
                            color: Color(0xFFA8C7FA),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tab.title,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabGroupGridCard({
    required BrowserTabGroup group,
    required List<BrowserTab> groupTabs,
    required BuildContext pageCtx,
    required StateSetter setGridState,
  }) {
    final grpColor = Color(group.colorValue);
    return GestureDetector(
      onTap: () =>
          _openTabGroupDetailDialog(group, pageCtx, setGridState),
      child: Container(
        decoration: BoxDecoration(
          color: grpColor.withOpacity(0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: grpColor.withOpacity(0.7), width: 1.5),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: grpColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${group.title} (${groupTabs.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        for (final t in groupTabs) {
                          t.groupId = null;
                        }
                        _tabGroups.remove(group);
                      });
                      _saveData();
                      setGridState(() {});
                    },
                    child: const Icon(Icons.close, size: 17),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: groupTabs.length.clamp(0, 4),
                  itemBuilder: (_, i) {
                    final t = groupTabs[i];
                    return Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12151C),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        t.title,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openTabGroupDetailDialog(
    BrowserTabGroup group,
    BuildContext switcherCtx,
    StateSetter setGridState,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setGrpDialog) {
          final groupTabs =
              _tabs.where((t) => t.groupId == group.id).toList();
          return AlertDialog(
            backgroundColor: const Color(0xFF1E232E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                CircleAvatar(
                    radius: 7, backgroundColor: Color(group.colorValue)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${group.title} (${groupTabs.length} tabs)',
                      style: const TextStyle(fontSize: 16)),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add tab to this group',
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(switcherCtx);
                    _createNewTab(groupId: group.id);
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: groupTabs.isEmpty
                  ? const Text('इस ग्रुप में अभी कोई टैब नहीं है।')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: groupTabs.length,
                      itemBuilder: (_, i) {
                        final t = groupTabs[i];
                        final rIdx = _tabs.indexOf(t);
                        return ListTile(
                          leading: const Icon(Icons.public,
                              color: Color(0xFFA8C7FA)),
                          title: Text(t.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(t.url,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() => t.groupId = null);
                              _saveData();
                              setGrpDialog(() {});
                              setGridState(() {});
                            },
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.pop(switcherCtx);
                            _switchToTab(rIdx);
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _promptCreateTabGroupForCurrentTab() {
    _promptCreateNewTabGroupDialog(null, assignCurrentTab: true);
  }

  void _promptCreateNewTabGroupDialog(
    StateSetter? setGridState, {
    bool assignCurrentTab = false,
  }) {
    final titleCtrl = TextEditingController(text: '1 tab');
    final List<int> palette = [
      0xFF94A3B8,
      0xFF3B82F6,
      0xFFEF4444,
      0xFFF59E0B,
      0xFF10B981,
      0xFFEC4899,
      0xFFA855F7,
      0xFF06B6D4,
    ];
    int selectedColor = palette[1];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E232E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('New tab group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: palette.map((c) {
                  final isSel = c == selectedColor;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: isSel
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final newGrp = BrowserTabGroup(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleCtrl.text.trim().isEmpty
                      ? 'Study Group'
                      : titleCtrl.text.trim(),
                  colorValue: selectedColor,
                );
                setState(() {
                  _tabGroups.add(newGrp);
                  if (assignCurrentTab &&
                      _tabs.isNotEmpty &&
                      _activeTabIndex < _tabs.length) {
                    _tabs[_activeTabIndex].groupId = newGrp.id;
                  }
                });
                _saveData();
                if (setGridState != null) setGridState(() {});
                Navigator.pop(ctx);
                _showToast('Tab group "${newGrp.title}" बनाया गया');
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  void _promptMoveTabToGroup(BrowserTab tab, StateSetter setGridState) {
    if (_tabGroups.isEmpty) {
      _promptCreateNewTabGroupDialog(setGridState, assignCurrentTab: true);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E232E),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add tab to group',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const Divider(),
            ..._tabGroups.map((g) => ListTile(
                  leading:
                      CircleAvatar(radius: 8, backgroundColor: Color(g.colorValue)),
                  title: Text(g.title),
                  onTap: () {
                    setState(() => tab.groupId = g.id);
                    _saveData();
                    setGridState(() {});
                    Navigator.pop(ctx);
                    _showToast('Tab added to ${g.title}');
                  },
                )),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // FULL-SCREEN CHROME DOWNLOADS PAGE (Video 1: 00:46 - 01:20)
  // ===========================================================================
  Future<void> _openFullScreenDownloadsPage() async {
    String selectedFilter = 'All';
    String searchQuery = '';
    bool showSearch = false;
    String storageLabel = 'Using 9.84 GB of 110.34 GB';
    double storageRatio = 0.12;

    try {
      final stats = await _intentChannel.invokeMethod('getStorageStats');
      if (stats is Map) {
        storageLabel = (stats['label'] ?? storageLabel).toString();
        storageRatio =
            ((stats['ratio'] ?? 0.12) as num).toDouble().clamp(0.02, 0.98);
      }
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setDlPage) {
            final filters = ['All', 'Videos', 'Images', 'Pages', 'Other'];
            final filteredList = _downloads.where((d) {
              if (selectedFilter != 'All' && d.category != selectedFilter) {
                return false;
              }
              if (searchQuery.trim().isNotEmpty) {
                final q = searchQuery.toLowerCase();
                return d.title.toLowerCase().contains(q) ||
                    d.url.toLowerCase().contains(q);
              }
              return true;
            }).toList();

            return Scaffold(
              backgroundColor: const Color(0xFF12151C),
              appBar: AppBar(
                backgroundColor: const Color(0xFF12151C),
                automaticallyImplyLeading: false,
                title: showSearch
                    ? TextField(
                        autofocus: true,
                        onChanged: (v) => setDlPage(() => searchQuery = v),
                        decoration: const InputDecoration(
                          hintText: 'Search downloads...',
                          border: InputBorder.none,
                        ),
                      )
                    : const Text('Downloads',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () {
                      Navigator.pop(pageCtx);
                      _openFullScreenSettingsPage();
                    },
                  ),
                  IconButton(
                    icon: Icon(showSearch ? Icons.search_off : Icons.search),
                    onPressed: () => setDlPage(() {
                      showSearch = !showSearch;
                      if (!showSearch) searchQuery = '';
                    }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(pageCtx),
                  ),
                ],
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Storage Usage Indicator
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          storageLabel,
                          style: const TextStyle(
                              fontSize: 12.5, color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: storageRatio,
                            minHeight: 4,
                            color: const Color(0xFF3B82F6),
                            backgroundColor: const Color(0xFF283040),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Filter Chips Row (All, Videos, Images, Pages, Other)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: filters.map((f) {
                        final isSel = selectedFilter == f;
                        IconData chipIcon = Icons.check;
                        if (f == 'Videos') chipIcon = Icons.videocam_outlined;
                        if (f == 'Images') chipIcon = Icons.image_outlined;
                        if (f == 'Pages') chipIcon = Icons.public;
                        if (f == 'Other') {
                          chipIcon = Icons.insert_drive_file_outlined;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            selected: isSel,
                            showCheckmark: false,
                            avatar: Icon(chipIcon, size: 17),
                            label: Text(f),
                            selectedColor: const Color(0xFF263147),
                            backgroundColor: const Color(0xFF1E232E),
                            onSelected: (_) =>
                                setDlPage(() => selectedFilter = f),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const Divider(height: 8),

                  Expanded(
                    child: filteredList.isEmpty
                        ? const Center(
                            child: Text(
                              'Downloads you save appear here',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: filteredList.length,
                            itemBuilder: (_, i) {
                              final item = filteredList[i];
                              final showHeader = i == 0 ||
                                  filteredList[i - 1].dateLabel !=
                                      item.dateLabel;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showHeader)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 12, bottom: 8),
                                      child: Text(
                                        item.dateLabel,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      radius: 20,
                                      backgroundColor:
                                          const Color(0xFF1E232E),
                                      child: Icon(
                                        item.category == 'Pages'
                                            ? Icons.public
                                            : (item.category == 'Images'
                                                ? Icons.image_outlined
                                                : (item.category == 'Videos'
                                                    ? Icons.videocam_outlined
                                                    : Icons
                                                        .insert_drive_file_outlined)),
                                        color: const Color(0xFFA8C7FA),
                                      ),
                                    ),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    subtitle: Text(
                                      item.sizeLabel,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white60),
                                    ),
                                    onTap: () => _openDownloadEntry(item),
                                    trailing: PopupMenuButton<String>(
                                      color: const Color(0xFF1E232E),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      onSelected: (val) async {
                                        if (val == 'share') {
                                          await _intentChannel
                                              .invokeMethod('shareLink', {
                                            'url': item.url.isNotEmpty
                                                ? item.url
                                                : item.filePath,
                                            'title': item.title,
                                          });
                                        } else if (val == 'rename') {
                                          _promptRenameDownloadItem(
                                              item, setDlPage);
                                        } else if (val == 'delete') {
                                          await _intentChannel.invokeMethod(
                                              'deleteFileOnDisk', {
                                            'filePath': item.filePath,
                                          });
                                          setState(
                                              () => _downloads.remove(item));
                                          setDlPage(() {});
                                          await _saveData();
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'share',
                                          child: Text('Share'),
                                        ),
                                        PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _promptRenameDownloadItem(
      DownloadEntry item, StateSetter setDlPage) {
    final ctrl = TextEditingController(text: item.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232E),
        title: const Text('Rename file'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty) {
                final updatedPath = await _intentChannel
                    .invokeMethod<String>('renameFileOnDisk', {
                  'oldPath': item.filePath,
                  'newName': newName,
                });
                setState(() {
                  item.title = newName;
                  if (updatedPath != null) item.filePath = updatedPath;
                });
                setDlPage(() {});
                await _saveData();
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FULL-SCREEN CHROME HISTORY PAGE & DELETE BROWSING DATA (Video 2: 00:13 - 00:48)
  // ===========================================================================
  void _openFullScreenHistoryPage() {
    String searchQuery = '';
    bool showSearch = false;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setHistPage) {
            final filtered = _history.where((h) {
              if (searchQuery.trim().isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return h.title.toLowerCase().contains(q) ||
                  h.url.toLowerCase().contains(q);
            }).toList();

            return Scaffold(
              backgroundColor: const Color(0xFF12151C),
              appBar: AppBar(
                backgroundColor: const Color(0xFF12151C),
                automaticallyImplyLeading: false,
                title: showSearch
                    ? TextField(
                        autofocus: true,
                        onChanged: (v) => setHistPage(() => searchQuery = v),
                        decoration: const InputDecoration(
                          hintText: 'Search history...',
                          border: InputBorder.none,
                        ),
                      )
                    : const Text('History',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () => _showToast(
                        'History is stored locally on your device only.'),
                  ),
                  IconButton(
                    icon: Icon(showSearch ? Icons.search_off : Icons.search),
                    onPressed: () => setHistPage(() {
                      showSearch = !showSearch;
                      if (!showSearch) searchQuery = '';
                    }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(pageCtx),
                  ),
                ],
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    color: const Color(0xFF181C26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'You may see history from links opened in Study Browser.',
                          style: TextStyle(fontSize: 12.5, color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            await _openDeleteBrowsingDataDialog();
                            setHistPage(() {});
                          },
                          child: const Text(
                            'Delete browsing data...',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFFA8C7FA),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No browsing history here',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final item = filtered[i];
                              final host = Uri.tryParse(item.url)
                                      ?.host
                                      .replaceAll('www.', '') ??
                                  item.url;
                              final showDate = i == 0 ||
                                  filtered[i - 1].dateGroup != item.dateGroup;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showDate)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 10, bottom: 8),
                                      child: Text(
                                        item.dateGroup,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor:
                                          const Color(0xFF1E232E),
                                      child: Text(
                                        host.isNotEmpty
                                            ? host[0].toUpperCase()
                                            : 'G',
                                        style: const TextStyle(
                                            color: Color(0xFFA8C7FA),
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      host,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white54),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.cancel_outlined,
                                          size: 20, color: Colors.white60),
                                      onPressed: () async {
                                        setState(() => _history.remove(item));
                                        setHistPage(() {});
                                        await _saveData();
                                      },
                                    ),
                                    onTap: () {
                                      Navigator.pop(pageCtx);
                                      _loadFromSearchBar(item.url);
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openDeleteBrowsingDataDialog() async {
    String timeRange = 'Last 15 minutes';
    bool delHistory = true;
    bool delCookies = true;
    bool delCache = true;
    bool delTabs = false;
    bool delAutofill = true;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setDelState) => Scaffold(
            backgroundColor: const Color(0xFF12151C),
            appBar: AppBar(
              backgroundColor: const Color(0xFF12151C),
              title: const Text('Delete browsing data'),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Time range',
                        style: TextStyle(color: Colors.white70)),
                    DropdownButton<String>(
                      value: timeRange,
                      dropdownColor: const Color(0xFF1E232E),
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                            value: 'Last 15 minutes',
                            child: Text('Last 15 minutes')),
                        DropdownMenuItem(
                            value: 'Last hour', child: Text('Last hour')),
                        DropdownMenuItem(
                            value: 'Last 24 hours',
                            child: Text('Last 24 hours')),
                        DropdownMenuItem(
                            value: 'Last 7 days', child: Text('Last 7 days')),
                        DropdownMenuItem(
                            value: 'All time', child: Text('All time')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDelState(() => timeRange = v);
                      },
                    ),
                  ],
                ),
                const Divider(height: 24),
                CheckboxListTile(
                  secondary: const Icon(Icons.history),
                  title: const Text('Browsing history'),
                  subtitle: Text('${_history.length} items recorded'),
                  value: delHistory,
                  onChanged: (v) =>
                      setDelState(() => delHistory = v ?? true),
                ),
                CheckboxListTile(
                  secondary: const Icon(Icons.cookie_outlined),
                  title: const Text('Cookies and site data'),
                  subtitle: const Text('Signs you out of most sites'),
                  value: delCookies,
                  onChanged: (v) =>
                      setDelState(() => delCookies = v ?? true),
                ),
                CheckboxListTile(
                  secondary: const Icon(Icons.image_outlined),
                  title: const Text('Cached images and files'),
                  subtitle: const Text('Frees up WebView storage'),
                  value: delCache,
                  onChanged: (v) => setDelState(() => delCache = v ?? true),
                ),
                CheckboxListTile(
                  secondary: const Icon(Icons.tab_outlined),
                  title: const Text('Close open tabs'),
                  subtitle: Text('${_tabs.length} tabs currently open'),
                  value: delTabs,
                  onChanged: (v) => setDelState(() => delTabs = v ?? false),
                ),
                CheckboxListTile(
                  secondary: const Icon(Icons.edit_outlined),
                  title: const Text('Autofill form data'),
                  subtitle: const Text('Clears form entries'),
                  value: delAutofill,
                  onChanged: (v) =>
                      setDelState(() => delAutofill = v ?? true),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Note: Your Focus & Lock passwords and Whitelist rules will NOT be deleted.',
                  style: TextStyle(fontSize: 12.5, color: Colors.white54),
                ),
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      if (delHistory) {
                        setState(() => _history.clear());
                      }
                      if (delCookies) {
                        await _webController.clearLocalStorage();
                      }
                      if (delCache) {
                        await _webController.clearCache();
                      }
                      if (delTabs) {
                        setState(() {
                          _tabs = [
                            BrowserTab(
                              id: DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              title: 'New Tab',
                              url: _homepageUrl,
                            )
                          ];
                          _activeTabIndex = 0;
                        });
                      }
                      await _saveData();
                      if (mounted) Navigator.pop(pageCtx);
                      _showToast('Browsing data ($timeRange) साफ़ कर दिया गया');
                    },
                    child: const Text('Delete data'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // FULL-SCREEN RECENT TABS, BOOKMARKS, SETTINGS & HELP PAGES
  // ===========================================================================
  void _openFullScreenRecentTabsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => Scaffold(
          backgroundColor: const Color(0xFF12151C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF12151C),
            title: const Text('Recent tabs'),
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(pageCtx),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Recently closed',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70),
              ),
              const SizedBox(height: 8),
              if (_recentlyClosedTabs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No recently closed tabs',
                      style: TextStyle(color: Colors.white54)),
                )
              else
                ..._recentlyClosedTabs.map((t) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF1E232E),
                        child:
                            Icon(Icons.public, color: Color(0xFFA8C7FA), size: 18),
                      ),
                      title: Text(t.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(t.url,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.pop(pageCtx);
                        _createNewTab(incognito: false, url: t.url);
                      },
                    )),
              const Divider(height: 28),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1E232E),
                  child: Icon(Icons.history, color: Color(0xFFA8C7FA)),
                ),
                title: const Text('Show full history'),
                onTap: () {
                  Navigator.pop(pageCtx);
                  _openFullScreenHistoryPage();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFullScreenBookmarksPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setBmPage) => Scaffold(
            backgroundColor: const Color(0xFF12151C),
            appBar: AppBar(
              backgroundColor: const Color(0xFF12151C),
              title: const Text('Bookmarks'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.bookmark_add_outlined),
                  tooltip: 'Bookmark current page',
                  onPressed: () async {
                    await _toggleCurrentBookmark();
                    setBmPage(() {});
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(pageCtx),
                ),
              ],
            ),
            body: _bookmarks.isEmpty
                ? const Center(
                    child: Text('No bookmarks saved yet',
                        style: TextStyle(color: Colors.white54)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _bookmarks.length,
                    itemBuilder: (_, i) {
                      final bm = _bookmarks[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF1E232E),
                          child: Icon(Icons.star,
                              color: Color(0xFFA8C7FA), size: 18),
                        ),
                        title: Text(bm.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(bm.url,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            setState(() => _bookmarks.removeAt(i));
                            setBmPage(() {});
                            await _saveData();
                          },
                        ),
                        onTap: () {
                          Navigator.pop(pageCtx);
                          _loadFromSearchBar(bm.url);
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  void _openFullScreenSettingsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setSettingsState) => Scaffold(
            backgroundColor: const Color(0xFF12151C),
            appBar: AppBar(
              backgroundColor: const Color(0xFF12151C),
              title: const Text('Settings'),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSettingsCard(
                  title: 'Default browser',
                  subtitle: 'Set Study Browser as your system default browser',
                  icon: Icons.open_in_browser,
                  onTap: () {
                    _intentChannel.invokeMethod('openDefaultAppsSettings');
                  },
                ),
                _buildSettingsCard(
                  title: 'Search engine',
                  subtitle: _searchEngineUrl.contains('duckduckgo')
                      ? 'DuckDuckGo'
                      : (_searchEngineUrl.contains('bing')
                          ? 'Microsoft Bing'
                          : 'Google'),
                  icon: Icons.search,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF1E232E),
                      builder: (ctx) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: const Text('Google (Default)'),
                            onTap: () {
                              setState(() => _searchEngineUrl =
                                  'https://www.google.com/search?q=');
                              setSettingsState(() {});
                              _saveData();
                              Navigator.pop(ctx);
                            },
                          ),
                          ListTile(
                            title: const Text('DuckDuckGo'),
                            onTap: () {
                              setState(() => _searchEngineUrl =
                                  'https://duckduckgo.com/?q=');
                              setSettingsState(() {});
                              _saveData();
                              Navigator.pop(ctx);
                            },
                          ),
                          ListTile(
                            title: const Text('Bing'),
                            onTap: () {
                              setState(() => _searchEngineUrl =
                                  'https://www.bing.com/search?q=');
                              setSettingsState(() {});
                              _saveData();
                              Navigator.pop(ctx);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Advanced',
                      style: TextStyle(
                          color: Color(0xFFA8C7FA),
                          fontWeight: FontWeight.w600)),
                ),
                _buildSettingsCard(
                  title: 'Tabs and tab groups',
                  subtitle: '${_tabs.length} open tabs • Auto-restore enabled',
                  icon: Icons.layers_outlined,
                  onTap: () {
                    Navigator.pop(pageCtx);
                    _openFullScreenTabSwitcher();
                  },
                ),
                _buildSettingsCard(
                  title: 'Homepage',
                  subtitle: 'On • $_homepageUrl',
                  icon: Icons.home_outlined,
                  onTap: () {
                    final ctrl = TextEditingController(text: _homepageUrl);
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1E232E),
                        title: const Text('Homepage URL'),
                        content: TextField(controller: ctrl),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel')),
                          FilledButton(
                            onPressed: () {
                              setState(
                                  () => _homepageUrl = ctrl.text.trim());
                              setSettingsState(() {});
                              _saveData();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                _buildSettingsCard(
                  title: 'Focus & Lock Security',
                  subtitle:
                      'Manage YouTube Shorts, Instagram Reels & Group Locks',
                  icon: Icons.shield_outlined,
                  onTap: () {
                    Navigator.pop(pageCtx);
                    _openLockManagerSheet();
                  },
                ),
                _buildSettingsCard(
                  title: 'Site settings',
                  subtitle:
                      'Desktop mode: ${_isDesktopMode ? "On" : "Off"} • Default Zoom: $_zoomPercent%',
                  icon: Icons.tune,
                  onTap: () {
                    _toggleDesktopMode();
                    setSettingsState(() {});
                  },
                ),
                _buildSettingsCard(
                  title: 'Downloads',
                  subtitle: '/storage/emulated/0/Download',
                  icon: Icons.download_done_outlined,
                  onTap: () {
                    Navigator.pop(pageCtx);
                    _openFullScreenDownloadsPage();
                  },
                ),
                _buildSettingsCard(
                  title: 'About Study Browser',
                  subtitle: 'Version 2.0.0 • Chrome Dark UI + Focus Vault',
                  icon: Icons.info_outline,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E232E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFA8C7FA)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.white60)),
        onTap: onTap,
      ),
    );
  }

  void _openFullScreenHelpPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => Scaffold(
          backgroundColor: const Color(0xFF12151C),
          appBar: AppBar(
            backgroundColor: const Color(0xFF12151C),
            title: const Text('Help & Feedback'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: const [
              Text(
                'Popular help resources',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFA8C7FA)),
              ),
              SizedBox(height: 12),
              ListTile(
                leading: Icon(Icons.article_outlined, color: Color(0xFFA8C7FA)),
                title: Text('How Time-Vault & Focus Locks work'),
                subtitle: Text(
                    'Generate a 16-digit password, copy it to Chronocrypt Vault, and lock distracting sites or YouTube Shorts.'),
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.desktop_windows_outlined,
                    color: Color(0xFFA8C7FA)),
                title: Text('Using Desktop Site Mode'),
                subtitle: Text(
                    'Turn on Desktop site from the 3-dot menu to view full 1280px computer layouts on mobile.'),
              ),
              Divider(),
              ListTile(
                leading:
                    Icon(Icons.add_to_home_screen, color: Color(0xFFA8C7FA)),
                title: Text('Install & Create Home Screen Shortcuts'),
                subtitle: Text(
                    'Use "Install and create shortcut" in the 3-dot menu to pin any study web app directly to your Realme home screen.'),
              ),
              Divider(),
              ListTile(
                leading:
                    Icon(Icons.download_done_outlined, color: Color(0xFFA8C7FA)),
                title: Text('Opening Downloaded ZIP, PDF & Offline Pages'),
                subtitle: Text(
                    'Tap any file in Downloads to open it directly or choose an app (Files by Google, WPS Office) via Open With.'),
              ),
            ],
          ),
        ),
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
  // PASSWORD DIALOGS & CLEAN 2-TAB FOCUS LOCK MANAGER
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
                        // TAB 1: FOCUS CONTROLS
                        ListView(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          children: [
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

                        // TAB 2: SITE LOCK GROUPS
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

  // ===========================================================================
  // MAIN SCAFFOLD (TOP BAR + WEBVIEW + AUTO-HIDING BOTTOM ZOOM OVERLAY)
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
          _loadFromSearchBar(_homepageUrl);
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
              // TOP CHROME BAR
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
                      onPressed: () => _loadFromSearchBar(_homepageUrl),
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
                    // Tab Counter Box [ 1 ] -> Opens Chrome Grid Tab Switcher
                    InkWell(
                      onTap: _openFullScreenTabSwitcher,
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
                    IconButton(
                      icon: const Icon(Icons.shield_outlined,
                          size: 21, color: Color(0xFFA8C7FA)),
                      tooltip: 'Focus & Lock Manager',
                      onPressed: _openLockManagerSheet,
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert, size: 22),
                      tooltip: 'More options',
                      onPressed: _openChromeStyleMenu,
                    ),
                  ],
                ),
              ),

              // FIND IN PAGE BAR
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

              if (_loadingProgress < 100)
                LinearProgressIndicator(
                  value: _loadingProgress / 100.0,
                  minHeight: 2,
                  color: const Color(0xFFA8C7FA),
                  backgroundColor: Colors.transparent,
                ),

              // MAIN WEBVIEW + FLOATING CHROME ZOOM BAR + BLOCKED OVERLAY
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _webController),

                    // CHROME-STYLE BOTTOM FLOATING ZOOM CONTROL (Auto-Hides after 4s)
                    if (_showZoomBar)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 18,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Top Pill: [ 100% | Reset ]
                            Material(
                              color: const Color(0xFF1E232E),
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(
                                    color: Color(0xFF2E3646)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$_zoomPercent %',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14),
                                    ),
                                    const SizedBox(width: 10),
                                    TextButton(
                                      onPressed: () {
                                        setState(() => _zoomPercent = 100);
                                        _injectFocusScripts();
                                        _scheduleZoomAutoHide();
                                      },
                                      child: const Text('Reset'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Bottom Slider Bar: [ - ] ====●==== [ + ]
                            Material(
                              color: const Color(0xFF1E232E),
                              elevation: 10,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                                side: const BorderSide(
                                    color: Color(0xFF2E3646)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove),
                                      onPressed: () {
                                        setState(() {
                                          _zoomPercent =
                                              (_zoomPercent - 10).clamp(50, 200);
                                        });
                                        _injectFocusScripts();
                                        _scheduleZoomAutoHide();
                                      },
                                    ),
                                    Expanded(
                                      child: Slider(
                                        value: _zoomPercent.toDouble(),
                                        min: 50,
                                        max: 200,
                                        divisions: 15,
                                        activeColor: const Color(0xFF3B82F6),
                                        onChanged: (v) {
                                          setState(
                                              () => _zoomPercent = v.round());
                                          _injectFocusScripts();
                                          _scheduleZoomAutoHide();
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add),
                                      onPressed: () {
                                        setState(() {
                                          _zoomPercent =
                                              (_zoomPercent + 10).clamp(50, 200);
                                        });
                                        _injectFocusScripts();
                                        _scheduleZoomAutoHide();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

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
              _loadFromSearchBar(_homepageUrl);
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
