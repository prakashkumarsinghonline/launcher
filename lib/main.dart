import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

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

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  static const platform = MethodChannel('com.fonehome.launcher/apps');
  
  List<Map<String, String>> _allApps = [];
  List<Map<String, String>> _filteredApps = [];
  String _timeString = "";
  String _dateString = "";
  Timer? _timer;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _updateTime());
    _loadApps();
    
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
      final List<Map<String, String>> apps = result.map((dynamic item) {
        final Map<dynamic, dynamic> map = item as Map<dynamic, dynamic>;
        return {
          "packageName": map["packageName"] as String,
          "appName": map["appName"] as String,
        };
      }).toList();
      
      setState(() {
        _allApps = apps;
        _filteredApps = apps;
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to get apps: '${e.message}'.");
    }
  }

  void _filterApps(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredApps = _allApps;
      });
    } else {
      setState(() {
        _filteredApps = _allApps.where((app) {
          return app["appName"]!.toLowerCase().contains(query.toLowerCase());
        }).toList();
      });
    }
  }

  Future<void> _launchApp(String packageName) async {
    try {
      await platform.invokeMethod('launchApp', {'packageName': packageName});
    } on PlatformException catch (e) {
      debugPrint("Failed to launch app: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header / Clock
            Padding(
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
            
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  filled: true,
                  fillColor: Color(0xFF1A1A1A), // Dark Neutral Grey
                  border: InputBorder.none, // NO BORDERS SHIT
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.all(20),
                ),
                cursorColor: Colors.white,
              ),
            ),
            
            // App List
            Expanded(
              child: _filteredApps.isEmpty 
                  ? const Center(
                      child: Text(
                        "NO APPS FOUND FR 💀",
                        style: TextStyle(
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
                        return InkWell(
                          onTap: () => _launchApp(app["packageName"]!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              app["appName"]!.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -1,
                              ),
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