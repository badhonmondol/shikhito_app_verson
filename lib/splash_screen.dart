import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:convert';
import 'permission_page.dart';
import 'main_page.dart';
import 'block_screen.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fb;
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// ─────────────────────────────────────────
//  এই app এর current version
//  নতুন APK বানালে এই number বাড়াবে
// ─────────────────────────────────────────
const String _fallbackCurrentVersion = '1.0.4';

// ─────────────────────────────────────────
//  GitHub raw link — তোমার repo অনুযায়ী ঠিক করা হয়েছে
// ─────────────────────────────────────────
const String _versionCheckUrl =
    'https://raw.githubusercontent.com/badhonmondol/shikhito_app_verson/main/version.json';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  // Update state
  String _currentVersion = _fallbackCurrentVersion;
  String _latestVersion = '';
  String _apkDownloadUrl = '';
  String _updateMessage = '';
  bool _isDownloading = false;
  double _downloadProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _scaleAnim = Tween<double>(begin: 0.6, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();

    Future.delayed(const Duration(seconds: 3), _checkUpdateThenStart);
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _currentVersion = info.version);
    } catch (_) {
      // fallback version দিয়ে update check চলবে
    }
  }

  // ─────────────────────────────────────────
  //  UPDATE CHECK
  // ─────────────────────────────────────────
  Future<void> _checkUpdateThenStart() async {
    await _loadCurrentVersion();
    try {
      final response = await http
          .get(Uri.parse(_versionCheckUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latest = data['version'] as String;
        final apkUrl = data['apk_url'] as String;
        final message = (data['message'] ?? '') as String;

        if (_isNewerVersion(latest, _currentVersion)) {
          setState(() {
            _latestVersion = latest;
            _apkDownloadUrl = apkUrl;
            _updateMessage = message;
          });
          _showUpdateDialog();
          return;
        }
      }
    } catch (_) {
      // internet নেই বা error — সরাসরি চালু করো
    }

    _startFlow();
  }

  bool _isNewerVersion(String latest, String current) {
    final l = latest.split('.').map(int.parse).toList();
    final c = current.split('.').map(int.parse).toList();
    for (int i = 0; i < l.length; i++) {
      final li = i < l.length ? l[i] : 0;
      final ci = i < c.length ? c[i] : 0;
      if (li > ci) return true;
      if (li < ci) return false;
    }
    return false;
  }

  // ─────────────────────────────────────────
  //  UPDATE DIALOG
  // ─────────────────────────────────────────
  void _showUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: Color(0xFF6C63FF),
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'নতুন আপডেট আছে!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1a1a2e),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Version $_currentVersion → $_latestVersion',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              if (_updateMessage.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _updateMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6C63FF),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Progress bar
              if (_isDownloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _downloadProgress,
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade200,
                    color: const Color(0xFF6C63FF),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ডাউনলোড হচ্ছে... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
              ],

              if (!_isDownloading) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      setDialogState(() => _isDownloading = true);
                      setState(() => _isDownloading = true);
                      await _downloadAndInstall(
                        onProgress: (p) {
                          setDialogState(() => _downloadProgress = p);
                          setState(() => _downloadProgress = p);
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'আপডেট করুন',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _startFlow();
                    },
                    child: const Text(
                      'এখন না',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  //  DOWNLOAD & INSTALL APK
  // ─────────────────────────────────────────
  Future<void> _downloadAndInstall({
    required Function(double) onProgress,
  }) async {
    try {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/shikhito_update.apk';
      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(_apkDownloadUrl));
      final response = await request.send();
      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final sink = file.openWrite();
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      });
      await sink.close();

      await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('ডাউনলোড ব্যর্থ হয়েছে। পরে চেষ্টা করুন।'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        _startFlow();
      }
    }
  }

  // ─────────────────────────────────────────
  //  DEVICE INFO / LOCATION
  // ─────────────────────────────────────────
  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.identifierForVendor ?? 'unknown_ios';
      }
    } catch (_) {
      // device id পাওয়া যায়নি
    }
    return 'unknown_device';
  }

  Future<String> _getPhoneNumber() async {
    try {
      final status = await Permission.phone.request();
      if (!status.isGranted) return 'Not Available';

      const channel = MethodChannel('shikhito/device');
      try {
        final res = await channel.invokeMethod<String>('getSimNumber');
        if (res != null && res.isNotEmpty) return res;
      } catch (_) {
        // platform channel কাজ করেনি
      }
      return 'Not Available';
    } catch (_) {
      return 'Not Available';
    }
  }

  Future<Map<String, dynamic>> _getLocation() async {
    try {
      await Permission.location.request();
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {'latitude': 0.0, 'longitude': 0.0, 'status': 'disabled'};
      }
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'status': 'success',
      };
    } catch (_) {
      return {'latitude': 0.0, 'longitude': 0.0, 'status': 'error'};
    }
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return {
          'device_name': info.device,
          'model': info.model,
          'manufacturer': info.manufacturer,
          'android_version': info.version.release,
          'device_id': info.id,
        };
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return {
          'device_name': info.name,
          'model': info.model,
          'manufacturer': 'Apple',
          'ios_version': info.systemVersion,
          'device_id': info.identifierForVendor ?? 'Unknown',
        };
      }
    } catch (_) {
      // device info পাওয়া যায়নি
    }
    return {'device_name': 'Unknown', 'model': 'Unknown'};
  }

  Future<void> _collectAndSaveDeviceInfo(String deviceId) async {
    try {
      final phoneNumber = await _getPhoneNumber();
      final location = await _getLocation();
      final deviceInfo = await _getDeviceInfo();

      final firestore = fb.FirebaseFirestore.instance;
      await firestore.collection('devices').doc(deviceId).set({
        'phone_number': phoneNumber,
        'location': {
          'latitude': location['latitude'],
          'longitude': location['longitude'],
        },
        'device_name': deviceInfo['device_name'],
        'model': deviceInfo['model'],
        'manufacturer': deviceInfo['manufacturer'],
        'version': deviceInfo['android_version'] ?? deviceInfo['ios_version'],
        'app_version': _currentVersion,
        'device_info_updated_at': fb.FieldValue.serverTimestamp(),
      }, fb.SetOptions(merge: true));
    } catch (_) {
      // Firestore save ব্যর্থ হলে ignore
    }
  }

  Future<void> _startFlow() async {
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PermissionPage(onAllGranted: _checkDevice),
          ),
        );
      }
    } else {
      await _checkDevice();
    }
  }

  Future<void> _checkDevice() async {
    try {
      final deviceId = await _getDeviceId();
      final firestore = fb.FirebaseFirestore.instance;
      final docRef = firestore.collection('devices').doc(deviceId);
      final doc = await docRef.get();

      if (!doc.exists) {
        await docRef.set({
          'device_id': deviceId,
          'active': false,
          'created_at': fb.FieldValue.serverTimestamp(),
          'platform': Platform.isAndroid ? 'android' : 'ios',
        });
        _collectAndSaveDeviceInfo(deviceId);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => BlockScreen(deviceId: deviceId)),
          );
        }
      } else {
        final bool isActive = doc.data()?['active'] ?? false;
        _collectAndSaveDeviceInfo(deviceId);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  isActive ? const MainPage() : BlockScreen(deviceId: deviceId),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const BlockScreen(deviceId: 'সংযোগ সমস্যা'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF3B82F6), Color(0xFF06B6D4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/shikhito.jpeg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'শিখিতো',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'পড়ো • শোনো • বলো',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.85),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 60),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      color: Colors.white.withValues(alpha: 0.8),
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'লোড হচ্ছে...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'v$_currentVersion',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
