import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const webBaseUrl =
    String.fromEnvironment('WEB_URL', defaultValue: 'https://wuarikes.com');

Future<void> openExternal(BuildContext context, String url) async {
  try {
    final uri = Uri.parse(url);
    if (!['https', 'http', 'tel', 'mailto'].contains(uri.scheme))
      throw const FormatException();
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication))
      throw const FormatException();
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el enlace.')));
  }
}

Future<void> sharePlace(BuildContext context, String id, String name) async {
  try {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
        text: '$name\n$webBaseUrl/restaurantes/$id',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size));
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo compartir.')));
  }
}

Future<void> inviteFriends(BuildContext context) async {
  try {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
        text: '¡Únete a Wuarikes y descubre los mejores huariques de Lima!\n$webBaseUrl',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size));
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo compartir la invitación.')));
  }
}
