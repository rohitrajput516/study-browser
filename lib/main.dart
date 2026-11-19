import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

final ValueNotifier<ThemeMode> appThemeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.system);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StudyBrowserApp());
}

class StudyBrowserApp extends StatelessWidget {
  const StudyBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeModeNotifier,
      builder: (_, themeMode, __) {
        return MaterialApp(
          title: 'Study Browser',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFFFFFFF),
            primaryColor: const Color(0xFF0B57D0),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0B57D0),
              secondary: Color(0xFF1A73E8),
              surface: Color(0xFFF3F6FC),
              onSurface: Color(0xFF1F1F1F),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFFFFFFF),
              foregroundColor: Color(0xFF1F1F1F),
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            dividerColor: const Color(0xFFE0E3E7),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF1F1F1F),
            primaryColor: const Color(0xFFA8C7FA),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFA8C7FA),
              secondary: Color(0xFF8AB4F8),
              surface: Color(0xFF28292C),
              onSurface: Color(0xFFE3E3E3),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1F1F1F),
              foregroundColor: Color(0xFFE3E3E3),
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
            dividerColor: const Color(0xFF3C4043),
          ),
          home: const BrowserHomeScreen(),
        );
      },
    );
  }
}

class ChromePalette {
  final bool isDark;
  final bool isIncognito;
  final Color bg;
  final Color surface;
  final Color surfaceVariant;
  final Color addressBar;
  final Color card;
  final Color border;
  final Color text;
  final Color subtext;
  final Color accent;
  final Color menuBg;
  final Color topIconBg;

  const ChromePalette({
    required this.isDark,
    required this.isIncognito,
    required this.bg,
    required this.surface,
    required this.surfaceVariant,
    required this.addressBar,
    required this.card,
    required this.border,
    required this.text,
    required this.subtext,
    required this.accent,
    required this.menuBg,
    required this.topIconBg,
  });

  static ChromePalette of(BuildContext context, {bool incognito = false}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (incognito) {
      return const ChromePalette(
        isDark: true,
        isIncognito: true,
        bg: Color(0xFF1F1F23),
        surface: Color(0xFF28282E),
        surfaceVariant: Color(0xFF32323A),
        addressBar: Color(0xFF33333C),
        card: Color(0xFF2A2A32),
        border: Color(0xFF42424D),
        text: Color(0xFFF1F3F4),
        subtext: Color(0xFFBDC1C6),
        accent: Color(0xFFA8C7FA),
        menuBg: Color(0xFF2A2A32),
        topIconBg: Color(0xFF383842),
      );
    }
    if (dark) {
      return const ChromePalette(
        isDark: true,
        isIncognito: false,
        bg: Color(0xFF1F1F1F),
        surface: Color(0xFF28292C),
        surfaceVariant: Color(0xFF303134),
        addressBar: Color(0xFF303134),
        card: Color(0xFF28292C),
        border: Color(0xFF3C4043),
        text: Color(0xFFE3E3E3),
        subtext: Color(0xFF9AA0A6),
        accent: Color(0xFFA8C7FA),
        menuBg: Color(0xFF2D2E31),
        topIconBg: Color(0xFF3C4043),
      );
    }
    return const ChromePalette(
      isDark: false,
      isIncognito: false,
      bg: Color(0xFFFFFFFF),
      surface: Color(0xFFF3F6FC),
      surfaceVariant: Color(0xFFE9EEF6),
      addressBar: Color(0xFFEDF2FA),
      card: Color(0xFFF6F8FC),
      border: Color(0xFFDDE3EA),
      text: Color(0xFF1F1F1F),
      subtext: Color(0xFF5F6368),
      accent: Color(0xFF0B57D0),
      menuBg: Color(0xFFFFFFFF),
      topIconBg: Color(0xFFEEF3FA),
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
  int createdAt;
  bool isReadingList;

  BookmarkItem({
    required this.title,
    required this.url,
    int? createdAt,
    this.isReadingList = false,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'createdAt': createdAt,
        'isReadingList': isReadingList,
      };

  factory BookmarkItem.fromJson(Map<String, dynamic> json) => BookmarkItem(
        title: (json['title'] ?? 'Bookmark').toString(),
        url: (json['url'] ?? 'https://www.google.com').toString(),
        createdAt: (json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch)
            as int,
        isReadingList: json['isReadingList'] == true,
      );
}

class HistoryItem {
  String title;
  String url;
  String timestamp;
  String dateGroup;
  int visitEpochMs;

  HistoryItem({
    required this.title,
    required this.url,
    required this.timestamp,
    required this.dateGroup,
    int? visitEpochMs,
  }) : visitEpochMs = visitEpochMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'timestamp': timestamp,
        'dateGroup': dateGroup,
        'visitEpochMs': visitEpochMs,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        title: (json['title'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        timestamp: (json['timestamp'] ?? '').toString(),
        dateGroup: (json['dateGroup'] ?? 'Today').toString(),
        visitEpochMs: (json['visitEpochMs'] ??
            DateTime.now().millisecondsSinceEpoch) as int,
      );
}

class DownloadEntry {
  String id;
  int downloadId;
  String title;
  String url;
  String filePath;
  String sizeLabel;
  String category; // Pages, Videos, Images, Other
  String dateLabel;
  String status; // running, pending, paused, successful, failed
  double progress; // 0.0..1.0, -1.0 indeterminate
  int bytesDownloaded;
  int totalBytes;

  DownloadEntry({
    required this.id,
    this.downloadId = -1,
    required this.title,
    required this.url,
    required this.filePath,
    required this.sizeLabel,
    required this.category,
    required this.dateLabel,
    this.status = 'successful',
    this.progress = 1.0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
  });

  bool get isInProgress =>
      status == 'running' || status == 'pending' || status == 'paused';

  Map<String, dynamic> toJson() => {
        'id': id,
        'downloadId': downloadId,
        'title': title,
        'url': url,
        'filePath': filePath,
        'sizeLabel': sizeLabel,
        'category': category,
        'dateLabel': dateLabel,
        'status': status,
        'progress': progress,
        'bytesDownloaded': bytesDownloaded,
        'totalBytes': totalBytes,
      };

  factory DownloadEntry.fromJson(Map<String, dynamic> json) => DownloadEntry(
        id: (json['id'] ?? '').toString(),
        downloadId: (json['downloadId'] ?? -1) as int,
        title: (json['title'] ?? 'Downloaded File').toString(),
        url: (json['url'] ?? '').toString(),
        filePath: (json['filePath'] ?? '').toString(),
        sizeLabel: (json['sizeLabel'] ?? '0 B').toString(),
        category: (json['category'] ?? 'Other').toString(),
        dateLabel: (json['dateLabel'] ?? 'Today').toString(),
        status: (json['status'] ?? 'successful').toString(),
        progress: ((json['progress'] ?? 1.0) as num).toDouble(),
        bytesDownloaded: (json['bytesDownloaded'] ?? 0) as int,
        totalBytes: (json['totalBytes'] ?? 0) as int,
      );
}

class BrowserTab {
  String id;
  String title;
  String url;
  bool isIncognito;
  bool isDesktop;
  String? groupId;
  String? thumbnailPath;

  BrowserTab({
    required this.id,
    required this.title,
    required this.url,
    this.isIncognito = false,
    this.isDesktop = false,
    this.groupId,
    this.thumbnailPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'isIncognito': isIncognito,
        'isDesktop': isDesktop,
        'groupId': groupId,
        'thumbnailPath': thumbnailPath,
      };

  factory BrowserTab.fromJson(Map<String, dynamic> json) => BrowserTab(
        id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString())
            .toString(),
        title: (json['title'] ?? 'New Tab').toString(),
        url: (json['url'] ?? 'https://www.google.com').toString(),
        isIncognito: json['isIncognito'] == true,
        isDesktop: json['isDesktop'] == true,
        groupId: json['groupId']?.toString(),
        thumbnailPath: json['thumbnailPath']?.toString(),
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
  Timer? _downloadPollTimer;
  Timer? _zoomAutoHideTimer;
  bool _webViewReady = false;

  int _loadingProgress = 0;
  String _currentUrl = 'https://www.google.com';
  String _pageTitle = 'Google';

  // Theme & Browser Preferences
  String _themePreference = 'system'; // system, light, dark
  bool _darkenWebsitesInDark = false;
  bool _isDesktopMode = false;
  bool _isIncognito = false;
  bool _isReadingMode = false;
  bool _showFindBar = false;
  bool _showZoomBar = false;
  int _zoomPercent = 100;
  String _searchEngineUrl = 'https://www.google.com/search?q=';
  String _homepageUrl = 'https://www.google.com';
  String _lastSharedApp = 'whatsapp'; // whatsapp, telegram, more
  bool _bookmarkVisualView = true;
  String _bookmarkSortOrder = 'manual'; // manual, newest, oldest, az, za

  List<BrowserTab> _tabs = [];
  List<BrowserTabGroup> _tabGroups = [];
  List<BrowserTab> _recentlyClosedTabs = [];
  List<String> _recentSearches = [];
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
  List<String> _permanentBlockedDomains = [];
  List<BookmarkItem> _bookmarks = [];
  List<HistoryItem> _history = [];
  List<DownloadEntry> _downloads = [];
  final ValueNotifier<int> _downloadsUpdateTick = ValueNotifier<int>(0);

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

      // 5. CHROME-STYLE IMAGE LONG-PRESS CONTEXT MENU DETECTOR
      if (!window.__SB_IMG_LONGPRESS_SET) {
        window.__SB_IMG_LONGPRESS_SET = true;
        var lpTimer = null;
        var lpStartX = 0;
        var lpStartY = 0;

        function findImageFromTarget(el) {
          var curr = el;
          for (var i = 0; i < 4 && curr; i++) {
            if (curr.tagName && curr.tagName.toLowerCase() === 'img' && curr.src) {
              return curr;
            }
            if (curr.querySelector) {
              var nested = curr.querySelector('img');
              if (nested && nested.src && curr.getBoundingClientRect().width < window.innerWidth * 1.05) {
                if (el === curr || el.tagName === 'DIV') return nested;
              }
            }
            curr = curr.parentElement;
          }
          return null;
        }

        document.addEventListener('contextmenu', function(e) {
          var img = findImageFromTarget(e.target);
          if (img && img.src && img.src.startsWith('http')) {
            e.preventDefault();
            e.stopPropagation();
            if (window.StudyBrowserBridge) {
              window.StudyBrowserBridge.postMessage(JSON.stringify({
                type: 'image_long_press',
                src: img.currentSrc || img.src,
                alt: img.alt || document.title || 'Image',
                pageUrl: window.location.href
              }));
            }
          }
        }, true);

        document.addEventListener('touchstart', function(e) {
          if (e.touches.length !== 1) return;
          var img = findImageFromTarget(e.target);
          if (!img || !img.src || !img.src.startsWith('http')) return;
          lpStartX = e.touches[0].clientX;
          lpStartY = e.touches[0].clientY;
          clearTimeout(lpTimer);
          lpTimer = setTimeout(function() {
            if (window.StudyBrowserBridge) {
              window.StudyBrowserBridge.postMessage(JSON.stringify({
                type: 'image_long_press',
                src: img.currentSrc || img.src,
                alt: img.alt || document.title || 'Image',
                pageUrl: window.location.href
              }));
            }
          }, 520);
        }, { passive: true });

        document.addEventListener('touchmove', function(e) {
          if (!lpTimer || e.touches.length !== 1) return;
          if (Math.abs(e.touches[0].clientX - lpStartX) > 14 || Math.abs(e.touches[0].clientY - lpStartY) > 14) {
            clearTimeout(lpTimer);
            lpTimer = null;
          }
        }, { passive: true });

        document.addEventListener('touchend', function() {
          clearTimeout(lpTimer);
          lpTimer = null;
        }, { passive: true });
      }
      
      
              // 6. PERMANENT BLOCKED SITES - HIDE FROM SEARCH RESULTS
        if (Array.isArray(window.__SB_PERM_DOMAINS) && window.__SB_PERM_DOMAINS.length > 0) {
          function matchesPermDomain(urlStr) {
            if (!urlStr) return false;
            try {
              var candidate = urlStr;
              if (candidate.indexOf('/url?') !== -1) {
                var qMatch = candidate.match(/[?&](?:q|url)=([^&]+)/i);
                if (qMatch && qMatch[1]) {
                  candidate = decodeURIComponent(qMatch[1]);
                }
              }
              var u = new URL(candidate, window.location.origin);
              var h = (u.hostname || '').toLowerCase().replace(/^www\./, '').replace(/^m\./, '');
              for (var i = 0; i < window.__SB_PERM_DOMAINS.length; i++) {
                var rule = window.__SB_PERM_DOMAINS[i];
                if (rule && (h === rule || h.endsWith('.' + rule))) {
                  return true;
                }
              }
            } catch (e) {}
            return false;
          }

          if (matchesPermDomain(window.location.href)) {
            window.location.replace('about:blank');
            return;
          }

          var isSearchEngine = host.includes('google.') || host.includes('bing.com') || host.includes('duckduckgo.com') || host.includes('yahoo.com') || host.includes('yandex.');
          if (isSearchEngine) {
            var links = document.querySelectorAll('a[href]');
            for (var j = 0; j < links.length; j++) {
              var a = links[j];
              if (matchesPermDomain(a.getAttribute('href')) || matchesPermDomain(a.href)) {
                var card = a.closest('div.xpd, div.Ww4FFb, div.ezO2md, div.g, div.mnr-c, g-card, li.b_algo, article[data-testid="result"], div.result, div.isv-r, div.MjjYud');
                if (card) {
                  card.style.setProperty('display', 'none', 'important');
                } else {
                  a.style.setProperty('display', 'none', 'important');
                }
              }
            }
            var cites = document.querySelectorAll('cite');
            for (var k = 0; k < cites.length; k++) {
              var cText = (cites[k].innerText || '').toLowerCase();
              for (var m = 0; m < window.__SB_PERM_DOMAINS.length; m++) {
                var r = window.__SB_PERM_DOMAINS[m];
                if (r && cText.includes(r)) {
                  var cCard = cites[k].closest('div.xpd, div.Ww4FFb, div.ezO2md, div.g, div.mnr-c, g-card, li.b_algo, article[data-testid="result"], div.result, div.MjjYud');
                  if (cCard) cCard.style.setProperty('display', 'none', 'important');
                  break;
                }
              }
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
    _startDownloadPollingTimer();
  }

  @override
  void dispose() {
    _lockEnforcementTimer?.cancel();
    _downloadPollTimer?.cancel();
    _zoomAutoHideTimer?.cancel();
    _downloadsUpdateTick.dispose();
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

  void _startDownloadPollingTimer() {
    _downloadPollTimer =
        Timer.periodic(const Duration(milliseconds: 800), (_) {
      _pollActiveDownloads();
    });
  }

  Future<void> _pollActiveDownloads() async {
    final activeEntries =
        _downloads.where((d) => d.downloadId > 0 && d.isInProgress).toList();
    if (activeEntries.isEmpty) return;

    try {
      final ids = activeEntries.map((e) => e.downloadId).toList();
      final res = await _intentChannel.invokeMethod('getDownloadsProgress', {
        'ids': ids,
      });
      if (res is Map && mounted) {
        bool changed = false;
        DownloadEntry? newlyFinished;
        for (final entry in activeEntries) {
          final info = res[entry.downloadId.toString()];
          if (info is Map) {
            final newStatus = (info['status'] ?? entry.status).toString();
            final newProgress =
                ((info['progress'] ?? entry.progress) as num).toDouble();
            final newSize = (info['sizeLabel'] ?? entry.sizeLabel).toString();
            final newDown = (info['bytesDownloaded'] ?? 0) as int;
            final newTotal = (info['totalBytes'] ?? 0) as int;
            final localPath = (info['localPath'] ?? '').toString();

            if (entry.status != newStatus ||
                entry.sizeLabel != newSize ||
                (entry.progress - newProgress).abs() > 0.005) {
              final wasInProgress = entry.isInProgress;
              entry.status = newStatus;
              entry.progress = newProgress;
              entry.sizeLabel = newSize;
              entry.bytesDownloaded = newDown;
              entry.totalBytes = newTotal;
              if (localPath.isNotEmpty) {
                entry.filePath = localPath;
              }
              changed = true;
              if (wasInProgress && newStatus == 'successful') {
                newlyFinished = entry;
              }
            }
          }
        }
        if (changed) {
          setState(() {});
          _downloadsUpdateTick.value++;
          await _saveData();
          if (newlyFinished != null) {
            _showDownloadBanner(newlyFinished);
          }
        }
      }
    } catch (_) {}
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
    _applyThemePreference(_themePreference, save: false);

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

  void _applyThemePreference(String pref, {bool save = true}) {
    _themePreference = pref;
    if (pref == 'light') {
      appThemeModeNotifier.value = ThemeMode.light;
    } else if (pref == 'dark') {
      appThemeModeNotifier.value = ThemeMode.dark;
    } else {
      appThemeModeNotifier.value = ThemeMode.system;
    }
    _syncWebViewTheme();
    if (save) _saveData();
  }

  Future<void> _syncWebViewTheme() async {
    if (!mounted || !_webViewReady) return;
    final platformDark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final effectiveDark = _themePreference == 'dark' ||
        (_themePreference == 'system' && platformDark);
    await _webController.setBackgroundColor(
      effectiveDark ? const Color(0xFF1F1F1F) : const Color(0xFFFFFFFF),
    );
    try {
      await _intentChannel.invokeMethod('setWebViewDarkening', {
        'isDark': effectiveDark && _darkenWebsitesInDark,
      });
    } catch (_) {}
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
      _themePreference = prefs.getString('themePreference') ?? 'system';
      _darkenWebsitesInDark = prefs.getBool('darkenWebsitesInDark') ?? false;
      _lastSharedApp = prefs.getString('lastSharedApp') ?? 'whatsapp';
      _bookmarkVisualView = prefs.getBool('bookmarkVisualView') ?? true;
      _bookmarkSortOrder = prefs.getString('bookmarkSortOrder') ?? 'manual';
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
            final savedPerm = prefs.getStringList('permanentBlockedDomainsV1');
      if (savedPerm != null) {
        _permanentBlockedDomains = savedPerm;
      }


      final savedSearches = prefs.getStringList('recentSearches');
      if (savedSearches != null) {
        _recentSearches = savedSearches;
      }

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
    await prefs.setString('themePreference', _themePreference);
    await prefs.setBool('darkenWebsitesInDark', _darkenWebsitesInDark);
    await prefs.setString('lastSharedApp', _lastSharedApp);
    await prefs.setBool('bookmarkVisualView', _bookmarkVisualView);
    await prefs.setString('bookmarkSortOrder', _bookmarkSortOrder);
    await prefs.setBool('blockYtShorts', _blockYtShorts);
    await prefs.setBool('hideYtFeed', _hideYtFeed);
    await prefs.setBool('blockIgReels', _blockIgReels);
    await prefs.setBool('whitelistMode', _whitelistMode);
    await prefs.setString('featurePassHash', _featurePassHash);
    await prefs.setInt('featureTempUnlockUntil', _featureTempUnlockUntil);
    await prefs.setString('homepageUrl', _homepageUrl);
    await prefs.setString('searchEngineUrl', _searchEngineUrl);
    await prefs.setStringList('whitelistedDomains', _whitelistedDomains);
        await prefs.setStringList(
        'permanentBlockedDomainsV1', _permanentBlockedDomains);
    await prefs.setStringList('recentSearches', _recentSearches);
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
      ..setUserAgent(_mobileUserAgent)
      ..addJavaScriptChannel(
        'StudyBrowserBridge',
        onMessageReceived: (JavaScriptMessage msg) {
          _handleJsBridgeMessage(msg.message);
        },
      )
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
            await _syncWebViewTheme();
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
            Future.delayed(const Duration(milliseconds: 550), () {
              if (mounted) _captureCurrentTabThumbnail();
            });
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

            final lower = reqUrl.toLowerCase().split('?').first;
            if (lower.endsWith('.pdf') ||
                lower.endsWith('.zip') ||
                lower.endsWith('.apk') ||
                lower.endsWith('.doc') ||
                lower.endsWith('.docx') ||
                lower.endsWith('.mp3') ||
                lower.endsWith('.mp4')) {
              _triggerRealFileDownload(reqUrl);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );
    _webViewReady = true;
  }

  // ===========================================================================
  // IMAGE LONG-PRESS CONTEXT MENU, PREVIEW & IN-APP IMAGE VIEWER
  // ===========================================================================
  void _handleJsBridgeMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['type'] == 'image_long_press') {
        final src = (decoded['src'] ?? '').toString();
        final alt = (decoded['alt'] ?? 'Image').toString();
        if (src.isNotEmpty) {
          HapticFeedback.mediumImpact();
          _openImageLongPressDialog(src, alt);
        }
      }
    } catch (_) {}
  }

  void _openImageLongPressDialog(String imageUrl, String altText) {
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final displayTitle = altText.trim().isNotEmpty ? altText.trim() : imageUrl;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: p.menuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 48,
                          height: 48,
                          color: p.surfaceVariant,
                          child: Icon(Icons.image_outlined, color: p.subtext),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: p.subtext,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 12, color: p.border),
              ListTile(
                title: Text('Open image in new tab',
                    style: TextStyle(color: p.text, fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openUrlInBackgroundTab(imageUrl, title: displayTitle);
                },
              ),
              ListTile(
                title: Text('Preview image',
                    style: TextStyle(color: p.text, fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openImagePreviewSheet(imageUrl, displayTitle);
                },
              ),
              ListTile(
                title: Text('Copy image',
                    style: TextStyle(color: p.text, fontSize: 15)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _intentChannel
                      .invokeMethod<bool>('copyImageToClipboard', {
                    'url': imageUrl,
                  });
                  _showToast(ok == true
                      ? 'Image copied to clipboard'
                      : 'Image link copied');
                },
              ),
              ListTile(
                title: Text('Download image',
                    style: TextStyle(color: p.text, fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerRealFileDownload(imageUrl, forceCategory: 'Images');
                },
              ),
              ListTile(
                title: Text('Search image with Google Lens',
                    style: TextStyle(color: p.text, fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  final lensUrl =
                      'https://lens.google.com/uploadbyurl?url=${Uri.encodeComponent(imageUrl)}';
                  _loadFromSearchBar(lensUrl);
                },
              ),
              ListTile(
                title: Text('Share image',
                    style: TextStyle(color: p.text, fontSize: 15)),
                trailing: InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareImageViaApp(imageUrl, _lastSharedApp);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: _buildLastShareAppBadge(),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openChromeShareSheet(
                    overrideUrl: imageUrl,
                    overrideTitle: displayTitle,
                    isImage: true,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openUrlInBackgroundTab(String url, {String? title}) {
    final newTab = BrowserTab(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: (title != null && title.isNotEmpty) ? title : url,
      url: url,
      isIncognito: _isIncognito,
      isDesktop: _isDesktopMode,
    );
    setState(() {
      _tabs.add(newTab);
    });
    _saveData();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Opened in new tab'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Switch',
          onPressed: () => _switchToTab(_tabs.length - 1),
        ),
      ),
    );
  }

  void _openImagePreviewSheet(String imageUrl, String title) {
    final p = ChromePalette.of(context, incognito: _isIncognito);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5,
                              color: p.text),
                        ),
                        Text(
                          Uri.tryParse(imageUrl)?.host ?? imageUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: p.subtext),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new),
                    tooltip: 'Open in new tab',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _createNewTab(incognito: _isIncognito, url: imageUrl);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                child: Center(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.broken_image, size: 56, color: p.subtext),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openInAppImageViewer({
    required String title,
    String? filePath,
    String? imageUrl,
  }) {
    final hasLocalFile =
        filePath != null && filePath.isNotEmpty && File(filePath).existsSync();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
                Text(
                  hasLocalFile ? filePath : (imageUrl ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () {
                  if (imageUrl != null && imageUrl.isNotEmpty) {
                    _shareImageViaApp(imageUrl, 'more');
                  } else if (hasLocalFile) {
                    _intentChannel.invokeMethod('openWithSystem', {
                      'filePath': filePath,
                      'url': imageUrl ?? '',
                    });
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Open with other app',
                onPressed: () {
                  _intentChannel.invokeMethod('openWithSystem', {
                    'filePath': filePath ?? '',
                    'url': imageUrl ?? '',
                  });
                },
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: hasLocalFile
                  ? Image.file(File(filePath), fit: BoxFit.contain)
                  : (imageUrl != null && imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.contain)
                      : const Icon(Icons.image_not_supported,
                          color: Colors.white54, size: 64)),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // DOWNLOADS ENGINE (LIVE PROGRESS + OFFLINE PAGES + SMART OPEN)
  // ===========================================================================
  String _detectDownloadCategory(String nameOrUrl) {
    final lower = nameOrUrl.toLowerCase().split('?').first;
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.3gp')) {
      return 'Videos';
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif')) {
      return 'Images';
    }
    if (lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.mhtml')) {
      return 'Pages';
    }
    return 'Other';
  }

  Future<void> _triggerRealFileDownload(
    String url, {
    String? forceCategory,
  }) async {
    try {
      final res = await _intentChannel.invokeMethod('downloadFile', {
        'url': url,
      });
      int dlId = -1;
      String fileName = url.split('/').last.split('?').first;
      if (fileName.isEmpty) fileName = 'Downloaded_File';
      String filePath = '/storage/emulated/0/Download/$fileName';
      String sizeLabel = 'Starting download...';

      if (res is Map) {
        dlId = (res['downloadId'] ?? -1) as int;
        fileName = (res['fileName'] ?? fileName).toString();
        filePath = (res['filePath'] ?? filePath).toString();
        sizeLabel = (res['sizeLabel'] ?? sizeLabel).toString();
      }

      final entry = DownloadEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        downloadId: dlId,
        title: fileName,
        url: url,
        filePath: filePath,
        sizeLabel: sizeLabel,
        category: forceCategory ?? _detectDownloadCategory(fileName),
        dateLabel: _todayLabel(),
        status: dlId > 0 ? 'running' : 'successful',
        progress: dlId > 0 ? 0.02 : 1.0,
      );

      setState(() => _downloads.insert(0, entry));
      _downloadsUpdateTick.value++;
      await _saveData();
      _showToast('Downloading $fileName...');
      _pollActiveDownloads();
    } catch (_) {}
  }

  Future<void> _downloadCurrentPageOffline() async {
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
        final filePath = (res['filePath'] ?? '').toString();
        final sizeLabel = (res['sizeLabel'] ?? '1.12 MB').toString();

        final entry = DownloadEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          downloadId: -1,
          title: titleToSave,
          url: _currentUrl,
          filePath: filePath,
          sizeLabel: sizeLabel,
          category: 'Pages',
          dateLabel: _todayLabel(),
          status: 'successful',
          progress: 1.0,
        );

        setState(() => _downloads.insert(0, entry));
        _downloadsUpdateTick.value++;
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: p.menuBg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(Icons.download_done, color: p.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'File downloaded',
                    style: TextStyle(
                        color: p.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5),
                  ),
                  Text(
                    '(${entry.sizeLabel}) ${entry.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.subtext, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Open',
          textColor: p.accent,
          onPressed: () => _openDownloadEntry(entry),
        ),
      ),
    );
  }

  Future<void> _openDownloadEntry(DownloadEntry entry) async {
    if (entry.isInProgress) {
      _showToast('Downloading: ${entry.sizeLabel}');
      return;
    }

    // 1. Images open directly inside Study Browser's built-in Chrome-style viewer!
    if (entry.category == 'Images') {
      _openInAppImageViewer(
        title: entry.title,
        filePath: entry.filePath,
        imageUrl: entry.url,
      );
      return;
    }

    // 2. Saved web pages open directly inside Study Browser!
    if (entry.category == 'Pages') {
      if (entry.url.isNotEmpty) {
        _loadFromSearchBar(entry.url);
        return;
      }
    }

    // 3. Unsupported binary files (.zip, .pdf, .apk, .mp4) show Android "Open with" chooser popup
    final ok = await _intentChannel.invokeMethod<bool>('openWithSystem', {
      'filePath': entry.filePath,
      'url': entry.url,
    });
    if (ok != true && entry.url.isNotEmpty) {
      _loadFromSearchBar(entry.url);
    }
  }

  // ===========================================================================
  // TAB SYNC, REAL THUMBNAILS, HISTORY & SECURITY ENGINE
  // ===========================================================================
  void _syncActiveTab({String? title, String? url}) {
    if (_tabs.isEmpty || _activeTabIndex >= _tabs.length) return;
    final tab = _tabs[_activeTabIndex];
    if (title != null && title.isNotEmpty) tab.title = title;
    if (url != null && url.isNotEmpty) tab.url = url;
    tab.isDesktop = _isDesktopMode;
    tab.isIncognito = _isIncognito;
    _saveData();
  }

  Future<void> _captureCurrentTabThumbnail() async {
    if (!_webViewReady || _tabs.isEmpty || _activeTabIndex >= _tabs.length) {
      return;
    }
    try {
      final tab = _tabs[_activeTabIndex];
      final path = await _intentChannel
          .invokeMethod<String>('captureWebViewThumbnail', {
        'tabId': tab.id,
      });
      if (path != null && path.isNotEmpty && mounted) {
        tab.thumbnailPath = path;
        await _saveData();
      }
    } catch (_) {}
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
      if (_history.length > 200) {
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
                window.__SB_PERM_DOMAINS = ${jsonEncode(_permanentBlockedDomains)};

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
        // 0. Permanent Irreversible Site Block (Highest Priority)
    for (final pDomain in _permanentBlockedDomains) {
      if (_domainMatches(host, url, pDomain)) {
        if (showOverlayOnBlock && mounted) {
          setState(() {
            _isPageBlocked = true;
            _blockedUrl = '';
            _blockedReason = 'यह साइट हमेशा के लिए ब्लॉक है';
            _blockingGroup = null;
          });
        }
        return false;
      }
    }


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

    // Chrome view-source: support!
    if (trimmed.toLowerCase().startsWith('view-source:')) {
      final target = trimmed.substring('view-source:'.length).trim();
      final fullUrl = target.startsWith('http') ? target : 'https://$target';
      if (!_evaluateUrl(fullUrl, showOverlayOnBlock: true)) return;
      _openViewSourcePage(fullUrl);
      return;
    }

    String targetUrl;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      targetUrl = trimmed;
    } else if (trimmed.contains('.') && !trimmed.contains(' ')) {
      targetUrl = 'https://$trimmed';
    } else {
      if (!_isIncognito) {
        _recentSearches.remove(trimmed);
        _recentSearches.insert(0, trimmed);
        if (_recentSearches.length > 25) _recentSearches.removeLast();
      }
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

  Future<void> _openViewSourcePage(String url) async {
    _showToast('Loading source code...');
    String sourceText = '';
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, _mobileUserAgent);
      final resp = await req.close();
      sourceText = await resp.transform(utf8.decoder).join();
      client.close();
    } catch (e) {
      sourceText = 'Unable to fetch source code for $url\nError: $e';
    }
    if (!mounted) return;
    final p = ChromePalette.of(context, incognito: _isIncognito);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            title: Text(
              'view-source:$url',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: sourceText));
                  _showToast('Source code copied');
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              sourceText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: p.text,
              ),
            ),
          ),
        ),
      ),
    );
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
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final bgHex = isDark ? '#1F1F1F' : '#FFFFFF';
      final fgHex = isDark ? '#E3E3E3' : '#1F1F1F';
      final headHex = isDark ? '#A8C7FA' : '#0B57D0';
      await _webController.runJavaScript('''
        (function() {
          if (document.getElementById('sb-reader-overlay')) return;
          var title = document.title || '';
          var paragraphs = Array.from(document.querySelectorAll('article p, main p, p'))
            .map(function(p) { return p.innerText.trim(); })
            .filter(function(t) { return t.length > 40; });
          var contentHtml = paragraphs.length > 0
            ? paragraphs.map(function(p) { return '<p style="margin-bottom:16px;line-height:1.75;font-size:18px;color:$fgHex;">' + p + '</p>'; }).join('')
            : '<p style="color:#888;">इस पेज पर रीडिंग मोड के लिए लंबा टेक्स्ट उपलब्ध नहीं है।</p>';
          var overlay = document.createElement('div');
          overlay.id = 'sb-reader-overlay';
          overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:$bgHex;color:$fgHex;overflow-y:auto;padding:24px 20px 80px 20px;font-family:sans-serif;';
          overlay.innerHTML = '<div style="max-width:680px;margin:0 auto;"><h1 style="font-size:24px;line-height:1.4;margin-bottom:20px;color:$headHex;border-bottom:1px solid #44444444;padding-bottom:12px;">' + title + '</h1>' + contentHtml + '</div>';
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

  Future<void> _createNewTab({
    bool incognito = false,
    String? url,
    String? groupId,
  }) async {
    await _captureCurrentTabThumbnail();
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

  Future<void> _switchToTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    await _captureCurrentTabThumbnail();
    final tab = _tabs[index];
    setState(() {
      _activeTabIndex = index;
      _isIncognito = tab.isIncognito;
      _isDesktopMode = tab.isDesktop;
    });
    _saveData();
    await _applyNativeDesktopViewport(_isDesktopMode);
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

  Future<void> _shareLinkViaApp(String url, String title, String appKey) async {
    setState(() => _lastSharedApp = appKey);
    await _saveData();
    String? pkg;
    if (appKey == 'whatsapp') pkg = 'com.whatsapp';
    if (appKey == 'telegram') pkg = 'org.telegram.messenger';
    await _intentChannel.invokeMethod('shareLink', {
      'url': url,
      'title': title,
      if (pkg != null) 'package': pkg,
    });
  }

  Future<void> _shareImageViaApp(String imageUrl, String appKey) async {
    setState(() => _lastSharedApp = appKey);
    await _saveData();
    String? pkg;
    if (appKey == 'whatsapp') pkg = 'com.whatsapp';
    if (appKey == 'telegram') pkg = 'org.telegram.messenger';
    await _intentChannel.invokeMethod('shareImage', {
      'url': imageUrl,
      if (pkg != null) 'package': pkg,
    });
  }

  Widget _buildLastShareAppBadge() {
    if (_lastSharedApp == 'telegram') {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          color: Color(0xFF2AABEE),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.send, size: 14, color: Colors.white),
      );
    }
    if (_lastSharedApp == 'whatsapp') {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          color: Color(0xFF25D366),
          shape: BoxShape.circle,
        ),
        child:
            const Icon(Icons.chat_bubble_outline, size: 15, color: Colors.white),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Color(0xFF1A73E8),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.share, size: 15, color: Colors.white),
    );
  }

  void _showToast(String msg) {
    if (!mounted) return;
    final p = ChromePalette.of(context, incognito: _isIncognito);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: TextStyle(color: p.text, fontSize: 13.5),
        ),
        backgroundColor: p.menuBg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: p.border),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  bool _isUrlPermanentlyBlocked(String input) {
    final lower = input.toLowerCase().trim();
    if (lower.isEmpty) return false;
    final uri = Uri.tryParse(lower);
    final host = (uri?.host.isNotEmpty == true) ? uri!.host : lower;
    for (final pDomain in _permanentBlockedDomains) {
      if (_domainMatches(host, lower, pDomain)) return true;
    }
    return false;
  }

  String _formatDisplayUrl(String url) {
    if (url.isEmpty || url == 'about:blank') return 'Search or type URL';
    return url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '');
  }

  // ===========================================================================
  // CHROME-STYLE FULL-SCREEN ADDRESS BAR / OMNIBOX OVERLAY
  // ===========================================================================
  Future<void> _openChromeAddressBarOverlay() async {
    String copiedUrl = '';
    try {
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final rawClip = (clipData?.text ?? '').trim();
      if ((rawClip.startsWith('http://') || rawClip.startsWith('https://')) &&
          !_isUrlPermanentlyBlocked(rawClip)) {
        copiedUrl = rawClip;
      }
    } catch (_) {}

    if (!mounted) return;

    final searchCtrl = TextEditingController();
    bool showCopiedUrlPreview = false;

    await Navigator.of(context)
        .push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 120),
            reverseTransitionDuration: const Duration(milliseconds: 100),
            pageBuilder: (overlayCtx, anim, _) => StatefulBuilder(
              builder: (overlayCtx, setOverlayState) {
                final p = ChromePalette.of(overlayCtx, incognito: _isIncognito);
                final q = searchCtrl.text.trim();
                final qLower = q.toLowerCase();

                final safeBookmarks = _bookmarks
                    .where((b) => !_isUrlPermanentlyBlocked(b.url))
                    .toList();

                final safeRecentSearches = _recentSearches
                    .where((s) => !_isUrlPermanentlyBlocked(s))
                    .toList();

                final matchingRecent = q.isEmpty
                    ? safeRecentSearches
                    : safeRecentSearches
                        .where((s) => s.toLowerCase().contains(qLower))
                        .toList();

                final matchingHistory = q.isEmpty
                    ? <HistoryItem>[]
                    : _history
                        .where((h) =>
                            !_isUrlPermanentlyBlocked(h.url) &&
                            (h.title.toLowerCase().contains(qLower) ||
                                h.url.toLowerCase().contains(qLower)))
                        .take(8)
                        .toList();

                final showCurrentPageRow = _currentUrl.isNotEmpty &&
                    _currentUrl != 'about:blank' &&
                    !_isUrlPermanentlyBlocked(_currentUrl) &&
                    (q.isEmpty || q == _currentUrl);

                return Scaffold(
                  backgroundColor: p.bg,
                  body: SafeArea(
                    child: Column(
                      children: [
                        // TOP CHROME SEARCH INPUT BAR
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Container(
                            height: 46,
                            decoration: BoxDecoration(
                              color: p.addressBar,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 14),
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: p.bg,
                                  child: Text(
                                    'G',
                                    style: TextStyle(
                                      color: p.accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: searchCtrl,
                                    autofocus: true,
                                    textInputAction: TextInputAction.search,
                                    style:
                                        TextStyle(fontSize: 15, color: p.text),
                                    onChanged: (_) => setOverlayState(() {}),
                                    onSubmitted: (val) {
                                      final input = val.trim();
                                      if (input.isEmpty) return;
                                      Navigator.pop(overlayCtx);
                                      _loadFromSearchBar(input);
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Search Google or type URL',
                                      hintStyle: TextStyle(
                                          color: p.subtext, fontSize: 15),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                if (q.isNotEmpty)
                                  IconButton(
                                    icon: Icon(Icons.close,
                                        size: 20, color: p.subtext),
                                    onPressed: () {
                                      searchCtrl.clear();
                                      setOverlayState(() {});
                                    },
                                  )
                                else
                                  IconButton(
                                    icon: Icon(Icons.close,
                                        size: 20, color: p.subtext),
                                    tooltip: 'Close',
                                    onPressed: () => Navigator.pop(overlayCtx),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.only(bottom: 24),
                            children: [
                              // 1. CURRENT PAGE ROW (SHARE, COPY, EDIT)
                              if (showCurrentPageRow)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: p.surfaceVariant,
                                        child: Icon(Icons.public,
                                            size: 19, color: p.subtext),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: InkWell(
                                          onTap: () =>
                                              Navigator.pop(overlayCtx),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _pageTitle.isNotEmpty
                                                    ? _pageTitle
                                                    : _formatDisplayUrl(
                                                        _currentUrl),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: p.text,
                                                ),
                                              ),
                                              Text(
                                                _currentUrl,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: p.accent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.share_outlined,
                                            size: 20, color: p.text),
                                        tooltip: 'Share',
                                        onPressed: () {
                                          Navigator.pop(overlayCtx);
                                          _openChromeShareSheet();
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.copy_outlined,
                                            size: 20, color: p.text),
                                        tooltip: 'Copy link',
                                        onPressed: () {
                                          Clipboard.setData(
                                              ClipboardData(text: _currentUrl));
                                          setOverlayState(
                                              () => copiedUrl = _currentUrl);
                                          _showToast('Link copied');
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.edit_outlined,
                                            size: 20, color: p.text),
                                        tooltip: 'Edit URL',
                                        onPressed: () {
                                          searchCtrl.text = _currentUrl;
                                          searchCtrl.selection =
                                              TextSelection.fromPosition(
                                            TextPosition(
                                                offset: searchCtrl.text.length),
                                          );
                                          setOverlayState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),

                              // 2. LINK THAT YOU COPIED ROW
                              if (q.isEmpty && copiedUrl.isNotEmpty)
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: p.surfaceVariant,
                                    child: Icon(Icons.public,
                                        size: 19, color: p.subtext),
                                  ),
                                  title: Text(
                                    'Link that you copied',
                                    style:
                                        TextStyle(fontSize: 14.5, color: p.text),
                                  ),
                                  subtitle: showCopiedUrlPreview
                                      ? Text(
                                          copiedUrl,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 12, color: p.accent),
                                        )
                                      : null,
                                  trailing: IconButton(
                                    icon: Icon(
                                      showCopiedUrlPreview
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 20,
                                      color: p.subtext,
                                    ),
                                    onPressed: () => setOverlayState(() =>
                                        showCopiedUrlPreview =
                                            !showCopiedUrlPreview),
                                  ),
                                  onTap: () {
                                    Navigator.pop(overlayCtx);
                                    _loadFromSearchBar(copiedUrl);
                                  },
                                ),

                              // 3. TOP SITES / BOOKMARKS HORIZONTAL ROW
                              if (q.isEmpty && safeBookmarks.isNotEmpty)
                                SizedBox(
                                  height: 92,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    itemCount: safeBookmarks.length,
                                    itemBuilder: (_, i) {
                                      final bm = safeBookmarks[i];
                                      final host = Uri.tryParse(bm.url)
                                              ?.host
                                              .replaceAll('www.', '') ??
                                          bm.title;
                                      return InkWell(
                                        onTap: () {
                                          Navigator.pop(overlayCtx);
                                          _loadFromSearchBar(bm.url);
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: SizedBox(
                                          width: 74,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              CircleAvatar(
                                                radius: 22,
                                                backgroundColor:
                                                    p.surfaceVariant,
                                                child: Text(
                                                  host.isNotEmpty
                                                      ? host[0].toUpperCase()
                                                      : 'W',
                                                  style: TextStyle(
                                                    color: p.accent,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                bm.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: p.text),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),

                              // 4. DIRECT SEARCH OPTION WHEN TYPING
                              if (q.isNotEmpty)
                                ListTile(
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: p.surfaceVariant,
                                    child: Icon(Icons.search,
                                        size: 19, color: p.subtext),
                                  ),
                                  title: Text(
                                    q,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.text),
                                  ),
                                  onTap: () {
                                    Navigator.pop(overlayCtx);
                                    _loadFromSearchBar(q);
                                  },
                                ),

                              // 5. RECENT SEARCHES HEADER & LIST
                              if (q.isEmpty && matchingRecent.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 10, 16, 4),
                                  child: Text(
                                    'Recent searches',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: p.subtext,
                                    ),
                                  ),
                                ),

                              ...matchingRecent.map(
                                (term) => ListTile(
                                  contentPadding: const EdgeInsets.only(
                                      left: 14, right: 6),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: p.surfaceVariant,
                                    child: Icon(Icons.history,
                                        size: 19, color: p.subtext),
                                  ),
                                  title: Text(
                                    term,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14.5, color: p.text),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.north_west,
                                        size: 19, color: p.subtext),
                                    onPressed: () {
                                      searchCtrl.text = term;
                                      searchCtrl.selection =
                                          TextSelection.fromPosition(
                                        TextPosition(
                                            offset: searchCtrl.text.length),
                                      );
                                      setOverlayState(() {});
                                    },
                                  ),
                                  onTap: () {
                                    Navigator.pop(overlayCtx);
                                    _loadFromSearchBar(term);
                                  },
                                  onLongPress: () async {
                                    setState(
                                        () => _recentSearches.remove(term));
                                    setOverlayState(() {});
                                    await _saveData();
                                    _showToast('Removed from recent searches');
                                  },
                                ),
                              ),

                              // 6. MATCHING HISTORY WHEN TYPING
                              ...matchingHistory.map(
                                (item) => ListTile(
                                  contentPadding: const EdgeInsets.only(
                                      left: 14, right: 6),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: p.surfaceVariant,
                                    child: Icon(Icons.public,
                                        size: 19, color: p.accent),
                                  ),
                                  title: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14, color: p.text),
                                  ),
                                  subtitle: Text(
                                    item.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12, color: p.subtext),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.north_west,
                                        size: 19, color: p.subtext),
                                    onPressed: () {
                                      searchCtrl.text = item.url;
                                      setOverlayState(() {});
                                    },
                                  ),
                                  onTap: () {
                                    Navigator.pop(overlayCtx);
                                    _loadFromSearchBar(item.url);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        )
        .whenComplete(() => searchCtrl.dispose());
  }

  // ===========================================================================
  // PERMANENT IRREVERSIBLE SITE BLOCKER (ZERO LIST VISIBILITY)
  // ===========================================================================
  Future<void> _promptAddPermanentBlockedSite() async {
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final ctrl = TextEditingController();

    final enteredDomain = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.menuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Permanent Site Block',
            style: TextStyle(fontSize: 17, color: p.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'जिस वेबसाइट को हमेशा के लिए ब्लॉक करना है उसका डोमेन लिखें:',
              style: TextStyle(fontSize: 13, color: p.subtext),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'उदाहरण: example.com',
                filled: true,
                fillColor: p.bg,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
              final clean = ctrl.text
                  .trim()
                  .toLowerCase()
                  .replaceAll('https://', '')
                  .replaceAll('http://', '')
                  .replaceAll('www.', '')
                  .replaceAll('m.', '')
                  .split('/')
                  .first
                  .trim();
              if (clean.length < 3 || !clean.contains('.')) {
                _showToast('सही डोमेन लिखें (जैसे: site.com)');
                return;
              }
              Navigator.pop(ctx, clean);
            },
            child: const Text('Next'),
          ),
        ],
      ),
    );

    if (enteredDomain == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.menuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('पक्का हमेशा के लिए ब्लॉक करें?',
            style: TextStyle(fontSize: 17, color: Colors.redAccent)),
        content: Text(
          '"$enteredDomain" को एक बार जोड़ने के बाद:\n\n'
          '• यह इस ब्राउज़र में कभी दोबारा नहीं खुलेगी\n'
          '• इसे कहीं से अनब्लॉक या देखा नहीं जा सकेगा\n'
          '• यह Search Results से भी गायब हो जाएगी',
          style: TextStyle(fontSize: 13.5, color: p.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block Forever'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      if (!_permanentBlockedDomains.contains(enteredDomain)) {
        _permanentBlockedDomains.add(enteredDomain);
      }
      _history.removeWhere((h) => _isUrlPermanentlyBlocked(h.url));
      _bookmarks.removeWhere((b) => _isUrlPermanentlyBlocked(b.url));
      _recentSearches.removeWhere((s) => _isUrlPermanentlyBlocked(s));
      _recentlyClosedTabs.removeWhere((t) => _isUrlPermanentlyBlocked(t.url));
      for (final t in _tabs) {
        if (_isUrlPermanentlyBlocked(t.url)) {
          t.url = _homepageUrl;
          t.title = 'New Tab';
        }
      }
    });

    await _saveData();
    await _injectFocusScripts();

    if (_isUrlPermanentlyBlocked(_currentUrl)) {
      _loadFromSearchBar(_homepageUrl);
    } else {
      _webController.reload();
    }
    _showToast('साइट हमेशा के लिए ब्लॉक कर दी गई है');
  }


  // ===========================================================================
  // CHROME-STYLE 3-DOT POPUP MENU (LIGHT & DARK ADAPTIVE)
  // ===========================================================================
  void _openChromeStyleMenu() {
    final p = ChromePalette.of(context, incognito: _isIncognito);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Browser Menu',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim1, anim2) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 52, right: 10),
              child: Material(
                color: p.menuBg,
                elevation: 16,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: p.border, width: 1),
                ),
                child: SizedBox(
                  width: 288,
                  height: MediaQuery.of(context).size.height * 0.84,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // TOP 5 CHROME ACTION ICONS ROW
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: p.border),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildTopMenuIconButton(
                              p: p,
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
                              p: p,
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
                              p: p,
                              icon: _isCurrentPageBookmarked
                                  ? Icons.star
                                  : Icons.star_border,
                              iconColor: _isCurrentPageBookmarked
                                  ? p.accent
                                  : p.text,
                              tooltip: 'Bookmark',
                              onTap: () {
                                Navigator.pop(ctx);
                                _toggleCurrentBookmark();
                              },
                            ),
                            _buildTopMenuIconButton(
                              p: p,
                              icon: Icons.download_outlined,
                              tooltip: 'Download offline page',
                              onTap: () {
                                Navigator.pop(ctx);
                                _downloadCurrentPageOffline();
                              },
                            ),
                            _buildTopMenuIconButton(
                              p: p,
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
                              p: p,
                              icon: Icons.add_box_outlined,
                              title: 'New tab',
                              onTap: () {
                                Navigator.pop(ctx);
                                _createNewTab(incognito: false);
                              },
                            ),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.visibility_off_outlined,
                              title: 'New Incognito tab',
                              onTap: () {
                                Navigator.pop(ctx);
                                _createNewTab(incognito: true);
                              },
                            ),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.grid_view_outlined,
                              title: 'Add tab to new group',
                              onTap: () {
                                Navigator.pop(ctx);
                                _promptCreateTabGroupForCurrentTab();
                              },
                            ),
                            Divider(height: 12, color: p.border),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.history,
                              title: 'History',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenHistoryPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.delete_outline,
                              title: 'Delete browsing data',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openDeleteBrowsingDataDialog();
                              },
                            ),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.tune,
                              title: 'Site controls',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openSiteControlsDialog();
                              },
                            ),
                            Divider(height: 12, color: p.border),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.download_done_outlined,
                              title: 'Downloads',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenDownloadsPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.star_border,
                              title: 'Bookmarks',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenBookmarksPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.devices_outlined,
                              title: 'Recent tabs',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenRecentTabsPage();
                              },
                            ),
                            Divider(height: 12, color: p.border),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.zoom_in,
                              title: 'Zoom',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openZoomControlsWithAutoHide();
                              },
                            ),
                            // SHARE ROW WITH LAST-SHARED APP QUICK ICON
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
                                    Icon(Icons.share_outlined,
                                        size: 21, color: p.text),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        'Share...',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: p.text,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _shareLinkViaApp(_currentUrl,
                                            _pageTitle, _lastSharedApp);
                                      },
                                      borderRadius: BorderRadius.circular(14),
                                      child: _buildLastShareAppBadge(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _buildChromeMenuItem(
                              p: p,
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
                              p: p,
                              icon: Icons.g_translate,
                              title: 'Translate...',
                              onTap: () {
                                Navigator.pop(ctx);
                                _translateCurrentPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              p: p,
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
                              p: p,
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
                                    Icon(Icons.desktop_windows_outlined,
                                        size: 21, color: p.text),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        'Desktop site',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: p.text,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: Checkbox(
                                        value: _isDesktopMode,
                                        activeColor: p.accent,
                                        checkColor: p.isDark
                                            ? const Color(0xFF1F1F1F)
                                            : Colors.white,
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
                            Divider(height: 12, color: p.border),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.shield_outlined,
                              title: 'Focus & Lock Settings',
                              iconColor: p.accent,
                              onTap: () {
                                Navigator.pop(ctx);
                                _openLockManagerSheet();
                              },
                            ),
                            _buildChromeMenuItem(
                              p: p,
                              icon: Icons.settings_outlined,
                              title: 'Settings',
                              onTap: () {
                                Navigator.pop(ctx);
                                _openFullScreenSettingsPage();
                              },
                            ),
                            _buildChromeMenuItem(
                              p: p,
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
    required ChromePalette p,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: p.topIconBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, size: 20, color: iconColor ?? p.text),
      ),
    );
  }

  Widget _buildChromeMenuItem({
    required ChromePalette p,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 21, color: iconColor ?? p.text),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  color: p.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // INSTALL AND CREATE SHORTCUT
  // ===========================================================================
  void _openInstallAndCreateShortcutSheet() {
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final defaultTitle = _pageTitle.isNotEmpty
        ? _pageTitle
        : (Uri.tryParse(_currentUrl)?.host ?? 'Study Shortcut');

    showModalBottomSheet(
      context: context,
      backgroundColor: p.menuBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Install and create shortcut',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: p.text),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.border),
              ),
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: p.topIconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.apps, color: p.accent),
                ),
                title: Text('Install page as app',
                    style: TextStyle(fontWeight: FontWeight.w500, color: p.text)),
                subtitle: Text(defaultTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.subtext)),
                trailing: Icon(Icons.chevron_right, color: p.subtext),
                onTap: () {
                  Navigator.pop(ctx);
                  _promptConfirmPinShortcut(defaultTitle);
                },
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.border),
              ),
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: p.topIconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.add_to_home_screen, color: p.accent),
                ),
                title: Text('Create shortcut',
                    style: TextStyle(fontWeight: FontWeight.w500, color: p.text)),
                subtitle: Text('Shortcuts open in Study Browser',
                    style: TextStyle(color: p.subtext)),
                trailing: Icon(Icons.chevron_right, color: p.subtext),
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final nameCtrl = TextEditingController(text: initialTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.menuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Add to Home screen', style: TextStyle(color: p.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Touch and hold the icon or tap Add to place it on your Home screen:',
              style: TextStyle(fontSize: 13, color: p.subtext),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Shortcut Title',
                filled: true,
                fillColor: p.bg,
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
  // CHROME-STYLE SHARE SHEET
  // ===========================================================================
  void _openChromeShareSheet({
    String? overrideUrl,
    String? overrideTitle,
    bool isImage = false,
  }) {
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final shareUrl = overrideUrl ?? _currentUrl;
    final shareTitle =
        (overrideTitle != null && overrideTitle.isNotEmpty)
            ? overrideTitle
            : (_pageTitle.isNotEmpty ? _pageTitle : 'Web Page');

    showModalBottomSheet(
      context: context,
      backgroundColor: p.menuBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                Text(
                  isImage ? 'Share image' : 'Share link',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  if (isImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        shareUrl,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 42,
                          height: 42,
                          color: p.topIconBg,
                          child: Icon(Icons.image_outlined, color: p.accent),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: p.topIconBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.public, color: p.accent),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shareTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: p.text),
                        ),
                        Text(
                          shareUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.accent, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, size: 20, color: p.text),
                    tooltip: 'Copy link',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: shareUrl));
                      Navigator.pop(ctx);
                      _showToast('लिंक कॉपी कर लिया गया');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
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
                        'title': shareTitle,
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.qr_code, size: 17),
                    label: const Text('QR Code'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showQrCodeDialog(shareUrl);
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.download_outlined, size: 17),
                    label: Text(isImage ? 'Download Image' : 'Save Offline'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (isImage) {
                        _triggerRealFileDownload(shareUrl,
                            forceCategory: 'Images');
                      } else {
                        _downloadCurrentPageOffline();
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildShareAppCircle(
                  p: p,
                  label: 'WhatsApp',
                  icon: Icons.chat_bubble_outline,
                  color: const Color(0xFF25D366),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (isImage) {
                      _shareImageViaApp(shareUrl, 'whatsapp');
                    } else {
                      _shareLinkViaApp(shareUrl, shareTitle, 'whatsapp');
                    }
                  },
                ),
                _buildShareAppCircle(
                  p: p,
                  label: 'Telegram',
                  icon: Icons.send,
                  color: const Color(0xFF2AABEE),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (isImage) {
                      _shareImageViaApp(shareUrl, 'telegram');
                    } else {
                      _shareLinkViaApp(shareUrl, shareTitle, 'telegram');
                    }
                  },
                ),
                _buildShareAppCircle(
                  p: p,
                  label: 'Copy Link',
                  icon: Icons.link,
                  color: const Color(0xFF5F6368),
                  onTap: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: shareUrl));
                    _showToast('लिंक कॉपी हो गया');
                  },
                ),
                _buildShareAppCircle(
                  p: p,
                  label: 'More Apps',
                  icon: Icons.more_horiz,
                  color: const Color(0xFF1A73E8),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (isImage) {
                      _shareImageViaApp(shareUrl, 'more');
                    } else {
                      _shareLinkViaApp(shareUrl, shareTitle, 'more');
                    }
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
    required ChromePalette p,
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
          Text(label, style: TextStyle(fontSize: 12, color: p.text)),
        ],
      ),
    );
  }

  void _showQrCodeDialog(String targetUrl) {
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final qrImageUrl =
        'https://api.qrserver.com/v1/create-qr-code/?size=240x240&data=${Uri.encodeComponent(targetUrl)}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.menuBg,
        title: Text('Scan QR Code', style: TextStyle(color: p.text)),
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
              targetUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.subtext),
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
  // FULL-SCREEN CHROME GRID TAB SWITCHER (WITH REAL PAGE THUMBNAILS)
  // ===========================================================================
  Future<void> _openFullScreenTabSwitcher() async {
    await _captureCurrentTabThumbnail();
    if (!mounted) return;

    String searchQuery = '';
    bool showIncognitoOnly = _isIncognito;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setGridState) {
            final p =
                ChromePalette.of(pageCtx, incognito: showIncognitoOnly);

            final filteredTabs = _tabs.where((t) {
              if (t.isIncognito != showIncognitoOnly) return false;
              if (searchQuery.trim().isNotEmpty) {
                final q = searchQuery.toLowerCase();
                return t.title.toLowerCase().contains(q) ||
                    t.url.toLowerCase().contains(q);
              }
              return true;
            }).toList();

            final ungroupedTabs = filteredTabs
                .where((t) =>
                    t.groupId == null ||
                    !_tabGroups.any((g) => g.id == t.groupId))
                .toList();

            return Scaffold(
              backgroundColor: p.bg,
              appBar: AppBar(
                backgroundColor: p.bg,
                foregroundColor: p.text,
                elevation: 0,
                automaticallyImplyLeading: false,
                titleSpacing: 12,
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // + New Tab Button
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
                          color: p.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.add,
                          color: p.isDark
                              ? const Color(0xFF1F1F1F)
                              : Colors.white,
                        ),
                      ),
                    ),

                    // Center Segmented Switcher ([ count ] | [ Incognito ])
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.border),
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
                                    ? p.topIconBg
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${_tabs.where((t) => !t.isIncognito).length}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: p.text),
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
                                    ? p.topIconBg
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.visibility_off_outlined,
                                  size: 18, color: p.text),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Right 3-Dot Menu
                    PopupMenuButton<String>(
                      color: p.menuBg,
                      icon: Icon(Icons.more_vert, color: p.text),
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
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: p.addressBar,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        style: TextStyle(color: p.text),
                        onChanged: (v) => setGridState(() => searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search your tabs',
                          hintStyle: TextStyle(color: p.subtext),
                          prefixIcon:
                              Icon(Icons.search, size: 20, color: p.subtext),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.76,
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
                            p: p,
                            group: group,
                            groupTabs: groupTabs,
                            pageCtx: pageCtx,
                            setGridState: setGridState,
                          );
                        }
                        final tab = ungroupedTabs[idx - groupCount];
                        final realIndex = _tabs.indexOf(tab);
                        return _buildSingleTabGridCard(
                          p: p,
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
    required ChromePalette p,
    required BrowserTab tab,
    required int realIndex,
    required BuildContext pageCtx,
    required StateSetter setGridState,
  }) {
    final isSelected = realIndex == _activeTabIndex;
    final host = Uri.tryParse(tab.url)?.host.replaceAll('www.', '') ?? tab.url;
    final hasThumb = tab.thumbnailPath != null &&
        tab.thumbnailPath!.isNotEmpty &&
        File(tab.thumbnailPath!).existsSync();

    return GestureDetector(
      onTap: () {
        Navigator.pop(pageCtx);
        _switchToTab(realIndex);
      },
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? p.accent : p.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 4),
              child: Row(
                children: [
                  Icon(
                    tab.isIncognito ? Icons.visibility_off : Icons.public,
                    size: 15,
                    color: p.accent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: p.text),
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    color: p.menuBg,
                    icon: Icon(Icons.more_vert, size: 16, color: p.subtext),
                    onSelected: (val) {
                      if (val == 'group') {
                        _promptMoveTabToGroup(tab, setGridState);
                      } else if (val == 'share') {
                        _shareLinkViaApp(tab.url, tab.title, 'more');
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
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 17, color: p.subtext),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                decoration: BoxDecoration(
                  color: p.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasThumb
                    ? Image.file(
                        File(tab.thumbnailPath!),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) =>
                            _buildTabCardFallbackBody(p, tab, host),
                      )
                    : _buildTabCardFallbackBody(p, tab, host),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabCardFallbackBody(
      ChromePalette p, BrowserTab tab, String host) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: p.topIconBg,
            child: Text(
              host.isNotEmpty ? host[0].toUpperCase() : 'W',
              style: TextStyle(color: p.accent, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tab.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w500, color: p.text),
          ),
          const SizedBox(height: 4),
          Text(
            host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: p.subtext),
          ),
        ],
      ),
    );
  }

  Widget _buildTabGroupGridCard({
    required ChromePalette p,
    required BrowserTabGroup group,
    required List<BrowserTab> groupTabs,
    required BuildContext pageCtx,
    required StateSetter setGridState,
  }) {
    final grpColor = Color(group.colorValue);
    return GestureDetector(
      onTap: () => _openTabGroupDetailDialog(group, pageCtx, setGridState),
      child: Container(
        decoration: BoxDecoration(
          color: grpColor.withAlpha(38),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: grpColor.withAlpha(180), width: 1.5),
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
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: p.text),
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
                    child: Icon(Icons.close, size: 17, color: p.text),
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
                    final hasThumb = t.thumbnailPath != null &&
                        t.thumbnailPath!.isNotEmpty &&
                        File(t.thumbnailPath!).existsSync();
                    return Container(
                      decoration: BoxDecoration(
                        color: p.bg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: hasThumb
                          ? Image.file(
                              File(t.thumbnailPath!),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(
                                t.title,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: p.text),
                              ),
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setGrpDialog) {
          final groupTabs =
              _tabs.where((t) => t.groupId == group.id).toList();
          return AlertDialog(
            backgroundColor: p.menuBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                CircleAvatar(
                    radius: 7, backgroundColor: Color(group.colorValue)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${group.title} (${groupTabs.length} tabs)',
                      style: TextStyle(fontSize: 16, color: p.text)),
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
                  ? Text('इस ग्रुप में अभी कोई टैब नहीं है।',
                      style: TextStyle(color: p.subtext))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: groupTabs.length,
                      itemBuilder: (_, i) {
                        final t = groupTabs[i];
                        final rIdx = _tabs.indexOf(t);
                        return ListTile(
                          leading: Icon(Icons.public, color: p.accent),
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
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
          backgroundColor: p.menuBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('New tab group', style: TextStyle(color: p.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
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
                            ? Border.all(color: p.text, width: 3)
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    showModalBottomSheet(
      context: context,
      backgroundColor: p.menuBg,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add tab to group',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: p.text)),
            Divider(color: p.border),
            ..._tabGroups.map((g) => ListTile(
                  leading: CircleAvatar(
                      radius: 8, backgroundColor: Color(g.colorValue)),
                  title: Text(g.title, style: TextStyle(color: p.text)),
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
  // FULL-SCREEN CHROME DOWNLOADS PAGE (WITH LIVE CIRCULAR PROGRESS RING!)
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
    _pollActiveDownloads();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setDlPage) {
            final p = ChromePalette.of(pageCtx);
            return ValueListenableBuilder<int>(
              valueListenable: _downloadsUpdateTick,
              builder: (_, __, ___) {
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
                  backgroundColor: p.bg,
                  appBar: AppBar(
                    backgroundColor: p.bg,
                    foregroundColor: p.text,
                    automaticallyImplyLeading: false,
                    title: showSearch
                        ? TextField(
                            autofocus: true,
                            style: TextStyle(color: p.text),
                            onChanged: (v) =>
                                setDlPage(() => searchQuery = v),
                            decoration: InputDecoration(
                              hintText: 'Search downloads...',
                              hintStyle: TextStyle(color: p.subtext),
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
                        icon: Icon(
                            showSearch ? Icons.search_off : Icons.search),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              storageLabel,
                              style:
                                  TextStyle(fontSize: 12.5, color: p.subtext),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: storageRatio,
                                minHeight: 4,
                                color: p.accent,
                                backgroundColor: p.surfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: filters.map((f) {
                            final isSel = selectedFilter == f;
                            IconData chipIcon = Icons.check;
                            if (f == 'Videos') {
                              chipIcon = Icons.videocam_outlined;
                            }
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
                                avatar: Icon(chipIcon,
                                    size: 17,
                                    color: isSel ? p.accent : p.subtext),
                                label: Text(
                                  f,
                                  style: TextStyle(
                                    color: isSel ? p.accent : p.text,
                                    fontWeight: isSel
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                                selectedColor: p.accent.withAlpha(32),
                                backgroundColor: p.surface,
                                side: BorderSide(
                                    color: isSel ? p.accent : p.border),
                                onSelected: (_) =>
                                    setDlPage(() => selectedFilter = f),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      Divider(height: 8, color: p.border),

                      Expanded(
                        child: filteredList.isEmpty
                            ? Center(
                                child: Text(
                                  'Downloads you save appear here',
                                  style: TextStyle(color: p.subtext),
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
                                  final host =
                                      Uri.tryParse(item.url)?.host ?? '';
                                  final hasLocalImage =
                                      item.category == 'Images' &&
                                          item.filePath.isNotEmpty &&
                                          File(item.filePath).existsSync();

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (showHeader)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              top: 12, bottom: 8),
                                          child: Text(
                                            item.dateLabel,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: p.subtext,
                                            ),
                                          ),
                                        ),
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: _buildDownloadLeadingWidget(
                                            p, item, hasLocalImage),
                                        title: Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: p.text),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.isInProgress
                                                  ? item.sizeLabel
                                                  : (host.isNotEmpty
                                                      ? '${item.sizeLabel} • $host'
                                                      : item.sizeLabel),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: item.status == 'failed'
                                                    ? Colors.redAccent
                                                    : (item.isInProgress
                                                        ? p.accent
                                                        : p.subtext),
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () => _openDownloadEntry(item),
                                        trailing: item.isInProgress
                                            ? IconButton(
                                                icon: Icon(Icons.close,
                                                    color: p.subtext),
                                                tooltip: 'Cancel download',
                                                onPressed: () async {
                                                  await _intentChannel
                                                      .invokeMethod(
                                                          'cancelDownload', {
                                                    'downloadId':
                                                        item.downloadId,
                                                  });
                                                  setState(() => _downloads
                                                      .remove(item));
                                                  _downloadsUpdateTick.value++;
                                                  await _saveData();
                                                },
                                              )
                                            : PopupMenuButton<String>(
                                                color: p.menuBg,
                                                icon: Icon(Icons.more_vert,
                                                    color: p.subtext),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14)),
                                                onSelected: (val) async {
                                                  if (val == 'open_with') {
                                                    await _intentChannel
                                                        .invokeMethod(
                                                            'openWithSystem', {
                                                      'filePath':
                                                          item.filePath,
                                                      'url': item.url,
                                                    });
                                                  } else if (val == 'share') {
                                                    await _intentChannel
                                                        .invokeMethod(
                                                            'shareLink', {
                                                      'url': item.url.isNotEmpty
                                                          ? item.url
                                                          : item.filePath,
                                                      'title': item.title,
                                                    });
                                                  } else if (val == 'rename') {
                                                    _promptRenameDownloadItem(
                                                        item, setDlPage);
                                                  } else if (val == 'delete') {
                                                    await _intentChannel
                                                        .invokeMethod(
                                                            'deleteFileOnDisk',
                                                            {
                                                          'filePath':
                                                              item.filePath,
                                                        });
                                                    setState(() => _downloads
                                                        .remove(item));
                                                    _downloadsUpdateTick
                                                        .value++;
                                                    await _saveData();
                                                  }
                                                },
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                    value: 'open_with',
                                                    child: Text('Open with...'),
                                                  ),
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildDownloadLeadingWidget(
    ChromePalette p,
    DownloadEntry item,
    bool hasLocalImage,
  ) {
    // Chrome-style live circular progress ring when downloading
    if (item.isInProgress) {
      final pct = item.progress >= 0
          ? '${(item.progress * 100).round().clamp(0, 100)}%'
          : '';
      return SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                value: item.progress >= 0 ? item.progress : null,
                strokeWidth: 3.2,
                color: p.accent,
                backgroundColor: p.surfaceVariant,
              ),
            ),
            if (pct.isNotEmpty)
              Text(
                pct,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: p.accent,
                ),
              )
            else
              Icon(Icons.arrow_downward, size: 17, color: p.accent),
          ],
        ),
      );
    }

    if (hasLocalImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(item.filePath),
          width: 42,
          height: 42,
          fit: BoxFit.cover,
        ),
      );
    }

    return CircleAvatar(
      radius: 21,
      backgroundColor: p.surfaceVariant,
      child: Icon(
        item.status == 'failed'
            ? Icons.error_outline
            : (item.category == 'Pages'
                ? Icons.public
                : (item.category == 'Images'
                    ? Icons.image_outlined
                    : (item.category == 'Videos'
                        ? Icons.videocam_outlined
                        : Icons.insert_drive_file_outlined))),
        color: item.status == 'failed' ? Colors.redAccent : p.accent,
        size: 20,
      ),
    );
  }

  void _promptRenameDownloadItem(
      DownloadEntry item, StateSetter setDlPage) {
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final ctrl = TextEditingController(text: item.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.menuBg,
        title: Text('Rename file', style: TextStyle(color: p.text)),
        content: TextField(controller: ctrl, autofocus: true),
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
                _downloadsUpdateTick.value++;
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
  // FULL-SCREEN CHROME HISTORY PAGE & DELETE BROWSING DATA
  // ===========================================================================
  void _openFullScreenHistoryPage() {
    String searchQuery = '';
    bool showSearch = false;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setHistPage) {
            final p = ChromePalette.of(pageCtx);
            final filtered = _history.where((h) {
              if (searchQuery.trim().isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return h.title.toLowerCase().contains(q) ||
                  h.url.toLowerCase().contains(q);
            }).toList();

            return Scaffold(
              backgroundColor: p.bg,
              appBar: AppBar(
                backgroundColor: p.bg,
                foregroundColor: p.text,
                automaticallyImplyLeading: false,
                title: showSearch
                    ? TextField(
                        autofocus: true,
                        style: TextStyle(color: p.text),
                        onChanged: (v) => setHistPage(() => searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search history...',
                          hintStyle: TextStyle(color: p.subtext),
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
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    color: p.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You may see history from links opened in Study Browser.',
                          style: TextStyle(fontSize: 12.5, color: p.subtext),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            await _openDeleteBrowsingDataDialog();
                            setHistPage(() {});
                          },
                          child: Text(
                            'Delete browsing data...',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: p.accent,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No browsing history here',
                              style: TextStyle(color: p.subtext),
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
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: p.subtext,
                                        ),
                                      ),
                                    ),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: p.surfaceVariant,
                                      child: Text(
                                        host.isNotEmpty
                                            ? host[0].toUpperCase()
                                            : 'G',
                                        style: TextStyle(
                                            color: p.accent,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: p.text),
                                    ),
                                    subtitle: Text(
                                      '$host • ${item.timestamp}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12, color: p.subtext),
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(Icons.cancel_outlined,
                                          size: 20, color: p.subtext),
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
          builder: (pageCtx, setDelState) {
            final p = ChromePalette.of(pageCtx);
            return Scaffold(
              backgroundColor: p.bg,
              appBar: AppBar(
                backgroundColor: p.bg,
                foregroundColor: p.text,
                title: const Text('Delete browsing data'),
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Time range', style: TextStyle(color: p.subtext)),
                      DropdownButton<String>(
                        value: timeRange,
                        dropdownColor: p.menuBg,
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
                  Divider(height: 24, color: p.border),
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
                    subtitle: const Text('Clears form entries & searches'),
                    value: delAutofill,
                    onChanged: (v) =>
                        setDelState(() => delAutofill = v ?? true),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Note: Your Focus & Lock passwords and Whitelist rules will NOT be deleted.',
                    style: TextStyle(fontSize: 12.5, color: p.subtext),
                  ),
                  const SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () async {
                        final nowMs = DateTime.now().millisecondsSinceEpoch;
                        int cutoffMs = 0;
                        if (timeRange == 'Last 15 minutes') {
                          cutoffMs = nowMs - const Duration(minutes: 15).inMilliseconds;
                        } else if (timeRange == 'Last hour') {
                          cutoffMs = nowMs - const Duration(hours: 1).inMilliseconds;
                        } else if (timeRange == 'Last 24 hours') {
                          cutoffMs = nowMs - const Duration(hours: 24).inMilliseconds;
                        } else if (timeRange == 'Last 7 days') {
                          cutoffMs = nowMs - const Duration(days: 7).inMilliseconds;
                        }

                        if (delHistory) {
                          setState(() {
                            if (timeRange == 'All time') {
                              _history.clear();
                            } else {
                              _history.removeWhere(
                                  (h) => h.visitEpochMs >= cutoffMs);
                            }
                          });
                        }
                        if (delAutofill) {
                          setState(() => _recentSearches.clear());
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
            );
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // FULL-SCREEN RECENT TABS, BOOKMARKS (VISUAL/COMPACT + SORT), SETTINGS & HELP
  // ===========================================================================
  void _openFullScreenRecentTabsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) {
          final p = ChromePalette.of(pageCtx);
          return Scaffold(
            backgroundColor: p.bg,
            appBar: AppBar(
              backgroundColor: p.bg,
              foregroundColor: p.text,
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
                Text(
                  'Recently closed',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.subtext),
                ),
                const SizedBox(height: 8),
                if (_recentlyClosedTabs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('No recently closed tabs',
                        style: TextStyle(color: p.subtext)),
                  )
                else
                  ..._recentlyClosedTabs.map((t) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: p.surfaceVariant,
                          child: Icon(Icons.public, color: p.accent, size: 18),
                        ),
                        title: Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.text)),
                        subtitle: Text(t.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.subtext)),
                        onTap: () {
                          Navigator.pop(pageCtx);
                          _createNewTab(incognito: false, url: t.url);
                        },
                      )),
                Divider(height: 28, color: p.border),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: p.surfaceVariant,
                    child: Icon(Icons.history, color: p.accent),
                  ),
                  title: Text('Show full history',
                      style: TextStyle(color: p.text)),
                  onTap: () {
                    Navigator.pop(pageCtx);
                    _openFullScreenHistoryPage();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openFullScreenBookmarksPage() {
    String searchQuery = '';
    bool readingListOnly = false;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setBmPage) {
            final p = ChromePalette.of(pageCtx);
            final list = _bookmarks.where((b) {
              if (b.isReadingList != readingListOnly) return false;
              if (searchQuery.trim().isNotEmpty) {
                final q = searchQuery.toLowerCase();
                return b.title.toLowerCase().contains(q) ||
                    b.url.toLowerCase().contains(q);
              }
              return true;
            }).toList();

            if (_bookmarkSortOrder == 'newest') {
              list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            } else if (_bookmarkSortOrder == 'oldest') {
              list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            } else if (_bookmarkSortOrder == 'az') {
              list.sort((a, b) =>
                  a.title.toLowerCase().compareTo(b.title.toLowerCase()));
            } else if (_bookmarkSortOrder == 'za') {
              list.sort((a, b) =>
                  b.title.toLowerCase().compareTo(a.title.toLowerCase()));
            }

            return Scaffold(
              backgroundColor: p.bg,
              appBar: AppBar(
                backgroundColor: p.bg,
                foregroundColor: p.text,
                title: Text(readingListOnly ? 'Reading list' : 'Bookmarks'),
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
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: p.addressBar,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TextField(
                        style: TextStyle(color: p.text),
                        onChanged: (v) => setBmPage(() => searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search your bookmarks',
                          hintStyle: TextStyle(color: p.subtext),
                          prefixIcon:
                              Icon(Icons.search, size: 20, color: p.subtext),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ),
                  // Folder tabs + Sort + Visual/Compact toggle row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Mobile'),
                          selected: !readingListOnly,
                          onSelected: (_) =>
                              setBmPage(() => readingListOnly = false),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Reading list'),
                          selected: readingListOnly,
                          onSelected: (_) =>
                              setBmPage(() => readingListOnly = true),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          color: p.menuBg,
                          tooltip: 'Sort bookmarks',
                          icon: Icon(Icons.sort, color: p.subtext, size: 20),
                          onSelected: (v) {
                            setState(() => _bookmarkSortOrder = v);
                            setBmPage(() {});
                            _saveData();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'manual', child: Text('Manual')),
                            PopupMenuItem(
                                value: 'newest', child: Text('Newest first')),
                            PopupMenuItem(
                                value: 'oldest', child: Text('Oldest first')),
                            PopupMenuItem(value: 'az', child: Text('A to Z')),
                            PopupMenuItem(value: 'za', child: Text('Z to A')),
                          ],
                        ),
                        IconButton(
                          icon: Icon(
                            _bookmarkVisualView
                                ? Icons.view_list_outlined
                                : Icons.view_agenda_outlined,
                            color: p.subtext,
                            size: 20,
                          ),
                          tooltip: _bookmarkVisualView
                              ? 'Compact view'
                              : 'Visual view',
                          onPressed: () {
                            setState(() =>
                                _bookmarkVisualView = !_bookmarkVisualView);
                            setBmPage(() {});
                            _saveData();
                          },
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 12, color: p.border),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Text('No bookmarks saved here',
                                style: TextStyle(color: p.subtext)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final bm = list[i];
                              final host =
                                  Uri.tryParse(bm.url)?.host ?? bm.url;
                              return Container(
                                margin: EdgeInsets.only(
                                    bottom: _bookmarkVisualView ? 10 : 2),
                                decoration: _bookmarkVisualView
                                    ? BoxDecoration(
                                        color: p.card,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: p.border),
                                      )
                                    : null,
                                child: ListTile(
                                  dense: !_bookmarkVisualView,
                                  leading: CircleAvatar(
                                    radius: _bookmarkVisualView ? 20 : 16,
                                    backgroundColor: p.surfaceVariant,
                                    child: Icon(Icons.star,
                                        color: p.accent,
                                        size: _bookmarkVisualView ? 20 : 16),
                                  ),
                                  title: Text(bm.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.text,
                                          fontWeight: FontWeight.w500)),
                                  subtitle: Text(host,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 12, color: p.subtext)),
                                  trailing: PopupMenuButton<String>(
                                    color: p.menuBg,
                                    icon: Icon(Icons.more_vert,
                                        size: 19, color: p.subtext),
                                    onSelected: (val) async {
                                      if (val == 'new_tab') {
                                        Navigator.pop(pageCtx);
                                        _createNewTab(url: bm.url);
                                      } else if (val == 'move') {
                                        setState(() => bm.isReadingList =
                                            !bm.isReadingList);
                                        setBmPage(() {});
                                        await _saveData();
                                      } else if (val == 'delete') {
                                        setState(() => _bookmarks.remove(bm));
                                        setBmPage(() {});
                                        await _saveData();
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                          value: 'new_tab',
                                          child: Text('Open in new tab')),
                                      PopupMenuItem(
                                          value: 'move',
                                          child: Text(bm.isReadingList
                                              ? 'Move to Mobile bookmarks'
                                              : 'Move to Reading list')),
                                      const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete')),
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.pop(pageCtx);
                                    _loadFromSearchBar(bm.url);
                                  },
                                ),
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

  Future<void> _openFullScreenSettingsPage() async {
    String dlPath = '/storage/emulated/0/Download';
    try {
      final res = await _intentChannel.invokeMethod<String>('getDownloadLocation');
      if (res != null && res.isNotEmpty) dlPath = res;
    } catch (_) {}
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setSettingsState) {
            final p = ChromePalette.of(pageCtx);
            final themeLabel = _themePreference == 'light'
                ? 'Light'
                : (_themePreference == 'dark' ? 'Dark' : 'System default');

            return Scaffold(
              backgroundColor: p.bg,
              appBar: AppBar(
                backgroundColor: p.bg,
                foregroundColor: p.text,
                title: const Text('Settings'),
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSettingsCard(
                    p: p,
                    title: 'Default browser',
                    subtitle: 'Set Study Browser as your system default browser',
                    icon: Icons.open_in_browser,
                    onTap: () {
                      _intentChannel.invokeMethod('openDefaultAppsSettings');
                    },
                  ),
                  _buildSettingsCard(
                    p: p,
                    title: 'Theme',
                    subtitle: themeLabel,
                    icon: Icons.brightness_6_outlined,
                    onTap: () async {
                      await _openThemeSettingsPage();
                      setSettingsState(() {});
                    },
                  ),
                  _buildSettingsCard(
                    p: p,
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
                        backgroundColor: p.menuBg,
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('Advanced',
                        style: TextStyle(
                            color: p.accent, fontWeight: FontWeight.w600)),
                  ),
                  _buildSettingsCard(
                    p: p,
                    title: 'Tabs and tab groups',
                    subtitle: '${_tabs.length} open tabs • Auto-restore enabled',
                    icon: Icons.layers_outlined,
                    onTap: () {
                      Navigator.pop(pageCtx);
                      _openFullScreenTabSwitcher();
                    },
                  ),
                  _buildSettingsCard(
                    p: p,
                    title: 'Homepage',
                    subtitle: 'On • $_homepageUrl',
                    icon: Icons.home_outlined,
                    onTap: () {
                      final ctrl = TextEditingController(text: _homepageUrl);
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: p.menuBg,
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
                    p: p,
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
                    p: p,
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
                    p: p,
                    title: 'Downloads',
                    subtitle: dlPath,
                    icon: Icons.download_done_outlined,
                    onTap: () {
                      Navigator.pop(pageCtx);
                      _openFullScreenDownloadsPage();
                    },
                  ),
                  _buildSettingsCard(
                    p: p,
                    title: 'About Study Browser',
                    subtitle: 'Version 3.0.0 • Chrome Light/Dark UI + Focus Vault',
                    icon: Icons.info_outline,
                    onTap: () {},
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openThemeSettingsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) => StatefulBuilder(
          builder: (pageCtx, setThemePage) {
            final p = ChromePalette.of(pageCtx);
            return Scaffold(
              backgroundColor: p.bg,
              appBar: AppBar(
                backgroundColor: p.bg,
                foregroundColor: p.text,
                title: const Text('Theme'),
              ),
              body: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  RadioListTile<String>(
                    value: 'system',
                    groupValue: _themePreference,
                    activeColor: p.accent,
                    title: Text('System default',
                        style: TextStyle(color: p.text)),
                    subtitle: Text(
                        'Turn on Dark theme when your device\'s Dark theme or Battery Saver is on',
                        style: TextStyle(color: p.subtext, fontSize: 12.5)),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _applyThemePreference(val));
                        setThemePage(() {});
                      }
                    },
                  ),
                  RadioListTile<String>(
                    value: 'light',
                    groupValue: _themePreference,
                    activeColor: p.accent,
                    title: Text('Light', style: TextStyle(color: p.text)),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _applyThemePreference(val));
                        setThemePage(() {});
                      }
                    },
                  ),
                  RadioListTile<String>(
                    value: 'dark',
                    groupValue: _themePreference,
                    activeColor: p.accent,
                    title: Text('Dark', style: TextStyle(color: p.text)),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _applyThemePreference(val));
                        setThemePage(() {});
                      }
                    },
                  ),
                  Divider(height: 24, color: p.border),
                  CheckboxListTile(
                    value: _darkenWebsitesInDark,
                    activeColor: p.accent,
                    title: Text('Apply Dark theme to sites, when possible',
                        style: TextStyle(color: p.text)),
                    subtitle: Text(
                      'Forces dark colors on web pages when Dark theme is active',
                      style: TextStyle(color: p.subtext, fontSize: 12.5),
                    ),
                    onChanged: (v) {
                      setState(() => _darkenWebsitesInDark = v ?? false);
                      setThemePage(() {});
                      _syncWebViewTheme();
                      _saveData();
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    required ChromePalette p,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: p.accent),
        title: Text(title,
            style: TextStyle(fontWeight: FontWeight.w500, color: p.text)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: p.subtext)),
        onTap: onTap,
      ),
    );
  }

  void _openFullScreenHelpPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageCtx) {
          final p = ChromePalette.of(pageCtx);
          return Scaffold(
            backgroundColor: p.bg,
            appBar: AppBar(
              backgroundColor: p.bg,
              foregroundColor: p.text,
              title: const Text('Help & Feedback'),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Popular help resources',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: p.accent),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.article_outlined, color: p.accent),
                  title: Text('How Time-Vault & Focus Locks work',
                      style: TextStyle(color: p.text)),
                  subtitle: Text(
                    'Generate a 16-digit password, copy it to Chronocrypt Vault, and lock distracting sites or YouTube Shorts.',
                    style: TextStyle(color: p.subtext),
                  ),
                ),
                Divider(color: p.border),
                ListTile(
                  leading: Icon(Icons.brightness_6_outlined, color: p.accent),
                  title: Text('Switch between Light, Dark & System theme',
                      style: TextStyle(color: p.text)),
                  subtitle: Text(
                    'Open 3-dot Menu > Settings > Theme to switch between Light mode, Dark mode, or System default.',
                    style: TextStyle(color: p.subtext),
                  ),
                ),
                Divider(color: p.border),
                ListTile(
                  leading: Icon(Icons.image_outlined, color: p.accent),
                  title: Text('Image Long-Press Menu',
                      style: TextStyle(color: p.text)),
                  subtitle: Text(
                    'Touch and hold any image on a webpage to preview, copy, download, share, or search with Google Lens.',
                    style: TextStyle(color: p.subtext),
                  ),
                ),
                Divider(color: p.border),
                ListTile(
                  leading: Icon(Icons.code, color: p.accent),
                  title: Text('View Webpage Source Code',
                      style: TextStyle(color: p.text)),
                  subtitle: Text(
                    'Type view-source:https://example.com in the address bar to inspect HTML source code.',
                    style: TextStyle(color: p.subtext),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openSiteControlsDialog() {
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final uri = Uri.tryParse(_currentUrl);
    final host = uri?.host ?? _currentUrl;
    final isSecure = _currentUrl.startsWith('https://');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.menuBg,
        title: Row(
          children: [
            Icon(
              isSecure ? Icons.lock_outline : Icons.info_outline,
              color: isSecure ? const Color(0xFF1E8E3E) : Colors.amber,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                host.isEmpty ? 'Site Controls' : host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: p.text),
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
              style: TextStyle(fontSize: 13, color: p.subtext),
            ),
            const SizedBox(height: 8),
            Text(
              'Mode: ${_isDesktopMode ? "Desktop Site" : "Mobile Site"} • Zoom: $_zoomPercent%',
              style: TextStyle(fontSize: 13, color: p.subtext),
            ),
            Divider(height: 20, color: p.border),
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final passCtrl = TextEditingController();
    String? errorText;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: p.menuBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: p.border),
          ),
          title: Text(title, style: TextStyle(fontSize: 17, color: p.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'अनलॉक करने के लिए अपना पासवर्ड (Time-Vault से) दर्ज करें:',
                style: TextStyle(fontSize: 13, color: p.subtext),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'पासवर्ड पेस्ट करें',
                  errorText: errorText,
                  filled: true,
                  fillColor: p.bg,
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final passCtrl = TextEditingController();
    bool obscure = false;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: p.menuBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: p.border),
          ),
          title: Text('$label पर लॉक सेट करें',
              style: TextStyle(fontSize: 17, color: p.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'पासवर्ड लिखें या रैंडम पासवर्ड जनरेट करके अपने Time-Vault में लॉक कर दें:',
                style: TextStyle(fontSize: 13, color: p.subtext),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'कम से कम 4 अक्षर का पासवर्ड',
                  filled: true,
                  fillColor: p.bg,
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.bg,
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
                        Row(
                          children: [
                            Icon(Icons.shield_outlined,
                                color: p.accent, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              'Focus & Lock Manager',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: p.text,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.close, size: 20, color: p.text),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.border),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor:
                          p.isDark ? const Color(0xFF1F1F1F) : Colors.white,
                      unselectedLabelColor: p.subtext,
                      indicator: BoxDecoration(
                        color: p.accent,
                        borderRadius:
                            const BorderRadius.all(Radius.circular(10)),
                      ),
                      tabs: const [
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
                                color: p.card,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: p.border),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _featurePassHash.isNotEmpty
                                        ? Icons.lock_outline
                                        : Icons.lock_open_outlined,
                                    color: _featurePassHash.isNotEmpty
                                        ? const Color(0xFF1E8E3E)
                                        : p.subtext,
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
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14.5,
                                            color: p.text,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'लॉक ऑन करने के बाद बिना पासवर्ड कोई नियम बंद नहीं होगा',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: p.subtext,
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
                                color: p.card,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: p.border),
                              ),
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    title: Text('Block YouTube Shorts',
                                        style: TextStyle(
                                            fontSize: 14.5, color: p.text)),
                                    subtitle: Text(
                                      'क्लासेस और लेक्चर चलेंगे, Shorts टैब और रील्स ब्लॉक रहेंगे',
                                      style: TextStyle(
                                          fontSize: 12, color: p.subtext),
                                    ),
                                    value: _blockYtShorts,
                                    onChanged: (_) => toggleFeature(
                                      currentValue: _blockYtShorts,
                                      onChanged: (v) => _blockYtShorts = v,
                                    ),
                                  ),
                                  Divider(height: 1, color: p.border),
                                  SwitchListTile(
                                    title: Text('YouTube Search-Only Mode',
                                        style: TextStyle(
                                            fontSize: 14.5, color: p.text)),
                                    subtitle: Text(
                                      'YouTube होमपेज फीड छिपाएं ताकि केवल सर्च काम करे',
                                      style: TextStyle(
                                          fontSize: 12, color: p.subtext),
                                    ),
                                    value: _hideYtFeed,
                                    onChanged: (_) => toggleFeature(
                                      currentValue: _hideYtFeed,
                                      onChanged: (v) => _hideYtFeed = v,
                                    ),
                                  ),
                                  Divider(height: 1, color: p.border),
                                  SwitchListTile(
                                    title: Text(
                                        'Block Instagram Reels & Explore',
                                        style: TextStyle(
                                            fontSize: 14.5, color: p.text)),
                                    subtitle: Text(
                                      'केवल DM/चैट चलेगा, Reels और Explore पेज बंद रहेंगे',
                                      style: TextStyle(
                                          fontSize: 12, color: p.subtext),
                                    ),
                                    value: _blockIgReels,
                                    onChanged: (_) => toggleFeature(
                                      currentValue: _blockIgReels,
                                      onChanged: (v) => _blockIgReels = v,
                                    ),
                                  ),
                                  Divider(height: 1, color: p.border),
                                  SwitchListTile(
                                    title: Text('Strict Whitelist Mode',
                                        style: TextStyle(
                                            fontSize: 14.5, color: p.text)),
                                    subtitle: Text(
                                      'केवल नीचे दी गई ${_whitelistedDomains.length} स्टडी वेबसाइट्स ही खुलेंगी',
                                      style: TextStyle(
                                          fontSize: 12, color: p.subtext),
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
                                color: p.card,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: p.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Allowed Study Domains (Whitelist)',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: p.text,
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
                                            style: TextStyle(
                                                fontSize: 12, color: p.text)),
                                        backgroundColor: p.bg,
                                        side: BorderSide(color: p.border),
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
                                              Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: p.card,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.redAccent.withAlpha(110)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.block,
                                      color: Colors.redAccent, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Permanent Block (Forever)',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: p.text,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'ब्लॉक की गई साइट्स न कभी खुलेंगी, न यहाँ दिखेंगी और न Search Results में आएंगी',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: p.subtext,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.tonal(
                                    onPressed: _promptAddPermanentBlockedSite,
                                    child: const Text('Add'),
                                  ),
                                ],
                              ),
                            ),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Custom Block Groups',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: p.text,
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
                                  color: p.card,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: active
                                        ? p.accent.withAlpha(140)
                                        : p.border,
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
                                                  ? p.accent
                                                  : p.subtext,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              group.name,
                                              style: TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.w600,
                                                color: p.text,
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
                                              icon: Icon(
                                                  Icons.delete_outline,
                                                  size: 19,
                                                  color: p.subtext),
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
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: p.text)),
                                            backgroundColor: p.bg,
                                            side: BorderSide(color: p.border),
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
                                          backgroundColor: p.topIconBg,
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.menuBg,
        title: Text('स्टडी वेबसाइट जोड़ें',
            style: TextStyle(fontSize: 17, color: p.text)),
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.menuBg,
        title: Text('नया Lock Group बनाएं',
            style: TextStyle(fontSize: 17, color: p.text)),
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
    final p = ChromePalette.of(context, incognito: _isIncognito);
    final domainCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.menuBg,
        title: Text('${group.name} में डोमेन जोड़ें',
            style: TextStyle(fontSize: 17, color: p.text)),
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
  // MAIN SCAFFOLD (CHROME LIGHT/DARK TOP BAR + WEBVIEW + FLOATING ZOOM)
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final p = ChromePalette.of(context, incognito: _isIncognito);

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
        backgroundColor: p.bg,
        body: SafeArea(
          child: Column(
            children: [
              
                                  Expanded(
                      child: InkWell(
                        onTap: _openChromeAddressBarOverlay,
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: p.addressBar,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isIncognito
                                    ? Icons.visibility_off_outlined
                                    : Icons.lock_outline,
                                size: 16,
                                color: p.accent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _formatDisplayUrl(_currentUrl),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(fontSize: 14.5, color: p.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

              
                    // Tab Counter Box [ 1 ]
                    InkWell(
                      onTap: _openFullScreenTabSwitcher,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: p.text, width: 1.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_tabs.length}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: p.text,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.shield_outlined,
                          size: 21, color: p.accent),
                      tooltip: 'Focus & Lock Manager',
                      onPressed: _openLockManagerSheet,
                    ),
                    IconButton(
                      icon: Icon(Icons.more_vert, size: 22, color: p.text),
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
                  color: p.surface,
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18, color: p.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _findController,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _performFindInPage,
                          style: TextStyle(fontSize: 14, color: p.text),
                          decoration: InputDecoration(
                            hintText: 'Find in page...',
                            hintStyle: TextStyle(color: p.subtext),
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
                        icon: Icon(Icons.close, size: 18, color: p.text),
                        onPressed: () => setState(() => _showFindBar = false),
                      ),
                    ],
                  ),
                ),

              if (_loadingProgress < 100)
                LinearProgressIndicator(
                  value: _loadingProgress / 100.0,
                  minHeight: 2,
                  color: p.accent,
                  backgroundColor: Colors.transparent,
                ),

              // MAIN WEBVIEW + AUTO-HIDING FLOATING CHROME ZOOM + BLOCKED OVERLAY
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _webController),

                    if (_showZoomBar)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 18,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Material(
                              color: p.menuBg,
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: p.border),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$_zoomPercent %',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: p.text),
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
                            Material(
                              color: p.menuBg,
                              elevation: 10,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                                side: BorderSide(color: p.border),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.remove, color: p.text),
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
                                        activeColor: p.accent,
                                        onChanged: (v) {
                                          setState(
                                              () => _zoomPercent = v.round());
                                          _injectFocusScripts();
                                          _scheduleZoomAutoHide();
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.add, color: p.text),
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

                    if (_isPageBlocked) _buildBlockedOverlay(p),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedOverlay(ChromePalette p) {
    return Container(
      width: double.infinity,
      color: p.bg,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.surface,
              shape: BoxShape.circle,
              border: Border.all(color: p.border),
            ),
            child: Icon(
              Icons.shield_outlined,
              size: 46,
              color: p.accent,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Access Restricted',
            style: TextStyle(
                fontSize: 21, fontWeight: FontWeight.w600, color: p.text),
          ),
          const SizedBox(height: 8),
          Text(
            _blockedReason,
            style: TextStyle(fontSize: 14.5, color: p.accent),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _blockedUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: p.subtext),
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
