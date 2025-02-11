import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/data/help/deduplication_help.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_registry.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_renderer.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_token.dart';
import 'package:shooting_sports_analyst/util.dart';

SSALogger _log = SSALogger("HelpTopic");

const _shouldDumpTokenTree = kDebugMode && true;

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
      tokens.addAll(_tokenizeLine(line));
    }

    if(_shouldDumpTokenTree && id == deduplicationHelpId) {
      _dumpTokenTree(tokens);
    }

    return tokens;
  }

  static final _ParseState _parseState = _ParseState();

  static final _headerPattern = RegExp(r'^#+\s');
  static final _linkPattern = RegExp(r'\[(.*?)\]\((.*?)\)');
  static final _emphasisPattern = RegExp(r'_(.*?)_|\*\*(.*?)\*\*');
  static final _listPattern = RegExp(r'^(\s*)(\*|\d+\.)\s');
  static final _emptyLinePattern = RegExp(r'^(\s*)\n');

  /// Tokenize some text. If [subline] is true, this is a recursive call from
  /// within a line, and should not reset list state.
  List<HelpToken> _tokenizeLine(String line, {bool subline = false}) {
    List<HelpToken> tokens = [];
    var listMatch = _listPattern.firstMatch(line);
    // Don't reset parse state on whitespace-only lines
    if(!subline && !_emptyLinePattern.hasMatch(line)) {
      if(listMatch == null) {
        _parseState.resetListState();
      }
    }

    if(id == deduplicationHelpId) {
      print("break");
    }

    if(line.startsWith(_headerPattern)) {
      // headers are a special case, since they modify an
      // entire line of text.
      tokens.addAll(_tokenizeHeaderLine(line));
    }
    else if(listMatch != null) {
      _parseState.inList = true;
      _parseState.inOrderedList = listMatch.group(2)!.startsWith(RegExp(r"\d"));
      var indent = listMatch.group(1)!.length ~/ 4;
      _parseState.listIndicesByIndent.increment(indent);

      tokens.addAll(_tokenizeListItem(line, ordered: _parseState.inOrderedList, indentDepth: indent, listIndex: _parseState.listIndicesByIndent[indent] ?? 1));
    }
    else if(_linkPattern.hasMatch(line)) {
      tokens.addAll(_tokenizeLinkLine(line));
    }
    else {
      tokens.addAll(_tokenizeText(line));
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
      Link(tokens: _tokenizeText(linkText, link: linkId), id: linkId),
    ];
  }

  List<HelpToken> _tokenizeText(String line, {String? link}) {
    List<HelpToken> tokens = [];
    var matches = _emphasisPattern.allMatches(line);
    var textParts = line.split(_emphasisPattern);
    List<String> parts = textParts.interleave(matches.map((e) => e.group(0)!).toList());
    for(int i = 0; i < parts.length; i++) {
      var part = parts[i];
      var lineStart = i == 0;
      var lineEnd = i == parts.length - 1;
      if(part.startsWith('_')) {
        tokens.add(Emphasis(type: EmphasisType.italic, token: PlainText(part.substring(1, part.length - 1), link: link, lineStart: lineStart, lineEnd: lineEnd)));
      }
      else if(part.startsWith('**')) {
        tokens.add(Emphasis(type: EmphasisType.bold, token: PlainText(part.substring(2, part.length - 2), link: link, lineStart: lineStart, lineEnd: lineEnd)));
      }
      else {
        tokens.add(PlainText(part, link: link, lineStart: lineStart, lineEnd: lineEnd));
      }
    }

    return tokens;
  }

  List<HelpToken> _tokenizeListItem(String line, {bool ordered = false, int indentDepth = 0, int listIndex = 0}) {
    var listMatch = _listPattern.firstMatch(line);
    if(listMatch == null) {
      throw ArgumentError("line is not a list item: $line");
    }

    var listText = line.substring(listMatch.end);
    // A list item can contain e.g. a link, so we need to run the full tokenizer on its contents
    return [
      ListItem(tokens: _tokenizeLine(listText, subline: true), ordered: ordered, indentDepth: indentDepth, listIndex: listIndex),
    ];
  }
}

void _dumpTokenTree(List<HelpToken> tokens, {int indent = 0}) {
  for(var token in tokens) {
    print("${"  " * indent}${token.toString()}");
    _dumpTokenTree(token.children, indent: indent + 1);
  }
}

class _ParseState {
  Map<int, int> listIndicesByIndent = {};
  bool inList = false;
  bool inOrderedList = false;

  void resetListState() {
    listIndicesByIndent = {};
    inList = false;
    inOrderedList = false;
  }
}