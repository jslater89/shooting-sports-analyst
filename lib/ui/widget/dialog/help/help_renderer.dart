import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';

class HelpRenderer extends StatelessWidget {
  const HelpRenderer({
    super.key,
    required this.topic,
    required this.onLinkTapped,
  });

  final HelpTopic topic;
  final void Function(String id) onLinkTapped;

  @override
  Widget build(BuildContext context) {
    var tokens = topic.tokenize();
    var spans = tokens.map((e) => e.intoSpans(context, Theme.of(context).textTheme.bodyMedium!, onLinkTapped: onLinkTapped)).flattened.toList();
    return SingleChildScrollView(
      child: RichText(
        text: TextSpan(
          children: spans,
        ),
      ),
    );
  }
}

/// Text in a help topic.
/// 
/// Tokens are hierarchical: a [Link] contains another help token,
/// which might be a [PlainText] or an [Emphasis], and in the latter
/// case, the [Emphasis] contains a [PlainText] holding the actual
/// string.
/// 
/// Headers and links are evaluated first, and their content will be
sealed class HelpToken {
  HelpToken();

  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped});

  String get asPlainText;
}

abstract class LinkableHelpToken extends HelpToken {
  final String? link;

  LinkableHelpToken({this.link});
}

/// A running string of plain text.
class PlainText extends LinkableHelpToken {
  final String text;

  PlainText(this.text, {super.link});

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
  String get asPlainText => text;
}

/// A header of some level.
class Header extends HelpToken {
  final List<HelpToken> tokens;
  final int level;

  Header(this.level, this.tokens);

  @override
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped}) {
    TextStyle style;
    if(level == 1) {
      style = Theme.of(context).textTheme.titleLarge!;
    }
    else if(level == 2) {
      style = Theme.of(context).textTheme.titleMedium!;
    }
    else {
      style = Theme.of(context).textTheme.titleSmall!;
    }
    return tokens.map((e) => e.intoSpans(context, style)).flattened.toList();
  }

  @override
  String get asPlainText => tokens.map((e) => e.asPlainText).join();
}

/// A link to another help topic or a URL.
class Link extends LinkableHelpToken {
  final List<HelpToken> tokens;
  final String id;

  Link({
    required this.tokens,
    required this.id,
    super.link,
  });

  @override
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped}) {
    var style = baseStyle.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
    return tokens.map((e) => e.intoSpans(context, style, onLinkTapped: onLinkTapped)).flattened.toList();
  }

  @override
  String get asPlainText => tokens.map((e) => e.asPlainText).join();
}

/// A type of text emphasis.
enum EmphasisType {
  italic,
  bold,
}

/// A section of text that is emphasized in some way.
class Emphasis extends LinkableHelpToken {
  final EmphasisType type;
  final PlainText token;

  Emphasis({
    required this.type,
    required this.token,
    super.link,
  });

  @override
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, {void Function(String)? onLinkTapped}) {
    TextStyle style;
    if(type == EmphasisType.italic) {
      style = baseStyle.copyWith(fontStyle: FontStyle.italic);
    }
    else {
      style = baseStyle.copyWith(fontWeight: FontWeight.bold);
    }

    return token.intoSpans(context, style, onLinkTapped: onLinkTapped);
  }

  @override
  String get asPlainText => token.asPlainText;
}