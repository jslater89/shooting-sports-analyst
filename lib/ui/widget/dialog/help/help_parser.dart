/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/foundation.dart';
import 'package:shooting_sports_analyst/data/help/about.dart';
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
    var currentParagraph = Paragraph([]);
    
    var processedContent = _processContent(topic.content);
    var lines = processedContent.split("\n");
    
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      
      // Skip empty lines, but use them to break paragraphs
      if (line.isEmpty) {
        if (currentParagraph.tokens.isNotEmpty) {
          tokens.add(currentParagraph);
          currentParagraph = Paragraph([]);
        }
        continue;
      }

      HelpToken? lastToken;
      if(currentParagraph.tokens.isNotEmpty) {
        lastToken = currentParagraph.tokens.last.lastChild;
      }
      else if(tokens.isNotEmpty) {
        lastToken = tokens.last.lastChild;
      }
      ListItem? lastListToken;
      for(var token in currentParagraph.tokens.reversed) {
        // We're iterating through the tokens in reverse order, but
        // we're iterating through the subnodes in forward order, so
        // we have to search to the end of the subnode list.
        for(var child in token.subnodes) {
          if(child is ListItem) {
            lastListToken = child;
          }
        }
      }
      if(lastListToken == null) {
        // If we didn't find a list item in the current paragraph, we have to
        // search through all the tokens in the entire document. Same note as
        // above on subndoe order vs token order.
        for(var token in tokens.reversed) {
          for(var child in token.subnodes) {
            if(child is ListItem) {
              lastListToken = child;
            }
          }
        }
      }
      var lineTokens = _tokenizeLine(line, lastToken: lastToken, parent: currentParagraph);
      
      // Headers always start a new paragraph
      if (lineTokens.any((t) => t is Header)) {
        if (currentParagraph.tokens.isNotEmpty) {
          tokens.add(currentParagraph);
          currentParagraph = Paragraph([]);
        }
        tokens.addAll(lineTokens);
      } else {
        currentParagraph.tokens.addAll(lineTokens);
      }
    }
    
    // Don't forget the last paragraph
    if (currentParagraph.tokens.isNotEmpty) {
      tokens.add(currentParagraph);
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
  static List<HelpToken> _tokenizeLine(String line, {HelpToken? parent, HelpToken? lastToken, bool subline = false}) {
    List<HelpToken> tokens = [];
    var listMatch = _listPattern.firstMatch(line);

    var lastTokenHasManualBreak = false;
    if(lastToken is PlainText && lastToken.hasManualBreak) {
      lastTokenHasManualBreak = true;
    }
    
    if(_parseState.inList && !subline && !_emptyLinePattern.hasMatch(line)) {
      // We get to here when we encounter a line that does not start with a list marker
      // after we've already started a list.
      //
      // If the last token was a manual break, we want to stay in the list. Otherwise we want
      // to cancel the list.
      // e.g.:
      // * This is a list\
      //   with a manual break
      // * This is another item in the same list
      if(!lastTokenHasManualBreak && listMatch == null) {
        _parseState.resetListState();
      }
    }

    if(line.startsWith(_headerPattern)) {
      tokens.addAll(_tokenizeHeaderLine(line, parent: parent));
    } 
    else if(listMatch != null) {
      _parseState.inList = true;
      _parseState.inOrderedList = listMatch.group(2)!.startsWith(RegExp(r"\d"));
      var indent = listMatch.group(1)!.length ~/ 4;
      _parseState.listIndicesByIndent.increment(indent);

      tokens.addAll(_tokenizeListItem(line,
        lastToken: lastToken,
        ordered: _parseState.inOrderedList, 
        indentDepth: indent, 
        listIndex: _parseState.listIndicesByIndent[indent] ?? 1));
    } 
    else if(_linkPattern.hasMatch(line)) {
      tokens.addAll(_tokenizeLinkLine(line, parent: parent));
    } 
    else {
      if(lastTokenHasManualBreak && lastToken?.parent is ListItem) {
        var parent = lastToken!.parent! as ListItem;
        parent.tokens.addAll(_tokenizeText(line, parent: parent));
      }
      else {
        tokens.addAll(_tokenizeText(line, parent: parent));
      }
    }
    
    return tokens;
  }

  static List<HelpToken> _tokenizeLinkLine(String line, {HelpToken? parent}) {
    List<HelpToken> tokens = [];
    // save the matches in order, split around the links, and return
    // a list of plain text-link-plain text-link-plain text... as needed.
    var matches = _linkPattern.allMatches(line);
    var textParts = line.split(_linkPattern);
    List<String> parts = textParts.interleave(matches.map((e) => e.group(0)!).toList());
    for(var part in parts) {
      if(part.startsWith('[')) {
        tokens.addAll(_tokenizeLink(part, parent: parent));
      }
      else {
        tokens.add(PlainText(part, parent: parent));
      }
    }

    return tokens;
  }

  static List<HelpToken> _tokenizeHeaderLine(String line, {HelpToken? parent}) {
    var headerMarker = _headerPattern.firstMatch(line);
    if(headerMarker == null) {
      throw ArgumentError("line is not a header: $line");
    }

    var headerLevel = headerMarker.group(0)!.length - 1; // includes \s after the #s
    var headerText = line.substring(headerMarker.end);

    var _tokenizedText = _tokenizeText(headerText);
    return [
      Header(headerLevel, _tokenizedText, parent: parent),
    ];
  }

  static List<HelpToken> _tokenizeLink(String linkElement, {HelpToken? parent}) {
    var match = _linkPattern.firstMatch(linkElement);
    if(match == null) {
      throw ArgumentError("linkElement is not a link: $linkElement");
    }

    var linkText = match.group(1)!;
    var linkId = match.group(2)!;

    return [
      Link(tokens: _tokenizeText(linkText, link: linkId), id: linkId, parent: parent),
    ];
  }

  static List<HelpToken> _tokenizeText(String line, {String? link, HelpToken? parent}) {
    List<HelpToken> tokens = [];
    var matches = _emphasisPattern.allMatches(line);
    var textParts = line.split(_emphasisPattern);
    List<String> parts = textParts.interleave(matches.map((e) => e.group(0)!).toList());
    for(int i = 0; i < parts.length; i++) {
      var part = parts[i];
      var lineStart = i == 0;
      var lineEnd = i == parts.length - 1;
      if(part.startsWith('_')) {
        var token = Emphasis(type: EmphasisType.italic, token: PlaceholderToken(), parent: parent);
        var text = PlainText(part.substring(1, part.length - 1), link: link, lineStart: lineStart, lineEnd: lineEnd, parent: token);
        token.token = text;
        tokens.add(token);
      }
      else if(part.startsWith('**')) {
        var token = Emphasis(type: EmphasisType.bold, token: PlaceholderToken(), parent: parent);
        var text = PlainText(part.substring(2, part.length - 2), link: link, lineStart: lineStart, lineEnd: lineEnd, parent: token);
        token.token = text;
        tokens.add(token);
      }
      else {
        tokens.add(PlainText(part, link: link, lineStart: lineStart, lineEnd: lineEnd, parent: parent));
      }
    }

    return tokens;
  }

  static List<HelpToken> _tokenizeListItem(String line, {bool ordered = false, int indentDepth = 0, int listIndex = 0, HelpToken? lastToken, HelpToken? parent}) {
    var listMatch = _listPattern.firstMatch(line);
    if(listMatch == null) {
      throw ArgumentError("line is not a list item: $line");
    }

    var listText = line.substring(listMatch.end).trimRight();
    // A list item can contain e.g. a link, so we need to run the full tokenizer on its contents
    var listItem = ListItem(tokens: [], ordered: ordered, indentDepth: indentDepth, listIndex: listIndex, parent: parent);
    listItem.tokens.addAll(_tokenizeLine(listText, subline: true, lastToken: lastToken, parent: listItem));
    return [listItem];
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