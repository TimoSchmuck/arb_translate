import 'dart:io';

import 'package:arb_translate/src/translate_options/translate_options.dart';
import 'package:arb_translate/src/translation_delegates/deepl_translation_delegate.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  group(
    'DeeplTranslationDelegate',
    () {
      setUpAll(
        () {
          if (Platform.environment['ARB_TRANSLATE_DEEPL_API_KEY']?.isEmpty ??
              true) {
            throw Exception(
                'Missing ARB_TRANSLATE_DEEPL_API_KEY environment variable');
          }
        },
      );

      DeeplTranslationDelegate createDelegate(Model model) {
        return DeeplTranslationDelegate(
          apiKey: Platform.environment['ARB_TRANSLATE_DEEPL_API_KEY']!,
          batchSize: 4096,
          context: context,
          useEscaping: false,
          relaxSyntax: false,
        );
      }

      for (final model in Model.deeplModels) {
        test(
          'returns a result from ${model.name}',
          () async {
            await tryTranslateWithDelegate(createDelegate(model));
          },
        );
      }
    },
  );
}
