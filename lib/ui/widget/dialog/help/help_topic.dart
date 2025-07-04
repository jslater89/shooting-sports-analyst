/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_parser.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_token.dart';

/// A help topic is an article that can be displayed to the user.
///
/// It can be formatted with a very small subset of Markdown,
/// including # and ## headers, _italics_, *bold*,
/// [links](?help-topic-id) or [links](https://example.com),
/// and * bullet lists.
class HelpTopic {
  final String id;
  final String name;
  final String content;

  HelpTopic({
    required this.id,
    required this.name,
    required this.content,
  });

  String contentPreview() {
    var tokens = HelpParser.tokenize(this).whereNot((element) => element is Heading);

    var buffer = StringBuffer();
    for(var token in tokens) {
      // preserve trailing spaces in case we have a paragraph break in the preview
      buffer.write(token.asPlainText.replaceAll(RegExp(r"\n+"), " ").trimLeft());
      if(buffer.length > 100) {
        break;
      }
    }
    return buffer.toString();
  }


}
