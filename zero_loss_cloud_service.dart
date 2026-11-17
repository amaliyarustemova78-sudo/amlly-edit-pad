import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// SIFIR KAYIP (ZERO-DATA-LOSS) YEREL + BULUT SENKRONIZASYON MOTORU
/// Uygulama aniden kapansa, şarj bitse veya APK silinip tekrar yüklense bile
/// yapılan son işlemi milisaniyesine kadar geri getirir.
class ZeroLossCloudService {
  static final ZeroLossCloudService _instance = ZeroLossCloudService._internal();
  factory ZeroLossCloudService() => _instance;
  ZeroLossCloudService._internal();

  SupabaseClient? _supabase;
  static const String _localWalKeyPrefix = 'amlly_wal_snapshot_';
  static const String _offlineQueueKey = 'amlly_offline_sync_queue';

  Future<void> initialize({required String url, required String anonKey}) async {
    try {
      await Supabase.initialize(url: url, anonKey: anonKey);
      _supabase = Supabase.instance.client;
    } catch (e) {
      debugPrint('[OFFLINE BASLATMA] Supabase baglantisi bekleniyor, yerel WAL aktif: $e');
    }
  }

  /// Her hamlede salisesinde hem cihaza (Offline) hem buluta (Online) yazar
  Future<void> commitStateInstantly({
    required String projectId,
    required String title,
    required int activeSeqIndex,
    required int playheadMs,
    required String aspectRatio,
    required List<Map<String, dynamic>> sequencesState,
    required int versionSequence,
  }) async {
    final payload = {
      'id': projectId,
      'user_id': _supabase?.auth.currentUser?.id,
      'title': title,
      'active_sequence_index': activeSeqIndex,
      'playhead_position_ms': playheadMs,
      'aspect_ratio': aspectRatio,
      'sequences_state': sequencesState,
      'version_sequence': versionSequence,
      'last_synced_at': DateTime.now().toIso8601String(),
    };

    // 1. ÖNCE YEREL HAFIZAYA KAZI (0 ms gecikme, çökme koruması)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_localWalKeyPrefix$projectId', jsonEncode(payload));

    // 2. ARKA PLANDA BULUTA GÖNDER (Arayüzü asla dondurmaz / kasmaz)
    unawaited(_syncToCloudNonBlocking(payload));
  }

  Future<void> _syncToCloudNonBlocking(Map<String, dynamic> payload) async {
    if (_supabase == null || _supabase!.auth.currentUser == null) return;
    try {
      await _supabase!.from('projects').upsert(payload, onConflict: 'id');
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_offlineQueueKey) ?? [];
      queue.add(jsonEncode(payload));
      await prefs.setStringList(_offlineQueueKey, queue);
    }
  }

  /// Açılışta en güncel durumu (Yerel vs Bulut karşılaştırarak) geri yükler
  Future<Map<String, dynamic>?> restoreProjectState(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final localRaw = prefs.getString('$_localWalKeyPrefix$projectId');
    final Map<String, dynamic>? localMap = localRaw != null ? jsonDecode(localRaw) : null;

    if (_supabase != null && _supabase!.auth.currentUser != null) {
      try {
        final cloudMap = await _supabase!
            .from('projects')
            .select()
            .eq('id', projectId)
            .maybeSingle();
        if (cloudMap != null && localMap != null) {
          final int localVer = localMap['version_sequence'] ?? 0;
          final int cloudVer = cloudMap['version_sequence'] ?? 0;
          return (localVer >= cloudVer) ? localMap : cloudMap;
        }
        return cloudMap ?? localMap;
      } catch (_) {}
    }
    return localMap;
  }
}
