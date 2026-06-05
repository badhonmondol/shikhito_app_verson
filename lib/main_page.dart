import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const String _fallbackCurrentVersion = '1.0.4';
const String _versionCheckUrl =
    'https://raw.githubusercontent.com/badhonmondol/shikhito_app_verson/main/version.json';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

enum VoiceGender { male, female }

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  // TTS
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _ttsController = TextEditingController();
  bool _isSpeaking = false;
  bool _ttsLoading = false;
  VoiceGender _selectedVoice = VoiceGender.male;
  double _speechRate = 0.45;
  String _currentlySpokenText = '';

  // STT
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _sttController = TextEditingController();
  bool _isListening = false;
  bool _speechAvailable = false;
  double _soundLevel = 0;

  // STT State
  // _savedText   : আগের সব session এর confirmed কথা (শুধু cross বাটনে মুছবে)
  // _currentText : এই session এ STT যা দিচ্ছে (partial/final)
  // _mergedInSession : এই session এ কি ইতিমধ্যে merge হয়েছে?
  String _savedText = '';
  String _currentText = '';
  bool _mergedInSession = false; // ← duplicate fix এর চাবিকাঠি
  bool _keepListening = false;
  bool _isManuallyStopped = false;
  bool _isStarting = false;

  // Update
  String _currentVersion = _fallbackCurrentVersion;
  bool _isCheckingUpdate = false;
  bool _isDownloadingUpdate = false;
  double _updateProgress = 0;

  // Word count
  int get _wordCount {
    final text = _sttController.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  // Animation
  late AnimationController _micPulseController;
  late Animation<double> _micPulseAnim;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSpeech();
    _loadCurrentVersion();

    _micPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _micPulseAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _micPulseController, curve: Curves.easeInOut),
    );
  }

  // ─────────────────────────────────────────
  //  TTS INIT
  // ─────────────────────────────────────────
  Future<void> _initTts() async {
    await _tts.setLanguage('bn-BD');
    await _tts.setVolume(1.0);
    await _setSpeechRate(_speechRate);
    await _applyVoice(_selectedVoice);

    _tts.setStartHandler(() => setState(() => _isSpeaking = true));
    _tts.setCompletionHandler(() => setState(() {
          _isSpeaking = false;
          _currentlySpokenText = '';
        }));
    _tts.setCancelHandler(() => setState(() => _isSpeaking = false));
    _tts.setErrorHandler((_) => setState(() => _isSpeaking = false));
  }

  Future<void> _applyVoice(VoiceGender gender) async {
    try {
      final dynamic rawVoices = await _tts.getVoices;
      if (rawVoices is List && rawVoices.isNotEmpty) {
        List<Map<String, String>> voices = [];
        for (final v in rawVoices) {
          if (v is Map) {
            final name = (v['name'] ?? '').toString();
            final locale = (v['locale'] ?? v['language'] ?? '').toString();
            voices.add({'name': name, 'locale': locale});
          }
        }

        Map<String, String>? picked;
        if (gender == VoiceGender.female) {
          picked = voices.firstWhere(
            (v) =>
                v['locale']!.toLowerCase().contains('bn') &&
                v['name']!.toLowerCase().contains('female'),
            orElse: () => {},
          );
          if (picked.isEmpty) {
            picked = voices.firstWhere(
              (v) => v['name']!.toLowerCase().contains('female'),
              orElse: () => {},
            );
          }
          if (picked.isEmpty) {
            picked = voices.firstWhere(
              (v) => v['locale']!.toLowerCase().startsWith('bn'),
              orElse: () => {},
            );
          }
        } else {
          picked = voices.firstWhere(
            (v) =>
                v['locale']!.toLowerCase().contains('bn') &&
                v['name']!.toLowerCase().contains('male'),
            orElse: () => {},
          );
          if (picked.isEmpty) {
            picked = voices.firstWhere(
              (v) => v['name']!.toLowerCase().contains('male'),
              orElse: () => {},
            );
          }
          if (picked.isEmpty) {
            picked = voices.firstWhere(
              (v) => v['locale']!.toLowerCase().startsWith('bn'),
              orElse: () => {},
            );
          }
        }
        if (picked.isNotEmpty) {
          await _tts.setVoice(picked);
        }
      }
    } catch (_) {}

    if (gender == VoiceGender.female) {
      await _tts.setPitch(1.5);
      await _tts.setSpeechRate((_speechRate * 0.9).clamp(0.2, 0.9));
    } else {
      await _tts.setPitch(0.8);
      await _tts.setSpeechRate(_speechRate);
    }
  }

  Future<void> _setSpeechRate(double rate) async {
    _speechRate = rate;
    if (_selectedVoice == VoiceGender.female) {
      await _tts.setSpeechRate((rate * 0.9).clamp(0.2, 0.9));
    } else {
      await _tts.setSpeechRate(rate);
    }
  }

  // ─────────────────────────────────────────
  //  STT INIT
  // ─────────────────────────────────────────
  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (e) {
        setState(() => _isListening = false);
        if (_keepListening && !_isManuallyStopped) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (_keepListening && !_isManuallyStopped) _startInternalListen();
          });
        }
      },
      onStatus: (status) {
        if (status == 'listening') {
          setState(() => _isListening = true);
        } else if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);

          // ── FIX: শুধু এই session এ merge না হলেই merge করবো ──
          if (!_mergedInSession) {
            _mergeCurrentToSaved();
          }
          _mergedInSession = false;

          if (_keepListening && !_isManuallyStopped) {
            Future.delayed(const Duration(milliseconds: 600), () {
              if (_keepListening && !_isManuallyStopped) _startInternalListen();
            });
          }
        }
      },
    );
    setState(() {});
  }

  // ─────────────────────────────────────────
  //  STT RESULT HANDLER
  // ─────────────────────────────────────────
  void _handleSTTResult(dynamic result) {
    final recognized = (result.recognizedWords as String).trim();

    setState(() {
      _currentText = recognized;
      _updateSttField();
    });

    // ── FIX: finalResult এ merge করো, কিন্তু flag set করো যাতে 'done' এ আবার না হয় ──
    if (result.finalResult as bool) {
      _mergeCurrentToSaved();
      _mergedInSession = true;
    }
  }

  // ─────────────────────────────────────────
  //  DISPLAY UPDATE
  // ─────────────────────────────────────────
  void _updateSttField() {
    String display;
    if (_savedText.isEmpty) {
      display = _currentText;
    } else if (_currentText.isEmpty) {
      display = _savedText;
    } else {
      display = '$_savedText $_currentText';
    }

    _sttController.text = display;
    _sttController.selection =
        TextSelection.fromPosition(TextPosition(offset: display.length));
  }

  // ─────────────────────────────────────────
  //  MERGE
  // ─────────────────────────────────────────
  void _mergeCurrentToSaved() {
    if (_currentText.isNotEmpty) {
      if (_savedText.isEmpty) {
        _savedText = _currentText;
      } else {
        _savedText = '$_savedText $_currentText';
      }
      _currentText = '';
      _updateSttField();
    }
  }

  // ─────────────────────────────────────────
  //  START INTERNAL LISTEN
  // ─────────────────────────────────────────
  Future<void> _startInternalListen() async {
    if (!_speechAvailable || _isStarting) return;
    _isStarting = true;
    _mergedInSession = false;
    _currentText = '';

    try {
      await _speech.listen(
        onResult: _handleSTTResult,
        listenOptions: stt.SpeechListenOptions(
          localeId: 'bn_BD',
          listenFor: const Duration(seconds: 30), // ← fix: device compatible
          pauseFor: const Duration(seconds: 3), // ← fix: চুপ থাকলেও restart
          onDevice: false,
          partialResults: true,
        ),
        onSoundLevelChange: (level) {
          setState(() => _soundLevel = level);
        },
      );
    } catch (_) {
      // ignore
    } finally {
      _isStarting = false; // ← fix: exception হলেও false হবে
    }
  }

  // ─────────────────────────────────────────
  //  TEXT CLEAN FOR TTS
  // ─────────────────────────────────────────
  String _cleanTextForSpeech(String text) {
    final emojiRegex = RegExp(
      r'[\u{1F000}-\u{1FFFF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|'
      r'[\u{FE00}-\u{FEFF}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA9F}]',
      unicode: true,
    );
    String cleaned = text.replaceAll(emojiRegex, '');
    cleaned =
        cleaned.replaceAll(RegExp(r'[#\-=+~`|\\^<>\[\]{}@&$%*()/:_?!;]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  // ─────────────────────────────────────────
  //  TTS ACTIONS
  // ─────────────────────────────────────────
  Future<void> _speakTtsText() async {
    final text = _ttsController.text.trim();
    if (text.isEmpty) return;
    final cleaned = _cleanTextForSpeech(text);
    if (cleaned.isEmpty) return;

    setState(() {
      _ttsLoading = true;
      _currentlySpokenText = cleaned;
    });
    if (_isSpeaking) await _tts.stop();
    await _tts.speak(cleaned);
    setState(() => _ttsLoading = false);
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    setState(() => _isSpeaking = false);
  }

  Future<void> _speakSttText() async {
    final text = _sttController.text.trim();
    if (text.isEmpty) return;
    final cleaned = _cleanTextForSpeech(text);
    if (cleaned.isEmpty) return;
    if (_isSpeaking) await _tts.stop();
    setState(() => _currentlySpokenText = cleaned);
    await _tts.speak(cleaned);
  }

  // ─────────────────────────────────────────
  //  STT TOGGLE
  // ─────────────────────────────────────────
  Future<void> _startListening() async {
    if (!_speechAvailable) {
      _showSnack('মাইক্রোফোন পাওয়া যাচ্ছে না');
      return;
    }

    if (_isListening) {
      _isManuallyStopped = true;
      _keepListening = false;
      try {
        await _speech.stop();
      } catch (_) {}
      setState(() => _isListening = false);
      return;
    }

    _isManuallyStopped = false;
    _keepListening = true;
    setState(() => _isListening = true);
    await _startInternalListen();
  }

  // ─────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────
  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _currentVersion = info.version);
    } catch (_) {
      // fallback version দিয়ে manual update check চলবে
    }
  }

  Future<void> _checkForUpdate({bool manual = false}) async {
    if (_isCheckingUpdate || _isDownloadingUpdate) return;

    setState(() => _isCheckingUpdate = true);
    try {
      final response = await http
          .get(Uri.parse(_versionCheckUrl))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception('Version check failed');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = (data['version'] ?? '').toString();
      final apkUrl = (data['apk_url'] ?? '').toString();
      final message = (data['message'] ?? '').toString();

      if (latest.isEmpty || apkUrl.isEmpty) {
        throw Exception('Invalid update info');
      }

      if (_isNewerVersion(latest, _currentVersion)) {
        if (!mounted) return;
        _showUpdateDialog(
          latestVersion: latest,
          apkUrl: apkUrl,
          message: message,
        );
      } else if (manual) {
        _showSnack('আপনার অ্যাপ আপডেটেড আছে');
      }
    } catch (_) {
      if (manual) {
        _showSnack('আপডেট চেক করা যায়নি। ইন্টারনেট দেখে আবার চেষ্টা করুন।');
      }
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  bool _isNewerVersion(String latest, String current) {
    final latestParts =
        latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentParts =
        current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final count = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (int i = 0; i < count; i++) {
      final latestPart = i < latestParts.length ? latestParts[i] : 0;
      final currentPart = i < currentParts.length ? currentParts[i] : 0;
      if (latestPart > currentPart) return true;
      if (latestPart < currentPart) return false;
    }
    return false;
  }

  void _showUpdateDialog({
    required String latestVersion,
    required String apkUrl,
    required String message,
  }) {
    _updateProgress = 0;
    _isDownloadingUpdate = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('নতুন আপডেট আছে!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Version $_currentVersion → $latestVersion'),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center),
              ],
              if (_isDownloadingUpdate) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _updateProgress),
                const SizedBox(height: 8),
                Text(
                  'ডাউনলোড হচ্ছে... ${(_updateProgress * 100).toStringAsFixed(0)}%',
                ),
              ],
            ],
          ),
          actions: [
            if (!_isDownloadingUpdate)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('এখন না'),
              ),
            if (!_isDownloadingUpdate)
              ElevatedButton.icon(
                onPressed: () async {
                  setDialogState(() => _isDownloadingUpdate = true);
                  setState(() => _isDownloadingUpdate = true);
                  await _downloadAndInstallUpdate(
                    apkUrl,
                    onProgress: (progress) {
                      setDialogState(() => _updateProgress = progress);
                      setState(() => _updateProgress = progress);
                    },
                  );
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('আপডেট করুন'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadAndInstallUpdate(
    String apkUrl, {
    required void Function(double) onProgress,
  }) async {
    try {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/shikhito_update.apk';
      final file = File(filePath);

      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await request.send();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = file.openWrite();
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) onProgress(receivedBytes / totalBytes);
      });
      await sink.close();

      await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack('ডাউনলোড ব্যর্থ হয়েছে। পরে চেষ্টা করুন।');
    } finally {
      if (mounted) setState(() => _isDownloadingUpdate = false);
    }
  }

  Future<void> _pasteToTtsField() async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      setState(() => _ttsController.text = data.text!);
      _showSnack('পেস্ট হয়েছে!');
    } else {
      _showSnack('ক্লিপবোর্ডে কিছু নেই');
    }
  }

  void _copySttText() {
    if (_sttController.text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: _sttController.text));
    _showSnack('কপি হয়েছে!');
  }

  void _copyTtsText() {
    if (_ttsController.text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: _ttsController.text));
    _showSnack('কপি হয়েছে!');
  }

  void _clearSttText() {
    _savedText = '';
    _currentText = '';
    _mergedInSession = false;
    setState(() => _sttController.clear());
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    _ttsController.dispose();
    _sttController.dispose();
    _micPulseController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF0F4FF), Color(0xFFE8F5E9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildTtsBox(),
                      const SizedBox(height: 20),
                      _buildSttBox(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x446C63FF),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/shikhito.jpeg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'শিখিতো',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'আপডেট চেক করুন',
            onPressed:
                _isCheckingUpdate ? null : () => _checkForUpdate(manual: true),
            icon: _isCheckingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.system_update_rounded, color: Colors.white),
          ),
          if (_isSpeaking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.volume_up, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'পড়ছে...',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── BOX ১: টেক্সট → TTS ──
  Widget _buildTtsBox() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF9C88FF)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: const Row(
              children: [
                Icon(Icons.text_fields_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text(
                  'লেখা পড়ে শোনাবে',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Voice selector
                Row(
                  children: [
                    const Text(
                      'কণ্ঠ নির্বাচন:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6C63FF),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                setState(
                                    () => _selectedVoice = VoiceGender.male);
                                await _applyVoice(VoiceGender.male);
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _selectedVoice == VoiceGender.male
                                      ? const Color(0xFF6C63FF)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _selectedVoice == VoiceGender.male
                                        ? const Color(0xFF6C63FF)
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '👨 ছেলে',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _selectedVoice == VoiceGender.male
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                setState(
                                    () => _selectedVoice = VoiceGender.female);
                                await _applyVoice(VoiceGender.female);
                              },
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: _selectedVoice == VoiceGender.female
                                      ? const Color(0xFF6C63FF)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _selectedVoice == VoiceGender.female
                                        ? const Color(0xFF6C63FF)
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '👧 মেয়ে',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          _selectedVoice == VoiceGender.female
                                              ? Colors.white
                                              : Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Speed slider
                Column(
                  children: [
                    const Text(
                      'গতি নির্বাচন করুন:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6C63FF),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 10,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 16,
                          elevation: 4.0,
                        ),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 24),
                        activeTrackColor: const Color(0xFF6C63FF),
                        inactiveTrackColor: Colors.grey.shade300,
                        thumbColor: const Color(0xFF6C63FF),
                      ),
                      child: Slider(
                        value: _speechRate,
                        min: 0.25,
                        max: 1.0,
                        divisions: 15,
                        onChanged: (value) async {
                          await _setSpeechRate(value);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ধীর (৩০%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6C63FF)
                                    .withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            '${(_speechRate * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          'দ্রুত (১০০%)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 16),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'টেক্সট',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    GestureDetector(
                      onTap: _pasteToTtsField,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF)
                                  .withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.paste, size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'পেস্ট করুন',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _ttsController,
                  maxLines: 6,
                  minLines: 4,
                  style: const TextStyle(fontSize: 16, height: 1.6),
                  decoration: InputDecoration(
                    hintText: 'এখানে লেখা পেস্ট করুন বা টাইপ করুন...',
                    hintStyle:
                        TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFF6C63FF), width: 2),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8F7FF),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ],
            ),
          ),

          // Currently speaking indicator
          if (_isSpeaking && _currentlySpokenText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'এখন পড়ছে:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6C63FF),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _currentlySpokenText,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _isSpeaking ? _stopSpeaking : _speakTtsText,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isSpeaking
                              ? [
                                  const Color(0xFFFF6584),
                                  const Color(0xFFFF8C42)
                                ]
                              : [
                                  const Color(0xFF6C63FF),
                                  const Color(0xFF3B82F6)
                                ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (_isSpeaking
                                    ? Colors.red
                                    : const Color(0xFF6C63FF))
                                .withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isSpeaking
                                ? Icons.stop_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _ttsLoading
                                ? 'লোড...'
                                : _isSpeaking
                                    ? 'থামাও'
                                    : 'পড়ে শোনাও',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _copyTtsText,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(Icons.copy_rounded,
                        color: Color(0xFF6C63FF), size: 22),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    _ttsController.clear();
                    _stopSpeaking();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEEEE),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Icon(Icons.close_rounded,
                        color: Colors.red.shade400, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── BOX ২: STT ──
  Widget _buildSttBox() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: const Row(
              children: [
                Icon(Icons.mic_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text(
                  'মুখে বলো → লেখা হবে',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Mic button
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _startListening,
                    child: AnimatedBuilder(
                      animation: _micPulseAnim,
                      builder: (_, child) {
                        return Transform.scale(
                          scale: _isListening ? _micPulseAnim.value : 1.0,
                          child: child,
                        );
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_isListening)
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF06B6D4)
                                    .withValues(alpha: 0.15),
                              ),
                            ),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: _isListening
                                    ? [
                                        const Color(0xFFFF6584),
                                        const Color(0xFFFF8C42)
                                      ]
                                    : [
                                        const Color(0xFF06B6D4),
                                        const Color(0xFF0EA5E9)
                                      ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isListening
                                          ? Colors.orange
                                          : const Color(0xFF06B6D4))
                                      .withValues(alpha: 0.4),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isListening
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isListening
                        ? 'শুনছি... (থামতে ট্যাপ করুন)'
                        : 'মাইক ট্যাপ করুন',
                    style: TextStyle(
                      color: _isListening
                          ? const Color(0xFFFF6584)
                          : Colors.grey.shade500,
                      fontSize: 13,
                      fontWeight:
                          _isListening ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (_isListening) ...[
                    const SizedBox(height: 8),
                    _buildSoundWave(),
                  ],
                ],
              ),
            ),
          ),

          // Word count badge
          if (_sttController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_wordCount টি শব্দ',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF06B6D4),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Text field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _sttController,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(fontSize: 16, height: 1.6),
              onChanged: (value) {
                _savedText = value.trim();
                _currentText = '';
              },
              decoration: InputDecoration(
                hintText: 'এখানে আপনার কথা দেখা যাবে...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFF06B6D4), width: 2),
                ),
                filled: true,
                fillColor: const Color(0xFFF0FDFF),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ),

          // Bottom buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _speakSttText,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF06B6D4).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.volume_up_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'শোনাও',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _copySttText,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFFAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF06B6D4).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(Icons.copy_rounded,
                        color: Color(0xFF06B6D4), size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _clearSttText,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEEEE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Icon(Icons.close_rounded,
                        color: Colors.red.shade400, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundWave() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (i) {
        final height = (i % 2 == 0 ? 8.0 : 16.0) +
            (_soundLevel.clamp(0, 10) * (i % 3 == 0 ? 1.5 : 1.0));
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 5,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6584),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
