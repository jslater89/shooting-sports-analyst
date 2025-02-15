/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_token.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_topic.dart';
import 'package:shooting_sports_analyst/util.dart';

SSALogger _log = SSALogger("HelpTopic");


class HelpParser {
  static Map<String, List<HelpToken>> _tokenizedCache = {};
  static const _shouldDumpTokenTree = kDebugMode && false;
  static const _shouldCacheTokenizedContent = !kDebugMode;

  /// Convert the help topic into a list of HelpTokens.
  static List<HelpToken> tokenize(HelpTopic topic) {
    if(_shouldCacheTokenizedContent && _tokenizedCache[topic.id] != null) {
      return _tokenizedCache[topic.id]!;
    }

    var tokens = <HelpToken>[];
    var currentParagraphTokens = <HelpToken>[];
    
    var processedContent = _processContent(topic.content);
    var lines = processedContent.split("\n");
    
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      
      // Skip empty lines, but use them to break paragraphs
      if (line.isEmpty) {
        if (currentParagraphTokens.isNotEmpty) {
          tokens.add(Paragraph(currentParagraphTokens));
          currentParagraphTokens = [];
        }
        continue;
      }

      var lineTokens = _tokenizeLine(line);
      
      // Headers always start a new paragraph
      if (lineTokens.any((t) => t is Header)) {
        if (currentParagraphTokens.isNotEmpty) {
          tokens.add(Paragraph(currentParagraphTokens));
          currentParagraphTokens = [];
        }
        tokens.addAll(lineTokens);
      } else {
        currentParagraphTokens.addAll(lineTokens);
      }
    }
    
    // Don't forget the last paragraph
    if (currentParagraphTokens.isNotEmpty) {
      tokens.add(Paragraph(currentParagraphTokens));
    }
    
    if(_shouldDumpTokenTree) {
      _dumpTokenTree(tokens);
    }

    _tokenizedCache[topic.id] = tokens;
    return tokens;
  }

  /// Process the content of the help topic to prepare it for tokenization.
  /// 
  /// The main processing step is removing all single newlines that do not
  /// precede a heading marker or a list marker.
  static String _processContent(String content) {
    var lines = content.split("\n");
    var processedLines = <String>[];
    
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var manualNewline = false;
      if(line.endsWith("  ")) {
        manualNewline = true;
      }
      else {
        line = line.trimRight();
      }

      if(line.endsWith("\\")) {
        manualNewline = true;
      }
      if(!line.startsWith(_listPattern)) {
        line = line.trimLeft();
      }

      var nextLine = i < lines.length - 1 ? lines[i + 1] : "";
      if(!nextLine.startsWith(_listPattern)) {
        nextLine = nextLine.trim();
      }
      
      // Keep the newline if:
      // 1. Next line is empty (double newline = paragraph break)
      // 2. Next line starts with header marker, or this line is a header
      // 3. Next line starts with list marker
      // 4. Current line is empty
      // 5. Current line ends with a single backslash or a pair of spaces
      bool keepNewline = nextLine.isEmpty ||
          line.startsWith(_headerPattern) ||
          nextLine.trimLeft().startsWith(_headerPattern) ||
          nextLine.trimLeft().startsWith(_listPattern) ||
          line.isEmpty ||
          manualNewline;
          
      var finalLine = line + (keepNewline ? "\n" : " ");
      processedLines.add(finalLine);

      if(manualNewline) {
        print("break");
      }
    }
    
    return processedLines.join();
  }

  static final _ParseState _parseState = _ParseState();

  static final _singleNewlinePattern = RegExp(r'^(.)\n(?![\n#*]|\d+\.)');
  static final _headerPattern = RegExp(r'^#+\s');
  static final _linkPattern = RegExp(r'\[(.*?)\]\((.*?)\)');
  static final _emphasisPattern = RegExp(r'_(.*?)_|\*\*(.*?)\*\*');
  static final _listPattern = RegExp(r'^(\s*)(\*|\d+\.)\s');
  static final _emptyLinePattern = RegExp(r'^(\s*)\n');

  /// Tokenize some text. If [subline] is true, this is a recursive call from
  /// within a line, and should not reset list state.
  static List<HelpToken> _tokenizeLine(String line, {bool subline = false}) {
    List<HelpToken> tokens = [];
    var listMatch = _listPattern.firstMatch(line);
    
    if (!subline && !_emptyLinePattern.hasMatch(line)) {
      if (listMatch == null) {
        _parseState.resetListState();
      }
    }

    if (line.startsWith(_headerPattern)) {
      tokens.addAll(_tokenizeHeaderLine(line));
    } else if (listMatch != null) {
      _parseState.inList = true;
      _parseState.inOrderedList = listMatch.group(2)!.startsWith(RegExp(r"\d"));
      var indent = listMatch.group(1)!.length ~/ 4;
      _parseState.listIndicesByIndent.increment(indent);

      tokens.addAll(_tokenizeListItem(line, 
        ordered: _parseState.inOrderedList, 
        indentDepth: indent, 
        listIndex: _parseState.listIndicesByIndent[indent] ?? 1));
    } else if (_linkPattern.hasMatch(line)) {
      tokens.addAll(_tokenizeLinkLine(line));
    } else {
      tokens.addAll(_tokenizeText(line));
    }
    
    return tokens;
  }

  static List<HelpToken> _tokenizeLinkLine(String line) {
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

  static List<HelpToken> _tokenizeHeaderLine(String line) {
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

  static List<HelpToken> _tokenizeLink(String linkElement) {
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

  static List<HelpToken> _tokenizeText(String line, {String? link}) {
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

  static List<HelpToken> _tokenizeListItem(String line, {bool ordered = false, int indentDepth = 0, int listIndex = 0}) {
    var listMatch = _listPattern.firstMatch(line);
    if(listMatch == null) {
      throw ArgumentError("line is not a list item: $line");
    }

    var listText = line.substring(listMatch.end).trimRight();
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