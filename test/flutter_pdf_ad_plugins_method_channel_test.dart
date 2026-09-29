import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pdf_ad_plugins/flutter_pdf_ad_plugins_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String channelName = 'flutter_pdf_ad_plugins/native_ad_headline';
  const StandardMethodCodec codec = StandardMethodCodec();

  test('nativeAdHeadlineStream forwards the native headline payload', () async {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final Completer<void> listenCompleter = Completer<void>();

    messenger.setMockMessageHandler(channelName, (ByteData? message) async {
      final MethodCall call = codec.decodeMethodCall(message);
      if (call.method == 'listen') {
        listenCompleter.complete();
      }
      return codec.encodeSuccessEnvelope(null);
    });

    final MethodChannelFlutterPdfAdPlugins platform =
        MethodChannelFlutterPdfAdPlugins();
    final Future<Map<String, dynamic>> eventFuture =
        platform.nativeAdHeadlineStream.first;
    await listenCompleter.future;

    await messenger.handlePlatformMessage(
      channelName,
      codec.encodeSuccessEnvelope(<String, dynamic>{
        'headline': 'Test Ad: Sample',
        'isNextGenAdmob': false,
      }),
      (_) {},
    );

    expect(await eventFuture, <String, dynamic>{
      'headline': 'Test Ad: Sample',
      'isNextGenAdmob': false,
    });

    messenger.setMockMessageHandler(channelName, null);
  });
}
