import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uspsa_result_viewer/data/model.dart';

class MatchListFilters {
  List<MatchLevel> levels = MatchLevel.values;
  DateTime? after;
  DateTime? before;

  MatchListFilters({
    this.levels = MatchLevel.values,
    this.after,
    this.before,
  });

  MatchListFilters.copy(MatchListFilters other) :
      this.levels = []..addAll(other.levels),
      this.after = other.after,
      this.before = other.before;
}

class MatchListFilterDialog extends StatefulWidget {
  const MatchListFilterDialog({Key? key, required this.filters}) : super(key: key);

  final MatchListFilters filters;

  @override
  State<MatchListFilterDialog> createState() => _MatchListFilterDialogState();

  static Future<MatchListFilters?> show(BuildContext context, MatchListFilters filters) {
    return showDialog<MatchListFilters>(
      context: context,
      builder: (context) => MatchListFilterDialog(filters: filters),
      barrierDismissible: false,
    );
  }
}

class _MatchListFilterDialogState extends State<MatchListFilterDialog> {
  late MatchListFilters filters;
  @override
  void initState() {
    super.initState();
    filters = MatchListFilters.copy(widget.filters);
    _updateDates();
  }

  TextEditingController beforeController = TextEditingController();
  TextEditingController afterController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Filter matches"),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    value: filters.levels.contains(MatchLevel.I),
                    title: Text("Level I"),
                    onChanged: (v) {
                      if(v != null) {
                        setState(() {
                          if(v && !filters.levels.contains(MatchLevel.I)) {
                            filters.levels.add(MatchLevel.I);
                          }
                          else {
                            filters.levels.remove(MatchLevel.I);
                          }
                        });
                      }
                    }
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    value: filters.levels.contains(MatchLevel.II),
                      title: Text("Level II"),
                    onChanged: (v) {
                      if(v != null) {
                        setState(() {
                          if(v && !filters.levels.contains(MatchLevel.II)) {
                            filters.levels.add(MatchLevel.II);
                          }
                          else {
                            filters.levels.remove(MatchLevel.II);
                          }
                        });
                      }
                    }
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    value: filters.levels.contains(MatchLevel.III),
                    title: Text("Level III"),
                    onChanged: (v) {
                      if(v != null) {
                        setState(() {
                          if(v && !filters.levels.contains(MatchLevel.III)) {
                            filters.levels.add(MatchLevel.III);
                          }
                          else {
                            filters.levels.remove(MatchLevel.III);
                          }
                        });
                      }
                    }
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      label: Text("After"),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      suffixIcon: IconButton(
                        color: Theme.of(context).primaryColor,
                        icon: Icon(Icons.calendar_month),
                        onPressed: () async {
                          var date = await showDatePicker(
                              context: context,
                              initialDate: filters.after ?? DateTime.now(),
                              firstDate: DateTime(1976, 5, 24),
                              lastDate: DateTime.now()
                          );

                          filters.after = date;
                          _updateDates();
                        },
                      )
                    ),
                    controller: afterController,
                  ),
                ),
                SizedBox(width: 5),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      label: Text("Before"),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      suffixIcon: IconButton(
                        color: Theme.of(context).primaryColor,
                        icon: Icon(Icons.calendar_month),
                        onPressed: () async {
                          var date = await showDatePicker(
                              context: context,
                              initialDate: filters.after ?? DateTime.now(),
                              firstDate: DateTime(1976, 5, 24),
                              lastDate: DateTime.now()
                          );

                          filters.before = date;
                          _updateDates();
                        },
                      )
                    ),
                    controller: beforeController,
                  ),
                )
              ],
            )
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () {
            Navigator.of(context).pop(filters);
          },
        )
      ],
    );
  }

  void _updateDates() {
    beforeController.text = filters.before != null ? DateFormat.yMMMd().format(filters.before!) : "(none)";
    afterController.text = filters.after != null ? DateFormat.yMMMd().format(filters.after!) : "(none)";
  }
}
