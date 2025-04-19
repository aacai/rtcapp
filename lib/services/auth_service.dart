import 'dart:convert';

import 'package:crypto/crypto.dart';

class AuthService {
  /// 生成视频通话的JWT令牌
  ///
  /// [roomName] - 房间名称
  /// [identity] - 用户标识
  /// [expiresIn] - 令牌有效期，可选值：
  ///   - 1小时 (1h)
  ///   - 6小时 (6h)
  ///   - 24小时 (24h)
  ///   - 168小时 (7天)
  ///   - 720小时 (30天)
  ///   - 8760小时 (1年)
  /// [key] - API密钥
  /// [secret] - API密钥对应的密钥
  static String generateVideoToken(String roomName, String identity,
      Duration expiresIn, String key, String secret) {
    final now = DateTime.now().toUtc();
    final nbf = now.millisecondsSinceEpoch ~/ 1000;
    final exp = now.add(expiresIn).millisecondsSinceEpoch ~/ 1000;
    final header = {'alg': 'HS256', 'typ': 'JWT'};
    final videoGrants = {
      'room': roomName,
      'roomJoin': true,
      'canPublish': true,
      'canSubscribe': true,
    };

    final claims = {
      'iss': key,
      'nbf': nbf,
      'exp': exp,
      'sub': identity,
      'video': videoGrants,
    };

    String base64UrlEncodeNoPadding(String str) =>
        base64Url.encode(utf8.encode(str)).replaceAll('=', '');

    final encodedHeader = base64UrlEncodeNoPadding(json.encode(header));
    final encodedPayload = base64UrlEncodeNoPadding(json.encode(claims));
    final message = '$encodedHeader.$encodedPayload';

    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode(message));
    final signature = base64Url.encode(digest.bytes).replaceAll('=', '');

    return '$encodedHeader.$encodedPayload.$signature';
  }
}
