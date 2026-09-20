import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_state.dart';

// ─── API Service ─────────────────────────────────────────────────────────────
// Calls the Python Flask backend (app.py running at _base URL).
// Change _base to your backend URL:
//   Android emulator → http://10.0.2.2:5000
//   Physical device  → http://<your-machine-local-ip>:5000
//   Desktop/Web      → http://localhost:5000

class ApiService {
  // ─────────────────────────────────────────────────────────────────────────
  // Backend configuration
  // ─────────────────────────────────────────────────────────────────────────

  // Vercel production backend
  static const String _vercelBase = 'https://mumsai.vercel.app';

  // Local Flask backend - physical Android phone
  static const String _localAndroidBase = 'http://10.38.142.57:5000';

  // Local Flask backend - desktop/web
  static const String _localDesktopBase = 'http://localhost:5000';

  // true  = use Vercel
  // false = use local Flask server
  static const bool useVercel = true;

  static String get _base {
    if (useVercel) {
      return _vercelBase;
    }

    if (kIsWeb) {
      return _localDesktopBase;
    }

    return _localAndroidBase;
  }

  static Future<http.Response> _post(
      String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base$path');

    return await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? dob,
    String? age,
    String? gender,
  }) async {
    final resp = await _post('/register', {
      'name': name,
      'email': email,
      'password': password,
      'dob': dob,
      'age': age,
      'gender': gender,
    });
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 201) {
      throw ApiException(j['error'] ?? 'Registration failed');
    }
    return j;
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final resp = await _post('/login', {
      'email': email,
      'password': password,
    });
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw ApiException(j['error'] ?? 'Login failed');
    }
    return j;
  }

  // ── Sync ──────────────────────────────────────────────────────────────────
  static Future<void> syncHistory(
      String email, List<SessionRecord> history) async {
    final resp = await _post('/sync-history', {
      'email': email,
      'history': history.map((s) => s.toJson()).toList(),
    });
    if (resp.statusCode != 200) {
      throw ApiException('History sync failed (${resp.statusCode})');
    }
  }

  static Future<List<SessionRecord>> getHistory(String email) async {
    final resp = await _post('/get-history', {'email': email});
    if (resp.statusCode != 200) {
      throw ApiException('Failed to fetch history (${resp.statusCode})');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = j['history'] as List<dynamic>;
    return list.map((e) => SessionRecord.fromJson(e)).toList();
  }

  static Future<void> syncPreferences(
      String email, List<BlockedSong> blocked, List<BlockedSong> liked) async {
    final resp = await _post('/sync-preferences', {
      'email': email,
      'blocked': blocked.map((b) => b.toJson()).toList(),
      'liked': liked.map((l) => l.toJson()).toList(),
    });
    if (resp.statusCode != 200) {
      throw ApiException('Preferences sync failed (${resp.statusCode})');
    }
  }

  static Future<Map<String, List<BlockedSong>>> getPreferences(
      String email) async {
    final resp = await _post('/get-preferences', {'email': email});
    if (resp.statusCode != 200) {
      throw ApiException('Failed to fetch preferences (${resp.statusCode})');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final blocked = (j['blocked'] as List<dynamic>)
        .map((e) => BlockedSong.fromJson(e))
        .toList();
    final liked = (j['liked'] as List<dynamic>)
        .map((e) => BlockedSong.fromJson(e))
        .toList();
    return {'blocked': blocked, 'liked': liked};
  }

  // ── /detect-mood ──────────────────────────────────────────────────────────
  static Future<MoodDetectResult> detectMood(String text) async {
    final resp = await _post('/detect-mood', {'text': text});
    if (resp.statusCode != 200) {
      throw ApiException('Mood detection failed (${resp.statusCode})');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return MoodDetectResult.fromJson(j);
  }

  // ── /get-song ─────────────────────────────────────────────────────────────
  static Future<SongBatch> getSongs({
    required String text,
    required List<String> languages,
    String email = '',
    List<BlockedSong> blocked = const [],
    List<BlockedSong> liked = const [],
    int limit = 20,
  }) async {
    final resp = await _post('/get-song', {
      'text': text,
      'languages': languages,
      'email': email,
      'limit': limit,
      'blocked': blocked.map((b) => b.toJson()).toList(),
      'liked': liked.map((l) => l.toJson()).toList(),
    });

    if (resp.statusCode != 200) {
      throw ApiException(
          'Song fetch failed (${resp.statusCode}): ${resp.body}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return SongBatch.fromJson(j);
  }

  // ── /api/lifecycle ────────────────────────────────────────────────────────
  static Future<void> sendLifecycle(String email, String status) async {
    try {
      // we need user_id or email, let's use email to find user on backend
      await _post('/api/lifecycle', {'email': email, 'status': status});
    } catch (e) {
      debugPrint('ApiService: sendLifecycle error: $e');
    }
  }

  // ── /log-song ─────────────────────────────────────────────────────────────
  static Future<void> logSong({
    required String email,
    required String mood,
    required String title,
    required String artist,
    required String action, // 'played' or 'skipped'
  }) async {
    try {
      await _post('/log-song', {
        'email': email,
        'mood': mood,
        'title': title,
        'artist': artist,
        'action': action,
      });
    } catch (e) {
      debugPrint('ApiService: logSong error: $e');
    }
  }

  // ── /clear-played-songs ───────────────────────────────────────────────────
  static Future<void> clearPlayedSongs({required String email}) async {
    try {
      await _post('/clear-played-songs', {'email': email});
    } catch (e) {
      debugPrint('ApiService: clearPlayedSongs error: $e');
    }
  }

  // ── /unlog-songs ──────────────────────────────────────────────────────────
  static Future<void> unlogSongs({
    required String email,
    required List<Map<String, dynamic>> songs,
  }) async {
    try {
      await _post('/unlog-songs', {'email': email, 'songs': songs});
    } catch (e) {
      debugPrint('ApiService: unlogSongs error: $e');
    }
  }

  // ── /log-session-outcome ─────────────────────────────────────────────────
  static Future<void> logSessionOutcome({
    required String email,
    required String startMood,
    required String endMood,
    required int startIntensity,
    required int endIntensity,
    required int songsPlayedCount,
    required int songsSkippedCount,
    required int likedSongsCount,
    required bool moodImproved,
    required int durationSecs,
    required String sessionDate, // ISO 8601
  }) async {
    try {
      await _post('/log-session-outcome', {
        'email': email,
        'start_mood': startMood,
        'end_mood': endMood,
        'start_intensity': startIntensity,
        'end_intensity': endIntensity,
        'songs_played_count': songsPlayedCount,
        'songs_skipped_count': songsSkippedCount,
        'liked_songs_count': likedSongsCount,
        'mood_improved': moodImproved,
        'session_duration_secs': durationSecs,
        'session_date': sessionDate,
      });
    } catch (e) {
      debugPrint('ApiService: logSessionOutcome error: $e');
    }
  }

  // ── /get-ai-insights ─────────────────────────────────────────────────────
  static Future<List<String>> getAiInsights({required String email}) async {
    try {
      final resp = await _post('/get-ai-insights', {'email': email});
      if (resp.statusCode != 200) return [];
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return (j['insights'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
    } catch (e) {
      debugPrint('ApiService: getAiInsights error: $e');
      return [];
    }
  }

  // ── /get-feature-toggles ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getFeatureToggles() async {
    try {
      final uri = Uri.parse('$_base/get-feature-toggles');

      final resp = await http.get(uri).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }

      debugPrint(
        'ApiService: getFeatureToggles failed: ${resp.statusCode}',
      );
    } catch (e) {
      debugPrint('ApiService: getFeatureToggles error: $e');
    }

    return {};
  }

  // ── /get-branding ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getBranding() async {
    try {
      final uri = Uri.parse('$_base/get-branding');

      final resp = await http.get(uri).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }

      debugPrint(
        'ApiService: getBranding failed: ${resp.statusCode}',
      );
    } catch (e) {
      debugPrint('ApiService: getBranding error: $e');
    }

    return {};
  }

  // ── /youtube-search ───────────────────────────────────────────────────────
  static Future<String?> getYouTubeVideoId(String query) async {
    try {
      final resp = await _post('/youtube-search', {'query': query});
      if (resp.statusCode != 200) {
        throw ApiException(
            'YouTube search failed (${resp.statusCode}): ${resp.body}');
      }
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return j['videoId'] as String?;
    } catch (e) {
      debugPrint('ApiService: getYouTubeVideoId error: $e');
      rethrow;
    }
  }
}

// ─── Result types ─────────────────────────────────────────────────────────────

class MoodDetectResult {
  final String mood;
  final int intensity;
  final String? label;

  const MoodDetectResult({
    required this.mood,
    required this.intensity,
    this.label,
  });

  factory MoodDetectResult.fromJson(Map<String, dynamic> j) => MoodDetectResult(
        mood: j['mood'] as String? ?? 'Neutral',
        intensity: (j['intensity'] as num?)?.toInt() ?? 50,
        label: j['label'] as String?,
      );
}

class SongBatch {
  final String currentMood;
  final String targetMood;
  final int intensity;
  final List<String> languages;
  final List<SongResult> songs;

  const SongBatch({
    required this.currentMood,
    required this.targetMood,
    required this.intensity,
    required this.languages,
    required this.songs,
  });

  factory SongBatch.fromJson(Map<String, dynamic> j) => SongBatch(
        currentMood: j['current_mood'] as String? ?? 'Neutral',
        targetMood: j['target_mood'] as String? ?? 'Happy',
        intensity: (j['intensity'] as num?)?.toInt() ?? 50,
        languages: (j['languages'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        songs: (j['songs'] as List<dynamic>? ?? [])
            .map((e) => SongResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => 'ApiException: $message';
}
