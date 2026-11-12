import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Android / iOS / macOS : sqflite natif.
/// Windows / Linux : SQLite via FFI (la DLL est fournie par sqlite3_flutter_libs).
DatabaseFactory platformDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }
  // Fabrique du plugin sqflite (Android / iOS), pas celle de sqflite_common.
  return sqflite.databaseFactory;
}

/// Dossier de la base. Sur ordinateur : %APPDATA%\ShopBook (jamais le dossier
/// d'installation, qui n'est pas modifiable dans « Program Files »).
Future<String> platformDatabaseDir(DatabaseFactory f) async {
  if (Platform.isWindows || Platform.isLinux) {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return p.normalize(dir.path);
  }
  return f.getDatabasesPath();
}
