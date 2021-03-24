
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/html_or/html_or.dart';
import 'package:uspsa_result_viewer/version.dart';

void showAbout(BuildContext context, Size screenSize) {
  showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
            title: Text("About"),
            content: SizedBox(
              width: screenSize.width * 0.5,
              child: RichText(
                  text: TextSpan(
                      children: [
                        TextSpan(
                            style: Theme.of(context).textTheme.bodyText1,
                            text: "A Flutter web app for displaying USPSA scores. You can also embed this widget into "
                                "your match website, automatically loading your results file from a provided Internet "
                                "address.\n\n"
                                "Visit the repository at "
                        ),
                        TextSpan(
                            text: "https://github.com/jslater89/uspsa-result-viewer",
                            style: Theme.of(context).textTheme.bodyText1!.apply(color: Theme.of(context).colorScheme.primary),
                            recognizer: TapGestureRecognizer()..onTap = () async {
                              String url = "https://github.com/jslater89/uspsa-result-viewer";
                              HtmlOr.openLink(url);
                            }
                        ),
                        TextSpan(
                            style: Theme.of(context).textTheme.bodyText1,
                            text: " for more information.\n\nuspsa_result_viewer v${VersionInfo.version}\n© Jay Slater 2020\nGPL 3.0"
                        )
                      ]
                  )
              ),
            )
        );
      }
  );
}