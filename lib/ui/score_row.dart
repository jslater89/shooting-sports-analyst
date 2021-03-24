import 'package:flutter/material.dart';

class ScoreRow extends StatefulWidget {
  final Widget? child;
  final bool? edited;
  final Color? color;
  final Color? textColor;
  final Color? hoverColor;
  final Color? hoverTextColor;

  const ScoreRow({Key? key, this.child, this.color, this.textColor, this.hoverColor, this.hoverTextColor, this.edited}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _ScoreRowState();
  }
}

class _ScoreRowState extends State<ScoreRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Color background = widget.color ?? Theme.of(context).colorScheme.background;
    Color hoverColor = widget.hoverColor ?? Theme.of(context).colorScheme.primary;
    Color? textColor = widget.textColor ?? Theme.of(context).textTheme.bodyText1!.color;
    Color hoverTextColor = widget.hoverTextColor ?? Theme.of(context).colorScheme.onPrimary;

    if(widget.edited!) {
      textColor = Colors.red;
    }

    ThemeData baseTheme = Theme.of(context);
    return MouseRegion(
      onHover: (e) => setState(() {
        _hover = true;
      }),
      onExit: (e) => setState(() {
        _hover = false;
      }),
      child: Container(
          color: _hover ? hoverColor : background,
          child: Theme(
            child: Builder(
              builder: (context) {
                return DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyText1!,
                  child: widget.child!,
                );
              }
            ),
            data: baseTheme.copyWith(
              textTheme: baseTheme.textTheme.copyWith(
                bodyText1: baseTheme.textTheme.bodyText1!.copyWith(
                  color: _hover ? hoverTextColor : textColor,
                )
              )
            ),
          )
      ),
    );
  }

}