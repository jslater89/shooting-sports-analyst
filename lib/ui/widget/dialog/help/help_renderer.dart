import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';
import 'package:shooting_sports_analyst/util.dart';

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
    var tokens = _tokenize(topic);
    var spans = tokens.map((e) => e.intoSpans(context, DefaultTextStyle.of(context).style, onLinkTapped)).flattened.toList();
    return SingleChildScrollView(
      child: RichText(
        text: TextSpan(
          children: spans,
        ),
      ),
    );
  }

  static final _headerPattern = RegExp(r'^#+\s');
  static final _linkPattern = RegExp(r'\[(.*?)\]\((.*?)\)');
  static final _emphasisPattern = RegExp(r'_(.*?)_|\*\*(.*?)\*\*');

  /// Convert the help topic into a list of HelpTokens.
  List<HelpToken> _tokenize(HelpTopic topic) {
    var tokens = <HelpToken>[];

    var lines = topic.content.split(RegExp(r'(?=[\n])|(?<=[\n])'));

    for(var line in lines) {
      if(line.startsWith(_headerPattern)) {
        // headers are a special case, since they modify an
        // entire line of text.
        tokens.add(Header(line.length, _tokenizeHeaderLine(line)));
      }
      else if(_linkPattern.hasMatch(line)) {
        tokens.addAll(_tokenizeLinkLine(line));
      }
      else {
        tokens.addAll(_tokenizeText(line));
      }
    }

    return tokens;
  }

  List<HelpToken> _tokenizeLinkLine(String line) {
    List<HelpToken> tokens = [];
    // save the matches in order, split around the links, and return
    // a list of plain text-link-plain text-link-plain text... as needed.
    var matches = _linkPattern.allMatches(line);
    var textParts = line.split(_linkPattern);
    List<String> parts = textParts.interleave(matches.map((e) => e.group(0)!).toList());
    for(var part in parts) {
      if(part.startsWith('[')) {
        tokens.addAll(_tokenizeLink(part));
      }
      else {
        tokens.add(PlainText(part));
      }
    }

    return tokens;
  }

  List<HelpToken> _tokenizeHeaderLine(String line) {
    var headerMarker = _headerPattern.firstMatch(line);
    if(headerMarker == null) {
      throw ArgumentError("line is not a header: $line");
    }

    var headerLevel = headerMarker.group(0)!.length - 1; // includes \s after the #s
    var headerText = line.substring(headerMarker.end);

    var _tokenizedText = _tokenizeText(headerText);
    return [
      Header(headerLevel, _tokenizedText),
    ];
  }

  List<HelpToken> _tokenizeLink(String linkElement) {
    var match = _linkPattern.firstMatch(linkElement);
    if(match == null) {
      throw ArgumentError("linkElement is not a link: $linkElement");
    }

    var linkText = match.group(1)!;
    var linkId = match.group(2)!;

    return [
      Link(tokens: _tokenizeText(linkText), id: linkId),
    ];
  }

  List<HelpToken> _tokenizeText(String line) {
    List<HelpToken> tokens = [];
    var matches = _emphasisPattern.allMatches(line);
    var textParts = line.split(_emphasisPattern);
    List<String> parts = textParts.interleave(matches.map((e) => e.group(0)!).toList());
    for(var part in parts) {
      if(part.startsWith('_')) {
        tokens.add(Emphasis(type: EmphasisType.italic, token: PlainText(part.substring(1, part.length - 1))));
      }
      else if(part.startsWith('**')) {
        tokens.add(Emphasis(type: EmphasisType.bold, token: PlainText(part.substring(2, part.length - 2))));
      }
      else {
        tokens.add(PlainText(part));
      }
    }

    return tokens;
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
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, void Function(String)? onLinkTapped);
}

/// A running string of plain text.
class PlainText extends HelpToken {
  final String text;

  PlainText(this.text);

  @override
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, void Function(String)? onLinkTapped) {
    var recognizer = onLinkTapped != null ? TapGestureRecognizer() : null;
    if(recognizer != null) {
      recognizer.onTap = () => onLinkTapped?.call(text);
    }
    return [
      TextSpan(text: text, style: baseStyle, recognizer: recognizer),
    ];
  }
}

/// A header of some level.
class Header extends HelpToken {
  final List<HelpToken> tokens;
  final int level;

  Header(this.level, this.tokens);

  @override
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, void Function(String)? onLinkTapped) {
    var style = baseStyle.copyWith(fontSize: 20 - level * 2, fontWeight: FontWeight.bold);
    return tokens.map((e) => e.intoSpans(context, style, null)).flattened.toList();
  }
}

/// A link to another help topic.
class Link extends HelpToken {
  final List<HelpToken> tokens;
  final String id;

  Link({
    required this.tokens,
    required this.id,
  });

  @override
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, void Function(String)? onLinkTapped) {
    var style = baseStyle.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline);
    return tokens.map((e) => e.intoSpans(context, style, onLinkTapped)).flattened.toList();
  }
}

/// A type of text emphasis.
enum EmphasisType {
  italic,
  bold,
}

/// A section of text that is emphasized in some way.
class Emphasis extends HelpToken {
  final EmphasisType type;
  final PlainText token;

  Emphasis({
    required this.type,
    required this.token,
  });

  @override
  List<TextSpan> intoSpans(BuildContext context, TextStyle baseStyle, void Function(String)? onLinkTapped) {
    TextStyle style;
    if(type == EmphasisType.italic) {
      style = baseStyle.copyWith(fontStyle: FontStyle.italic);
    }
    else {
      style = baseStyle.copyWith(fontWeight: FontWeight.bold);
    }

    return token.intoSpans(context, style, null);
  }
}