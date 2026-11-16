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
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF38BDF8),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF818CF8),
          surface: Color(0xFF1E293B),
        ),
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
  int tempUnlockUntil; // Epoch ms

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'domains': domains,
        'passwordHash': passwordHash,
        'isLocked': isLocked,
        'tempUnlockUntil': tempUnlockUntil,
      };

  factory LockGroup.fromJson(Map<String, dynamic> json) => LockGroup(
        id: json['id'] ?? '',
        name: json['name'] ?? 'Group',
        domains: List<String>.from(json['domains'] ?? []),
        passwordHash: json['passwordHash'] ?? '',
        isLocked: json['isLocked'] ?? false,
        tempUnlockUntil: json['tempUnlockUntil'] ?? 0,
      );
}

class BrowserHomeScreen extends StatefulWidget {
  const BrowserHomeScreen({super.key});

  @override
  State<BrowserHomeScreen> createState() => _BrowserHomeScreenState();
}

class _BrowserHomeScreenState extends State<BrowserHomeScreen> {
  late final WebViewController _webController;
  final TextEditingController _urlController = TextEditingController();

  int _loadingProgress = 0;
  String _currentUrl = 'https://www.google.com';

  // Feature Locks (YouTube & Instagram & Whitelist)
  bool _blockYtShorts = true;
  bool _hideYtFeed = false;
  bool _blockIgReels = true;
  bool _whitelistMode = false;
  String _featurePassHash = '';
  int _featureTempUnlockUntil = 0;

  List<String> _whitelistedDomains = [
    'google.com',
    'youtube.com',
    'wikipedia.org',
    'ncert.nic.in',
    'upsc.gov.in',
    'github.com',
  ];

  List<LockGroup> _lockGroups = [];
  List _bookmarks = [];

  // Blocked Screen Overlay State
  bool _isPageBlocked = false;
  String _blockedUrl = '';
  String _blockedReason = '';
  LockGroup? _blockingGroup;

  // Raw JS for hiding YouTube Shorts, Home Feed, and Instagram Reels
  static const String _focusFilterJs = r'''
    (function() {
      if (window.__SB_INTERVAL_SET) return;
      window.__SB_INTERVAL_SET = true;

      function applyFocusRules() {
        var host = window.location.hostname || '';
        var path = window.location.pathname || '';

        // 1. YouTube Rules
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
                [is-shorts],
                a[href^="/shorts"],
                ytm-pivot-bar-item-renderer:nth-child(2) {
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

        // 2. Instagram Rules
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
                a[href*="/explore/"] {
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

      setInterval(applyFocusRules, 450);
      applyFocusRules();
    })();
  ''';

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _initWebView();
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

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
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
        _lockGroups = decoded.map((e) => LockGroup.fromJson(e)).toList();
      } else {
        // Default Starter Groups (Unlocked initially)
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
        _bookmarks =
            decoded.map((e) => Map<String, String>.from(e as Map)).toList();
      } else {
        _bookmarks = [
          {'title': 'Google Search', 'url': 'https://www.google.com'},
          {'title': 'YouTube Study', 'url': 'https://m.youtube.com'},
          {'title': 'NCERT Books', 'url': 'https://ncert.nic.in'},
        ];
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
    await prefs.setString('bookmarks', jsonEncode(_bookmarks));
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F172A))
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 13; RMX3395) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() => _loadingProgress = progress);
            }
            _injectFocusScripts();
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _currentUrl = url;
                _urlController.text = url;
              });
            }
            _checkAndBlockUrl(url);
            _injectFocusScripts();
          },
          onPageFinished: (url) {
            _injectFocusScripts();
          },
          onUrlChange: (change) {
            final newUrl = change.url ?? '';
            if (newUrl.isNotEmpty) {
              if (mounted) {
                setState(() {
                  _currentUrl = newUrl;
                  _urlController.text = newUrl;
                });
              }
              _checkAndBlockUrl(newUrl);
              _injectFocusScripts();
            }
          },
          onNavigationRequest: (request) {
            final decision = _evaluateUrl(request.url);
            if (!decision) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.google.com'));
  }

  Future<void> _injectFocusScripts() async {
    try {
      final bool shortsActive =
          _blockYtShorts && (_featurePassHash.isEmpty || _isFeatureLockActive);
      final bool feedActive =
          _hideYtFeed && (_featurePassHash.isEmpty || _isFeatureLockActive);
      final bool igActive =
          _blockIgReels && (_featurePassHash.isEmpty || _isFeatureLockActive);

      final flagsJs =
          'window.__SB_YT_SHORTS = $shortsActive; window.__SB_YT_FEED = $feedActive; window.__SB_IG_REELS = $igActive;';
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
        .split('/')
        .first
        .trim();
    if (cleanRule.isEmpty) return false;

    final cleanHost = host.toLowerCase().replaceAll('www.', '');
    if (cleanHost == cleanRule || cleanHost.endsWith('.$cleanRule')) {
      return true;
    }
    // Proxy / Google Translate bypass protection
    final cleanRuleHyphen = cleanRule.replaceAll('.', '-');
    if (fullUrl.toLowerCase().contains(cleanRule) ||
        cleanHost.contains(cleanRuleHyphen)) {
      return true;
    }
    return false;
  }

  bool _evaluateUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return true;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final featureEnforced = _featurePassHash.isEmpty || _isFeatureLockActive;

    // 1. Check Feature Locks (YouTube Shorts & Instagram Reels)
    if (featureEnforced) {
      if (_blockYtShorts &&
          host.contains('youtube.com') &&
          path.startsWith('/shorts')) {
        _showToast('🔒 YouTube Shorts लॉक है! सिर्फ़ पढ़ाई के वीडियो चालू हैं।');
        return false;
      }
      if (_blockIgReels &&
          host.contains('instagram.com') &&
          (path.startsWith('/reels') ||
              path.startsWith('/reel/') ||
              path.startsWith('/explore'))) {
        _showToast('🔒 Instagram Reels & Explore लॉक है!');
        return false;
      }
    }

    // 2. Check Custom Lock Groups
    for (final group in _lockGroups) {
      if (group.isCurrentlyActive) {
        for (final domain in group.domains) {
          if (_domainMatches(host, url, domain)) {
            setState(() {
              _isPageBlocked = true;
              _blockedUrl = url;
              _blockedReason = 'Group: ${group.name}';
              _blockingGroup = group;
            });
            return false;
          }
        }
      }
    }

    // 3. Check Whitelist Exam Mode
    if (_whitelistMode && featureEnforced) {
      bool allowed = false;
      for (final wDomain in _whitelistedDomains) {
        final cleanW = wDomain.toLowerCase().replaceAll('www.', '').trim();
        final cleanH = host.replaceAll('www.', '');
        if (cleanH == cleanW || cleanH.endsWith('.$cleanW')) {
          allowed = true;
          break;
        }
      }
      if (!allowed) {
        setState(() {
          _isPageBlocked = true;
          _blockedUrl = url;
          _blockedReason = 'Exam Whitelist Mode (सिर्फ़ पढ़ाई की साइट्स चालू हैं)';
          _blockingGroup = null;
        });
        return false;
      }
    }

    if (_isPageBlocked) {
      setState(() => _isPageBlocked = false);
    }
    return true;
  }

  void _checkAndBlockUrl(String url) {
    final allowed = _evaluateUrl(url);
    if (!allowed && !_isPageBlocked) {
      _webController.loadRequest(Uri.parse('https://www.google.com'));
    }
  }

  void _loadFromSearchBar(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    setState(() => _isPageBlocked = false);
    String targetUrl;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      targetUrl = trimmed;
    } else if (trimmed.contains('.') && !trimmed.contains(' ')) {
      targetUrl = 'https://$trimmed';
    } else {
      targetUrl =
          'https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}';
    }
    _webController.loadRequest(Uri.parse(targetUrl));
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Dialog to Verify Password (with 10-Min Temp Unlock option)
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
          backgroundColor: const Color(0xFF1E293B),
          title: Text(title, style: const TextStyle(fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'अनलॉक करने के लिए अपना पासवर्ड (Time-Vault से) डालें:',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'पासवर्ड यहाँ पेस्ट करें',
                  errorText: errorText,
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
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
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                ),
                onPressed: () {
                  if (_hashPassword(passCtrl.text) == expectedHash) {
                    Navigator.pop(ctx, 'TEMP_10');
                  } else {
                    setDialogState(() => errorText = 'गलत पासवर्ड!');
                  }
                },
                child: const Text('10 Min Unlock'),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.black,
              ),
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

  // Dialog to Set a New Password (with 1-Tap Random Generator for Time-Vault)
  Future<String?> _promptSetNewPassword(String label) async {
    final passCtrl = TextEditingController();
    bool obscure = false;

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text('🔒 $label पर लॉक लगाएं',
              style: const TextStyle(fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'कोई पासवर्ड डालें या नीचे बटन दबाकर रैंडम पासवर्ड बनाएं और उसे अपने Time-Vault में लॉक कर दें:',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'पासवर्ड लिखें या जनरेट करें',
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
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
                  icon: const Icon(Icons.bolt, color: Colors.amber),
                  label: const Text('Random Password बनाएं + Copy करें'),
                  onPressed: () {
                    final rndPass = _generateRandomPassword();
                    setDialogState(() {
                      passCtrl.text = rndPass;
                      obscure = true; // ताकि याद न रहे
                    });
                    Clipboard.setData(ClipboardData(text: rndPass));
                    _showToast(
                        '✅ रैंडम पासवर्ड Copy हो गया! अब इसे Time-Vault में पेस्ट कर दें।');
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (passCtrl.text.trim().length < 4) {
                  _showToast('कम से कम 4 अक्षर का पासवर्ड रखें!');
                  return;
                }
                Clipboard.setData(ClipboardData(text: passCtrl.text.trim()));
                Navigator.pop(ctx, _hashPassword(passCtrl.text));
              },
              child: const Text('Lock Activate करें'),
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
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> toggleFeature({
              required bool currentValue,
              required Function(bool) onChanged,
            }) async {
              // Turning ON is always instant without password
              if (!currentValue) {
                setState(() => onChanged(true));
                setSheetState(() {});
                await _saveData();
                _injectFocusScripts();
                return;
              }
              // Turning OFF requires password if Feature Lock is set
              if (_isFeatureLockActive) {
                final res = await _promptPasswordVerification(
                  title: 'Feature Lock पासवर्ड',
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
                  _showToast('⏱️ 10 मिनट के लिए अनलॉक किया गया!');
                }
              } else {
                setState(() => onChanged(false));
              }
              setSheetState(() {});
              await _saveData();
              _injectFocusScripts();
            }

            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🛡️ Focus & Lock Manager',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24),

                // SECTION 1: FEATURE LOCKS (YOUTUBE & INSTAGRAM)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _isFeatureLockActive
                          ? Colors.greenAccent.withOpacity(0.5)
                          : Colors.white12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              '🎯 YouTube, Insta & Exam Controls',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ),
                          if (_featurePassHash.isEmpty)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.lock_outline, size: 16),
                              label: const Text('Password लगाएं'),
                              onPressed: () async {
                                final hash = await _promptSetNewPassword(
                                    'Feature Controls');
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
                            TextButton.icon(
                              icon: const Icon(Icons.lock,
                                  color: Colors.greenAccent, size: 16),
                              label: const Text(
                                'Locked (Reset)',
                                style: TextStyle(color: Colors.greenAccent),
                              ),
                              onPressed: () async {
                                final res = await _promptPasswordVerification(
                                  title: 'Feature Lock हटाएं',
                                  expectedHash: _featurePassHash,
                                  allowTempUnlock: false,
                                );
                                if (res == 'FULL') {
                                  setState(() => _featurePassHash = '');
                                  setSheetState(() {});
                                  await _saveData();
                                  _showToast('Feature पासवर्ड हटा दिया गया।');
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Block YouTube Shorts'),
                        subtitle: const Text(
                            'लेक्चर चलेंगे, पर Shorts बटन और रील्स गायब रहेंगे'),
                        value: _blockYtShorts,
                        onChanged: (_) => toggleFeature(
                          currentValue: _blockYtShorts,
                          onChanged: (v) => _blockYtShorts = v,
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('YouTube Search-Only Mode'),
                        subtitle: const Text(
                            'होमपेज के फालतू वीडियो छिपाएं, सिर्फ़ सर्च काम करेगा'),
                        value: _hideYtFeed,
                        onChanged: (_) => toggleFeature(
                          currentValue: _hideYtFeed,
                          onChanged: (v) => _hideYtFeed = v,
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Block Instagram Reels & Explore'),
                        subtitle: const Text(
                            'DM/चैट चलेगा, पर Reels और Explore पेज ब्लॉक रहेंगे'),
                        value: _blockIgReels,
                        onChanged: (_) => toggleFeature(
                          currentValue: _blockIgReels,
                          onChanged: (v) => _blockIgReels = v,
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('🔥 Exam Whitelist Mode'),
                        subtitle: Text(
                            'सिर्फ़ मंज़ूर की गई ${_whitelistedDomains.length} पढ़ाई की साइट्स खुलेंगी'),
                        value: _whitelistMode,
                        onChanged: (_) => toggleFeature(
                          currentValue: _whitelistMode,
                          onChanged: (v) => _whitelistMode = v,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.playlist_add, size: 18),
                          label: const Text('Whitelist में पढ़ाई की साइट जोड़ें'),
                          onPressed: () =>
                              _promptAddWhitelistDomain(setSheetState),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // SECTION 2: CUSTOM SITE LOCK GROUPS
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📂 Custom Site Lock Groups',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF38BDF8),
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('नया Group बनाएं'),
                      onPressed: () => _promptCreateNewGroup(setSheetState),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                ..._lockGroups.map((group) {
                  final active = group.isCurrentlyActive;
                  return Card(
                    color: const Color(0xFF1E293B),
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: active
                            ? Colors.redAccent.withOpacity(0.6)
                            : Colors.white12,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    active ? Icons.lock : Icons.lock_open,
                                    color: active
                                        ? Colors.redAccent
                                        : Colors.greenAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    group.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  if (!group.isLocked)
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.redAccent,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () async {
                                        if (group.domains.isEmpty) {
                                          _showToast(
                                              'पहले इस ग्रुप में कम से कम 1 साइट जोड़ें!');
                                          return;
                                        }
                                        final hash = await _promptSetNewPassword(
                                            group.name);
                                        if (hash != null) {
                                          setState(() {
                                            group.passwordHash = hash;
                                            group.isLocked = true;
                                            group.tempUnlockUntil = 0;
                                          });
                                          setSheetState(() {});
                                          await _saveData();
                                          _checkAndBlockUrl(_currentUrl);
                                        }
                                      },
                                      child: const Text('Lock लगाएं'),
                                    )
                                  else
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.amber,
                                      ),
                                      onPressed: () async {
                                        final res =
                                            await _promptPasswordVerification(
                                          title: '${group.name} अनलॉक करें',
                                          expectedHash: group.passwordHash,
                                        );
                                        if (res == 'FULL') {
                                          setState(() {
                                            group.isLocked = false;
                                            group.passwordHash = '';
                                          });
                                          _showToast(
                                              '🔓 ${group.name} अनलॉक हो गया!');
                                        } else if (res == 'TEMP_10') {
                                          setState(() {
                                            group.tempUnlockUntil =
                                                DateTime.now()
                                                    .add(const Duration(
                                                        minutes: 10))
                                                    .millisecondsSinceEpoch;
                                          });
                                          _showToast(
                                              '⏱️ ${group.name} 10 मिनट के लिए अनलॉक हुआ!');
                                        }
                                        setSheetState(() {});
                                        await _saveData();
                                      },
                                      child: Text(active
                                          ? 'Unlock करें'
                                          : '10m खुला है'),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.white54),
                                    onPressed: () async {
                                      if (group.isCurrentlyActive) {
                                        _showToast(
                                            '🔒 लॉक लगे हुए ग्रुप को डिलीट करने के लिए पहले अनलॉक करें!');
                                        return;
                                      }
                                      setState(() => _lockGroups.remove(group));
                                      setSheetState(() {});
                                      await _saveData();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ...group.domains.map(
                                (domain) => Chip(
                                  label: Text(domain,
                                      style: const TextStyle(fontSize: 12)),
                                  backgroundColor: const Color(0xFF0F172A),
                                  deleteIcon: const Icon(Icons.close, size: 15),
                                  onDeleted: () async {
                                    if (group.isCurrentlyActive) {
                                      _showToast(
                                          '🔒 लॉक ग्रुप से साइट हटाने के लिए पहले ग्रुप अनलॉक करें!');
                                      return;
                                    }
                                    setState(
                                        () => group.domains.remove(domain));
                                    setSheetState(() {});
                                    await _saveData();
                                  },
                                ),
                              ),
                              ActionChip(
                                avatar: const Icon(Icons.add, size: 16),
                                label: const Text('+ साइट जोड़ें'),
                                backgroundColor:
                                    const Color(0xFF38BDF8).withOpacity(0.2),
                                onPressed: () =>
                                    _promptAddDomainToGroup(group, setSheetState),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _promptAddWhitelistDomain(StateSetter setSheetState) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('पढ़ाई की वेबसाइट जोड़ें'),
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
          ElevatedButton(
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
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('नया Lock Group बनाएं'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            hintText: 'ग्रुप का नाम (जैसे: Gaming, News, Social)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
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
        backgroundColor: const Color(0xFF1E293B),
        title: Text('${group.name} में साइट जोड़ें'),
        content: TextField(
          controller: domainCtrl,
          decoration: const InputDecoration(
            hintText: 'उदाहरण: instagram.com या snapchat.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
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
                _checkAndBlockUrl(_currentUrl);
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Add Site'),
          ),
        ],
      ),
    );
  }

  void _openBookmarksSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
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
                  const Text('⭐ Study Bookmarks',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.bookmark_add, size: 16),
                    label: const Text('मौजूदा पेज सेव करें'),
                    onPressed: () async {
                      final uri = Uri.tryParse(_currentUrl);
                      final title = uri?.host ?? 'Bookmark';
                      setState(() {
                        _bookmarks.add({'title': title, 'url': _currentUrl});
                      });
                      setBmState(() {});
                      await _saveData();
                      _showToast('⭐ बुकमार्क सेव हो गया!');
                    },
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _bookmarks.length,
                  itemBuilder: (_, i) {
                    final bm = _bookmarks[i];
                    return ListTile(
                      leading: const Icon(Icons.public,
                          color: Color(0xFF38BDF8)),
                      title: Text(bm['title'] ?? ''),
                      subtitle: Text(
                        bm['url'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          setState(() => _bookmarks.removeAt(i));
                          setBmState(() {});
                          await _saveData();
                        },
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _loadFromSearchBar(bm['url'] ?? 'https://www.google.com');
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isPageBlocked) {
          setState(() => _isPageBlocked = false);
          _webController.loadRequest(Uri.parse('https://www.google.com'));
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
              // TOP ADDRESS & CONTROL BAR
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: const Color(0xFF1E293B),
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
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: _urlController,
                          textInputAction: TextInputAction.go,
                          onSubmitted: _loadFromSearchBar,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Google सर्च या वेबसाइट डालें...',
                            prefixIcon: const Icon(Icons.lock_outline,
                                size: 16, color: Color(0xFF38BDF8)),
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
                    IconButton(
                      icon: const Icon(Icons.shield_outlined,
                          color: Color(0xFF38BDF8)),
                      tooltip: 'Focus & Lock Manager',
                      onPressed: _openLockManagerSheet,
                    ),
                  ],
                ),
              ),

              if (_loadingProgress < 100)
                LinearProgressIndicator(
                  value: _loadingProgress / 100.0,
                  minHeight: 2.5,
                  color: const Color(0xFF38BDF8),
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

              // BOTTOM NAVIGATION BAR
              Container(
                height: 48,
                color: const Color(0xFF1E293B),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                      onPressed: () async {
                        if (await _webController.canGoBack()) {
                          await _webController.goBack();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 18),
                      onPressed: () async {
                        if (await _webController.canGoForward()) {
                          await _webController.goForward();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () => _webController.reload(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.bookmarks_outlined, size: 20),
                      onPressed: _openBookmarksSheet,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.security,
                          size: 18, color: Colors.greenAccent),
                      label: const Text(
                        'Locks',
                        style: TextStyle(color: Colors.greenAccent),
                      ),
                      onPressed: _openLockManagerSheet,
                    ),
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
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_person_rounded,
              size: 72, color: Colors.redAccent),
          const SizedBox(height: 16),
          const Text(
            'यह वेबसाइट अभी लॉक है!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _blockedReason,
            style: const TextStyle(fontSize: 15, color: Color(0xFF38BDF8)),
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
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: Colors.black,
              minimumSize: const Size(220, 46),
            ),
            icon: const Icon(Icons.menu_book),
            label: const Text('पढ़ाई पर वापस जाएं (Google)'),
            onPressed: () {
              setState(() => _isPageBlocked = false);
              _loadFromSearchBar('https://www.google.com');
            },
          ),
          const SizedBox(height: 12),
          if (_blockingGroup != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.key),
              label: Text('${_blockingGroup!.name} का पासवर्ड डालें'),
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
                  _webController.loadRequest(Uri.parse(_blockedUrl));
                }
              },
            ),
        ],
      ),
    );
  }
}
