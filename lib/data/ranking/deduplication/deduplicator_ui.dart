/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/icore_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/typo_deduplicator.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/uspsa_deduplicator.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/idpa.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';
import 'package:url_launcher/url_launcher.dart';

class MemberNumberLinker {
  /// Given a string containing member numbers, return an InlineSpan that provides
  /// URL-launch links to the member's profile on those member numbers.
  /// Default implementation returns a single InlineSpan with no links.
  InlineSpan linksForMemberNumbers({
    required BuildContext context,
    required String text,
    required List<String> memberNumbers,
    TextStyle? runningStyle,
    TextStyle? linkStyle,
  }) {
    runningStyle ??= TextStyles.bodyMedium(context);

    return TextSpan(
      text: text,
      style: runningStyle,
    );
  }

  static MemberNumberLinker forDeduplicator(ShooterDeduplicator d) {
    if(d is TypoDeduplicator) {
      return TypoLinker(d.sport);
    }
    else if(d is IcoreDeduplicator) {
      return IcoreLinker();
    }
    else if(d is USPSADeduplicator) {
      return USPSALinker();
    }

    return MemberNumberLinker();
  }
}

class TypoLinker extends MemberNumberLinker {
  Sport sport;
  TypoLinker(this.sport);

  @override
  InlineSpan linksForMemberNumbers({required BuildContext context, required String text, required List<String> memberNumbers, TextStyle? runningStyle, TextStyle? linkStyle}) {
    if(sport == idpaSport) {
      return MemberNumberLinkBuilder("https://www.idpa.com/members/{{number}}/").linksForMemberNumbers(context: context, text: text, memberNumbers: memberNumbers, runningStyle: runningStyle, linkStyle: linkStyle);
    }
    else {
      return super.linksForMemberNumbers(context: context, text: text, memberNumbers: memberNumbers, runningStyle: runningStyle, linkStyle: linkStyle);
    }
  }
}

class IcoreLinker extends MemberNumberLinker {
  @override
  InlineSpan linksForMemberNumbers({required BuildContext context, required String text, required List<String> memberNumbers, TextStyle? runningStyle, TextStyle? linkStyle}) {
    runningStyle ??= TextStyles.bodyMedium(context);
    linkStyle ??= TextStyles.linkBodyMedium(context);

    // sort member numbers by length, longest first, so that
    // we never split a longer member number by a shorter one
    // that happens to be a substring of it
    // e.g. for "53007" and "A53007", if we split by "53007" first
    // we'll end up with "A53007" -> ["A", "53007"] eventually
    memberNumbers.sort((a, b) => b.length.compareTo(a.length));

    Map<String, TextSpan> spans = {};
    for(var number in memberNumbers) {
      var uniqueId = IcoreMemberNumber(number).uniqueIdentifier;
      var numericUniqueId = uniqueId.replaceAll(RegExp(r"[^0-9]"), "");
      if(uniqueId != numericUniqueId) {
        // If the unique identifier is not entirely numeric, it isn't a DB
        // ID, so we can't link to it; link to the active members list/search
        // instead because all vanity IDs are lifetime/active members.
        spans[number] = TextSpan(
          text: number,
          style: linkStyle,
          recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse("https://icore.org/members-list-active.php")),
          mouseCursor: SystemMouseCursors.click
        );
        continue;
      }

      spans[number] = TextSpan(
        text: number,
        style: linkStyle,
        recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse("https://icore.org/member-details.php?id=$numericUniqueId")),
        mouseCursor: SystemMouseCursors.click,
      );
    }

    int index = 0;
    Map<int, String> numberIndexes = {};

    // Replace each member number with a guard string that will let us split
    // after the member number.
    // e.g.: "String contains A123456, a standard number" -> "String contains ZzZ0XxX, a standard number"
    List<TextSpan> allSpans = [];
    String splittableText = text;
    for(var n in memberNumbers) {
      numberIndexes[index] = n;
      splittableText = splittableText.replaceAll(n, "ZzZ${index}XxX");
      index++;
    }

    // Split the text into parts, and replace each part with a TextSpan, replacing each
    // member number guard string with the corresponding text span.
    // e.g.: "String contains ZzZ0XxX, a standard number" -> ["String contains ZzZ0", ", a standard number"]
    List<String> parts = splittableText.split("XxX");
    for(var part in parts) {
      TextSpan? linkSpan;
      // Each part should contain zero or one guard strings of the format ZzZ<index>.
      // Extract it and replace it with the corresponding TextSpan.
      var pattern = RegExp(r"ZzZ(\d+)");
      var match = pattern.firstMatch(part);
      if(match != null) {
        var index = int.parse(match.group(1)!);
        var number = numberIndexes[index];
        linkSpan = spans[number];
        part = part.replaceFirst(pattern, "");
      }

      allSpans.add(TextSpan(text: part, style: runningStyle));
      if(linkSpan != null) {
        allSpans.add(linkSpan);
      }
    }

    return TextSpan(
      children: allSpans,
    );
  }
}

class USPSALinker extends MemberNumberLinker {
  @override
  InlineSpan linksForMemberNumbers({
    required BuildContext context,
    required String text,
    required List<String> memberNumbers,
    TextStyle? runningStyle,
    TextStyle? linkStyle,
  }) {
    runningStyle ??= TextStyles.bodyMedium(context);
    linkStyle ??= TextStyles.linkBodyMedium(context);

    // sort member numbers by length, longest first, so that
    // we never split a longer member number by a shorter one
    // that happens to be a substring of it
    // e.g. for "53007" and "A53007", if we split by "53007" first
    // we'll end up with "A53007" -> ["A", "53007"] eventually
    memberNumbers.sort((a, b) => b.length.compareTo(a.length));

    Map<String, TextSpan> spans = {};
    for(var number in memberNumbers) {
      spans[number] = TextSpan(
        text: number,
        style: linkStyle,
        recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse("https://uspsa.org/classification/$number")),
        mouseCursor: SystemMouseCursors.click,
      );
    }

    int index = 0;
    Map<int, String> numberIndexes = {};

    // Replace each member number with a guard string that will let us split
    // after the member number.
    // e.g.: "String contains A123456, a standard number" -> "String contains ZzZ0XxX, a standard number"
    List<TextSpan> allSpans = [];
    String splittableText = text;
    for(var n in memberNumbers) {
      numberIndexes[index] = n;
      splittableText = splittableText.replaceAll(n, "ZzZ${index}XxX");
      index++;
    }

    // Split the text into parts, and replace each part with a TextSpan, replacing each
    // member number guard string with the corresponding text span.
    // e.g.: "String contains ZzZ0XxX, a standard number" -> ["String contains ZzZ0", ", a standard number"]
    List<String> parts = splittableText.split("XxX");
    for(var part in parts) {
      TextSpan? linkSpan;
      // Each part should contain zero or one guard strings of the format ZzZ<index>.
      // Extract it and replace it with the corresponding TextSpan.
      var pattern = RegExp(r"ZzZ(\d+)");
      var match = pattern.firstMatch(part);
      if(match != null) {
        var index = int.parse(match.group(1)!);
        var number = numberIndexes[index];
        linkSpan = spans[number];
        part = part.replaceFirst(pattern, "");
      }

      allSpans.add(TextSpan(text: part, style: runningStyle));
      if(linkSpan != null) {
        allSpans.add(linkSpan);
      }
    }

    return TextSpan(
      children: allSpans,
    );
  }
}

class MemberNumberLinkBuilder {
  // The URL to use for the link. The location of the member number in the URL should
  // be indicated by the placeholder string {{number}}.
  final String url;

  MemberNumberLinkBuilder(this.url);

   InlineSpan linksForMemberNumbers({
    required BuildContext context,
    required String text,
    required List<String> memberNumbers,
    TextStyle? runningStyle,
    TextStyle? linkStyle,
  }) {
    runningStyle ??= TextStyles.bodyMedium(context);
    linkStyle ??= TextStyles.linkBodyMedium(context);

    // sort member numbers by length, longest first, so that
    // we never split a longer member number by a shorter one
    // that happens to be a substring of it
    // e.g. for "53007" and "A53007", if we split by "53007" first
    // we'll end up with "A53007" -> ["A", "53007"] eventually
    memberNumbers.sort((a, b) => b.length.compareTo(a.length));

    Map<String, TextSpan> spans = {};
    for(var number in memberNumbers) {
      spans[number] = TextSpan(
        text: number,
        style: linkStyle,
        recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url.replaceFirst("{{number}}", number))),
        mouseCursor: SystemMouseCursors.click,
      );
    }

    int index = 0;
    Map<int, String> numberIndexes = {};

    // Replace each member number with a guard string that will let us split
    // after the member number.
    // e.g.: "String contains A123456, a standard number" -> "String contains ZzZ0XxX, a standard number"
    List<TextSpan> allSpans = [];
    String splittableText = text;
    for(var n in memberNumbers) {
      numberIndexes[index] = n;
      splittableText = splittableText.replaceAll(n, "ZzZ${index}XxX");
      index++;
    }

    // Split the text into parts, and replace each part with a TextSpan, replacing each
    // member number guard string with the corresponding text span.
    // e.g.: "String contains ZzZ0XxX, a standard number" -> ["String contains ZzZ0", ", a standard number"]
    List<String> parts = splittableText.split("XxX");
    for(var part in parts) {
      TextSpan? linkSpan;
      // Each part should contain zero or one guard strings of the format ZzZ<index>.
      // Extract it and replace it with the corresponding TextSpan.
      var pattern = RegExp(r"ZzZ(\d+)");
      var match = pattern.firstMatch(part);
      if(match != null) {
        var index = int.parse(match.group(1)!);
        var number = numberIndexes[index];
        linkSpan = spans[number];
        part = part.replaceFirst(pattern, "");
      }

      allSpans.add(TextSpan(text: part, style: runningStyle));
      if(linkSpan != null) {
        allSpans.add(linkSpan);
      }
    }

    return TextSpan(
      children: allSpans,
    );
  }
}
