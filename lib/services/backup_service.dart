import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../data/shop_repository.dart';

/// Sauvegarde chiffrée de la boutique (fichier .shopbook) et exports CSV.
///
/// Format : JSON { format, v, iter, salt, nonce, mac, data } où data est
/// l'export de la boutique chiffré en AES-256-GCM avec une clé dérivée du
/// mot de passe de sauvegarde (PBKDF2-HMAC-SHA256).
class BackupService {
  static const fileFormat = 'shopbook-encrypted-backup';
  static const iterations = 100000;

  static Future<SecretKey> _key(String password, List<int> salt, int iter) =>
      Pbkdf2.hmacSha256(iterations: iter, bits: 256).deriveKeyFromPassword(password: password, nonce: salt);

  static List<int> _random(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(256));
  }

  /// Chiffre les données exportées par [ShopRepository.exportData].
  static Future<Uint8List> encrypt(Map<String, Object?> data, String password, {int iter = iterations}) async {
    final salt = _random(16);
    final algo = AesGcm.with256bits();
    final box = await algo.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: await _key(password, salt, iter),
      nonce: _random(12),
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': fileFormat,
          'v': 1,
          'iter': iter,
          'salt': base64.encode(salt),
          'nonce': base64.encode(box.nonce),
          'mac': base64.encode(box.mac.bytes),
          'data': base64.encode(box.cipherText),
        }),
      ),
    );
  }

  /// Déchiffre un fichier de sauvegarde. Mauvais mot de passe ou fichier abîmé → [BusinessException].
  static Future<Map<String, Object?>> decrypt(Uint8List bytes, String password) async {
    Map<String, Object?> file;
    try {
      file = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
    } catch (_) {
      throw const BusinessException('Ce fichier n\'est pas une sauvegarde ShopBook');
    }
    if (file['format'] != fileFormat) {
      throw const BusinessException('Ce fichier n\'est pas une sauvegarde ShopBook');
    }
    try {
      final box = SecretBox(
        base64.decode(file['data'] as String),
        nonce: base64.decode(file['nonce'] as String),
        mac: Mac(base64.decode(file['mac'] as String)),
      );
      final key = await _key(password, base64.decode(file['salt'] as String), file['iter'] as int);
      final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
      return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
    } on SecretBoxAuthenticationError {
      throw const BusinessException('Mot de passe de sauvegarde incorrect');
    } catch (_) {
      throw const BusinessException('Sauvegarde illisible ou abîmée');
    }
  }

  static String _stamp() => DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());

  /// Partage un fichier généré (WhatsApp, Drive, e-mail...).
  static Future<void> shareFile(Uint8List bytes, String name, String mime, {String? text}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mime, name: name)],
        fileNameOverrides: [name],
        text: text,
      ),
    );
  }

  static Future<void> shareBackup(Uint8List bytes) => shareFile(
    bytes,
    'shopbook_${_stamp()}.shopbook',
    'application/octet-stream',
    text: 'Sauvegarde ShopBook (chiffrée)',
  );

  /// CSV en UTF-8 avec BOM : Excel affiche correctement les accents.
  static Future<void> shareCsv(String csv, String baseName) =>
      shareFile(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]), '${baseName}_${_stamp()}.csv', 'text/csv');

  /// Ouvre le sélecteur de fichiers ; null si annulé.
  static Future<Uint8List?> pickBackupFile() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Choisir la sauvegarde ShopBook');
    if (file == null) return null;
    return file.readAsBytes();
  }
}
