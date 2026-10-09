# EyePhone 👁️📱 - AI Vision & Navigation Assistant for the Blind

**EyePhone** is an accessibility-first mobile application built with Flutter that transforms a smartphone into visual "eyes" for blind and visually impaired individuals. It couples continuous camera scene comprehension with intelligent voice interaction and spatial headphone audio guidance.

---

## 🌟 Key Highlights

### 1. 🎧 Headphone & Earbud First Architecture
- **Bluetooth & Wired Detection**: Automatically detects when wired headphones (3.5mm / USB-C) or Bluetooth headsets (AirPods, Galaxy Buds, Pixel Buds) are connected.
- **Hands-Free Earbud Button Hook**: Intercepts the physical media/action button on your wired headset or Bluetooth earbuds (`KEYCODE_HEADSETHOOK`, `KEYCODE_MEDIA_PLAY_PAUSE`). Simply click your earbud button while walking to immediately ask questions or trigger a scene scan without having to locate or touch the phone screen.
- **3D Spatial Audio Cues**: Panning obstacle warning beeps directly into your left or right headphone ear based on clock position:
  - Obstacle at **9 to 11 o'clock** ➡️ Warning chime panned to **Left Ear**.
  - Obstacle at **1 to 3 o'clock** ➡️ Warning chime panned to **Right Ear**.
  - Obstacle at **12 o'clock** ➡️ Centered in both ears.

### 2. 🧠 Dual-Engine AI: Internal Gemini Nano + Cloud Gemini Flash
- **Internal Gemini (On-Device Gemini Nano / AICore)**:
  - Integrates with Android's native `com.google.android.aicore` system service.
  - On supported devices (such as Google Pixel 8/9 series and Samsung Galaxy S24/S25 series), on-device Gemini Nano processes speech intents and commands offline with zero latency and complete privacy.
- **Gemini Multimodal Flash Vision**:
  - Leverages Google's high-speed multimodal vision models (`gemini-1.5-flash`) for spatial reasoning, hazard identification, and text reading.
  - Tailored blindness prompts enforce clock coordinates ("Door at 2 o'clock, 3 meters away"), clear path status, and concise spoken answers (under 25 words).

### 3. 🚶 Continuous "Smart Eyes" Walking Mode
- In Continuous Mode, EyePhone captures camera frames periodically (every 3 to 7 seconds).
- It announces actionable directions:
  - *"Path is clear for 4 meters ahead."*
  - *"Caution: Low step down in 2 meters directly ahead."*
  - *"Pedestrian crosswalk detected. Walk straight."*

### 4. 🗣️ Full Voice Interaction System
Speak naturally to EyePhone anytime:
- **"Is the path clear?"** / **"Guide me"** ➔ Activates walking path & obstacle scan.
- **"Read this label"** / **"What does this sign say?"** ➔ Transcribes packaging, signs, and door numbers.
- **"Where is my cup?"** / **"Find the door"** ➔ Pinpoints target items with clock direction and reach advice.
- **"Describe surroundings"** ➔ Summarizes the room layout, indoor/outdoor context, and lighting.
- **"Turn on light"** / **"Flashlight"** ➔ Toggles torch for dark corridors or night walks.
- **"Headphone status"** ➔ Reports connected headset name and status.
- **"Stop"** / **"Quiet"** ➔ Silences speech immediately.

### 5. ♿ Accessibility-First Touch Gestures & High-Contrast UI
- **Single Tap Anywhere**: Spoken status check (mode, headphone connectivity, battery, continuous guide state).
- **Double Tap Anywhere**: Activates voice listening / push-to-talk.
- **Swipe Left / Right**: Cycles between Vision Modes (Navigation, Read Text, Describe Scene, Find Object).
- **Long Press**: Emergency 360-degree scene scan.
- **Visual Design**: High-contrast OLED pure black (`#000000`), High-visibility Amber (`#FFD600`), and Electric Cyan (`#00E5FF`) with massive touch targets and full TalkBack / VoiceOver `Semantics`.

---

## 📁 Project Architecture

```
lib/
├── main.dart                          # App entry point, orientation lock, system theme
├── models/
│   ├── app_settings.dart              # User preferences & API key storage
│   ├── guidance_result.dart           # Structured AI navigation & hazard output
│   ├── headphone_status.dart          # Headphone connection model
│   └── vision_mode.dart               # Vision modes (Navigation, ReadText, Scene, Find)
├── services/
│   ├── audio_feedback_service.dart    # Directional spatial beeps & chimes
│   ├── audio_headphone_service.dart   # Headphone detection & media button listener
│   ├── camera_service.dart            # Camera frame snapshot & torch control
│   ├── gemini_nano_service.dart       # Android AICore / on-device Gemini Nano bridge
│   ├── gemini_vision_service.dart     # Multimodal Gemini vision reasoning
│   ├── guidance_controller.dart       # Master coordinator connecting all services
│   ├── haptic_service.dart            # Tactile vibration navigation patterns
│   ├── stt_service.dart               # Hands-free speech recognition
│   └── tts_service.dart               # Screen-reader style text-to-speech
├── ui/
│   ├── camera_viewfinder.dart         # Live camera feed + clock direction HUD
│   ├── gesture_overlay.dart           # Full-screen multi-touch gesture responder
│   ├── home_screen.dart               # Main accessible screen
│   ├── settings_sheet.dart            # Key configuration & spatial audio test
│   ├── status_announcement_bar.dart   # Top bar with headphone & AI status
│   └── widgets/
│       ├── accessible_button.dart     # Accessible high-contrast large buttons
│       ├── hazard_badge.dart          # Path safety & clock hazard badge
│       └── mode_selector.dart         # Mode navigation banner
└── utils/
    ├── app_theme.dart                 # High-contrast accessibility theme
    └── sound_generator.dart           # In-memory stereo PCM WAV spatial tone synthesizer
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev) (v3.24+ / 3.47+)
- Android SDK 34+ (compileSdk 37)

### Run & Build

1. Clone or open the repository:
   ```bash
   cd C:\Projects\EyePhone
   ```

2. Fetch dependencies:
   ```bash
   flutter pub get
   ```

3. Run automated tests:
   ```bash
   flutter test
   ```

4. Run the app on a connected Android device:
   ```bash
   flutter run
   ```

5. Or install the pre-built debug APK directly:
   ```bash
   flutter build apk --debug
   adb install build/app/outputs/flutter-apk/app-debug.apk
   ```

---

## ⚙️ Configuration
Open the **Settings** menu (or speak into the app) to:
1. **Enter Gemini API Key**: Obtain a key from [Google AI Studio](https://aistudio.google.com/) to enable cloud multimodal vision.
2. **AI Engine Mode**: Select **Auto Hybrid** to automatically use internal Gemini Nano for offline intent parsing and Gemini Flash for visual guidance.
3. **Test Headphone Spatial Audio**: Plays an audio sequence (Left Ear ➔ Right Ear ➔ Center) to verify that your earbuds correctly deliver directional navigation cues.
