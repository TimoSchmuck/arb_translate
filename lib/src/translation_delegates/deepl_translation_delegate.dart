import 'dart:convert';

import 'package:arb_translate/src/flutter_tools/localizations_utils.dart';
import 'package:arb_translate/src/translation_delegates/translate_exception.dart';
import 'package:arb_translate/src/translation_delegates/translation_delegate.dart';
import 'package:dart_openai/dart_openai.dart';
import 'package:deepl_dart/deepl_dart.dart';

class DeeplTranslationDelegate extends TranslationDelegate {
  DeeplTranslationDelegate({
    required String apiKey,
    required super.batchSize,
    required super.context,
    required super.useEscaping,
    required super.relaxSyntax,
  }) : _apiKey = apiKey;

  late final String _apiKey;

  @override
  int get maxRetryCount => 5;
  @override
  int get maxParallelQueries => 5;
  @override
  Duration get queryBackoff => Duration(seconds: 5);

  @override
  Future<String> getModelResponse(
    Map<String, Object?> resources,
    LocaleInfo locale,
  ) async {
    final encodedResources = JsonEncoder.withIndent('  ').convert(resources);

    try {
      Translator translator = Translator(authKey: _apiKey, maxRetries: maxRetryCount);
      // Get available languages

      // Get usage
      Usage usage = await translator.getUsage();
      if (usage.anyLimitReached()) {
        throw QuotaExceededException();
      }

      List<Language> targetLanguages = await translator.getTargetLanguages();
      var list = targetLanguages.where((language) {
        return language.languageCode.toLowerCase() == locale.languageCode.toLowerCase();
      });
      if (list.isEmpty) {
        //'Language ${locale.languageCode} not supported. Supported are only ${targetLanguages.toString()
        throw UnsupportedUserLocationException();
      }
      List<String> texts = [];
      var json = jsonDecode(encodedResources);
      for (String entry in json.keys) {
        if (entry.startsWith("@")) {
          continue;
        }
        texts.add(json[entry].toString());
      }
      List<TextResult> result = await translator.translateTextList(
        texts,
        locale.languageCode,
        options: TranslateTextOptions(
          context: super.context,
        ),
      );
      //assumption: the order of the result entry is the same as the one send to Deepl
      int i = 0;
      for (String entry in json.keys) {
        if (entry.startsWith("@")) {
          continue;
        }
        String newValue = result[i].text;
        int depth = _getMaxNestingDepth(newValue);
        switch (depth) {
          case 0:
            json[entry] = newValue;
            break;
          case 1:
            //normal variables
            String oldEntry = json[entry];
            List<String> newVariables = _getBracketsLevel(newValue, 1);
            List<String> oldVariables = _getBracketsLevel(oldEntry, 1);

            int j = 0;
            for (String newVariable in newVariables) {
              newValue = newValue.replaceAll(newVariable, oldVariables[j]);
              j++;
            }
            json[entry] = newValue;
            break;
          case 2:
          case 3:
            //complex expressions variables, extract 1 level
            String oldEntry = json[entry];
            List<String> newVariables = _getBracketsLevel(newValue, 2);
            List<String> oldVariables = _getBracketsLevel(oldEntry, 2);
            int j = 0;
            for (String newVariable in newVariables) {
              if (_getMaxNestingDepth(newVariable) > 1) {
                List<String> newVariables2 = _getBracketsLevel(newVariable, 2);
                List<String> oldVariables2 = _getBracketsLevel(oldVariables[j], 2);
                oldVariables[j] = oldVariables[j].replaceAll('{${oldVariables[j]}', '{$newVariable}');
                newVariable = newVariable.replaceAll(newVariables2.first, oldVariables2.first);
                oldEntry = oldEntry.replaceAll(oldVariables[j], newVariable);
              } else {
                oldEntry = oldEntry.replaceAll(oldVariables[j], newVariable);
              }
              j++;
            }
            json[entry] = oldEntry;
            break;
          default:
            throw Exception();
        }

        i++;
      }
      final response = jsonEncode(json); //result.text;

      return response;
    } on DeepLError catch (_) {
      throw ServerBusyException();
    } on RequestFailedException catch (e) {
      if (e.statusCode == 401) {
        throw InvalidApiKeyException();
      } else if (e.statusCode == 429) {
        throw QuotaExceededException();
      }
      rethrow;
    }
  }

  List<String> _getBracketsLevel(String input, int depth) {
    List<String> secondLevelMatches = [];
    int currentDepth = 0;
    int startIndex = -1;

    for (int i = 0; i < input.length; i++) {
      if (input[i] == '{') {
        currentDepth++;
        if (currentDepth == depth) {
          startIndex = i; // Start der zweiten Ebene speichern
        }
      } else if (input[i] == '}') {
        if (currentDepth == depth && startIndex != -1) {
          secondLevelMatches.add(input.substring(startIndex, i + 1));
          startIndex = -1;
        }
        currentDepth--;
      }
    }

    return secondLevelMatches;
  }

  int _getMaxNestingDepth(String input) {
    int maxDepth = 0;
    int currentDepth = 0;

    for (int i = 0; i < input.length; i++) {
      if (input[i] == '{') {
        currentDepth++;
        if (currentDepth > maxDepth) {
          maxDepth = currentDepth;
        }
      } else if (input[i] == '}') {
        currentDepth--;
      }
    }

    return maxDepth;
  }
}
