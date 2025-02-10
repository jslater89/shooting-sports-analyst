import 'package:collection/collection.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_registry.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_renderer.dart';
import 'package:shooting_sports_analyst/util.dart';

SSALogger _log = SSALogger("HelpTopic");

/// A help topic is an article that can be displayed to the user.
/// 
/// It can be formatted with a very small subset of Markdown,
/// including # and ## headers, _italics_, *bold*, and
/// [links](#help-topic-id).
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
    var tokens = tokenize().whereNot((element) => element is Header);

    var buffer = StringBuffer();
    for(var token in tokens) {
      buffer.write(token.asPlainText.replaceAll(RegExp(r"\n+"), " ").trim());
      if(buffer.length > 100) {
        break;
      }
    }
    return buffer.toString();
  }

  /// Convert the help topic into a list of HelpTokens.
  List<HelpToken> tokenize() {
    var tokens = <HelpToken>[];

    var lines = this.content.split(RegExp(r'(?=[\n])|(?<=[\n])'));

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

  static final _headerPattern = RegExp(r'^#+\s');
  static final _linkPattern = RegExp(r'\[(.*?)\]\((.*?)\)');
  static final _emphasisPattern = RegExp(r'_(.*?)_|\*\*(.*?)\*\*');

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
      Link(tokens: _tokenizeText(linkText, link: linkId), id: linkId),
    ];
  }

  List<HelpToken> _tokenizeText(String line, {String? link}) {
    List<HelpToken> tokens = [];
    var matches = _emphasisPattern.allMatches(line);
    var textParts = line.split(_emphasisPattern);
    List<String> parts = textParts.interleave(matches.map((e) => e.group(0)!).toList());
    for(var part in parts) {
      if(part.startsWith('_')) {
        tokens.add(Emphasis(type: EmphasisType.italic, token: PlainText(part.substring(1, part.length - 1), link: link)));
      }
      else if(part.startsWith('**')) {
        tokens.add(Emphasis(type: EmphasisType.bold, token: PlainText(part.substring(2, part.length - 2), link: link)));
      }
      else {
        tokens.add(PlainText(part, link: link));
      }
    }

    return tokens;
  }
}