/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Text in a help topic.
/// 
/// Tokens are hierarchical: a [Link] contains another help token,
/// which might be a [PlainText] or an [Emphasis], and in the latter
/// case, the [Emphasis] contains a [PlainText] holding the actual
/// string.
/// 
/// Headers and links are evaluated first, and their content will be
sealed class HelpToken {
  HelpToken({required this.lineStart, required this.lineEnd});

  bool lineStart;
  bool lineEnd;

  List<InlineSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped});

  List<HelpToken> get children;
  String get asPlainText;
}

/// A linkable help token is a token that is either a [Link] itself, or can be a child of a [Link].
abstract class LinkableHelpToken extends HelpToken {
  final String? link;

  LinkableHelpToken({this.link, required super.lineStart, required super.lineEnd});
}

class Paragraph extends HelpToken {
  final List<HelpToken> tokens;

  Paragraph(this.tokens, {super.lineStart = false, super.lineEnd = false});

  @override
  List<InlineSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped}) {
    var spans = tokens.map((e) => e.intoSpans(context, baseStyle, onLinkTapped: onLinkTapped)).flattened.toList();

    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: RichText(
            text: TextSpan(
              children: spans,
            ),
          ),
        )
      )
    ];
  }

  @override
  String get asPlainText => tokens.map((e) => e.asPlainText).join(" ") + "\n\n";

  @override
  List<HelpToken> get children => tokens;

  @override
  String toString() {
    return "Paragraph()";
  }
}

/// A running string of plain text.
class PlainText extends LinkableHelpToken {
  String text;

  PlainText(this.text, {super.link, super.lineStart = false, super.lineEnd = false});

  @override
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped}) {
    TapGestureRecognizer? recognizer;
    if(link != null) {
      recognizer = TapGestureRecognizer()..onTap = () => onLinkTapped?.call(link!);
    }
    return [
      TextSpan(text: text, style: baseStyle, recognizer: recognizer),
    ];
  }

  @override
  List<HelpToken> get children => [];

  @override
  String get asPlainText => text;

  @override
  String toString() {
    return "PlainText(${text.trim()})";
  }
}

/// A header of some level.
class Header extends HelpToken {
  final List<HelpToken> tokens;
  final int level;

  Header(this.level, this.tokens, {super.lineStart = false, super.lineEnd = false});

  @override
  List<InlineSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped}) {
    TextStyle style;
    var renderLevel = level;
    if(level == 1) {
      style = Theme.of(context).textTheme.titleLarge!;
    }
    else if(level == 2) {
      style = Theme.of(context).textTheme.titleMedium!.copyWith(decoration: TextDecoration.underline);
    }
    else {
      renderLevel = 3;
      style = Theme.of(context).textTheme.titleSmall!.copyWith(decoration: TextDecoration.underline);
    }
    var spans = tokens.map((e) => e.intoSpans(context, style)).flattened.toList();
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Row(
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: (6 * (4 - renderLevel)).toDouble()),
              child: RichText(
                text: TextSpan(
                  children: spans,
                ),
              ),
            ),
          ],
        ),
      )
    ];
  }

  @override
  String get asPlainText => tokens.map((e) => e.asPlainText).join();

  @override
  List<HelpToken> get children => tokens;

  @override
  String toString() {
    return "Header($level)";
  }
}

/// A link to another help topic or a URL.
class Link extends LinkableHelpToken {
  final List<HelpToken> tokens;
  final String id;

  Link({
    required this.tokens,
    required this.id,
    super.link,
    super.lineStart = false,
    super.lineEnd = false,
  });

  @override
  List<InlineSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped}) {
    var style = baseStyle.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
    return tokens.map((e) => e.intoSpans(context, style, onLinkTapped: onLinkTapped)).flattened.toList();
  }

  @override
  String get asPlainText => tokens.map((e) => e.asPlainText).join();

  @override
  List<HelpToken> get children => tokens;

  @override
  String toString() {
    return "Link($id)";
  }
}

/// A type of text emphasis.
enum EmphasisType {
  italic,
  bold,
}

/// A list item is an element in an ordered or unordered list.
/// 
/// For the moment, ordered lists do not support indenting/nesting.
class ListItem extends LinkableHelpToken {
  final List<HelpToken> tokens;
  final bool ordered;
  final int indentDepth;
  final int listIndex;

  ListItem({
    required this.tokens,
    required this.ordered,
    required this.indentDepth,
    required this.listIndex,
    super.link,
  }) : super(lineStart: true, lineEnd: true);
  
  @override
  String get asPlainText => tokens.map((e) => e.asPlainText).join();
  
  @override
  List<InlineSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String p1)? onLinkTapped}) {
    var contentTokens = tokens.map((e) => e.intoSpans(context, baseStyle, onLinkTapped: onLinkTapped)).flattened.toList();
    Widget bulletWidget;
    if(ordered) {
      // TODO: sequences
      bulletWidget = Padding(
        padding: EdgeInsets.only(left: (8 + 12 * indentDepth).toDouble()),
        child: Text(
          "$listIndex. ",
          style: baseStyle,
        ),
      );
    }
    else {
      var bullet = "•";
      if(indentDepth % 4 == 1) {
        bullet = "∘";
      }
      else if(indentDepth % 4 == 2) {
        bullet = "▪";
      }
      else if(indentDepth % 4 == 3) {
        bullet = "▫";
      }
      bulletWidget = Padding(
        padding: EdgeInsets.only(left: (8 + 12 * indentDepth).toDouble(), right: 4),
        child: Text(
          bullet,
          style: baseStyle,
        ),
      );
    }

    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bulletWidget,
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: contentTokens,
                ),
              ),
            )
          ]
        )
      )
    ];
  }

  @override
  List<HelpToken> get children => tokens;

  @override
  String toString() {
    return "ListItem($listIndex, ordered: $ordered, indentDepth: $indentDepth)";
  }
}

/// A section of text that is emphasized in some way.
class Emphasis extends LinkableHelpToken {
  final EmphasisType type;
  final PlainText token;

  Emphasis({
    required this.type,
    required this.token,
    super.link,
    super.lineStart = false,
    super.lineEnd = false,
  });

  @override
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped}) {
    TextStyle style;
    if(type == EmphasisType.italic) {
      style = baseStyle.copyWith(fontStyle: FontStyle.italic);
    }
    else {
      style = baseStyle.copyWith(fontWeight: FontWeight.w500);
    }

    return token.intoSpans(context, style, onLinkTapped: onLinkTapped);
  }

  @override
  List<HelpToken> get children => [token];

  @override
  String get asPlainText => token.asPlainText;

  @override
  String toString() {
    return "Emphasis($type)";
  }
}