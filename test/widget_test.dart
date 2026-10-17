import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:eyephone/services/network_camera_source.dart';
import 'package:eyephone/utils/fisheye_corrector.dart';

import 'package:eyephone/models/app_settings.dart';
import 'package:eyephone/models/guidance_result.dart';
import 'package:eyephone/models/vision_mode.dart';
import 'package:eyephone/services/local_llm_service.dart';
import 'package:eyephone/services/wake_word_matcher.dart';
import 'package:eyephone/ui/widgets/hazard_badge.dart';
import 'package:eyephone/utils/sound_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GuidanceResult parses clock directions and hazards correctly', () {
    const aiText = 'Warning: chair obstacle at 2 o\'clock, 1.5 meters away. Step slightly left.';
    final result = GuidanceResult.fromAiResponse(aiText);

    expect(result.isPathClear, false);
    expect(result.clockDirection, 2);
    expect(result.hazards.isNotEmpty, true);
  });

  test('GuidanceResult parses clear path correctly', () {
    const aiText = 'Path is clear for 5 meters. Continue walking straight ahead.';
    final result = GuidanceResult.fromAiResponse(aiText);

    expect(result.isPathClear, true);
  });

  test('SoundGenerator creates valid stereo PCM WAV audio bytes', () {
    final wavBytes = SoundGenerator.createToneWav(
      frequency: 440.0,
      durationSeconds: 0.1,
      volume: 0.5,
      pan: -0.75, // panned left for spatial audio
    );

    expect(wavBytes.isNotEmpty, true);
    // WAV header checks
    expect(wavBytes[0], 0x52); // 'R'
    expect(wavBytes[1], 0x49); // 'I'
    expect(wavBytes[2], 0x46); // 'F'
    expect(wavBytes[3], 0x46); // 'F'
  });

  test('VisionMode extension provides correct announcements and titles', () {
    expect(VisionMode.navigation.title, 'Path Navigation');
    expect(VisionMode.readText.title, 'Read Text & Signs');
    expect(VisionMode.sceneDescriber.title, 'Describe Scene');
    expect(VisionMode.findObject.title, 'Find Object');
  });

  test('AppSettings initializes with sensible defaults for blind navigation', () {
    final settings = AppSettings();
    expect(settings.hapticsEnabled, true);
    expect(settings.soundCuesEnabled, true);
    expect(settings.continuousScanIntervalSeconds, 4);
    expect(settings.aiEngine, AiEnginePreference.autoHybrid);
  });

  test('Detects people ahead without firing on explicit denials', () {
    final person = GuidanceResult.fromAiResponse(
      'Person at 2 o\'clock, 3 meters, walking toward you. Step left.',
    );
    expect(person.personAhead, true);

    final crowd = GuidanceResult.fromAiResponse('Queue of people blocking the way ahead.');
    expect(crowd.personAhead, true);

    // "no one ahead" contains no person word, but these phrasings are the trap.
    for (final denial in [
      'No one ahead. Path clear for 4 meters.',
      'Nobody in the way, path clear.',
      'No people ahead, clear path.',
    ]) {
      expect(
        GuidanceResult.fromAiResponse(denial).personAhead,
        false,
        reason: 'should not report a person for: $denial',
      );
    }
  });

  test('Classifies door state and flags when the user must open it', () {
    expect(
      GuidanceResult.fromAiResponse(
        'Closed door at 12 o\'clock, 2 meters, handle on the right.',
      ).doorState,
      DoorState.closed,
    );
    expect(
      GuidanceResult.fromAiResponse('Open doorway at 11 o\'clock, walk through.').doorState,
      DoorState.open,
    );
    expect(
      GuidanceResult.fromAiResponse('Door is ajar at 1 o\'clock.').doorState,
      DoorState.partlyOpen,
    );
    expect(
      GuidanceResult.fromAiResponse('Path clear for 3 meters.').doorState,
      DoorState.none,
    );

    // Only a closed door demands action from the user.
    expect(
      GuidanceResult.fromAiResponse('Door is closed, you must open it.').doorNeedsOpening,
      true,
    );
    expect(
      GuidanceResult.fromAiResponse('Open door at 12 o\'clock.').doorNeedsOpening,
      false,
    );

    // Unstated state must fail safe to "closed" — assuming open walks someone into it.
    expect(
      GuidanceResult.fromAiResponse('Door at 12 o\'clock, 2 meters.').doorState,
      DoorState.closed,
    );
  });

  test('Wake word matches real recognizer mis-transcriptions', () {
    final m = WakeWordMatcher();

    // Android rarely returns "EyePhone" verbatim; these are what it actually produces.
    for (final heard in [
      'Hey EyePhone',
      'hey eyephone',
      'hey iPhone',
      'hey i phone',
      'hey eye phone',
      'Hi iPhone',
      'ok eyephone',
      'hey eyephone is the path clear',
      'so I said hey iPhone and it worked',
    ]) {
      expect(m.matches(heard), true, reason: 'should wake on: "$heard"');
    }
  });

  test('Wake word does not fire on unrelated speech', () {
    final m = WakeWordMatcher();

    for (final heard in [
      '',
      'the path is clear ahead',
      'what time is it',
      'can you pass me the phone',
      'I need a new telephone',
      'hey there how are you',
    ]) {
      expect(m.matches(heard), false, reason: 'should NOT wake on: "$heard"');
    }
  });

  test('Wake word supports a custom phrase', () {
    final m = WakeWordMatcher(phrase: 'Hello Vision');
    expect(m.matches('hello vision'), true);
    expect(m.matches('Hello Vision, describe the room'), true);
    expect(m.matches('hey eyephone'), false, reason: 'default aliases must not leak');

    // Empty or blank custom phrases fall back to the default rather than matching
    // everything, which would make the app wake constantly.
    expect(WakeWordMatcher(phrase: '   ').phrase, WakeWordMatcher.defaultPhrase);
  });

  test('Wake word extracts a command spoken in the same breath', () {
    final m = WakeWordMatcher();
    expect(m.commandAfterWake('hey eyephone is the path clear'), 'is the path clear');
    expect(m.commandAfterWake('hey iphone read this label'), 'read this label');
    // Phrase alone means "just start listening", not "run an empty command".
    expect(m.commandAfterWake('hey eyephone'), null);
  });

  test('Network camera URL normalization handles what people actually type', () {
    // A bare host means the "IP Webcam" app in practice; assume its snapshot path.
    expect(
      NetworkCameraSource.normalizeUrl('192.168.1.50:8080'),
      'http://192.168.1.50:8080/shot.jpg',
    );
    expect(
      NetworkCameraSource.normalizeUrl('192.168.1.50'),
      'http://192.168.1.50/shot.jpg',
    );
    // An explicit path is respected, not overwritten.
    expect(
      NetworkCameraSource.normalizeUrl('http://192.168.1.50/capture'),
      'http://192.168.1.50/capture',
    );
    expect(
      NetworkCameraSource.normalizeUrl('https://cam.local/snapshot.jpg'),
      'https://cam.local/snapshot.jpg',
    );
    expect(NetworkCameraSource.normalizeUrl('  '), '');
  });

  test('Fisheye correction preserves image size and leaves centre pixels put', () {
    // A 64x64 test image; the centre of a radial remap must not move.
    final src = img.Image(width: 64, height: 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        src.setPixelRgba(x, y, x * 4, y * 4, 128, 255);
      }
    }

    final out = FisheyeCorrector.remap(src, 0.6);
    expect(out.width, 64);
    expect(out.height, 64);

    // Centre pixel is the fixed point of the transform.
    final centreIn = src.getPixel(32, 32);
    final centreOut = out.getPixel(32, 32);
    expect((centreOut.r - centreIn.r).abs() < 6, true);
    expect((centreOut.g - centreIn.g).abs() < 6, true);
  });

  test('Fisheye correction is a no-op when disabled', () {
    final bytes = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
    // strength 0 must return the exact same bytes, not a re-encode.
    expect(identical(FisheyeCorrector.correct(bytes, strength: 0), bytes), true);
  });

  test('AI engine preference routes to the correct backends', () {
    // Auto hybrid is the only mode that may use both.
    expect(AiEnginePreference.autoHybrid.usesLocal, true);
    expect(AiEnginePreference.autoHybrid.usesCloud, true);

    // On-device only must never reach the network — this is the privacy guarantee.
    expect(AiEnginePreference.onDeviceOnly.usesLocal, true);
    expect(AiEnginePreference.onDeviceOnly.usesCloud, false);

    // Cloud only must not wait on the local model.
    expect(AiEnginePreference.cloudFlashOnly.usesLocal, false);
    expect(AiEnginePreference.cloudFlashOnly.usesCloud, true);
  });

  test('Local model status reports readiness and never promises cloud fallback', () {
    const missing = LocalLlmStatus(state: LocalLlmState.modelMissing);
    expect(missing.isReady, false);
    expect(missing.hasModelFile, false);
    // Engine-preference-dependent claims must not leak into the spoken text.
    expect(missing.spokenDescription.toLowerCase().contains('cloud'), false);

    const ready = LocalLlmStatus(
      state: LocalLlmState.ready,
      modelName: 'gemma-3n-E2B-it-int4.task',
      modelSizeBytes: 3221225472,
    );
    expect(ready.isReady, true);
    expect(ready.hasModelFile, true);
    expect(ready.modelSizeGb, closeTo(3.0, 0.01));
    expect(ready.shortLabel, contains('gemma-3n-E2B'));
  });

  testWidgets('Failed scans show a neutral error badge, never an obstacle', (tester) async {
    final cameraError = GuidanceResult.failed(
      failure: ScanFailure.camera,
      spokenText: 'Camera image could not be captured.',
      engineUsed: 'Camera Error',
    );
    expect(cameraError.isError, true);
    // Nothing was seen, so nothing may be claimed clear either.
    expect(cameraError.isPathClear, false);
    expect(GuidanceResult.empty().isError, false);
    expect(GuidanceResult.fromAiResponse('Path is clear ahead.').isError, false);

    await tester.pumpWidget(MaterialApp(home: HazardBadge(result: cameraError)));
    expect(find.text('CAMERA UNAVAILABLE'), findsOneWidget);
    expect(find.text('OBSTACLE DETECTED'), findsNothing);

    final engineError = GuidanceResult.failed(
      failure: ScanFailure.engine,
      spokenText: 'Network error.',
      engineUsed: 'Error',
    );
    await tester.pumpWidget(MaterialApp(home: HazardBadge(result: engineError)));
    expect(find.text('NO SCAN'), findsOneWidget);
    expect(find.text('OBSTACLE DETECTED'), findsNothing);

    // A real obstacle still shows as one.
    final obstacle = GuidanceResult.fromAiResponse('Warning: chair obstacle at 2 o\'clock.');
    await tester.pumpWidget(MaterialApp(home: HazardBadge(result: obstacle)));
    expect(find.text('OBSTACLE DETECTED'), findsOneWidget);
  });
}
