import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get portalClient => Supabase.instance.client;

final Completer<void> _portalReadyCompleter = Completer<void>();

/// Completes once Supabase.initialize() has finished (success or failure),
/// so screens reached via a direct URL can wait for it before checking auth.
Future<void> get portalReady => _portalReadyCompleter.future;

void markPortalReady() {
  if (!_portalReadyCompleter.isCompleted) _portalReadyCompleter.complete();
}
