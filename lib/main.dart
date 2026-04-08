import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FoneHomeApp());
}

class FoneHomeApp extends StatelessWidget {
  const FoneHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FoneHome',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF000000), // Pure black
        fontFamily: 'Courier', // Brutalist monospace vibe
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
  
  List<AppItem> _allApps = [];
  List<AppItem> _filteredApps = [];
  
  // State for premium features
  List<String> _pinnedApps = [];
  List<String> _hiddenApps = [];
  Map<String, String> _renamedApps = {};
  bool _showHidden = false; // Toggle to view hidden apps
  
  String _timeString = "";
  String _dateString = "";
  Timer? _timer;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());
    _loadPreferences().then((_) => _loadApps());
    
    _searchController.addListener(() {
      _filterApps(_searchController.text);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pinnedApps = prefs.getStringList('pinnedApps') ?? [];
      _hiddenApps = prefs.getStringList('hiddenApps') ?? [];
      String? renamedJson = prefs.getString('renamedApps');
      if (renamedJson != null) {
        _renamedApps = Map<String, String>.from(json.decode(renamedJson));
      }
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinnedApps', _pinnedApps);
    await prefs.setStringList('hiddenApps', _hiddenApps);
    await prefs.setString('renamedApps', json.encode(_renamedApps));
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
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
  
  void _showAppMenu(AppItem app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
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
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, color: Colors.white),
                title: Text(isPinned ? "UNPIN APP" : "PIN APP", style: const TextStyle(color: Colors.white)),
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
                leading: Icon(isHidden ? Icons.visibility : Icons.visibility_off, color: Colors.white),
                title: Text(isHidden ? "UNHIDE APP" : "HIDE APP", style: const TextStyle(color: Colors.white)),
                onTap: () {
                  setState(() {
                    if (isHidden) _hiddenApps.remove(app.packageName);
                    else _hiddenApps.add(app.packageName);
                    _savePreferences();
                    _filterApps(_searchController.text);
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Color(0xFFCCFF00)),
                title: const Text("RENAME APP (PRO UNLOCKED 👑)", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
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
  
  void _showRenameDialog(AppItem app) {
    TextEditingController ctrl = TextEditingController(text: _renamedApps[app.packageName] ?? app.originalName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text("RENAME APP", style: TextStyle(color: Colors.white, fontFamily: 'Courier')),
          content: TextField(
            controller: ctrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFCCFF00))),
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
              child: const Text("SAVE", style: TextStyle(color: Color(0xFFCCFF00))),
            ),
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header / Clock
            GestureDetector(
              onLongPress: () {
                setState(() {
                  _showHidden = !_showHidden;
                  _filterApps(_searchController.text);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_showHidden ? "GHOST MODE: ON 👻 (Showing Hidden)" : "GHOST MODE: OFF"),
                    backgroundColor: _showHidden ? const Color(0xFFFF00FF) : Colors.black,
                    duration: const Duration(seconds: 2),
                  )
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _timeString,
                      style: const TextStyle(
                        fontSize: 80,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFCCFF00), // Neon Lime
                        height: 1.0,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _dateString,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Search Bar (Rounded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A), // Dark Neutral Grey
                  borderRadius: BorderRadius.circular(30), // ROUNDED STYLE
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'SEARCH APPS...',
                    hintStyle: TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.bold,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                  cursorColor: Colors.white,
                ),
              ),
            ),
            
            // App List
            Expanded(
              child: _filteredApps.isEmpty 
                  ? Center(
                      child: Text(
                        _showHidden ? "NO HIDDEN APPS 👻" : "NO APPS FOUND FR 💀",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
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
                                // Minimalistic Aesthetic Grayscale Icon
                                ColorFiltered(
                                  colorFilter: const ColorFilter.matrix([
                                    0.2126, 0.7152, 0.0722, 0, 0,
                                    0.2126, 0.7152, 0.0722, 0, 0,
                                    0.2126, 0.7152, 0.0722, 0, 0,
                                    0,      0,      0,      1, 0,
                                  ]),
                                  child: Image.memory(
                                    app.icon,
                                    width: 40,
                                    height: 40,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    displayName.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -1,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isPinned)
                                  const Icon(Icons.push_pin, color: Color(0xFFCCFF00), size: 20),
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
    );
  }
}
