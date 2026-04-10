/*
 * Minimal TUI framework with proper paste support and keyboard focus cycling.
 *
 * Designed to replace Dascade for apps that need:
 *  - Correct terminal paste handling (bracketed paste mode + byte accumulation)
 *  - Tab / Shift-Tab focus cycling and Enter activation
 *  - Mouse click support
 *  - Flicker-free ANSI rendering with line-level diffing
 */

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math" as math;

// ---------------------------------------------------------------------------
// Input event types
// ---------------------------------------------------------------------------

enum TuiKey {
  tab,
  shiftTab,
  enter,
  escape,
  backspace,
  delete,
  up,
  down,
  left,
  right,
  home,
  end,
  pageUp,
  pageDown,
  ctrlC,
  ctrlV,
}

sealed class TuiEvent {}

class TuiKeyEvent extends TuiEvent {
  final TuiKey key;
  TuiKeyEvent(this.key);
}

/// One or more printable characters (handles paste as a single event).
class TuiTextEvent extends TuiEvent {
  final String text;
  TuiTextEvent(this.text);
}

class TuiMouseEvent extends TuiEvent {
  final int row;
  final int col;
  final int button;
  final bool isRelease;
  final bool isScroll;
  final bool scrollUp;

  TuiMouseEvent({
    required this.row,
    required this.col,
    required this.button,
    this.isRelease = false,
    this.isScroll = false,
    this.scrollUp = false,
  });
}

// ---------------------------------------------------------------------------
// Text field
// ---------------------------------------------------------------------------

/// Single-line editable text field with cursor, paste, and navigation.
class TuiTextField {
  String text;
  int cursor;

  TuiTextField({String initialText = ""})
      : text = initialText,
        cursor = initialText.length;

  /// Process text/navigation events directed at this field.
  void handleEvents(Iterable<TuiEvent> events) {
    for (final e in events) {
      if (e is TuiTextEvent) {
        final clean = e.text.replaceAll(RegExp(r"[\r\n]+"), " ");
        text = text.substring(0, cursor) + clean + text.substring(cursor);
        cursor += clean.length;
      }
      else if (e is TuiKeyEvent) {
        switch (e.key) {
          case TuiKey.backspace:
            if (cursor > 0) {
              text = text.substring(0, cursor - 1) + text.substring(cursor);
              cursor--;
            }
          case TuiKey.delete:
            if (cursor < text.length) {
              text = text.substring(0, cursor) + text.substring(cursor + 1);
            }
          case TuiKey.left:
            if (cursor > 0) cursor--;
          case TuiKey.right:
            if (cursor < text.length) cursor++;
          case TuiKey.home:
            cursor = 0;
          case TuiKey.end:
            cursor = text.length;
          default:
            break;
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

class _WidgetArea {
  final int startRow;
  final int endRow;
  final int startCol;
  final int endCol;
  _WidgetArea(this.startRow, this.endRow, this.startCol, this.endCol);

  bool contains(int row, int col) =>
      row >= startRow && row <= endRow && col >= startCol && col < endCol;
}

// ---------------------------------------------------------------------------
// Main TUI framework
// ---------------------------------------------------------------------------

class Tui {
  StreamSubscription<List<int>>? _stdinSub;
  final _rawBytes = <int>[];
  List<String> _prevScreen = [];
  int _prevWidth = 0;
  int _prevHeight = 0;
  bool _cursorVisible = false;

  // Focus
  List<String> _focusOrder = [];
  String? _focusedId;
  final _activatedIds = <String>{};
  final _fieldIds = <String>{};

  // Widget hit areas (current frame for recording, prev frame for hit-testing)
  final _widgetAreas = <String, _WidgetArea>{};
  final _prevWidgetAreas = <String, _WidgetArea>{};
  final _prevFieldIds = <String>{};

  // Input
  final _events = <TuiEvent>[];
  bool _inBracketedPaste = false;
  final _pasteBytes = <int>[];
  int? _pendingEsc;

  // Mouse
  int mouseRow = 0;
  int mouseCol = 0;

  // Rendered lines for current frame
  final _lines = <String>[];

  // Cursor placement for focused text fields
  int? _cursorRow;
  int? _cursorCol;

  int get width => stdout.terminalColumns;
  int get height => stdout.terminalLines;

  String? get focusedId => _focusedId;
  List<TuiEvent> get events => _events;

  /// Whether [key] was pressed this frame.
  bool hasKey(TuiKey key) => _events.any((e) => e is TuiKeyEvent && e.key == key);

  /// Whether the widget [id] was activated (Enter while focused, or mouse click).
  bool activated(String id) => _activatedIds.contains(id);

  /// Whether the widget [id] is currently focused.
  bool isFocused(String id) => _focusedId == id;

  // ---- lifecycle ----------------------------------------------------------

  Future<void> run(Future<void> Function() body) async {
    _enterRawMode();
    try {
      await body();
    } finally {
      _exitRawMode();
    }
  }

  void _enterRawMode() {
    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
    }
    catch (_) {}
    stdout.write(
      "\x1b[?1049h" // alternate screen buffer
      "\x1b[?1000h" // normal mouse tracking
      "\x1b[?1006h" // SGR extended encoding
      "\x1b[?2004h" // bracketed paste
      "\x1b[?25l", // hide cursor
    );
    _stdinSub = stdin.listen((bytes) => _rawBytes.addAll(bytes));
  }

  void _exitRawMode() {
    _stdinSub?.cancel();
    stdout.write(
      "\x1b[?25h" // show cursor
      "\x1b[?2004l" // disable bracketed paste
      "\x1b[?1000l" // disable mouse tracking
      "\x1b[?1006l"
      "\x1b[?1049l", // restore screen
    );
    try {
      stdin.echoMode = true;
      stdin.lineMode = true;
    }
    catch (_) {}
  }

  /// Start a new frame: process input, prepare for rendering.
  void beginFrame() {
    _lines.clear();
    _activatedIds.clear();
    _cursorRow = null;
    _cursorCol = null;

    _prevWidgetAreas
      ..clear()
      ..addAll(_widgetAreas);
    _widgetAreas.clear();
    _prevFieldIds
      ..clear()
      ..addAll(_fieldIds);
    _fieldIds.clear();

    // Detect terminal resize
    final w = width;
    final h = height;
    if (w != _prevWidth || h != _prevHeight) {
      _prevScreen.clear();
      _prevWidth = w;
      _prevHeight = h;
      stdout.write("\x1b[2J");
    }

    _parseRawInput();
    _handleGlobalInput();
  }

  /// End the frame: flush rendered output.
  void endFrame() {
    _flushScreen();
  }

  /// Declare the focusable widget order for the current mode.
  void setFocusOrder(List<String> ids) {
    _focusOrder = ids;
    if (ids.isEmpty) {
      _focusedId = null;
    }
    else if (_focusedId == null || !ids.contains(_focusedId)) {
      _focusedId = ids.isNotEmpty ? ids.first : null;
    }
  }

  /// Force a full redraw next frame.
  void invalidate() => _prevScreen.clear();

  // ---- input parsing ------------------------------------------------------

  void _parseRawInput() {
    _events.clear();
    final bytes = <int>[];

    if (_pendingEsc != null) {
      if (_rawBytes.isEmpty) {
        _events.add(TuiKeyEvent(TuiKey.escape));
        _pendingEsc = null;
        return;
      }
      if (_rawBytes[0] != 0x5b && _rawBytes[0] != 0x4f) {
        _events.add(TuiKeyEvent(TuiKey.escape));
        _pendingEsc = null;
      }
      else {
        bytes.add(0x1b);
        _pendingEsc = null;
      }
    }

    bytes.addAll(_rawBytes);
    _rawBytes.clear();

    var i = 0;
    while (i < bytes.length) {
      // ---------- bracketed paste accumulation ----------
      if (_inBracketedPaste) {
        _pasteBytes.add(bytes[i]);
        i++;
        if (_pasteBytes.length >= 6 && _pasteBytes.last == 0x7e) {
          final len = _pasteBytes.length;
          if (len >= 6 &&
              _pasteBytes[len - 6] == 0x1b &&
              _pasteBytes[len - 5] == 0x5b &&
              _pasteBytes[len - 4] == 0x32 &&
              _pasteBytes[len - 3] == 0x30 &&
              _pasteBytes[len - 2] == 0x31) {
            _inBracketedPaste = false;
            final textBytes = _pasteBytes.sublist(0, len - 6);
            final text = utf8.decode(textBytes, allowMalformed: true);
            if (text.isNotEmpty) {
              _events.add(TuiTextEvent(text));
            }
            _pasteBytes.clear();
          }
        }
        continue;
      }

      final b = bytes[i];

      // ---------- ESC sequences ----------
      if (b == 0x1b) {
        if (i + 1 >= bytes.length) {
          _pendingEsc = 0x1b;
          i++;
          continue;
        }

        if (bytes[i + 1] == 0x5b) {
          // CSI: ESC [
          i += 2;

          // Bracketed paste start: ESC [ 2 0 0 ~
          if (i + 3 < bytes.length &&
              bytes[i] == 0x32 &&
              bytes[i + 1] == 0x30 &&
              bytes[i + 2] == 0x30 &&
              bytes[i + 3] == 0x7e) {
            _inBracketedPaste = true;
            _pasteBytes.clear();
            i += 4;
            continue;
          }

          final params = StringBuffer();
          while (i < bytes.length && bytes[i] >= 0x30 && bytes[i] <= 0x3f) {
            params.writeCharCode(bytes[i++]);
          }
          while (i < bytes.length && bytes[i] >= 0x20 && bytes[i] <= 0x2f) {
            i++;
          }
          if (i < bytes.length && bytes[i] >= 0x40 && bytes[i] <= 0x7e) {
            _parseCsi(params.toString(), bytes[i++]);
          }
        }
        else if (bytes[i + 1] == 0x4f) {
          // SS3: ESC O
          i += 2;
          if (i < bytes.length) {
            switch (bytes[i++]) {
              case 0x41: _events.add(TuiKeyEvent(TuiKey.up));
              case 0x42: _events.add(TuiKeyEvent(TuiKey.down));
              case 0x43: _events.add(TuiKeyEvent(TuiKey.right));
              case 0x44: _events.add(TuiKeyEvent(TuiKey.left));
              case 0x48: _events.add(TuiKeyEvent(TuiKey.home));
              case 0x46: _events.add(TuiKeyEvent(TuiKey.end));
            }
          }
        }
        else {
          _events.add(TuiKeyEvent(TuiKey.escape));
          i++;
        }
      }
      // ---------- control chars ----------
      else if (b == 0x09) {
        _events.add(TuiKeyEvent(TuiKey.tab));
        i++;
      }
      else if (b == 0x0d || b == 0x0a) {
        _events.add(TuiKeyEvent(TuiKey.enter));
        i++;
        if (b == 0x0d && i < bytes.length && bytes[i] == 0x0a) i++;
      }
      else if (b == 0x7f || b == 0x08) {
        _events.add(TuiKeyEvent(TuiKey.backspace));
        i++;
      }
      else if (b == 0x03) {
        _events.add(TuiKeyEvent(TuiKey.ctrlC));
        i++;
      }
      else if (b == 0x16) {
        _events.add(TuiKeyEvent(TuiKey.ctrlV));
        i++;
      }
      else if (b < 0x20) {
        i++;
      }
      // ---------- printable text (accumulate for paste support) ----------
      else {
        final start = i;
        while (i < bytes.length && bytes[i] >= 0x20 && bytes[i] != 0x7f && bytes[i] != 0x1b) {
          i++;
        }
        final text = utf8.decode(bytes.sublist(start, i), allowMalformed: true);
        if (text.isNotEmpty) {
          _events.add(TuiTextEvent(text));
        }
      }
    }
  }

  void _parseCsi(String params, int cmd) {
    // SGR mouse: params start with '<'
    if (params.startsWith("<")) {
      final parts = params.substring(1).split(";");
      if (parts.length >= 3) {
        final btn = int.tryParse(parts[0]) ?? 0;
        final col = (int.tryParse(parts[1]) ?? 1) - 1;
        final row = (int.tryParse(parts[2]) ?? 1) - 1;
        _events.add(TuiMouseEvent(
          row: row,
          col: col,
          button: btn & 3,
          isRelease: cmd == 0x6d,
          isScroll: (btn & 64) != 0,
          scrollUp: (btn & 64) != 0 && (btn & 1) == 0,
        ));
      }
      return;
    }

    switch (cmd) {
      case 0x41: _events.add(TuiKeyEvent(TuiKey.up));
      case 0x42: _events.add(TuiKeyEvent(TuiKey.down));
      case 0x43: _events.add(TuiKeyEvent(TuiKey.right));
      case 0x44: _events.add(TuiKeyEvent(TuiKey.left));
      case 0x48: _events.add(TuiKeyEvent(TuiKey.home));
      case 0x46: _events.add(TuiKeyEvent(TuiKey.end));
      case 0x5a: _events.add(TuiKeyEvent(TuiKey.shiftTab));
      case 0x7e:
        switch (params) {
          case "1": _events.add(TuiKeyEvent(TuiKey.home));
          case "3": _events.add(TuiKeyEvent(TuiKey.delete));
          case "4": _events.add(TuiKeyEvent(TuiKey.end));
          case "5": _events.add(TuiKeyEvent(TuiKey.pageUp));
          case "6": _events.add(TuiKeyEvent(TuiKey.pageDown));
        }
    }
  }

  // ---- global navigation --------------------------------------------------

  void _handleGlobalInput() {
    for (final e in _events) {
      if (e is TuiKeyEvent) {
        switch (e.key) {
          case TuiKey.tab:
            _focusNext();
          case TuiKey.shiftTab:
            _focusPrev();
          case TuiKey.enter:
            if (_focusedId != null) _activatedIds.add(_focusedId!);
          default:
            break;
        }
      }
      else if (e is TuiMouseEvent && !e.isRelease && !e.isScroll) {
        for (final entry in _prevWidgetAreas.entries) {
          if (entry.value.contains(e.row, e.col)) {
            _focusedId = entry.key;
            if (!_prevFieldIds.contains(entry.key)) {
              _activatedIds.add(entry.key);
            }
            break;
          }
        }
      }
    }
  }

  void _focusNext() {
    if (_focusOrder.isEmpty) return;
    final idx = _focusedId != null ? _focusOrder.indexOf(_focusedId!) : -1;
    _focusedId = _focusOrder[(idx + 1) % _focusOrder.length];
  }

  void _focusPrev() {
    if (_focusOrder.isEmpty) return;
    final idx = _focusedId != null ? _focusOrder.indexOf(_focusedId!) : 1;
    _focusedId = _focusOrder[(idx - 1 + _focusOrder.length) % _focusOrder.length];
  }

  // ---- rendering helpers --------------------------------------------------

  /// Append a pre-formatted line.
  void writeLine(String line) => _lines.add(line);

  /// Append a blank line.
  void blankLine() => _lines.add("");

  /// Render a bordered read-only box.
  void renderBox(String label, String content, {int? maxLines}) {
    final w = width;
    final innerW = math.max(w - 4, 0);
    final contentLines = content.split("\n");
    final limit = maxLines ?? contentLines.length;

    final labelPart = label.isNotEmpty ? "─ $label " : "";
    final topFill = math.max(w - 2 - labelPart.length, 0);
    _lines.add("┌$labelPart${"─" * topFill}┐");

    for (var i = 0; i < limit; i++) {
      final raw = i < contentLines.length ? contentLines[i] : "";
      final vis = _truncate(raw, innerW);
      _lines.add("│ ${vis.padRight(innerW)} │");
    }

    _lines.add("└${"─" * math.max(w - 2, 0)}┘");
  }

  /// Render a single-line editable text field (3 terminal rows).
  ///
  /// Dispatches text/navigation events when focused and tracks cursor.
  void renderField(String id, String label, TuiTextField field) {
    _fieldIds.add(id);
    final w = width;
    final innerW = math.max(w - 4, 0);
    final focused = _focusedId == id;

    if (focused) {
      field.handleEvents(_events.where((e) =>
          e is TuiTextEvent ||
          (e is TuiKeyEvent &&
              const [
                TuiKey.backspace,
                TuiKey.delete,
                TuiKey.left,
                TuiKey.right,
                TuiKey.home,
                TuiKey.end,
              ].contains(e.key))));
    }

    var scrollOff = 0;
    if (innerW > 0 && field.cursor > innerW - 1) {
      scrollOff = field.cursor - innerW + 1;
    }
    final visEnd = math.min(scrollOff + innerW, field.text.length);
    final visible = scrollOff < field.text.length
        ? field.text.substring(scrollOff, visEnd)
        : "";
    final padded = visible.padRight(innerW);

    final sty = focused ? "\x1b[36m" : "";
    const rst = "\x1b[0m";

    final startRow = _lines.length;
    _widgetAreas[id] = _WidgetArea(startRow, startRow + 2, 0, w);

    final labelPart = label.isNotEmpty ? "─ $label " : "";
    final topFill = math.max(w - 2 - labelPart.length, 0);
    _lines.add("$sty┌$labelPart${"─" * topFill}┐$rst");
    _lines.add("$sty│$rst $padded $sty│$rst");
    _lines.add("$sty└${"─" * math.max(w - 2, 0)}┘$rst");

    if (focused) {
      _cursorRow = startRow + 1;
      _cursorCol = 2 + (field.cursor - scrollOff);
    }
  }

  /// Render a horizontal row of buttons.
  void renderButtonRow(List<(String id, String label)> buttons) {
    final row = _lines.length;
    final buf = StringBuffer("  ");
    var col = 2;

    for (var i = 0; i < buttons.length; i++) {
      final (id, label) = buttons[i];
      final focused = _focusedId == id;
      final startCol = col;

      if (focused) buf.write("\x1b[7m");
      buf.write("[ $label ]");
      if (focused) buf.write("\x1b[0m");
      col += label.length + 4;

      _widgetAreas[id] = _WidgetArea(row, row, startCol, col);

      if (i < buttons.length - 1) {
        buf.write("  ");
        col += 2;
      }
    }

    _lines.add(buf.toString());
  }

  /// Render a single button on its own line.
  void renderButton(String id, String label) {
    renderButtonRow([(id, label)]);
  }

  // ---- screen flush -------------------------------------------------------

  void _flushScreen() {
    final w = width;
    final h = height;
    final buf = StringBuffer();

    for (var i = 0; i < h; i++) {
      final line = i < _lines.length ? _padLine(_lines[i], w) : " " * w;
      if (i >= _prevScreen.length || _prevScreen[i] != line) {
        buf.write("\x1b[${i + 1};1H$line");
      }
    }

    _prevScreen = [
      for (var i = 0; i < h; i++)
        i < _lines.length ? _padLine(_lines[i], w) : " " * w,
    ];

    if (_cursorRow != null && _cursorCol != null) {
      if (!_cursorVisible) {
        buf.write("\x1b[?25h");
        _cursorVisible = true;
      }
      buf.write("\x1b[${_cursorRow! + 1};${_cursorCol! + 1}H");
    }
    else {
      if (_cursorVisible) {
        buf.write("\x1b[?25l");
        _cursorVisible = false;
      }
    }

    if (buf.isNotEmpty) stdout.write(buf);
  }

  // ---- static style helpers -----------------------------------------------

  static String dim(String s) => "\x1b[2m$s\x1b[0m";
  static String bold(String s) => "\x1b[1m$s\x1b[0m";
  static String cyan(String s) => "\x1b[36m$s\x1b[0m";
  static String red(String s) => "\x1b[31m$s\x1b[0m";
  static String green(String s) => "\x1b[32m$s\x1b[0m";
  static String inverse(String s) => "\x1b[7m$s\x1b[0m";

  static String _truncate(String s, int maxLen) =>
      s.length <= maxLen ? s : s.substring(0, maxLen);

  static String _padLine(String s, int targetWidth) {
    final vis = _visibleLength(s);
    if (vis >= targetWidth) return s;
    return "$s${" " * (targetWidth - vis)}";
  }

  static int _visibleLength(String s) =>
      s.replaceAll(RegExp(r"\x1b\[[0-9;]*[a-zA-Z]"), "").length;
}
