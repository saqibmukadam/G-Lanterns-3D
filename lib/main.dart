import 'package:flutter/material.dart';
import 'dart:async';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:permission_handler/permission_handler.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter/webview_flutter.dart' show WebViewController;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Lock the application strictly to Portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  final prefs = await SharedPreferences.getInstance();
  final bool hasSeenIntro = prefs.getBool('hasSeenIntro') ?? false;

  runApp(LanternApp(hasSeenIntro: hasSeenIntro));
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String _channelId = 'power_ring_alerts_v1';
const String _channelName = 'Power Ring Alerts';

const NotificationDetails _notificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: 'Tracks the dynamic battery drain',
    importance: Importance.max,
    priority: Priority.high,
  ),
);

const NotificationDetails _depletionNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'ring_depletion_channel_v1',
    'Ring Depletion Alerts',
    channelDescription: 'Plays the warning sound at 20, 15, and 10 percent',
    importance: Importance.max,
    priority: Priority.high,
    sound: RawResourceAndroidNotificationSound('ring_depletion'),
  ),
);

const NotificationDetails _rejectNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    'ring_rejection_channel_v1',
    'Ring Rejection',
    channelDescription: 'Shown when you decline the ring in the intro',
    importance: Importance.max,
    priority: Priority.high,
  ),
);

// ==========================================
// IOS-STYLE HARDWARE LRA HAPTICS ENGINE
// ==========================================
class _LanternHaptics {
  static const MethodChannel _channel = MethodChannel('lantern.audio/mute');
  static DateTime _lastSpinTick = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _lastVoicePulse = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> _send(String type, {int amp = 130}) async {
    try {
      await _channel.invokeMethod('haptic', {'type': type, 'amp': amp});
    } catch (_) {
      // Fallback if MainActivity.kt hasn't been rebuilt yet
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
    }
  }

  // Crisp micro-tick (karaoke words, subtle UI taps)
  static void tap() {
    unawaited(_send('tick', amp: 120));
  }

  // Soft detent click (switches, duration pills, menu items)
  static void toggle() {
    unawaited(_send('click', amp: 160));
  }

  // Medium confirmation thud (lantern selection, page actions)
  static void medium() {
    unawaited(_send('click', amp: 200));
  }

  // Deep heavy thud (warnings, rejection, major actions)
  static void heavy() {
    unawaited(_send('heavy', amp: 255));
  }

  // iOS Digital Crown / Scroll-Wheel detent feel when spinning the 3D lantern
  static void spinDetent({double velocity = 1.0}) {
    final now = DateTime.now();
    // Cap tick rate to ~45 Hz so fast spins feel like a smooth mechanical wheel
    if (now.difference(_lastSpinTick).inMilliseconds < 22) return;
    _lastSpinTick = now;
    final int dynamicAmp = (75 + (velocity * 25).clamp(0.0, 110.0)).toInt();
    unawaited(_send('lowTick', amp: dynamicAmp));
  }

  // Real-time voice-reactive vibration while reciting the oath
  static void voiceResonance(double soundLevel) {
    final now = DateTime.now();
    if (now.difference(_lastVoicePulse).inMilliseconds < 95) return;
    _lastVoicePulse = now;
    final double norm = ((soundLevel - 1.5) / 12.0).clamp(0.0, 1.0);
    if (norm <= 0.05) return;
    final int amp = (55 + (norm * 165)).toInt();
    unawaited(_send('pulse', amp: amp));
  }

  // Two-stage magnetic lock-on when holding the screen
  static Future<void> holdLockOn() async {
    await _send('click', amp: 170);
    await Future.delayed(const Duration(milliseconds: 55));
    await _send('heavy', amp: 230);
  }

  // Smooth decelerating ratchet when the lantern unwinds back to front
  static Future<void> unwindToFront() async {
    const delays = [45, 55, 70, 90, 120];
    const amps = [110, 95, 80, 65, 50];
    for (int i = 0; i < delays.length; i++) {
      await Future.delayed(Duration(milliseconds: delays[i]));
      await _send('lowTick', amp: amps[i]);
    }
  }

  // Three-stage ascending surge when the full oath is recognized
  static Future<void> oathCompletedSurge() async {
    await _send('tick', amp: 130);
    await Future.delayed(const Duration(milliseconds: 50));
    await _send('click', amp: 190);
    await Future.delayed(const Duration(milliseconds: 65));
    await _send('heavy', amp: 255);
  }

  // Powerful energy wave blast when releasing to 100% charge
  static Future<void> fullChargeBlast() async {
    await _send('heavy', amp: 255);
    await Future.delayed(const Duration(milliseconds: 70));
    await _send('click', amp: 200);
    await Future.delayed(const Duration(milliseconds: 85));
    await _send('heavy', amp: 255);
  }

  // Crisp double-pulse for the 5% Knock Charge
  static Future<void> quickChargePulse() async {
    await _send('click', amp: 190);
    await Future.delayed(const Duration(milliseconds: 65));
    await _send('tick', amp: 140);
  }
}

Future<void> _requestStartupPermissions() async {
  try {
    await Permission.notification.request();
    await Permission.microphone.request();
    final exact = await Permission.scheduleExactAlarm.status;
    if (!exact.isGranted) await Permission.scheduleExactAlarm.request();
  } catch (e) {
    debugPrint("Startup permission error: $e");
  }
}

Future<void> _prepareNotificationsForExit() async {
  try {
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'ring_rejection_channel_v1',
        'Ring Rejection',
        description: 'Shown when you decline the ring in the intro',
        importance: Importance.max,
      ),
    );
  } catch (e) {
    debugPrint("Reject notification setup error: $e");
  }
}

const String _holdFile = 'master_holding.mp3';
const String _oathFile = 'master_oath_reciting.mp3';
const String _releaseFile = 'master_releasing.mp3';
const String _quickChargeFile = 'ring_charge_5.mp3';
const String _depletionFile = 'ring_depletion.mp3';
const String _countdownFile = 'countdown.mp3';

const String _modelControlJs = r'''
(function () {
  var TWO_PI = Math.PI * 2;
  var FRONT_DEG = 180;
  var FRONT = FRONT_DEG * Math.PI / 180;
  var HOME_ORBIT = "0deg 90deg 105%";
  var ALT_ORBIT = "0.001deg 90deg 105%";
  var raf = 0;
  var spinDir = 1;
  var lastYaw = null;

  function viewer() { return document.querySelector("model-viewer"); }
  function yawOf(el) { return typeof el.turntableRotation === "number" ? el.turntableRotation : 0; }
  function stopAnim() { if (raf) { cancelAnimationFrame(raf); raf = 0; } }
  function ease(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }

  function faceFront() {
    var el = viewer();
    if (el && typeof el.resetTurntableRotation === "function" && !raf) el.resetTurntableRotation(FRONT);
  }
  (function hookLoad() {
    var el = viewer();
    if (!el) { setTimeout(hookLoad, 50); return; }
    if (el.addEventListener) el.addEventListener("load", faceFront);
    if (el.loaded) faceFront();
  })();

  setInterval(function () {
    var el = viewer();
    if (!el || raf) return;
    var y = yawOf(el);
    if (lastYaw !== null && Math.abs(y - lastYaw) > 1e-4) spinDir = y > lastYaw ? 1 : -1;
    lastYaw = y;
  }, 150);

  function resetCamera(el) {
    try { el.cameraOrbit = el.cameraOrbit === HOME_ORBIT ? ALT_ORBIT : HOME_ORBIT; } catch (e) {}
  }

  function returnToFront(el) {
    resetCamera(el);
    if (typeof el.resetTurntableRotation !== "function") return;

    var from = yawOf(el);
    var rel = from - FRONT;
    var target = (spinDir > 0
      ? Math.floor(rel / TWO_PI + 1e-3)
      : Math.ceil(rel / TWO_PI - 1e-3)) * TWO_PI + FRONT;
    var dist = target - from;

    if (Math.abs(dist) < 0.005) { el.resetTurntableRotation(FRONT); return; }

    var duration = 700 + 900 * Math.min(Math.abs(dist) / TWO_PI, 1);
    var t0 = null;
    function step(ts) {
      if (t0 === null) t0 = ts;
      var p = Math.min((ts - t0) / duration, 1);
      if (p < 1) {
        el.resetTurntableRotation(from + dist * ease(p));
        raf = requestAnimationFrame(step);
      } else {
        el.resetTurntableRotation(FRONT);
        raf = 0;
        lastYaw = null;
      }
    }
    raf = requestAnimationFrame(step);
  }

  window.lanternSetSpin = function (spin) {
    var el = viewer();
    if (!el) return "no";
    stopAnim();
    lastYaw = null;
    if (spin) {
      el.setAttribute("auto-rotate", "");
      el.autoRotate = true;
    } else {
      el.removeAttribute("auto-rotate");
      el.autoRotate = false;
      returnToFront(el);
    }
    return "ok";
  };
})();
''';

List<String> _oathSplit(String text) =>
    RegExp(r"([A-Za-z']+|[^A-Za-z']+)").allMatches(text).map((m) => m.group(0)!).toList();

String _cleanSpoken(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r"['’`]"), '')
    .replaceAll(RegExp(r"[^a-z\s]"), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class _LanternProfile {
  final String id;
  final String name;
  final String modelAsset;
  final String menuIcon;
  final double frontDeg;
  final String cameraOrbit;
  final String? fieldOfView;
  final bool fuzzy;
  final String oathText;
  final String oathPreview;
  final List<List<String>> aliases;
  final List<String> words;
  final Set<int> droppable;
  final bool Function(String raw) finishCheck;
  final List<String> segments;
  final List<bool> segmentIsWord;

  _LanternProfile({
    required this.id,
    required this.name,
    required this.modelAsset,
    required this.menuIcon,
    required this.frontDeg,
    required this.cameraOrbit,
    this.fieldOfView,
    this.fuzzy = false,
    required this.oathText,
    required this.oathPreview,
    required this.aliases,
    required this.words,
    required this.droppable,
    required this.finishCheck,
  })  : segments = _oathSplit(oathText),
        segmentIsWord = _oathSplit(oathText).map((seg) => RegExp(r"^[A-Za-z']+$").hasMatch(seg)).toList();
}

bool _halFinish(String raw) {
  final t = _cleanSpoken(raw);
  bool has(String s) => t.contains(s);

  final endOk = (has('green') || has('lantern') || has('phantom')) &&
      (has('light') || has('night') || has('right') || has('like'));
  if (has('power') && endOk) return true;

  const keys = ['brightest', 'blackest', 'night', 'evil', 'escape', 'sight', 'worship', 'might', 'beware', 'power', 'green', 'lantern', 'light'];
  final words = t.split(' ').toSet();
  int hits = 0;
  for (final k in keys) {
    if (words.contains(k) || words.contains('${k}s')) hits++;
  }
  return hits >= 10;
}

bool _johnFinish(String raw) {
  final t = _cleanSpoken(raw);
  bool has(String s) => t.contains(s);

  final hasServiceLine = has('service') || has('surface') || has('serve') || has('servants');
  final hasLantern = has('lantern') || has('london') || has('landing') || has('phantom') ||
      has('lamp') || has('latin') || has('lenten') || has('pattern') || has('planter') || has('atlanta');
  final hasLight = has('light') || has('night') || has('right') || has('like') ||
      has('life') || has('white') || has('might') || has('sight') || has('fight') || has('lite') || has('slide');

  if (hasServiceLine && (hasLantern || hasLight)) return true;
  if (hasLantern && hasLight) return true;

  const keys = [
    'brightest', 'darkest', 'night', 'embrace', 'fear',
    'right', 'choose', 'ring', 'fight', 'service', 'lantern', 'light'
  ];
  final words = t.split(' ').toSet();
  int hits = 0;
  for (final k in keys) {
    if (words.contains(k) || words.contains('${k}s')) hits++;
  }
  return hits >= 9;
}

final List<_LanternProfile> _lanternProfiles = [
  _LanternProfile(
    id: 'hal',
    name: 'Hal Jordan',
    modelAsset: 'assets/green_lanterns_power_battery_from_lanterns.glb',
    menuIcon: 'assets/image_aeb898.png',
    frontDeg: 180,
    cameraOrbit: '0deg 90deg 105%',
    oathText: "\"In brightest day, in blackest night,\nNo evil shall escape my sight,\nLet those who worship evil's might,\nBeware my power... Green Lantern's light!\"",
    oathPreview: '"In brightest day, in blackest night..."',
    aliases: [
      ['in', 'and', 'an', 'on'],                                     
      ['brightest', 'bright', 'right', 'write', 'bride', 'lightest'],
      ['day', 'they', 'the', 'de', 'stay'],                          
      ['in', 'and', 'an', 'on'],                                     
      ['blackest', 'black', 'blanket', 'block', 'darkest', 'back'],  
      ['night', 'knight', 'nite', 'nine', 'light', 'right'],         
      ['no', 'know', 'now', 'not'],                                  
      ['evil', 'even', 'able', 'eva', 'devil'],                      
      ['shall', 'shell', 'should', 'will', 'show', 'sha'],           
      ['escape', 'scrape', 'skip', 'skate', 'state', 'escaped'],     
      ['my', 'by', 'me', 'might'],                                   
      ['sight', 'site', 'side', 'sign', 'fight', 'light', 'right'],  
      ['let', 'left', 'like', 'that', 'get', 'late'],                
      ['those', 'these', 'dose', 'goes', 'toast', 'though'],         
      ['who', 'how', 'to', 'do', 'you'],                             
      ['worship', 'warship', 'washing', 'watch', 'worth', 'ship'],   
      ['evils', 'evil', 'even', 'devil', 'devils', 'his'],           
      ['might', 'mite', 'night', 'light', 'right', 'fight', 'mind'], 
      ['beware', 'where', 'aware', 'before'],
      ['my', 'by', 'me'],                                            
      ['power', 'our', 'hour', 'tower', 'flower', 'powers'],         
      ['green', 'clean', 'queen', 'bean', 'dream', 'free'],          
      ['lanterns', 'lantern', 'london', 'landing', 'phantom', 'lamp', 'latin'],       
      ['light', 'night', 'right', 'like', 'life', 'white', 'might', 'lights', 'lite'], 
    ],
    words: [
      'in', 'brightest', 'day', 'in', 'blackest', 'night',
      'no', 'evil', 'shall', 'escape', 'my', 'sight',
      'let', 'those', 'who', 'worship', 'evils', 'might',
      'beware', 'my', 'power', 'green', 'lanterns', 'light',
    ],
    droppable: {0, 3, 6, 10, 12, 14, 19, 22},
    finishCheck: _halFinish,
  ),
  _LanternProfile(
    id: 'john',
    name: 'John Stewart',
    modelAsset: 'assets/john_stewart_lantern.glb',
    menuIcon: 'assets/image_aeb85d.png',
    frontDeg: 0,
    cameraOrbit: '0deg 90deg 105%',
    fieldOfView: '20deg',
    fuzzy: true,
    oathText:
        "\"In brightest day, in darkest night,\nI'll embrace my fear.\nI'll do what's right.\nI choose this ring.\nI choose this fight,\nIn service to this lantern's light.\"",
    oathPreview: '"In brightest day, in darkest night..."',
    aliases: [
      ['in', 'and', 'an', 'on'],                                            // 0 in
      ['brightest', 'bright', 'right', 'write', 'bride', 'lightest'],       // 1 brightest
      ['day', 'they', 'the', 'de', 'stay'],                                 // 2 day
      ['in', 'and', 'an', 'on'],                                            // 3 in
      ['darkest', 'dark', 'darker', 'darkness'],                            // 4 darkest
      ['night', 'knight', 'nite', 'nine', 'light', 'right'],                // 5 night
      ['ill', 'i', 'will', 'all', 'aisle', 'isle'],                         // 6 I'll
      ['embrace', 'embraced', 'embraces', 'brace', 'embrase'],              // 7 embrace
      ['my', 'by', 'me', 'might', 'i'],                                     // 8 my
      ['fear', 'fears', 'fair', 'fur', 'free', 'here', 'feel'],             // 9 fear
      ['ill', 'i', 'will', 'all', 'aisle', 'isle'],                         // 10 I'll
      ['do', 'due', 'to', 'you', 'dew', 'will'],                            // 11 do
      ['whats', 'what', 'watts', 'wants', 'was', 'one'],                    // 12 what's
      ['right', 'write', 'rite', 'white', 'bright', 'light', 'night', 'fight'], // 13 right
      ['i', 'eye', 'aye', 'a', 'ai', 'and'],                                // 14 I
      ['choose', 'chose', 'chews', 'shoes', 'choice', 'chooses'],           // 15 choose
      ['this', 'these', 'his', 'the', 'is', 'that'],                        // 16 this
      ['ring', 'rain', 'rink', 'wing', 'rang', 'king', 'rings'],            // 17 ring
      ['i', 'eye', 'aye', 'a', 'ai', 'and'],                                // 18 I
      ['choose', 'chose', 'chews', 'shoes', 'choice', 'chooses'],           // 19 choose
      ['this', 'these', 'his', 'the', 'is', 'that'],                        // 20 this
      ['fight', 'fights', 'fire', 'flight', 'light', 'right', 'night', 'fit'], // 21 fight
      ['in', 'and', 'an', 'on'],                                            // 22 in
      ['service', 'services', 'serves', 'serve', 'surface', 'servants'],    // 23 service
      ['to', 'two', 'too', 'do', 'the'],                                    // 24 to
      ['this', 'these', 'his', 'the', 'is', 'that'],                        // 25 this
      [
        'lanterns', 'lantern', 'london', 'landing', 'phantom', 'lamp', 'lamps',
        'latin', 'lenten', 'planter', 'pattern', 'patterns', 'hunters', 'lenses',
        'atlanta', 'later', 'letter', 'letters', 'land', 'turn', 'learns', 'lanternlight'
      ],                                                                    // 26 lantern's
      [
        'light', 'lights', 'night', 'right', 'like', 'life', 'white', 'might',
        'lite', 'line', 'live', 'lie', 'late', 'sight', 'fight', 'bright',
        'flight', 'knight', 'slide', 'slight', 'bite', 'height', 'lanternlight'
      ],                                                                    // 27 light
    ],
    words: [
      'in', 'brightest', 'day', 'in', 'darkest', 'night',
      'ill', 'embrace', 'my', 'fear',
      'ill', 'do', 'whats', 'right',
      'i', 'choose', 'this', 'ring',
      'i', 'choose', 'this', 'fight',
      'in', 'service', 'to', 'this', 'lanterns', 'light',
    ],
    droppable: {0, 3, 6, 8, 10, 11, 14, 16, 18, 20, 22, 24, 25, 26},
    finishCheck: _johnFinish,
  ),
];

_LanternProfile _lanternById(String? id) =>
    _lanternProfiles.firstWhere((p) => p.id == id, orElse: () => _lanternProfiles.first);

String _modelControlJsFor(double frontDeg) =>
    _modelControlJs.replaceFirst('var FRONT_DEG = 180;', 'var FRONT_DEG = $frontDeg;');

// ==========================================
// FIRST-LAUNCH TUTORIAL STEPS
// ==========================================
class _TutorialStep {
  final IconData icon;
  final String title;
  final String body;
  const _TutorialStep(this.icon, this.title, this.body);
}

const List<_TutorialStep> _tutorialSteps = [
  _TutorialStep(
    Icons.adjust,
    "WELCOME, RECRUIT",
    "This quick tour shows you how to power your ring. Tap NEXT to continue.",
  ),
  _TutorialStep(
    Icons.battery_charging_full,
    "CORE CHARGE",
    "The big percentage at the top is your ring's battery. While it is charged, the time remaining is shown underneath.",
  ),
  _TutorialStep(
    Icons.timer_outlined,
    "CHOOSE A DURATION",
    "When the ring is at 0%, pick how long a full charge should last: 48 sec, 48 min, 48 hr, or Custom to enter your own minutes.",
  ),
  _TutorialStep(
    Icons.touch_app,
    "HOLD & RECITE THE OATH",
    "Press and hold anywhere on the lantern and recite the oath out loud. Each word lights up as you say it. Allow microphone access when asked.",
  ),
  _TutorialStep(
    Icons.bolt,
    "RELEASE TO CHARGE",
    "Once every word has lit up, let go. Your ring charges to 100% and starts draining right away.",
  ),
  _TutorialStep(
    Icons.volume_up_outlined,
    "KNOCK CHARGE",
    "No time for the oath? Open the settings menu at the top right, turn on Knock Charge, then double tap a table for a quick 5% charge.",
  ),
  _TutorialStep(
    Icons.warning_amber_rounded,
    "LOW BATTERY ALERTS",
    "You get a warning sound and notification at 20%, 15% and 10%. Below 10% the display blinks red, and a countdown plays in the last seconds.",
  ),
  _TutorialStep(
    Icons.swap_horiz,
    "CHOOSE YOUR LANTERN",
    "Tap the ring logo in the top left corner to switch between Hal Jordan's and John Stewart's lanterns. Each one has its own 3D model and its own oath to recite.",
  ),
  _TutorialStep(
    Icons.settings_outlined,
    "SETTINGS",
    "Use the gear icon to reset the ring, try Spin Mode to turn the 3D lantern with your finger, switch Auto Spin on or off, or replay this tutorial any time.",
  ),
];

class LanternApp extends StatelessWidget {
  final bool hasSeenIntro;
  const LanternApp({super.key, required this.hasSeenIntro});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'G-Lanterns 3D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Roboto',
      ),
      home: hasSeenIntro ? const RingChargerScreen() : const IntroScreen(),
    );
  }
}

// ==========================================
// COMIC BOOK INTRO SCREEN
// ==========================================
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  String _userName = "";

  final AudioPlayer _introAudioPlayer = AudioPlayer();

  final List<String> _introAudioFiles = [
    'scene1.mp3',
    'scene2.mp3',
    'scene 3.mp3',
    'scene 4.mp3',
    'scene5.mp3',
    'scene6.mp3',
    'scene7.mp3',
    'scene8.mp3',
    'scene9.mp3',
  ];

  @override
  void initState() {
    super.initState();
    _playAudioForPage(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestStartupPermissions());
  }

  void _playAudioForPage(int pageIndex) async {
    await _introAudioPlayer.stop();
    if (pageIndex < _introAudioFiles.length) {
      try {
        await _introAudioPlayer.play(AssetSource(_introAudioFiles[pageIndex]));
      } catch (e) {
        debugPrint("Intro audio play error for page $pageIndex: $e");
      }
    }
  }

  void _nextPage() {
    _LanternHaptics.tap();
    FocusScope.of(context).unfocus();
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _finishIntro() async {
    _LanternHaptics.medium();
    await _introAudioPlayer.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenIntro', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RingChargerScreen()),
    );
  }

  @override
  void dispose() {
    _introAudioPlayer.dispose();
    super.dispose();
  }

  Widget _buildComicPage(Widget child) {
    return Container(
      color: Colors.black, 
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          _playAudioForPage(index);
        },
        children: [
          _buildTapScreen('assets/94777.png'),
          _buildTapScreen('assets/94807.png'),
          _buildTapScreen('assets/94779.png'),
          _buildNameInputScreen(),
          _buildShowNameScreen(),
          _buildYesNoScreen(),
          _buildTapScreen('assets/94783.png'),
          _buildTapScreen('assets/94785.png'),
          _buildBeginScreen(),
        ],
      ),
    );
  }

  Widget _buildTapScreen(String assetPath) {
    return GestureDetector(
      onTap: _nextPage,
      child: _buildComicPage(
        Image.asset(
          assetPath,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
        ),
      ),
    );
  }

  Widget _buildNameInputScreen() {
    return _buildComicPage(
      LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final width = constraints.maxWidth;
          
          return Stack(
            children: [
              SizedBox(
                width: width, 
                height: height,
                child: Image.asset(
                  'assets/94780.png', 
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                ),
              ),
              Positioned(
                top: height * 0.772,
                left: width * 0.12,
                right: width * 0.12,
                child: Container(
                  height: height * 0.065,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.greenAccent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.greenAccent.withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ],
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _nameController,
                    onTap: _LanternHaptics.tap,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "Enter your name...",
                      hintStyle: TextStyle(color: Colors.white54, fontSize: 16),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) {
                      _LanternHaptics.spinDetent(velocity: 0.5);
                      _userName = val.trim().toUpperCase();
                    },
                  ),
                ),
              ),
              Positioned(
                top: height * 0.855, 
                left: width * 0.12,
                right: width * 0.12,
                child: GestureDetector(
                  onTap: () {
                    if (_nameController.text.trim().isNotEmpty) {
                      _LanternHaptics.toggle();
                      setState(() {
                        _userName = _nameController.text.trim().toUpperCase();
                      });
                      _nextPage();
                    } else {
                      _LanternHaptics.heavy();
                    }
                  },
                  child: Container(
                    height: height * 0.065,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.greenAccent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'CONTINUE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildShowNameScreen() {
    return GestureDetector(
      onTap: _nextPage,
      child: _buildComicPage(
        Stack(
          children: [
            SizedBox(
              width: double.infinity, 
              height: double.infinity,
              child: Image.asset(
                'assets/94781.png', 
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
              ),
            ),
            Align(
              alignment: const Alignment(-0.65, -0.665),
              child: Container(
                color: const Color(0xFFF3EDDF),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  _userName.isEmpty ? "RECRUIT" : _userName,
                  style: const TextStyle(
                    color: Color(0xFF063B20),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _leaving = false;

  Future<void> _onRejectTap() async {
    if (_leaving) return;
    _leaving = true;
    _LanternHaptics.heavy();
    try {
      await _introAudioPlayer.stop();
    } catch (_) {}

    await _prepareNotificationsForExit();
    try {
      await flutterLocalNotificationsPlugin.show(
        id: 100,
        title: "The ring has rejected you",
        body: "You're not worthy of this ring. Better luck next time!",
        notificationDetails: _rejectNotificationDetails,
      );
    } catch (e) {
      debugPrint("Reject notification error: $e");
    }

    await Future.delayed(const Duration(milliseconds: 400));
    await SystemNavigator.pop();
  }

  Widget _buildYesNoScreen() {
    return _buildComicPage(
      Stack(
        children: [
          SizedBox(
            width: double.infinity, 
            height: double.infinity,
            child: Image.asset(
              'assets/94782.png', 
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
            ),
          ),
          Align(
            alignment: const Alignment(-0.6, 0.77),
            child: GestureDetector(
              onTap: _onRejectTap,
              child: Container(
                width: 140, height: 70,
                color: Colors.transparent,
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0.6, 0.77),
            child: GestureDetector(
              onTap: () {
                _LanternHaptics.medium();
                _nextPage();
              },
              child: Container(
                width: 140, height: 70,
                color: Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeginScreen() {
    return _buildComicPage(
      Stack(
        children: [
          SizedBox(
            width: double.infinity, 
            height: double.infinity,
            child: Image.asset(
              'assets/94786.png', 
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.85),
            child: GestureDetector(
              onTap: _finishIntro,
              child: Container(
                width: 250, height: 70,
                color: Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// RING CHARGER SCREEN
// ==========================================
class RingChargerScreen extends StatefulWidget {
  const RingChargerScreen({super.key});

  @override
  State<RingChargerScreen> createState() => _RingChargerScreenState();
}

class _RingChargerScreenState extends State<RingChargerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _muteChannel = MethodChannel('lantern.audio/mute');

  double chargeLevel = 0.0;
  Timer? _drainTimer;
  Timer? _handoffTimer;
  Timer? _micDelayTimer;
  Timer? _holdHapticTimer;
  Timer? _tailWordTimer;
  SharedPreferences? prefs;

  int _totalDrainSeconds = 2880;

  DateTime _lastKnockTime = DateTime.now();
  int _knockCount = 0;

  bool isListeningForOath = false;
  bool _oathTriggered = false;
  bool _spinMode = false;
  bool _autoRotateModel = true; 
  bool _audioKnockMode = false;
  bool _countdownPlayed = false;

  // Tracks manual 3D spin drag distance for iOS Digital Crown detent ticks
  double _spinDragAccumulator = 0.0;

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;

  final Completer<void> _notifReady = Completer<void>();

  final AudioPlayer _holdPlayer = AudioPlayer();
  final AudioPlayer _oathPlayer = AudioPlayer();
  final AudioPlayer _releasePlayer = AudioPlayer();
  final AudioPlayer _quickChargePlayer = AudioPlayer();
  final AudioPlayer _depletionPlayer = AudioPlayer();
  final AudioPlayer _countdownPlayer = AudioPlayer();

  final Map<String, String> _cachedPaths = {};
  bool _isPressing = false;
  bool _audioReady = false;

  int? _activePointer;
  int _pressId = 0;
  String _oathHistory = '';
  String _currentText = '';
  bool _oathDetected = false;
  int _matchedWordCount = 0;
  int _lastHapticWordIdx = 0;
  final ValueNotifier<double> _oathProgress = ValueNotifier<double>(0.0);
  DateTime _pressStartedAt = DateTime.now();
  bool _preferOnDevice = false;
  Ticker? _oathTicker;
  Duration _oathLastTick = Duration.zero;
  
  final ValueNotifier<double> _voiceNotifier = ValueNotifier<double>(0.0);

  late AnimationController _blinkController;

  WebViewController? _modelController;
  bool _prefsReady = false;
  _LanternProfile _lantern = _lanternProfiles.first;
  bool _initialSpin = true;
  bool? _appliedSpin;
  bool _spinSyncBusy = false;
  bool? _syncTarget;
  int _syncTries = 0;
  Timer? _spinSyncRetry;
  DateTime _lastDrainTick = DateTime.now();

  bool _showTutorial = false;
  int _tutorialStep = 0;

  bool get _shouldSpin => _autoRotateModel && !_isPressing && !_spinMode;

  Future<void> _loadModelPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoRotateModel = p.getBool('autoRotateModel') ?? true;
      _lantern = _lanternById(p.getString('selectedLantern'));
      _initialSpin = _shouldSpin;
      _appliedSpin = _initialSpin;
      _showTutorial = !(p.getBool('hasSeenTutorial') ?? false);
      _prefsReady = true;
    });
  }

  Future<void> _selectLantern(_LanternProfile p) async {
    if (p.id == _lantern.id) return;
    _LanternHaptics.medium();
    setState(() {
      _lantern = p;
      _modelController = null;
      _spinSyncRetry?.cancel();
      _syncTarget = null;
      _syncTries = 0;
      _initialSpin = _shouldSpin;
      _appliedSpin = _initialSpin;
      _matchedWordCount = 0;
      _lastHapticWordIdx = 0;
      _oathProgress.value = 0.0;
      _oathHistory = '';
      _currentText = '';
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedLantern', p.id);
    } catch (e) {
      debugPrint("Lantern save error: $e");
    }
  }

  void _showLanternPicker() {
    _LanternHaptics.tap();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F1A15),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CHOOSE YOUR LANTERN',
                  style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                for (final p in _lanternProfiles)
                  GestureDetector(
                    onTap: () {
                      _LanternHaptics.tap();
                      Navigator.pop(sheetContext);
                      _selectLantern(p);
                    },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: p.id == _lantern.id ? Colors.greenAccent.withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: p.id == _lantern.id ? Colors.greenAccent : Colors.white24,
                          width: p.id == _lantern.id ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: TextStyle(
                                    color: p.id == _lantern.id ? Colors.greenAccent : Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(p.oathPreview, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              ],
                            ),
                          ),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: p.id == _lantern.id ? 1.0 : 0.4,
                            child: Container(
                              height: 55,
                              width: 40,
                              decoration: p.id == _lantern.id ? BoxDecoration(
                                boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.4), blurRadius: 12)]
                              ) : null,
                              child: Image.asset(p.menuIcon, fit: BoxFit.contain),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _syncModelSpin() async {
    final controller = _modelController;
    if (controller == null || !_prefsReady || _spinSyncBusy) return;

    final want = _shouldSpin;
    if (_appliedSpin == want) {
      _syncTarget = null;
      return;
    }
    if (_syncTarget != want) {
      _syncTarget = want;
      _syncTries = 0;
    }
    if (_syncTries++ > 60) return;

    _spinSyncBusy = true;
    try {
      final res = await controller.runJavaScriptReturningResult(
        'window.lanternSetSpin ? window.lanternSetSpin($want) : "wait"',
      );
      if (res.toString().contains('ok')) {
        if (_appliedSpin == true && !want) {
          // Subtle decelerating ratchet ticks as the lantern unwinds to face front
          unawaited(_LanternHaptics.unwindToFront());
        }
        _appliedSpin = want;
      }
    } catch (e) {
      debugPrint('Model spin sync error: $e');
    } finally {
      _spinSyncBusy = false;
    }

    if (!mounted) return;
    if (_appliedSpin != _shouldSpin) {
      _spinSyncRetry?.cancel();
      _spinSyncRetry = Timer(const Duration(milliseconds: 200), _syncModelSpin);
    }
  }

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    WidgetsBinding.instance.addObserver(this);
    _loadModelPrefs();
    _initSystem();
  }

  void _updateBlinkState() {
    if (chargeLevel > 0 && chargeLevel <= 10.0) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat(reverse: true);
      }
    } else {
      if (_blinkController.isAnimating) {
        _blinkController.stop();
        _blinkController.value = 1.0;
      }
    }
  }

  Future<void> _setBeepMute(bool mute) async {
    try {
      await _muteChannel.invokeMethod(mute ? 'muteMedia' : 'unmuteMedia');
    } catch (_) {}
  }

  void _initSystem() async {
    try {
      await _muteChannel.invokeMethod('unmuteMedia');
    } catch (_) {}

    await _initAudio();
    await _initNotifications();

    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (e) {
          debugPrint("Speech error: ${e.errorMsg}");
          final msg = e.errorMsg.toLowerCase();
          if (_preferOnDevice && (msg.contains('language') || msg.contains('not_supported') || msg.contains('unavailable'))) {
            _preferOnDevice = false;
            debugPrint("[oath] on-device speech unavailable, using the default recogniser");
          }
        },
        onStatus: (status) {
          if ((status == 'notListening' || status == 'done') &&
              _isPressing &&
              !_oathTriggered) {
            final id = _pressId;
            Future.delayed(const Duration(milliseconds: 150), () {
              if (_isPressing && id == _pressId && !_speechToText.isListening) {
                _listenForOath(id);
              }
            });
          }
          if (status == 'notListening' && _audioKnockMode && !isListeningForOath) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (_audioKnockMode && !isListeningForOath && chargeLevel == 0.0) {
                _startContinuousListening();
              }
            });
          }
        },
      );
    } catch (e) {
      debugPrint("Speech init error: $e");
    }

    prefs = await SharedPreferences.getInstance();
    _loadSavedData();
  }

  Future<void> _initAudio() async {
    try {
      final audioContext = AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: false,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.none,
        ),
      );
      await AudioPlayer.global.setAudioContext(audioContext);

      final allPlayers = [
        _holdPlayer, _oathPlayer, _releasePlayer, 
        _quickChargePlayer, _depletionPlayer, _countdownPlayer
      ];

      for (final p in allPlayers) {
        await p.setAudioContext(audioContext);
        await p.setPlayerMode(PlayerMode.mediaPlayer);
        await p.setReleaseMode(ReleaseMode.stop);
      }

      final files = [
        _holdFile, _oathFile, _releaseFile, 
        _quickChargeFile, _depletionFile, _countdownFile
      ];
      
      for (final f in files) {
        final uri = await AudioCache.instance.load(f);
        _cachedPaths[f] = uri.toFilePath();
      }

      await _holdPlayer.setSource(DeviceFileSource(_cachedPaths[_holdFile]!));
      await _oathPlayer.setSource(DeviceFileSource(_cachedPaths[_oathFile]!));
      await _oathPlayer.setReleaseMode(ReleaseMode.loop);
      await _releasePlayer.setSource(DeviceFileSource(_cachedPaths[_releaseFile]!));
      await _quickChargePlayer.setSource(DeviceFileSource(_cachedPaths[_quickChargeFile]!));
      await _depletionPlayer.setSource(DeviceFileSource(_cachedPaths[_depletionFile]!));
      await _countdownPlayer.setSource(DeviceFileSource(_cachedPaths[_countdownFile]!));

      _oathPlayer.onPlayerComplete.listen((_) {
        if (_isPressing) {
          _playInstant(_oathPlayer, _oathFile, onlyWhilePressing: true);
        }
      });

      _audioReady = true;
    } catch (e) {
      debugPrint("AUDIO INIT ERROR: $e");
    }
  }

  Future<void> _haltPlayer(AudioPlayer player) async {
    try { await player.stop(); } catch (e) { debugPrint("Audio halt error: $e"); }
  }

  Future<void> _playInstant(AudioPlayer player, String assetFile, {bool onlyWhilePressing = false}) async {
    try {
      if (onlyWhilePressing && !_isPressing) return;
      final path = _cachedPaths[assetFile];
      if (path != null) {
        await player.play(DeviceFileSource(path));
      } else {
        await player.play(AssetSource(assetFile));
      }
    } catch (e) {
      debugPrint("Audio play error: $e");
    }
  }

  void _startOathTicker() {
    _oathTicker ??= createTicker(_onOathTick);
    final t = _oathTicker!;
    if (!t.isActive) {
      _oathLastTick = Duration.zero;
      t.start();
    }
  }

  void _onOathTick(Duration elapsed) {
    final double dt = ((elapsed - _oathLastTick).inMicroseconds / 1000000.0).clamp(0.0, 0.1).toDouble();
    _oathLastTick = elapsed;

    final double target = _matchedWordCount.toDouble();
    final double cur = _oathProgress.value;
    final double gap = target - cur;

    if (gap <= 0.001) {
      _oathProgress.value = target < cur ? cur : target;
      if (!_isPressing) _oathTicker?.stop();
      return;
    }

    final double speed = (3.2 + 2.0 * gap).clamp(3.2, 16.0).toDouble();
    final double nextVal = (cur + speed * dt).clamp(0.0, target).toDouble();
    _oathProgress.value = nextVal;

    // Crisp iOS Taptic tick as each word visually locks in
    final int litWordIdx = nextVal.floor();
    if (litWordIdx > _lastHapticWordIdx) {
      _lastHapticWordIdx = litWordIdx;
      if (_isPressing && litWordIdx < _oathWordAliases.length) {
        _LanternHaptics.tap();
      }
    }
  }

  List<List<String>> get _oathWordAliases => _lantern.aliases;
  List<String> get _oathWords => _lantern.words;
  Set<int> get _droppableOathIdx => _lantern.droppable;
  List<String> get _oathSegments => _lantern.segments;
  List<bool> get _oathSegmentIsWord => _lantern.segmentIsWord;

  static int _editDistance(String a, String b) {
    List<int> prev = List<int>.generate(b.length + 1, (i) => i);
    for (int i = 1; i <= a.length; i++) {
      final List<int> cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final int cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        int best = prev[j - 1] + cost;
        if (prev[j] + 1 < best) best = prev[j] + 1;
        if (cur[j - 1] + 1 < best) best = cur[j - 1] + 1;
        cur[j] = best;
      }
      prev = cur;
    }
    return prev[b.length];
  }

  bool _weakOathMatch(String token, int idx) {
    final aliases = _oathWordAliases[idx];
    if (aliases.contains(token) || (token.length >= 4 && aliases.any((a) => a.startsWith(token) || token.startsWith(a)))) {
      return true;
    }
    if (_lantern.fuzzy && token.length >= 4) {
      final String w = _oathWords[idx];
      if (w.length >= 4 && _editDistance(token, w) <= (w.length >= 7 ? 2 : 1)) return true;
    }
    return false;
  }

  bool _strongOathMatch(String token, int idx) {
    final w = _oathWords[idx];
    if (token == w) return true;
    if (token.length >= 4 && _oathWordAliases[idx].contains(token)) return true;
    return token.length >= 5 && w.length >= 5 && _editDistance(token, w) <= 1;
  }

  int _alignOath(List<String> tokens) {
    final int total = _oathWordAliases.length;
    int idx = 0;
    for (int i = 0; i < tokens.length && idx < total; i++) {
      final String t = tokens[i];
      if (_weakOathMatch(t, idx)) {
        if (idx == total - 2 && (t.contains('light') || t.contains('night') || t.contains('right'))) {
          idx = total;
        } else {
          idx++;
        }
        continue;
      }
      if (idx + 1 < total &&
          (_strongOathMatch(t, idx + 1) || (idx >= total - 2 && _weakOathMatch(t, idx + 1)))) {
        final bool droppable = _droppableOathIdx.contains(idx) || idx >= total - 2;
        final bool confirmed =
            i + 1 < tokens.length && idx + 2 < total && _weakOathMatch(tokens[i + 1], idx + 2);
        if (droppable || confirmed) {
          idx += 2;
          continue;
        }
      }
      if (_lantern.fuzzy &&
          idx + 2 < total &&
          ((i + 1 < tokens.length &&
                  idx + 3 < total &&
                  _strongOathMatch(t, idx + 2) &&
                  _weakOathMatch(tokens[i + 1], idx + 3)) ||
              (idx + 2 == total - 1 && _weakOathMatch(t, idx + 2)))) {
        idx += 3;
        continue;
      }
      if (idx >= total - 2 && t.length >= 3) {
        idx++;
      }
    }
    return idx;
  }

  void _completeOathTrigger() {
    final int totalWords = _oathWordAliases.length;
    _matchedWordCount = totalWords;
    if (!_oathTriggered) {
      _oathTriggered = true;
      _oathDetected = true;
      unawaited(_LanternHaptics.oathCompletedSurge());
    }
  }

  void _updateKaraokeProgress(String rawSpoken) {
    final cleaned = _cleanSpoken(rawSpoken);
    if (cleaned.isEmpty) return;

    final int totalWords = _oathWordAliases.length;
    final int aligned = _alignOath(cleaned.split(RegExp(r'\s+')));

    if (aligned > _matchedWordCount) _matchedWordCount = aligned;

    if (_matchedWordCount == totalWords - 1 && !_oathTriggered) {
      _tailWordTimer?.cancel();
      final int activeId = _pressId;
      _tailWordTimer = Timer(const Duration(milliseconds: 350), () {
        if (mounted && _isPressing && _pressId == activeId && !_oathTriggered) {
          setState(() {
            _completeOathTrigger();
          });
        }
      });
    }

    if (!_oathTriggered) {
      if (_matchedWordCount == totalWords ||
          (_matchedWordCount >= (totalWords * 2 / 3).floor() && _matchesOath(rawSpoken))) {
        _tailWordTimer?.cancel();
        _completeOathTrigger();
      }
    }
  }

  bool _matchesOath(String raw) => _lantern.finishCheck(raw);

  Future<void> _initNotifications() async {
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

      final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
        try { await androidPlugin.requestExactAlarmsPermission(); } catch (e) { debugPrint("Exact alarm permission request failed: $e"); }

        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          _channelId, _channelName, description: 'Tracks the battery drain', importance: Importance.max,
        );
        await androidPlugin.createNotificationChannel(channel);

        const AndroidNotificationChannel depletionChannel = AndroidNotificationChannel(
          'ring_depletion_channel_v1', 'Ring Depletion Alerts', description: 'Plays the warning sound at 20, 15, and 10 percent', importance: Importance.max, sound: RawResourceAndroidNotificationSound('ring_depletion'),
        );
        await androidPlugin.createNotificationChannel(depletionChannel);
      }
    } catch (e) {
      debugPrint("INIT CRASH: $e");
    } finally {
      if (!_notifReady.isCompleted) _notifReady.complete();
    }
  }

  void _loadSavedData() {
    double savedCharge = prefs?.getDouble('chargeLevel') ?? 0.0;
    int lastTimeMs = prefs?.getInt('lastUpdateTime') ?? 0;
    _totalDrainSeconds = prefs?.getInt('totalDrainSeconds') ?? 2880;
    _autoRotateModel = prefs?.getBool('autoRotateModel') ?? true;

    if (savedCharge > 0) {
      DateTime lastTime = DateTime.fromMillisecondsSinceEpoch(lastTimeMs);
      int elapsedSeconds = DateTime.now().difference(lastTime).inSeconds;
      double drain = elapsedSeconds * (100.0 / _totalDrainSeconds);
      chargeLevel = savedCharge - drain;

      if (chargeLevel <= 0) {
        chargeLevel = 0.0;
        _countdownPlayed = true;
      } else {
        int rem = (chargeLevel / 100.0 * _totalDrainSeconds).ceil();
        if (rem <= 6) _countdownPlayed = true;
        _startDrain();
      }
    } else {
      chargeLevel = 0.0;
    }
    setState(() {
      _updateBlinkState();
    });
  }

  void _saveData() {
    prefs?.setDouble('chargeLevel', chargeLevel);
    prefs?.setInt('lastUpdateTime', DateTime.now().millisecondsSinceEpoch);
    prefs?.setInt('totalDrainSeconds', _totalDrainSeconds);
    prefs?.setBool('autoRotateModel', _autoRotateModel);
  }

  void _checkInAppThresholds(double oldCharge, double newCharge) {
    const thresholds = [20.0, 15.0, 10.0];
    for (double t in thresholds) {
      if (oldCharge > t && newCharge <= t) {
        _LanternHaptics.heavy();
        unawaited(_playInstant(_depletionPlayer, _depletionFile));
      }
    }
  }

  void _startDrain() {
    _drainTimer?.cancel();
    _lastDrainTick = DateTime.now();
    _drainTimer = Timer.periodic(const Duration(seconds: 1), (_) => _drainTick());
  }

  void _drainTick() {
    if (!mounted) return;
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastDrainTick).inMilliseconds;
    _lastDrainTick = now;
    if (elapsedMs <= 0) return;

    setState(() {
      if (chargeLevel > 0) {
        final double prevCharge = chargeLevel;
        chargeLevel -= (elapsedMs / 1000.0) * (100.0 / _totalDrainSeconds);

        if (chargeLevel <= 0) {
          chargeLevel = 0;
          _drainTimer?.cancel();
        }

        final bool caughtUp = elapsedMs > 3000;
        if (!caughtUp) _checkInAppThresholds(prevCharge, chargeLevel);
        _updateBlinkState();

        final int prevRemaining = (prevCharge / 100.0 * _totalDrainSeconds).ceil();
        final int remainingSeconds = (chargeLevel / 100.0 * _totalDrainSeconds).ceil();
        if (remainingSeconds <= 6 && caughtUp) {
          _countdownPlayed = true;
        } else if (prevRemaining > 6 && remainingSeconds <= 6 && !_countdownPlayed) {
          _countdownPlayed = true;
          unawaited(_playInstant(_countdownPlayer, _countdownFile));
        }
        _saveData();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && chargeLevel > 0) _drainTick();
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidNotif =>
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> _ensureNotificationAccess({bool showMessage = true}) async {
    final android = _androidNotif;
    if (android == null) return true;

    bool enabled = true;
    try {
      enabled = await android.areNotificationsEnabled() ?? true;
      if (!enabled) enabled = await android.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint("Notification permission check failed: $e");
    }

    try {
      final exact = await android.canScheduleExactNotifications() ?? true;
      if (!exact) await android.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint("Exact alarm permission check failed: $e");
    }

    if (!enabled && showMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 6),
          content: Text("Notifications are blocked for this app. Turn them on in system settings to get battery alerts."),
        ),
      );
    }
    return enabled;
  }

  Future<bool> _ensureSpeechReady() async {
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
    }
    if (!micStatus.isGranted) return false;

    if (_speechEnabled) return true;

    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (e) {
          debugPrint("Speech error: ${e.errorMsg}");
          if (_preferOnDevice) {
            _preferOnDevice = false;
          }
        },
        onStatus: (status) {
          if ((status == 'notListening' || status == 'done') &&
              _isPressing &&
              !_oathTriggered) {
            final id = _pressId;
            Future.delayed(const Duration(milliseconds: 150), () {
              if (_isPressing && id == _pressId && !_speechToText.isListening) {
                _listenForOath(id);
              }
            });
          }
          if (status == 'notListening' && _audioKnockMode && !isListeningForOath) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (_audioKnockMode && !isListeningForOath && chargeLevel == 0.0) {
                _startContinuousListening();
              }
            });
          }
        },
      );
    } catch (e) {
      debugPrint("Speech init error: $e");
      _speechEnabled = false;
    }
    return _speechEnabled;
  }

  Future<void> _scheduleQuickChargeAlert() async {
    await _notifReady.future;
    await _ensureNotificationAccess(showMessage: false);
    await flutterLocalNotificationsPlugin.cancelAll();
    final secs = (_totalDrainSeconds * 0.05).toInt();
    await _scheduleAlert(5, "Ring Depleted", "Battery at 0%. Charge immediately.", secs < 1 ? 1 : secs, customSound: false);
  }

  Future<void> _scheduleNotifications() async {
    await _notifReady.future;
    await _ensureNotificationAccess();
    await flutterLocalNotificationsPlugin.cancelAll();

    await _scheduleAlert(1, "Ring Battery Low", "Battery at 20%. Charge immediately.", (_totalDrainSeconds * 0.80).toInt(), customSound: true);
    await _scheduleAlert(2, "Ring Battery Low", "Battery at 15%. Charge immediately.", (_totalDrainSeconds * 0.85).toInt(), customSound: true);
    await _scheduleAlert(3, "Ring Battery Low", "Battery at 10%. Charge immediately.", (_totalDrainSeconds * 0.90).toInt(), customSound: true);
    await _scheduleAlert(4, "Ring Battery Low", "Battery at 5%. Charge immediately.", (_totalDrainSeconds * 0.95).toInt(), customSound: false);
    await _scheduleAlert(5, "Ring Depleted", "Battery at 0%. Charge immediately.", _totalDrainSeconds, customSound: false);

    try {
      final pending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      debugPrint("Scheduled alerts pending: ${pending.length} (expected 5)");
    } catch (e) {
      debugPrint("Pending check failed: $e");
    }
  }

  Future<void> _scheduleAlert(int id, String title, String body, int seconds, {required bool customSound}) async {
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    Future<void> doSchedule(AndroidScheduleMode mode) {
      return flutterLocalNotificationsPlugin.zonedSchedule(
        id: id, title: title, body: body, scheduledDate: when,
        notificationDetails: customSound ? _depletionNotificationDetails : _notificationDetails,
        androidScheduleMode: mode,
      );
    }
    const modes = [
      AndroidScheduleMode.alarmClock,
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ];
    for (final mode in modes) {
      try {
        await doSchedule(mode);
        debugPrint("Alert $id scheduled in ${seconds}s using $mode");
        return;
      } catch (e) {
        debugPrint("Alert $id: $mode failed: $e");
      }
    }
    debugPrint("Alert $id could not be scheduled at all");
  }

  void _restartRing() async {
    _LanternHaptics.medium();
    await _notifReady.future;
    _drainTimer?.cancel();
    _handoffTimer?.cancel();
    _micDelayTimer?.cancel();
    _holdHapticTimer?.cancel();
    _tailWordTimer?.cancel();
    await flutterLocalNotificationsPlugin.cancelAll();

    setState(() {
      chargeLevel = 0.0;
      _knockCount = 0;
      _audioKnockMode = false;
      _spinMode = false;
      _countdownPlayed = false;
      _voiceNotifier.value = 0.0;
      _matchedWordCount = 0;
      _lastHapticWordIdx = 0;
      _oathProgress.value = 0.0;
      _updateBlinkState();
    });

    _saveData();
    await _speechToText.stop();
    await _setBeepMute(false);
  }

  void _triggerQuickCharge() {
    unawaited(_LanternHaptics.quickChargePulse());
    setState(() {
      if (chargeLevel == 0.0) {
        chargeLevel = 5.0;
        _countdownPlayed = false;
        _saveData();
        unawaited(_scheduleQuickChargeAlert());
        _updateBlinkState();
      }
    });
    unawaited(_playInstant(_quickChargePlayer, _quickChargeFile));
    _startDrain();
  }

  void _triggerFullCharge() async {
    unawaited(_LanternHaptics.fullChargeBlast());
    setState(() {
      chargeLevel = 100.0;
      _countdownPlayed = false;
      _updateBlinkState();
    });
    _saveData();
    _startDrain();
    await _scheduleNotifications();
  }

  void _startContinuousListening() async {
    final ready = await _ensureSpeechReady();
    if (ready && !_speechToText.isListening) {
      await _setBeepMute(true);
      await _speechToText.listen(
        onResult: (result) {},
        onSoundLevelChange: (level) {
          if (level > 9.8) {
            DateTime now = DateTime.now();
            int timeSinceLastSound = now.difference(_lastKnockTime).inMilliseconds;

            if (timeSinceLastSound > 150) {
              if (timeSinceLastSound > 800) {
                _knockCount = 1;
              } else {
                _knockCount++;
              }
              _lastKnockTime = now;

              if (_knockCount >= 2 && chargeLevel == 0.0) {
                _triggerQuickCharge();
                _knockCount = 0;
                setState(() => _audioKnockMode = false);
                _speechToText.stop();
                Future.delayed(const Duration(milliseconds: 400), () {
                  if (!_isPressing && !_audioKnockMode) _setBeepMute(false);
                });
              }
            }
          }
        },
        listenOptions: SpeechListenOptions(
          cancelOnError: false,
          listenFor: const Duration(minutes: 60),
          pauseFor: const Duration(minutes: 60),
        ),
      );
    }
  }

  void _startListeningForOath() async {
    _isPressing = true;
    _oathTriggered = false;
    _oathDetected = false;
    _oathHistory = '';
    _currentText = '';
    _matchedWordCount = 0;
    _lastHapticWordIdx = 0;
    _oathProgress.value = 0.0;
    _pressStartedAt = DateTime.now();
    _startOathTicker();
    _voiceNotifier.value = 0.0;
    final id = ++_pressId;

    unawaited(_LanternHaptics.holdLockOn());
    _holdHapticTimer?.cancel();
    int tickCount = 0;
    _holdHapticTimer = Timer.periodic(const Duration(milliseconds: 220), (timer) {
      if (!_isPressing || id != _pressId) {
        timer.cancel();
        return;
      }
      tickCount++;
      if (_oathTriggered) {
        _LanternHaptics.toggle();
      } else if (_voiceNotifier.value <= 2.0 && tickCount % 2 == 0) {
        _LanternHaptics.spinDetent(velocity: 0.4);
      }
    });

    setState(() => isListeningForOath = true);
    unawaited(_setBeepMute(true));

    if (_audioReady) {
      _handoffTimer?.cancel();
      unawaited(_haltPlayer(_oathPlayer));
      unawaited(_haltPlayer(_releasePlayer));
      unawaited(_playInstant(_holdPlayer, _holdFile, onlyWhilePressing: true));

      _handoffTimer = Timer(const Duration(milliseconds: 1000), () {
        if (_isPressing && id == _pressId) {
          unawaited(_playInstant(_oathPlayer, _oathFile, onlyWhilePressing: true));
        }
      });
    }

    _micDelayTimer?.cancel();
    _micDelayTimer = Timer(const Duration(milliseconds: 150), () async {
      if (!_isPressing || id != _pressId) return;
      final ready = await _ensureSpeechReady();
      if (ready && _isPressing && id == _pressId) {
        _listenForOath(id);
      }
    });
  }

  Future<void> _listenForOath(int id) async {
    if (!_speechEnabled || !_isPressing || id != _pressId) return;
    if (_speechToText.isListening) return;

    if (_currentText.isNotEmpty) {
      _oathHistory = '$_oathHistory $_currentText';
      _currentText = '';
    }

    try {
      await _setBeepMute(true);
      await _speechToText.listen(
        onResult: (result) {
          if (id != _pressId) return;
          
          if (mounted && isListeningForOath) {
            setState(() {
              _currentText = result.recognizedWords;
              _updateKaraokeProgress('$_oathHistory $_currentText');
            });
            final int ms = DateTime.now().difference(_pressStartedAt).inMilliseconds;
            debugPrint('[oath] +${ms}ms final=${result.finalResult} matched=$_matchedWordCount "${result.recognizedWords}"');
          }
        },
        onSoundLevelChange: (level) {
          if (mounted && isListeningForOath) {
            _voiceNotifier.value = level;
            // Live voice-reactive vibration as you speak into the ring
            if (level > 2.0 && !_oathTriggered) {
              _LanternHaptics.voiceResonance(level);
            }
          }
        },
        listenOptions: SpeechListenOptions(
          cancelOnError: false,
          partialResults: true,
          listenMode: ListenMode.deviceDefault,
          onDevice: _preferOnDevice,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 30),
        ),
      );
    } catch (e) {
      debugPrint("Oath listen error: $e");
    }
  }

  void _stopListening() async {
    if (!_isPressing) return;
    _isPressing = false;
    _handoffTimer?.cancel();
    _micDelayTimer?.cancel();
    _holdHapticTimer?.cancel();
    _tailWordTimer?.cancel();
    final id = _pressId;
    
    setState(() {
      isListeningForOath = false;
      _voiceNotifier.value = 0.0;
    });

    unawaited(_haltPlayer(_holdPlayer));
    unawaited(_haltPlayer(_oathPlayer));

    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    _updateKaraokeProgress('$_oathHistory $_currentText');

    final int totalWords = _oathWordAliases.length;
    if (!_oathTriggered && _matchedWordCount >= totalWords - 1) {
      _completeOathTrigger();
    }

    if (_oathTriggered) {
      unawaited(_playInstant(_releasePlayer, _releaseFile));
      _triggerFullCharge();
      _oathTriggered = false;
    } else {
      _LanternHaptics.tap();
    }

    if (mounted) {
      setState(() {
        _oathDetected = false;
      });
    }

    if (_audioKnockMode && chargeLevel == 0.0) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _startContinuousListening();
      });
    } else {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_isPressing && !_audioKnockMode && id == _pressId) {
          _setBeepMute(false);
        }
      });
    }
  }

  void _showCustomTimeDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F1A15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3))),
          title: const Text('Custom Drain Time', style: TextStyle(color: Colors.greenAccent)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Duration in minutes',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _LanternHaptics.tap();
                Navigator.pop(context);
              },
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                _LanternHaptics.toggle();
                int? mins = int.tryParse(controller.text);
                if (mins != null && mins > 0) {
                  setState(() {
                    _totalDrainSeconds = mins * 60;
                    _saveData();
                  });
                }
                Navigator.pop(context);
              },
              child: const Text('Set', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _setBeepMute(false);
    _blinkController.dispose();
    _drainTimer?.cancel();
    _handoffTimer?.cancel();
    _micDelayTimer?.cancel();
    _holdHapticTimer?.cancel();
    _tailWordTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _voiceNotifier.dispose();
    _oathTicker?.dispose();
    _oathProgress.dispose();
    _spinSyncRetry?.cancel();
    _speechToText.cancel();
    _holdPlayer.dispose();
    _oathPlayer.dispose();
    _releasePlayer.dispose();
    _quickChargePlayer.dispose();
    _depletionPlayer.dispose();
    _countdownPlayer.dispose();
    super.dispose();
  }

  Widget _buildDurationBtn(String label, int seconds) {
    bool isSelected = _totalDrainSeconds == seconds;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _LanternHaptics.toggle();
          if (seconds == -1) {
            _showCustomTimeDialog();
          } else {
            setState(() {
              _totalDrainSeconds = seconds;
              _saveData();
            });
          }
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.greenAccent.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(
              color: isSelected ? Colors.greenAccent : Colors.white24,
              width: isSelected ? 1.5 : 1.0,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.2), blurRadius: 10)] : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKaraokeOathText() {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _oathProgress,
        builder: (context, progress, _) {
          final List<InlineSpan> spans = [];
          int wordIdx = 0;

          for (int i = 0; i < _oathSegments.length; i++) {
            double amt;
            if (_oathSegmentIsWord[i]) {
              amt = (progress - wordIdx).clamp(0.0, 1.0).toDouble();
              wordIdx++;
            } else {
              amt = wordIdx == 0 ? 0.0 : (progress - (wordIdx - 1)).clamp(0.0, 1.0).toDouble();
            }
            amt = Curves.easeOut.transform(amt);

            spans.add(
              TextSpan(
                text: _oathSegments[i],
                style: TextStyle(
                  color: Color.lerp(Colors.white70, Colors.greenAccent, amt),
                  shadows: [
                    const Shadow(color: Colors.black, blurRadius: 4),
                    if (amt > 0.01)
                      Shadow(color: Colors.greenAccent.withValues(alpha: amt), blurRadius: 10 * amt),
                  ],
                ),
              ),
            );
          }

          return RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w800,
                fontFamily: 'Roboto',
              ),
              children: spans,
            ),
          );
        },
      ),
    );
  }

  Widget _buildRingLogo() {
    return Container(
      width: 48,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.2), blurRadius: 4)],
      ),
      child: Image.asset(
        'assets/ring_logo.png',
        fit: BoxFit.contain,
      ),
    );
  }

  String get _formattedTime {
    if (chargeLevel <= 0) return "";
    int totalSec = (chargeLevel / 100.0 * _totalDrainSeconds).ceil();
    int hours = totalSec ~/ 3600;
    int minutes = (totalSec % 3600) ~/ 60;
    int seconds = totalSec % 60;
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get _selectedDurationText {
    if (_totalDrainSeconds == 48) return "DURATION: 48 SEC";
    if (_totalDrainSeconds == 2880) return "DURATION: 48 MIN";
    if (_totalDrainSeconds == 172800) return "DURATION: 48 HR";
    return "DURATION: ${_totalDrainSeconds ~/ 60} MIN";
  }

  String _instructionText() {
    if (_spinMode) return "Spin Mode active. Drag to view 3D lantern.";
    if (_audioKnockMode) return "Double tap any surface to quick charge the ring.";
    return "Hold the ring to the lantern and recite the oath.";
  }

  Future<void> _finishTutorial() async {
    _LanternHaptics.toggle();
    if (mounted) setState(() => _showTutorial = false);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('hasSeenTutorial', true);
    } catch (e) {
      debugPrint("Tutorial flag save error: $e");
    }
  }

  Widget _buildTutorialOverlay() {
    final step = _tutorialSteps[_tutorialStep];
    final bool isFirst = _tutorialStep == 0;
    final bool isLast = _tutorialStep == _tutorialSteps.length - 1;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          color: Colors.black.withValues(alpha: 0.86),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
              child: Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: isLast
                          ? const SizedBox.shrink()
                          : TextButton(
                              onPressed: _finishTutorial,
                              child: const Text(
                                'SKIP',
                                style: TextStyle(color: Colors.white54, letterSpacing: 2, fontWeight: FontWeight.bold),
                              ),
                            ),
                    ),
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(_tutorialStep),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.greenAccent.withValues(alpha: 0.1),
                            border: Border.all(color: Colors.greenAccent, width: 2),
                            boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.35), blurRadius: 24)],
                          ),
                          child: Icon(step.icon, color: Colors.greenAccent, size: 44),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          step.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_tutorialSteps.length, (i) {
                      final active = i == _tutorialStep;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active ? Colors.greenAccent : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (!isFirst) ...[
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () {
                              _LanternHaptics.tap();
                              setState(() => _tutorialStep--);
                            },
                            child: Container(
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24, width: 1.5),
                              ),
                              child: const Text(
                                'BACK',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 3,
                        child: GestureDetector(
                          onTap: () {
                            if (isLast) {
                              _finishTutorial();
                            } else {
                              _LanternHaptics.tap();
                              setState(() => _tutorialStep++);
                            }
                          },
                          child: Container(
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.greenAccent, width: 2),
                              boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.4), blurRadius: 10)],
                            ),
                            child: Text(
                              isLast ? 'GET STARTED' : 'NEXT',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDischarged = chargeLevel <= 0.0;

    if (_prefsReady && _appliedSpin != _shouldSpin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncModelSpin();
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: _voiceNotifier,
              builder: (context, voiceLevel, _) {
                final double normalizedVoice = voiceLevel.clamp(0.0, 15.0).toDouble() / 15.0;
                final double bgRadius = isListeningForOath
                    ? 0.75 + (normalizedVoice * 0.65)
                    : 0.8 + (chargeLevel / 100) * 0.4;
                final double bgOpacity = isListeningForOath
                    ? 0.28 + (normalizedVoice * 0.55)
                    : 0.15 + ((chargeLevel / 100) * 0.15);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.1),
                      radius: bgRadius,
                      colors: [
                        Colors.greenAccent.withValues(alpha: bgOpacity.clamp(0.0, 1.0).toDouble()),
                        Colors.black,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          Positioned.fill(
            child: Center(
              child: Icon(
                Icons.adjust,
                size: 350,
                color: Colors.greenAccent.withValues(alpha: 0.03),
              ),
            ),
          ),

          // 3D Model Viewer wrapped in a translucent Listener so manual 3D spinning
          // triggers smooth iOS Digital Crown / scroll-wheel detent haptics!
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                _spinDragAccumulator = 0.0;
                if (_spinMode) {
                  _LanternHaptics.spinDetent(velocity: 0.8);
                }
              },
              onPointerMove: (e) {
                if (!_spinMode) return;
                final double delta = e.delta.distance;
                _spinDragAccumulator += delta;
                // Fire a crisp mechanical micro-tick every 11 logical pixels of rotation drag
                if (_spinDragAccumulator >= 11.0) {
                  _spinDragAccumulator %= 11.0;
                  _LanternHaptics.spinDetent(velocity: (delta / 8.0).clamp(0.4, 3.0));
                }
              },
              child: AnimatedScale(
                scale: isListeningForOath ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                child: !_prefsReady
                    ? const SizedBox.shrink()
                    : ModelViewer(
                        key: ValueKey(_lantern.id),
                        src: _lantern.modelAsset,
                        alt: 'Power Battery',
                        autoRotate: _initialSpin,
                        autoRotateDelay: 0,
                        rotationPerSecond: '20deg', 
                        cameraOrbit: _lantern.cameraOrbit,
                        fieldOfView: _lantern.fieldOfView,
                        cameraControls: true,
                        backgroundColor: Colors.transparent,
                        interactionPrompt: InteractionPrompt.none,
                        relatedJs: _modelControlJsFor(_lantern.frontDeg),
                        onWebViewCreated: (controller) {
                          _modelController = controller;
                          _syncModelSpin();
                        },
                      ),
              ),
            ),
          ),

          if (!_spinMode)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  if (_isPressing) return;
                  if (!isDischarged) {
                    // Subtle feedback tap if user touches the lantern while already charged
                    _LanternHaptics.spinDetent(velocity: 0.6);
                    return;
                  }
                  _activePointer = e.pointer;
                  _startListeningForOath();
                },
                onPointerUp: (e) {
                  if (e.pointer != _activePointer) return;
                  _activePointer = null;
                  _stopListening();
                },
                onPointerCancel: (e) {
                  if (e.pointer != _activePointer) return;
                  _activePointer = null;
                  _stopListening();
                },
                child: Container(color: Colors.transparent),
              ),
            ),

          Positioned(
            top: MediaQuery.of(context).size.height * 0.32,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: isListeningForOath ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: _buildKaraokeOathText(),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _showLanternPicker,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.35), blurRadius: 10)],
                            ),
                            child: Image.asset(
                              'assets/image_aeb43c.png',
                              width: 34,
                              height: 34,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => const Icon(Icons.adjust, color: Colors.greenAccent, size: 28),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'LANTERN ',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2),
                          ),
                          const Text(
                            'CORE',
                            style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 2),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: isListeningForOath ? Colors.white : Colors.greenAccent,
                              shape: BoxShape.circle,
                              boxShadow: const [BoxShadow(color: Colors.greenAccent, blurRadius: 6)],
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        right: 0,
                        child: PopupMenuButton<int>(
                          icon: const Icon(Icons.settings_outlined, color: Colors.white70, size: 26),
                          color: const Color(0xFF0F1A15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.3)),
                          ),
                          offset: const Offset(0, 45),
                          onOpened: _LanternHaptics.tap,
                          onSelected: (value) {
                            _LanternHaptics.toggle();
                            if (value == 0) {
                              setState(() => _audioKnockMode = !_audioKnockMode);
                              if (_audioKnockMode) {
                                _startContinuousListening();
                              } else {
                                _speechToText.stop();
                                Future.delayed(const Duration(milliseconds: 400), () {
                                  if (!_isPressing) _setBeepMute(false);
                                });
                              }
                            } else if (value == 1) {
                              _restartRing();
                            } else if (value == 2) {
                              setState(() => _spinMode = !_spinMode);
                            } else if (value == 3) {
                              setState(() {
                                _autoRotateModel = !_autoRotateModel;
                                _saveData();
                              });
                            } else if (value == 4) {
                              setState(() {
                                _tutorialStep = 0;
                                _showTutorial = true;
                              });
                            }
                          },
                          itemBuilder: (context) {
                            List<PopupMenuEntry<int>> menuItems = [];
                            
                            if (isDischarged) {
                              menuItems.addAll([
                                PopupMenuItem(
                                  value: 0,
                                  child: Row(
                                    children: [
                                      Icon(Icons.touch_app, color: _audioKnockMode ? Colors.greenAccent : Colors.white70),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Knock Charge', style: TextStyle(color: _audioKnockMode ? Colors.greenAccent : Colors.white, fontWeight: FontWeight.bold)),
                                          const Text('Double tap table', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(height: 1),
                              ]);
                            }

                            menuItems.addAll([
                              PopupMenuItem(
                                value: 1,
                                child: Row(
                                  children: [
                                    const Icon(Icons.restart_alt, color: Colors.white70),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Text('Reset Ring', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        Text('Clear charge to 0%', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              PopupMenuItem(
                                value: 2,
                                child: Row(
                                  children: [
                                    Icon(Icons.threed_rotation, color: _spinMode ? Colors.greenAccent : Colors.white70),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Spin Mode', style: TextStyle(color: _spinMode ? Colors.greenAccent : Colors.white, fontWeight: FontWeight.bold)),
                                        const Text('Interact with 3D model', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              PopupMenuItem(
                                value: 3,
                                child: Row(
                                  children: [
                                    Icon(Icons.autorenew, color: _autoRotateModel ? Colors.greenAccent : Colors.white70),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Auto Spin', style: TextStyle(color: _autoRotateModel ? Colors.greenAccent : Colors.white, fontWeight: FontWeight.bold)),
                                        const Text('Lantern spins automatically', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              PopupMenuItem(
                                value: 4,
                                child: Row(
                                  children: [
                                    const Icon(Icons.help_outline, color: Colors.white70),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Text('Tutorial', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        Text('Replay the walkthrough', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ]);

                            // 🟢 ADDING YOUR SIGNATURE HERE
                            menuItems.addAll([
                              const PopupMenuDivider(height: 1),
                              const PopupMenuItem(
                                enabled: false,
                                height: 35, // Keeps it compact
                                child: Center(
                                  child: Text(
                                    'Developed By - Saqib Mukadam/SM Labs', 
                                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ]);

                            return menuItems;
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _blinkController,
                    builder: (context, child) {
                      bool isLowBattery = chargeLevel > 0 && chargeLevel <= 10.0;
                      
                      Color baseColor = (isDischarged || isLowBattery) ? Colors.redAccent : Colors.white;
                      Color glowColor = (isDischarged || isLowBattery) ? Colors.redAccent.withValues(alpha: 0.8) : Colors.greenAccent.withValues(alpha: 0.8);
                      Color remainingColor = (isDischarged || isLowBattery) ? Colors.redAccent : Colors.greenAccent;
                      
                      double currentOpacity = isLowBattery ? _blinkController.value : 1.0;

                      return Opacity(
                        opacity: currentOpacity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 10),
                            Text(
                              'CORE CHARGE',
                              style: TextStyle(color: (isDischarged || isLowBattery) ? Colors.redAccent.withValues(alpha: 0.7) : Colors.white60, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${chargeLevel.ceil()}%',
                              style: TextStyle(
                                color: baseColor,
                                fontSize: 56,
                                fontWeight: FontWeight.bold,
                                shadows: [Shadow(color: glowColor, blurRadius: 15)],
                              ),
                            ),
                            if (chargeLevel > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '$_formattedTime remaining',
                                style: TextStyle(
                                  color: remainingColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                  shadows: const [Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2))],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const Expanded(
                  child: IgnorePointer(
                    child: SizedBox(),
                  ),
                ),

                if (!_isPressing && !_spinMode)
                  if (isDischarged)
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF030D08).withValues(alpha: 0.85),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3), width: 1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'CHARGE DURATION',
                            style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildDurationBtn("48 sec", 48),
                              _buildDurationBtn("48 min", 2880),
                              _buildDurationBtn("48 hr", 172800),
                              _buildDurationBtn("Custom", -1),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              _buildRingLogo(),
                              Container(
                                width: 1,
                                height: 35,
                                color: Colors.greenAccent.withValues(alpha: 0.2),
                                margin: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              Expanded(
                                child: Text(
                                  _instructionText(),
                                  style: TextStyle(
                                    color: _oathDetected ? Colors.greenAccent : Colors.white60, 
                                    fontSize: 13, 
                                    height: 1.4
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      margin: const EdgeInsets.only(bottom: 40),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3), width: 1.5),
                          boxShadow: [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.1), blurRadius: 10)],
                        ),
                        child: Text(
                          _selectedDurationText,
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 13,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          if (_showTutorial) _buildTutorialOverlay(),
        ],
      ),
    );
  }
}