import 'dart:math';

final _rand = Random();

/// Mirrors the original `generateId` — 9 uppercase base36 chars.
String genId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(9, (_) => chars[_rand.nextInt(chars.length)]).join();
}

/// Random integer in [min, max] inclusive.
int randInt(int min, int max) => min + _rand.nextInt(max - min + 1);
