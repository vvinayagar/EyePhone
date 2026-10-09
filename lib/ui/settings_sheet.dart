import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/guidance_controller.dart';
import '../services/frame_source.dart';
import '../services/local_llm_service.dart';
import '../services/wake_word_matcher.dart';
import '../utils/app_theme.dart';

class SettingsSheet extends StatefulWidget {
  final GuidanceController controller;

  const SettingsSheet({super.key, required this.controller});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late TextEditingController _apiKeyController;
  late double _speechRate;
  late int _scanInterval;
  late bool _haptics;
  late bool _soundCues;
  late AiEnginePreference _enginePreference;
  late bool _wakeWordEnabled;
  late String _wakeWordText;
  late TextEditingController _wakeWordController;

  late CameraSourceKind _cameraSource;
  late TextEditingController _networkUrlController;
  late TextEditingController _networkUserController;
  late TextEditingController _networkPassController;
  late bool _fisheyeEnabled;
  late double _fisheyeStrength;
  bool _isTestingCamera = false;
  String? _cameraTestResult;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings;
    _apiKeyController = TextEditingController(text: s.apiKey);
    _speechRate = s.speechRate;
    _scanInterval = s.continuousScanIntervalSeconds;
    _haptics = s.hapticsEnabled;
    _soundCues = s.soundCuesEnabled;
    _enginePreference = s.aiEngine;
    _wakeWordEnabled = s.wakeWordEnabled;
    _wakeWordText = s.wakeWord;
    _wakeWordController = TextEditingController(text: s.wakeWord);
    _cameraSource = s.cameraSource;
    _networkUrlController = TextEditingController(text: s.networkCameraUrl);
    _networkUserController = TextEditingController(text: s.networkCameraUsername);
    _networkPassController = TextEditingController(text: s.networkCameraPassword);
    _fisheyeEnabled = s.fisheyeCorrectionEnabled;
    _fisheyeStrength = s.fisheyeStrength;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _wakeWordController.dispose();
    _networkUrlController.dispose();
    _networkUserController.dispose();
    _networkPassController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    final s = widget.controller.settings;
    s.apiKey = _apiKeyController.text.trim();
    s.speechRate = _speechRate;
    s.continuousScanIntervalSeconds = _scanInterval;
    s.hapticsEnabled = _haptics;
    s.soundCuesEnabled = _soundCues;
    s.aiEngine = _enginePreference;
    s.wakeWordEnabled = _wakeWordEnabled;
    s.wakeWord = _wakeWordController.text.trim().isEmpty
        ? WakeWordMatcher.defaultPhrase
        : _wakeWordController.text.trim();
    s.save();

    // Apply immediately so the listener reflects the saved phrase without a restart.
    widget.controller.updateWakeWord(
      phrase: s.wakeWord,
      enabled: s.wakeWordEnabled,
    );
    widget.controller.updateCameraSource(
      kind: _cameraSource,
      networkUrl: _networkUrlController.text,
      username: _networkUserController.text,
      password: _networkPassController.text,
      fisheyeEnabled: _fisheyeEnabled,
      fisheyeStrength: _fisheyeStrength,
    );

    widget.controller.updateApiKey(s.apiKey);
    widget.controller.updateSpeechRate(_speechRate);
    widget.controller.hapticService.enabled = _haptics;
    widget.controller.audioFeedbackService.enabled = _soundCues;

    widget.controller.ttsService.speak('Settings saved.', interrupt: true);
    Navigator.of(context).pop();
  }

  bool _isTestingModel = false;
  String? _modelTestResult;

  /// Camera source: phone, wireless/IP, or USB — plus fisheye correction.
  Widget _buildCameraSourceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('CAMERA SOURCE'),
        const SizedBox(height: 8),
        DropdownButtonFormField<CameraSourceKind>(
          initialValue: _cameraSource,
          dropdownColor: AppTheme.surfaceLight,
          decoration: InputDecoration(
            labelText: 'Which camera are the eyes?',
            labelStyle: const TextStyle(color: AppTheme.highVisYellow),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: CameraSourceKind.values
              .map((k) => DropdownMenuItem(
                    value: k,
                    child: Text(k.label,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _cameraSource = v);
            widget.controller.updateCameraSource(kind: v);
          },
        ),
        if (_cameraSource == CameraSourceKind.network) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _networkUrlController,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Camera address',
              labelStyle: const TextStyle(color: AppTheme.highVisYellow),
              hintText: '192.168.1.50:8080',
              hintStyle: const TextStyle(color: AppTheme.textDim),
              helperText: 'Snapshot or MJPEG URL. A plain IP assumes /shot.jpg.',
              helperStyle: const TextStyle(color: AppTheme.textDim, fontSize: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _networkUserController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Username (optional)',
                    labelStyle: const TextStyle(color: AppTheme.textDim, fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _networkPassController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: AppTheme.textDim, fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'RTSP is not supported. Use the camera\'s HTTP snapshot or MJPEG address.',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
        ],
        if (_cameraSource == CameraSourceKind.usb) ...[
          const SizedBox(height: 10),
          const Text(
            'Connect a UVC camera by OTG cable. Android exposes USB cameras to apps only '
            'on some phones — if the test finds nothing with a camera plugged in, this '
            'phone does not support it.',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
        ],
        if (_cameraSource != CameraSourceKind.device) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: _isTestingCamera ? null : _runCameraTest,
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: Text(_isTestingCamera ? 'Testing...' : 'Test camera'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.cyanAccent),
              ),
            ],
          ),
          if (_cameraTestResult != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _cameraTestResult!,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
        ],
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _fisheyeEnabled,
          activeThumbColor: AppTheme.highVisYellow,
          title: const Text(
            'Fisheye correction',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            'Straightens wide-angle distortion so clock directions and distances stay '
            'accurate. Turn on only for fisheye or very wide lenses.',
            style: TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
          onChanged: (v) {
            setState(() => _fisheyeEnabled = v);
            widget.controller.updateCameraSource(fisheyeEnabled: v);
          },
        ),
        if (_fisheyeEnabled) ...[
          Text(
            'Correction strength: ${_fisheyeStrength.toStringAsFixed(1)}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Slider(
            value: _fisheyeStrength,
            min: 0.1,
            max: 1.5,
            divisions: 14,
            activeColor: AppTheme.highVisYellow,
            label: _fisheyeStrength.toStringAsFixed(1),
            onChanged: (v) => setState(() => _fisheyeStrength = v),
            onChangeEnd: (v) =>
                widget.controller.updateCameraSource(fisheyeStrength: v),
          ),
          const Text(
            '0.6 suits a mild wide-angle lens; 1.0 and above suits a true 180-degree fisheye.',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Future<void> _runCameraTest() async {
    setState(() {
      _isTestingCamera = true;
      _cameraTestResult = null;
    });

    // Persist what was typed before probing, so the test uses the current address.
    await widget.controller.updateCameraSource(
      kind: _cameraSource,
      networkUrl: _networkUrlController.text,
      username: _networkUserController.text,
      password: _networkPassController.text,
    );

    final result = await widget.controller.cameraSources.testSource(_cameraSource);
    if (!mounted) return;

    setState(() {
      _isTestingCamera = false;
      _cameraTestResult = result.success
          ? 'Connected. ${result.millis != null ? "${result.millis} ms, " : ""}'
              '${result.frameBytes != null ? "${(result.frameBytes! / 1024).round()} KB frame" : ""}'
          : result.message;
    });
    widget.controller.ttsService.speak(
      result.success ? 'Camera connected.' : result.message,
      interrupt: true,
    );
  }

  /// Wake word controls. Changing the phrase restarts the listener immediately so the
  /// user can test it without leaving the screen.
  Widget _buildWakeWordSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('HANDS-FREE WAKE WORD'),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _wakeWordEnabled,
          activeThumbColor: AppTheme.highVisYellow,
          title: const Text(
            'Listen for wake word',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            _wakeWordEnabled
                ? 'Say "$_wakeWordText" any time to start talking, without touching the phone.'
                : 'Off. Double tap the screen or press your headset button to talk.',
            style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
          onChanged: (v) {
            setState(() => _wakeWordEnabled = v);
            widget.controller.updateWakeWord(enabled: v);
            widget.controller.ttsService.speak(
              v ? 'Wake word on. Say $_wakeWordText to talk.' : 'Wake word off.',
              interrupt: true,
            );
          },
        ),
        if (_wakeWordEnabled) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _wakeWordController,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Wake phrase',
              labelStyle: const TextStyle(color: AppTheme.highVisYellow),
              helperText: 'Two or three easy words work best. Single words misfire.',
              helperStyle: const TextStyle(color: AppTheme.textDim, fontSize: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh, color: AppTheme.textDim),
                tooltip: 'Reset to default',
                onPressed: () {
                  setState(() {
                    _wakeWordController.text = WakeWordMatcher.defaultPhrase;
                    _wakeWordText = WakeWordMatcher.defaultPhrase;
                  });
                  widget.controller.updateWakeWord(
                    phrase: WakeWordMatcher.defaultPhrase,
                  );
                },
              ),
            ),
            onSubmitted: (value) {
              final phrase =
                  value.trim().isEmpty ? WakeWordMatcher.defaultPhrase : value.trim();
              setState(() => _wakeWordText = phrase);
              widget.controller.updateWakeWord(phrase: phrase);
              widget.controller.ttsService.speak(
                'Wake phrase set to $phrase.',
                interrupt: true,
              );
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'Listening continuously uses the microphone and extra battery. '
            'It pauses automatically while EyePhone is speaking.',
            style: TextStyle(color: AppTheme.textDim, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Future<void> _runModelSelfTest() async {
    setState(() {
      _isTestingModel = true;
      _modelTestResult = null;
    });
    final result = await widget.controller.localLlm.selfTest();
    if (!mounted) return;
    setState(() {
      _isTestingModel = false;
      _modelTestResult = result == null
          ? 'Model did not return a response.'
          : '${(result.millis / 1000).toStringAsFixed(1)}s — ${result.text}';
    });
  }

  /// Shows whether the offline model bundle is installed and loaded, and where to
  /// put it if not. Without this the on-device mode fails silently from the user's side.
  Widget _buildLocalModelPanel() {
    final service = widget.controller.localLlm;

    return ValueListenableBuilder<LocalLlmStatus>(
      valueListenable: service.statusNotifier,
      builder: (context, status, _) {
        final Color color;
        final IconData icon;
        switch (status.state) {
          case LocalLlmState.ready:
            color = AppTheme.safeGreen;
            icon = Icons.offline_bolt_rounded;
          case LocalLlmState.loading:
            color = AppTheme.cyanAccent;
            icon = Icons.hourglass_top_rounded;
          case LocalLlmState.error:
            color = AppTheme.dangerRed;
            icon = Icons.error_outline_rounded;
          default:
            color = AppTheme.textDim;
            icon = Icons.download_for_offline_outlined;
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline Model: ${status.shortLabel}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                status.state == LocalLlmState.ready
                    ? status.supportsVision
                        ? 'Vision runs fully on this phone. No network, no API cost, '
                            'camera frames never leave the device.'
                        : 'Text-only model: answers questions offline, but cannot analyse '
                            'camera frames. Scene scans still use cloud vision. '
                            'Install a Gemma 3n bundle for offline vision.'
                    : status.state == LocalLlmState.modelMissing
                        ? 'Copy a .task bundle into:\n${status.modelsDir}\n'
                            'Gemma 3n E2B/E4B for offline vision; DeepSeek R1 distill for '
                            'offline text only.'
                        : status.error.isNotEmpty
                            ? status.error
                            : status.spokenDescription,
                style: const TextStyle(color: AppTheme.textDim, fontSize: 13),
              ),
              if (status.modelSizeBytes > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${status.modelName} — ${status.modelSizeGb.toStringAsFixed(2)} GB',
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => service.refreshStatus(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Re-check'),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.highVisYellow),
                  ),
                  const SizedBox(width: 8),
                  if (status.hasModelFile && status.state != LocalLlmState.ready)
                    TextButton.icon(
                      onPressed: status.state == LocalLlmState.loading
                          ? null
                          : () => service.initialize(),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Load model'),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.cyanAccent),
                    ),
                  if (status.state == LocalLlmState.ready)
                    TextButton.icon(
                      onPressed: _isTestingModel ? null : _runModelSelfTest,
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: Text(_isTestingModel ? 'Testing...' : 'Test model'),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.safeGreen),
                    ),
                ],
              ),
              if (_modelTestResult != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _modelTestResult!,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _testSpatialAudio() async {
    widget.controller.ttsService.speak('Testing left ear', interrupt: true);
    await Future.delayed(const Duration(milliseconds: 1400));
    await widget.controller.audioFeedbackService.playObstacleAlert(clockDirection: 9); // Left ear
    await Future.delayed(const Duration(milliseconds: 1000));

    widget.controller.ttsService.speak('Testing right ear', interrupt: true);
    await Future.delayed(const Duration(milliseconds: 1400));
    await widget.controller.audioFeedbackService.playObstacleAlert(clockDirection: 3); // Right ear
    await Future.delayed(const Duration(milliseconds: 1000));

    widget.controller.ttsService.speak('Testing center straight ahead', interrupt: true);
    await Future.delayed(const Duration(milliseconds: 1400));
    await widget.controller.audioFeedbackService.playObstacleAlert(clockDirection: 12); // Center
  }

  @override
  Widget build(BuildContext context) {
    final nanoStatus = widget.controller.nanoService.status;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'EyePhone Settings',
          style: TextStyle(color: AppTheme.highVisYellow, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text(
              'SAVE',
              style: TextStyle(color: AppTheme.highVisYellow, fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Gemini API Key Section
          _buildSectionHeader('GEMINI VISION AI KEY'),
          const SizedBox(height: 8),
          const Text(
            'Google Gemini Flash powers real-time multimodal spatial vision, reading text, and hazard navigation.',
            style: TextStyle(color: AppTheme.textDim, fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.surfaceLight,
              labelText: 'Gemini API Key',
              labelStyle: const TextStyle(color: AppTheme.highVisYellow),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: Colors.white60),
                onPressed: () => _apiKeyController.clear(),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Internal Gemini / On-Device AICore Section
          _buildSectionHeader('INTERNAL GEMINI (ON-DEVICE)'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: nanoStatus.isAvailable ? Colors.purpleAccent : Colors.white12,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      nanoStatus.isAvailable ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: nanoStatus.isAvailable ? Colors.purpleAccent : AppTheme.highVisYellow,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        nanoStatus.isAvailable
                            ? 'Gemini Nano (AICore) Detected'
                            : 'Standard Device AI Mode',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  nanoStatus.details,
                  style: const TextStyle(color: AppTheme.textDim, fontSize: 14),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AiEnginePreference>(
                  initialValue: _enginePreference,
                  dropdownColor: AppTheme.surfaceLight,
                  decoration: InputDecoration(
                    labelText: 'AI Engine Mode',
                    labelStyle: const TextStyle(color: AppTheme.highVisYellow),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: AiEnginePreference.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(
                        mode.shortLabel,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _enginePreference = val);
                  },
                ),
                const SizedBox(height: 16),
                _buildLocalModelPanel(),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildCameraSourceSection(),
          const SizedBox(height: 24),

          _buildWakeWordSection(),
          const SizedBox(height: 24),

          // Headphone & Spatial Audio Section
          _buildSectionHeader('HEADPHONE & SPATIAL AUDIO'),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.spatial_audio_rounded, color: AppTheme.cyanAccent),
            title: const Text('Directional Spatial Beeps', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Pans obstacle alert tones to left/right ear corresponding to clock direction',
              style: TextStyle(color: AppTheme.textDim, fontSize: 13),
            ),
            trailing: Switch(
              value: _soundCues,
              activeThumbColor: AppTheme.cyanAccent,
              onChanged: (val) => setState(() => _soundCues = val),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surfaceLight,
              foregroundColor: AppTheme.cyanAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.headphones_rounded),
            label: const Text('TEST HEADPHONE SPATIAL AUDIO', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _testSpatialAudio,
          ),
          const SizedBox(height: 24),

          // Speech & Haptics Section
          _buildSectionHeader('SPEECH RATE & HAPTICS'),
          const SizedBox(height: 8),
          Text(
            'Speech Rate: ${(_speechRate * 2).toStringAsFixed(1)}x',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          Slider(
            value: _speechRate,
            min: 0.3,
            max: 0.8,
            divisions: 10,
            activeColor: AppTheme.highVisYellow,
            inactiveColor: Colors.white24,
            onChanged: (val) {
              setState(() => _speechRate = val);
              widget.controller.ttsService.setSpeechRate(val);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.vibration_rounded, color: AppTheme.highVisYellow),
            title: const Text('Directional Haptic Pulses', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Vibrates phone when hazards or steps are detected', style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
            trailing: Switch(
              value: _haptics,
              activeThumbColor: AppTheme.highVisYellow,
              onChanged: (val) => setState(() => _haptics = val),
            ),
          ),
          const SizedBox(height: 24),

          // Continuous Guidance Frequency
          _buildSectionHeader('CONTINUOUS EYES SCAN INTERVAL'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 3, label: Text('3s (Active)')),
              ButtonSegment(value: 4, label: Text('4s (Normal)')),
              ButtonSegment(value: 7, label: Text('7s (Battery)')),
            ],
            selected: {_scanInterval},
            onSelectionChanged: (set) => setState(() => _scanInterval = set.first),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return AppTheme.highVisYellow;
                return AppTheme.surfaceLight;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.black;
                return Colors.white;
              }),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppTheme.highVisYellow,
        fontSize: 14,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
      ),
    );
  }
}
