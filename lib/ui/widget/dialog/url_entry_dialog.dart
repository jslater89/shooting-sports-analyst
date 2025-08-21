/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:shooting_sports_analyst/data/source/source.dart';

class UrlEntryDialog extends StatefulWidget {
  const UrlEntryDialog({
    Key? key,
    this.hintText,
    this.sources,
    this.title,
    this.descriptionText,
    this.validator,
    this.showCacheCheckbox,
    this.initialCacheValue,
    this.initialUrl,
    this.typeaheadSuggestions,
    this.typeaheadSuggestionsFunction,
  }) : super(key: key);

  /// The title for the URL entry dialog.
  final String? title;
  /// The description text to show in the URL dialog, above the entry dialog.
  final String? descriptionText;
  /// The hint text to show in the URL dialog.
  final String? hintText;
  /// If present, show a dropdown list of match sources below the URL entry
  /// dialog, and return a tuple of (MatchSource, String?) instead of a string.
  final List<MatchSource>? sources;
  /// A validator function that returns an error message if the URL is invalid
  /// or null if the URL is valid.
  final String? Function(String)? validator;
  /// If true, show a checkbox for the user to indicate whether the caller
  /// is permitted to use cached data, if available. If set, return a tuple of
  /// (bool, String?) instead of a string. Incompatible with [sources].
  final bool? showCacheCheckbox;
  /// If non-null, the initial value of the cache checkbox.
  final bool? initialCacheValue;
  /// If non-null, the initial value of the URL field.
  final String? initialUrl;
  /// If non-null, a list of typeahead suggestions to show in the URL field.
  final List<TypeaheadUrlSuggestion>? typeaheadSuggestions;
  /// If non-null, a function that returns a list of typeahead suggestions
  /// based on the current URL.
  final TypeaheadSuggestionsFunction? typeaheadSuggestionsFunction;

  @override
  State<UrlEntryDialog> createState() => _UrlEntryDialogState();
}

class _UrlEntryDialogState extends State<UrlEntryDialog> {
  final TextEditingController _urlController = TextEditingController();

  String? errorText;
  MatchSource? source;
  bool allowCached = true;
  late TypeaheadSuggestionsFunction? typeaheadSuggestionsFunction;

  @override
  void initState() {
    super.initState();
    if(widget.sources != null) {
      source = widget.sources!.first;
    }
    if(widget.initialCacheValue != null) {
      allowCached = widget.initialCacheValue!;
    }
    if(widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
    }

    if(widget.typeaheadSuggestionsFunction != null) {
      typeaheadSuggestionsFunction = widget.typeaheadSuggestionsFunction!;
    }
    else if(widget.typeaheadSuggestions != null) {
      typeaheadSuggestionsFunction = (String url) {
        var suggestions = widget.typeaheadSuggestions!;
        if(url.isNotEmpty) {
          suggestions = suggestions.where((e) => e.url.toLowerCase().contains(url.toLowerCase())).toList();
        }
        if(suggestions.length > 10) {
          suggestions = suggestions.sublist(0, 10);
        }
        return suggestions;
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? "Enter match link"),
      content: Container(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.descriptionText ?? "Enter a link to a match."),
            TypeAheadFormField(
              suggestionsCallback: (String pattern) async {
                return typeaheadSuggestionsFunction?.call(pattern) ?? [];
              },
              onSuggestionSelected: (suggestion) {
                _urlController.text = suggestion.url;
              },
              itemBuilder: (context, suggestion) {
                return ListTile(
                  title: Text(suggestion.matchName),
                  subtitle: Text(suggestion.url),
                );
              },
              textFieldConfiguration: TextFieldConfiguration(
                decoration: InputDecoration(
                  hintText: widget.hintText ?? "https://practiscore.com/results/new/...",
                  errorText: errorText,
                ),
                controller: _urlController,
              ),
            ),
            if(widget.sources != null)
              DropdownButton<MatchSource>(
                items: widget.sources!.map((e) =>
                    DropdownMenuItem<MatchSource>(
                      child: Text(e.name),
                      value: e,
                    )
                ).toList(),
                value: source!,
                onChanged: (v) {
                  setState(() {
                    source = v;
                  });
                },
              )
            else if(widget.showCacheCheckbox == true)
              CheckboxListTile(
                title: Text("Use cached data"),
                controlAffinity: ListTileControlAffinity.leading,
                value: allowCached,
                onChanged: (v) {
                  setState(() {
                    allowCached = v ?? true;
                  });
                },
              )
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
            child: Text("OK"),
            onPressed: () {
              var url = _urlController.text;
              var error = widget.validator?.call(url);

              setState(() {
                errorText = error;
              });
              if(error == null) submit(url);
            }
        )
      ],
    );
  }

  void submit(String url) {
    if(widget.sources != null) {
      Navigator.of(context).pop((source, url));
    }
    else if(widget.showCacheCheckbox == true) {
      Navigator.of(context).pop((allowCached, url));
    }
    else {
      Navigator.of(context).pop(url);
    }
  }
}

typedef TypeaheadSuggestionsFunction = List<TypeaheadUrlSuggestion>? Function(String);

class TypeaheadUrlSuggestion {
  final String url;
  final String? matchName;

  TypeaheadUrlSuggestion({required this.url, this.matchName});
}
