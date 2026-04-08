import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FoneHomeApp());
}

class FoneHomeApp extends StatefulWidget {
  const FoneHomeApp({super.key});

  static _FoneHomeAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_FoneHomeAppState>();

  @override
  State<FoneHomeApp> createState() => _FoneHomeAppState();
}

class _FoneHomeAppState extends State<FoneHomeApp> {
  String _fontFamily = 'Courier';

  void updateFont(String font) {
    setState(() {
      _fontFamily = font;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoneHome',
      themeMode: ThemeMode.system, // Support Light and Dark theme natively
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF0F0F0),
        fontFamily: _fontFamily,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFF111111)),
          bodyMedium: TextStyle(color: Color(0xFF111111)),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        fontFamily: _fontFamily,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFE0E0E0)),
          bodyMedium: TextStyle(color: Color(0xFFE0E0E0)),
        ),
      ),
      home: const LauncherScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppItem {
  final String packageName;
  final String originalName;
  final Uint8List icon;

  AppItem({
    required this.packageName,
    required this.originalName,
    required this.icon,
  });
}

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  static const platform = MethodChannel('com.fonehome.launcher/apps');
  static const notificationChannel = EventChannel('com.fonehome.launcher/notifications');
  
  List<AppItem> _allApps = [];
  List<AppItem> _filteredApps = [];
  
  List<String> _pinnedApps = [];
  List<String> _hiddenApps = [];
  Map<String, String> _renamedApps = {};
  bool _showHidden = false;
  
  // Customization State
  int _wallpaperIndex = 0;
  String _clockStyle = 'Bold'; // Bold, Thin, Outline, Stacked, Analog
  int _clockColorIndex = 0;
  String _fontStyle = 'Courier'; // Courier, Roboto, Arial, Times New Roman, monospace, sans-serif, serif, cursive
  String _iconShape = 'Original'; // Original, Circle, Squircle
  String _notificationStyle = 'Toast'; // Toast, Minimal, Card

  String _timeString = "";
  String _dateString = "";
  DateTime _currentDate = DateTime.now();
  Timer? _timer;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _notificationSubscription;
  bool _hasNotificationAccess = true;

  // Recorder State
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String _recordTime = "00:00";
  Timer? _recordTimer;
  int _recordSeconds = 0;

  final List<Color> _wallpapers = [
    Colors.transparent,
    const Color(0xFF1E1E24), // Dark Grey
    const Color(0xFFFFB6C1), // Pastel Pink
    const Color(0xFF87CEFA), // Light Blue
    const Color(0xFF98FB98), // Sky Blue
    const Color(0xFFE6E6FA), // Pale Green
  ];

  final List<Color> _clockColors = [
    const Color(0xFFCCFF00), // Neon Lime
    Colors.blueAccent,
    Colors.redAccent,
    Colors.purpleAccent,
    Colors.cyanAccent,
    Colors.orangeAccent,
    Colors.white,
    Colors.black,
  ];

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());
    _loadPreferences().then((_) => _loadApps());
    
    _searchController.addListener(() {
      _filterApps(_searchController.text);
    });

    _checkNotificationAccess();
    _initNotifications();
  }

  Future<void> _checkNotificationAccess() async {
    try {
      final bool granted = await platform.invokeMethod('isNotificationAccessGranted');
      setState(() {
        _hasNotificationAccess = granted;
      });
    } catch (e) {
      debugPrint("Failed to check notification access: $e");
    }
  }

  void _initNotifications() {
    _notificationSubscription = notificationChannel.receiveBroadcastStream().listen((event) {
      final data = Map<String, dynamic>.from(event);
      _showCustomNotification(data['title'] ?? 'Notification', data['text'] ?? '', data['packageName'] ?? '');
    });
  }

  void _showCustomNotification(String title, String text, String packageName) {
    if (!mounted) return;
    
    AppItem? app = _allApps.cast<AppItem?>().firstWhere(
      (a) => a?.packageName == packageName, 
      orElse: () => null
    );

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget notificationContent;

    if (_notificationStyle == 'Minimal') {
      notificationContent = Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111111) : Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (app != null) ...[
              ClipOval(child: Image.memory(app.icon, width: 24, height: 24)),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Text(
                title.isNotEmpty ? "$title: $text" : text,
                style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else if (_notificationStyle == 'Card') {
      notificationContent = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(left: BorderSide(color: _clockColors[_clockColorIndex], width: 4)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (app != null) ...[
                  Image.memory(app.icon, width: 20, height: 20),
                  const SizedBox(width: 8),
                ],
                Text(app?.originalName ?? 'System', style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.black)),
            const SizedBox(height: 4),
            Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
          ],
        ),
      );
    } else {
      // Toast (Default)
      notificationContent = Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF222222) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
          border: Border.all(color: _clockColors[_clockColorIndex], width: 2)
        ),
        child: Row(
          children: [
            if (app != null)
              ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(app.icon, width: 40, height: 40)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black)),
                  Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 50.0,
        left: _notificationStyle == 'Minimal' ? null : 20.0,
        right: _notificationStyle == 'Minimal' ? null : 20.0,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, -50 * (1 - value)),
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: notificationContent,
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 4), () {
      overlayEntry.remove();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordTimer?.cancel();
    _searchController.dispose();
    _notificationSubscription?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }
  
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pinnedApps = prefs.getStringList('pinnedApps') ?? [];
      _hiddenApps = prefs.getStringList('hiddenApps') ?? [];
      _wallpaperIndex = prefs.getInt('wallpaperIndex') ?? 0;
      _clockStyle = prefs.getString('clockStyle') ?? 'Bold';
      _clockColorIndex = prefs.getInt('clockColorIndex') ?? 0;
      _fontStyle = prefs.getString('fontStyle') ?? 'Courier';
      _iconShape = prefs.getString('iconShape') ?? 'Original';
      _notificationStyle = prefs.getString('notificationStyle') ?? 'Toast';
      
      String? renamedJson = prefs.getString('renamedApps');
      if (renamedJson != null) {
        _renamedApps = Map<String, String>.from(json.decode(renamedJson));
      }
    });
    // ignore: use_build_context_synchronously
    FoneHomeApp.of(context)?.updateFont(_fontStyle);
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinnedApps', _pinnedApps);
    await prefs.setStringList('hiddenApps', _hiddenApps);
    await prefs.setInt('wallpaperIndex', _wallpaperIndex);
    await prefs.setString('clockStyle', _clockStyle);
    await prefs.setInt('clockColorIndex', _clockColorIndex);
    await prefs.setString('fontStyle', _fontStyle);
    await prefs.setString('iconShape', _iconShape);
    await prefs.setString('notificationStyle', _notificationStyle);
    await prefs.setString('renamedApps', json.encode(_renamedApps));
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _currentDate = now;
      _timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      _dateString = "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}";
    });
  }

  Future<void> _loadApps() async {
    try {
      final List<dynamic> result = await platform.invokeMethod('getInstalledApps');
      final List<AppItem> apps = result.map((dynamic item) {
        final Map<dynamic, dynamic> map = item as Map<dynamic, dynamic>;
        return AppItem(
          packageName: map["packageName"] as String,
          originalName: map["appName"] as String,
          icon: map["icon"] as Uint8List,
        );
      }).toList();
      
      setState(() {
        _allApps = apps;
      });
      _filterApps(_searchController.text);
    } on PlatformException catch (e) {
      debugPrint("Failed to get apps: '${e.message}'.");
    }
  }

  void _filterApps(String query) {
    List<AppItem> visible = _allApps.where((app) {
      if (_showHidden) {
        return _hiddenApps.contains(app.packageName);
      }
      return !_hiddenApps.contains(app.packageName);
    }).toList();

    if (query.isNotEmpty) {
      visible = visible.where((app) {
        String name = _renamedApps[app.packageName] ?? app.originalName;
        return name.toLowerCase().contains(query.toLowerCase());
      }).toList();
    }

    visible.sort((a, b) {
      bool aPinned = _pinnedApps.contains(a.packageName);
      bool bPinned = _pinnedApps.contains(b.packageName);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      String aName = _renamedApps[a.packageName] ?? a.originalName;
      String bName = _renamedApps[b.packageName] ?? b.originalName;
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    });

    setState(() {
      _filteredApps = visible;
    });
  }

  Future<void> _launchApp(String packageName) async {
    try {
      await platform.invokeMethod('launchApp', {'packageName': packageName});
    } on PlatformException catch (e) {
      debugPrint("Failed to launch app: '${e.message}'.");
    }
  }

  Future<void> _disableAppSilently(String packageName) async {
    try {
      await platform.invokeMethod('disableApp', {'packageName': packageName});
    } catch (e) {
      // Silently catch error, we will just hide it in our launcher UI.
      debugPrint("Silent hide: System disable not allowed.");
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _audioRecorder.stop();
      _recordTimer?.cancel();
      setState(() {
        _isRecording = false;
        _recordSeconds = 0;
        _recordTime = "00:00";
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Recording saved to Documents!"),
            backgroundColor: _clockColors[_clockColorIndex],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) return;

      Directory dir = await getApplicationDocumentsDirectory();
      String path = '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(const RecordConfig(), path: path);
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
        _recordTime = "00:00";
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        setState(() {
          _recordSeconds++;
          final minutes = (_recordSeconds / 60).floor().toString().padLeft(2, '0');
          final seconds = (_recordSeconds % 60).toString().padLeft(2, '0');
          _recordTime = "$minutes:$seconds";
        });
      });
    }
  }
  
  void _showAppMenu(AppItem app) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        bool isPinned = _pinnedApps.contains(app.packageName);
        bool isHidden = _hiddenApps.contains(app.packageName);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _renamedApps[app.packageName] ?? app.originalName,
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: isDark ? Colors.white : Colors.black),
                title: Text(isPinned ? "UNPIN APP" : "PIN APP", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () {
                  setState(() {
                    if (isPinned) _pinnedApps.remove(app.packageName);
                    else _pinnedApps.add(app.packageName);
                    _savePreferences();
                    _filterApps(_searchController.text);
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(isHidden ? Icons.visibility : Icons.visibility_off, color: isDark ? Colors.white : Colors.black),
                title: Text(isHidden ? "UNHIDE APP" : "HIDE APP", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                onTap: () {
                  setState(() {
                    if (isHidden) _hiddenApps.remove(app.packageName);
                    else {
                      _hiddenApps.add(app.packageName);
                      _disableAppSilently(app.packageName); 
                    }
                    _savePreferences();
                    _filterApps(_searchController.text);
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blueAccent),
                title: const Text("RENAME APP", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(app);
                },
              ),
            ],
          ),
        );
      }
    );
  }

  void _showCustomizationMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("CUSTOMIZATION", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    const SizedBox(height: 20),
                    
                    Text("Wallpaper", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 50,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _wallpapers.length,
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () {
                              setModalState(() => _wallpaperIndex = index);
                              setState(() { _wallpaperIndex = index; _savePreferences(); });
                            },
                            child: Container(
                              width: 50,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: _wallpapers[index] == Colors.transparent ? (isDark ? Colors.black : Colors.white) : _wallpapers[index],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _wallpaperIndex == index ? Colors.blueAccent : Colors.grey,
                                  width: _wallpaperIndex == index ? 3 : 1,
                                )
                              ),
                              child: _wallpapers[index] == Colors.transparent ? const Icon(Icons.block, color: Colors.grey) : null,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text("Clock Style", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    DropdownButton<String>(
                      value: _clockStyle,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF222222) : Colors.white,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      items: ['Bold', 'Thin', 'Outline', 'Stacked', 'Analog'].map((String value) {
                        return DropdownMenuItem<String>(value: value, child: Text(value));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _clockStyle = val);
                          setState(() { _clockStyle = val; _savePreferences(); });
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    Text("Clock Color", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _clockColors.length,
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () {
                              setModalState(() => _clockColorIndex = index);
                              setState(() { _clockColorIndex = index; _savePreferences(); });
                            },
                            child: Container(
                              width: 40,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: _clockColors[index],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _clockColorIndex == index ? (isDark ? Colors.white : Colors.black) : Colors.transparent,
                                  width: 3,
                                )
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text("Font Style", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    DropdownButton<String>(
                      value: _fontStyle,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF222222) : Colors.white,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      items: ['Courier', 'Roboto', 'Arial', 'Times New Roman', 'monospace', 'sans-serif', 'serif', 'cursive'].map((String value) {
                        return DropdownMenuItem<String>(value: value, child: Text(value));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _fontStyle = val);
                          setState(() { _fontStyle = val; _savePreferences(); });
                          FoneHomeApp.of(this.context)?.updateFont(val);
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    Text("Icon Shape", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    DropdownButton<String>(
                      value: _iconShape,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF222222) : Colors.white,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      items: ['Original', 'Circle', 'Squircle'].map((String value) {
                        return DropdownMenuItem<String>(value: value, child: Text(value));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _iconShape = val);
                          setState(() { _iconShape = val; _savePreferences(); });
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    Text("Notification Style", style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                    DropdownButton<String>(
                      value: _notificationStyle,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF222222) : Colors.white,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                      items: ['Toast', 'Minimal', 'Card'].map((String value) {
                        return DropdownMenuItem<String>(value: value, child: Text(value));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => _notificationStyle = val);
                          setState(() { _notificationStyle = val; _savePreferences(); });
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }
  
  void _showRenameDialog(AppItem app) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    TextEditingController ctrl = TextEditingController(text: _renamedApps[app.packageName] ?? app.originalName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          title: Text("RENAME APP", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
          content: TextField(
            controller: ctrl,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white54 : Colors.black54)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _renamedApps.remove(app.packageName);
                  _savePreferences();
                  _filterApps(_searchController.text);
                });
                Navigator.pop(context);
              },
              child: const Text("RESET", style: TextStyle(color: Colors.redAccent)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _renamedApps[app.packageName] = ctrl.text.trim();
                  _savePreferences();
                  _filterApps(_searchController.text);
                });
                Navigator.pop(context);
              },
              child: const Text("SAVE", style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        );
      }
    );
  }

  Widget _buildAnalogClock(Color clockColor) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: clockColor, width: 4),
      ),
      child: CustomPaint(
        painter: AnalogClockPainter(
          datetime: _currentDate,
          color: clockColor,
        ),
      ),
    );
  }

  Widget _buildClock() {
    Color clockColor = _clockColors[_clockColorIndex];
    
    if (_clockStyle == 'Analog') {
      return _buildAnalogClock(clockColor);
    }

    if (_clockStyle == 'Stacked') {
      final hour = _currentDate.hour.toString().padLeft(2, '0');
      final minute = _currentDate.minute.toString().padLeft(2, '0');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hour, style: TextStyle(fontSize: 80, height: 0.9, letterSpacing: -2, fontWeight: FontWeight.w900, color: clockColor)),
          Text(minute, style: TextStyle(fontSize: 80, height: 0.9, letterSpacing: -2, fontWeight: FontWeight.w900, color: clockColor.withOpacity(0.5))),
        ],
      );
    }

    TextStyle baseStyle = TextStyle(
      fontSize: 80,
      height: 1.0,
      letterSpacing: -2,
      color: _clockStyle == 'Outline' ? Colors.transparent : clockColor,
    );

    if (_clockStyle == 'Thin') {
      baseStyle = baseStyle.copyWith(fontWeight: FontWeight.w200);
    } else {
      baseStyle = baseStyle.copyWith(fontWeight: FontWeight.w900);
    }

    Widget clockWidget = Text(_timeString, style: baseStyle);

    if (_clockStyle == 'Outline') {
      clockWidget = Stack(
        children: [
          Text(
            _timeString,
            style: baseStyle.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = clockColor,
            ),
          ),
        ],
      );
    }

    return clockWidget;
  }

  Widget _buildIcon(Uint8List iconData) {
    Widget img = Image.memory(iconData, width: 48, height: 48, gaplessPlayback: true);
    if (_iconShape == 'Circle') {
      return ClipOval(child: img);
    } else if (_iconShape == 'Squircle') {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: img);
    }
    return img; // Original
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: _wallpapers[_wallpaperIndex] == Colors.transparent 
          ? Theme.of(context).scaffoldBackgroundColor 
          : _wallpapers[_wallpaperIndex],
      body: GestureDetector(
        onLongPress: _showCustomizationMenu,
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Permission Banner
              if (!_hasNotificationAccess)
                GestureDetector(
                  onTap: () {
                    platform.invokeMethod('requestNotificationAccess');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.redAccent,
                    child: const Text(
                      "⚠️ Tap to enable Notification Access for custom notifications",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

              // Header Row (Clock + Recorder)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onLongPress: () {
                          setState(() {
                            _showHidden = !_showHidden;
                            _filterApps(_searchController.text);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_showHidden ? "GHOST MODE: ON 👻 (Showing Hidden)" : "GHOST MODE: OFF"),
                              backgroundColor: _showHidden ? _clockColors[_clockColorIndex] : (isDark ? Colors.black : Colors.white),
                              duration: const Duration(seconds: 2),
                            )
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildClock(),
                            const SizedBox(height: 8),
                            Text(
                              _dateString,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Nothing-style Universal Recorder Widget
                    GestureDetector(
                      onTap: _toggleRecording,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _isRecording ? Colors.redAccent.withOpacity(0.2) : (isDark ? const Color(0xFF1A1A1A) : Colors.white),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: _isRecording ? Colors.redAccent : Colors.transparent),
                          boxShadow: [
                            if (!isDark && !_isRecording)
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                          ]
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _isRecording ? Colors.redAccent : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (_isRecording) ...[
                              const SizedBox(width: 8),
                              Text(
                                _recordTime,
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                              )
                            ]
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
              
              // Search Bar (Rounded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                    ]
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'SEARCH APPS...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontWeight: FontWeight.bold,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    cursorColor: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              
              // App List
              Expanded(
                child: _filteredApps.isEmpty 
                    ? Center(
                        child: Text(
                          _showHidden ? "NO HIDDEN APPS 👻" : "NO APPS FOUND FR 💀",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: _filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = _filteredApps[index];
                          String displayName = _renamedApps[app.packageName] ?? app.originalName;
                          bool isPinned = _pinnedApps.contains(app.packageName);
                          
                          return InkWell(
                            onTap: () => _launchApp(app.packageName),
                            onLongPress: () => _showAppMenu(app),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                children: [
                                  // Real Colored Icons with custom Shape
                                  _buildIcon(app.icon),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black87,
                                        letterSpacing: -0.5,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isPinned)
                                    Icon(Icons.push_pin, color: _clockColors[_clockColorIndex], size: 20),
                                ],
                              ),
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
}

class AnalogClockPainter extends CustomPainter {
  final DateTime datetime;
  final Color color;

  AnalogClockPainter({required this.datetime, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final hourPaint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final minutePaint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final secondPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Draw Hands
    final hourHandLength = radius * 0.5;
    final minuteHandLength = radius * 0.7;
    final secondHandLength = radius * 0.8;

    final hourAngle = (datetime.hour % 12 + datetime.minute / 60) * 30 * math.pi / 180;
    final minuteAngle = (datetime.minute + datetime.second / 60) * 6 * math.pi / 180;
    final secondAngle = datetime.second * 6 * math.pi / 180;

    canvas.drawLine(
      center,
      Offset(center.dx + hourHandLength * math.sin(hourAngle), center.dy - hourHandLength * math.cos(hourAngle)),
      hourPaint,
    );

    canvas.drawLine(
      center,
      Offset(center.dx + minuteHandLength * math.sin(minuteAngle), center.dy - minuteHandLength * math.cos(minuteAngle)),
      minutePaint,
    );

    canvas.drawLine(
      center,
      Offset(center.dx + secondHandLength * math.sin(secondAngle), center.dy - secondHandLength * math.cos(secondAngle)),
      secondPaint,
    );

    // Center Dot
    canvas.drawCircle(center, 6, hourPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}