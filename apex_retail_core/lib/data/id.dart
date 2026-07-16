import 'dart:math';

final _rand = Random();

/// Mirrors the original `generateId` — 9 uppercase base36 chars.
String genId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(9, (_) => chars[_rand.nextInt(chars.length)]).join();
}

/// Random integer in [min, max] inclusive.
int randInt(int min, int max) => min + _rand.nextInt(max - min + 1);

/// Mints a product id. `id` is the sync primary key both clients upsert into,
/// so the React web app must mint these identically — see `generateProductId`
/// in `src/utils/localDB.ts`. The old `P###` form had only 900 values, so two
/// terminals adding products on the same day could collide and silently
/// overwrite each other. Time prefix keeps ids roughly ordered; the random
/// suffix separates products created within the same millisecond. Legacy `P###`
/// ids stay valid — nothing parses this format, it only has to be unique.
String genProductId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final ts =
      DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
  final suffix = List.generate(4, (_) => chars[_rand.nextInt(chars.length)]).join();
  return 'P$ts$suffix';
}
