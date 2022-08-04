import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uspsa_result_viewer/data/ranking/raters/multiplayer_percent_elo_rater.dart';
import 'package:uspsa_result_viewer/data/ranking/rating_history.dart';
import 'package:uspsa_result_viewer/ui/rater/enter_urls_dialog.dart';

class ConfigureRatingsPage extends StatefulWidget {
  const ConfigureRatingsPage({Key? key, required this.onSettingsReady}) : super(key: key);

  final void Function(RatingHistorySettings, List<String>) onSettingsReady;

  @override
  State<ConfigureRatingsPage> createState() => _ConfigureRatingsPageState();
}

class _ConfigureRatingsPageState extends State<ConfigureRatingsPage> {
  final bool _operationInProgress = false;

  static const combinedLocap = const [
    RaterGroup.open,
    RaterGroup.limited,
    RaterGroup.pcc,
    RaterGroup.carryOptics,
    RaterGroup.locap,
  ];

  static const splitLocap = const [
    RaterGroup.open,
    RaterGroup.limited,
    RaterGroup.pcc,
    RaterGroup.carryOptics,
    RaterGroup.production,
    RaterGroup.singleStack,
    RaterGroup.revolver,
    RaterGroup.limited10,
  ];

  List<String> matchUrls = [];

  @override
  void initState() {
    super.initState();

    _pctWeightController.addListener(() {
      if(_pctWeightController.text.length > 0) {
        var newPctWeight = double.tryParse(_pctWeightController.text);
        if(newPctWeight != null) {
          if(newPctWeight > 1) {
            // _pctWeightController.text = "1.0";
            newPctWeight = 1.0;
          }
          else if(newPctWeight < 0) {
            // _pctWeightController.text = "0.0";
            newPctWeight = 0.0;
          }

          var splitNumber = _pctWeightController.text.split(".");
          int fractionDigits = 2;
          if(splitNumber.length > 1) {
            var lastPart = splitNumber.last;
            if(lastPart.length > 0) {
              fractionDigits = lastPart.length;
            }
          }
          _placeWeightController.text = (1.0 - newPctWeight).toStringAsFixed(fractionDigits);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;
    var animation = (_operationInProgress) ?
      AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);

    return Scaffold(
      appBar: AppBar(
        title: Text("Shooter Rating Calculator"),
        centerTitle: true,
        actions: _generateActions(),
        bottom: _operationInProgress ? PreferredSize(
          preferredSize: Size(double.infinity, 5),
          child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
        ) : null,
      ),
      body: _body(),
    );
  }

  bool _byStage = true;
  bool _keepHistory = false;
  bool _combineLocap = true;

  TextEditingController _kController = TextEditingController(text: "${MultiplayerPercentEloRater.defaultK}");
  TextEditingController _scaleController = TextEditingController(text: "${MultiplayerPercentEloRater.defaultScale}");
  TextEditingController _pctWeightController = TextEditingController(text: "${MultiplayerPercentEloRater.defaultPercentWeight}");
  TextEditingController _placeWeightController = TextEditingController(text: "${MultiplayerPercentEloRater.defaultPlaceWeight}");

  String _validationError = "";

  Widget _body() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                child: Text("ADVANCE"),
                onPressed: () {

                  double? K = double.tryParse(_kController.text);
                  double? scale = double.tryParse(_scaleController.text);
                  double? pctWeight = double.tryParse(_pctWeightController.text);

                  if(K == null) {
                    setState(() {
                      _validationError = "K factor incorrectly formatted";
                    });
                    return;
                  }

                  if(scale == null) {
                    setState(() {
                      _validationError = "Scale factor incorrectly formatted";
                    });
                    return;
                  }

                  if(pctWeight == null || pctWeight > 1 || pctWeight < 0) {
                    setState(() {
                      _validationError = "Percent weight incorrectly formatted or out of range (0-1)";
                    });
                    return;
                  }

                  var ratingSystem = MultiplayerPercentEloRater(
                    K:  K,
                    scale: scale,
                    percentWeight: pctWeight,
                  );

                  var groups = _combineLocap ? combinedLocap : splitLocap;

                  if(matchUrls.isEmpty) {
                    setState(() {
                      _validationError = "No match URLs entered";
                    });
                    return;
                  }

                  if(matchUrls.isEmpty) {
                    setState(() {
                      _validationError = "No match URLs entered";
                    });
                    return;
                  }

                  widget.onSettingsReady(RatingHistorySettings(algorithm: ratingSystem, byStage: _byStage, preserveHistory: _keepHistory, groups: groups), matchUrls);
                },
              ),
              SizedBox(width: 20),
              ElevatedButton(
                child: Text("RESTORE DEFAULTS"),
                onPressed: () {
                  setState(() {
                    _byStage = true;
                    _keepHistory = false;
                    _combineLocap = true;
                    _validationError = "";
                  });
                  _kController.text = "${MultiplayerPercentEloRater.defaultK}";
                  _scaleController.text = "${MultiplayerPercentEloRater.defaultScale}";
                  _pctWeightController.text = "${MultiplayerPercentEloRater.defaultPercentWeight}";
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(width: 400, child: Text(_validationError, style: Theme.of(context).textTheme.bodyText1!.copyWith(color: Theme.of(context).errorColor))),
        ),
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 10),
                      Text("Settings", style: Theme.of(context).textTheme.labelLarge),
                      SizedBox(height: 10),
                      CheckboxListTile(
                        title: Tooltip(
                          child: Text("By stage?"),
                          message: "Calculate and update ratings after each stage if checked, or after each match if unchecked.",
                        ),
                        value: _byStage,
                        onChanged: (value) {
                          if(value != null) {
                            _byStage = value;
                          }
                        }
                      ),
                      CheckboxListTile(
                        title: Tooltip(
                          child: Text("Keep full history?"),
                          message: "Keep intermediate ratings after each match if checked, or keep only final ratings if unchecked.",
                        ),
                        value: _keepHistory,
                        onChanged: (value) {
                          if(value != null) {
                            _keepHistory = value;
                          }
                        }
                      ),
                      CheckboxListTile(
                        title: Tooltip(
                          child: Text("Combine locap?"),
                          message: "Combine ratings for Single Stack, Revolver, Production, and Limited 10 if checked.",
                        ),
                        value: _combineLocap,
                        onChanged: (value) {
                          if(value != null) {
                            _combineLocap = value;
                          }
                        }
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Tooltip(
                            message: "K factor adjusts how volatile ratings are. A higher K means ratings will "
                                "change more rapidly in response to missed predictions.",
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text("K factor", style: Theme.of(context).textTheme.subtitle1!),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 20),
                              child: TextFormField(
                                controller: _kController,
                                textAlign: TextAlign.end,
                                keyboardType: TextInputType.numberWithOptions(),
                                inputFormatters: [
                                  FilteringTextInputFormatter(RegExp(r"[0-9\.]*"), allow: true),
                                ],
                              ),
                            ),
                          ),
                        ]
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Tooltip(
                            message: "Scale factor controls the spread of ratings. A higher scale factor yields ratings with "
                                "larger differences in rating for the same difference in predicted skill.",
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text("Scale factor", style: Theme.of(context).textTheme.subtitle1!),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 20),
                              child: TextFormField(
                                controller: _scaleController,
                                textAlign: TextAlign.end,
                                keyboardType: TextInputType.numberWithOptions(),
                                inputFormatters: [
                                  FilteringTextInputFormatter(RegExp(r"[0-9]*"), allow: true),
                                ],
                              ),
                            ),
                          ),
                        ]
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Tooltip(
                            message: "Percent/placement weight control how much weight the algorithm gives to percent finish "
                                "vs. placement. Too little placement weight can cause initial ratings to adjust very slowly. "
                                "Too much placement weight can unfairly penalize shooters who finish near strong competition in percentage terms.",
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text("Percent/Place Weight", style: Theme.of(context).textTheme.subtitle1!),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 80,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 20),
                                  child: Tooltip(
                                    message: "Edit percent weight to change this field.",
                                    child: TextFormField(
                                      decoration: InputDecoration(
                                        labelText: "Place Wt.",
                                        floatingLabelBehavior: FloatingLabelBehavior.always,
                                      ),
                                      enabled: false,
                                      controller: _placeWeightController,
                                      textAlign: TextAlign.end,
                                      keyboardType: TextInputType.numberWithOptions(),
                                      inputFormatters: [
                                        FilteringTextInputFormatter(RegExp(r"[0-9\-\.]*"), allow: true),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 20),
                                  child: TextFormField(
                                    decoration: InputDecoration(
                                      labelText: "Pct Wt.",
                                      floatingLabelBehavior: FloatingLabelBehavior.always,
                                    ),
                                    controller: _pctWeightController,
                                    textAlign: TextAlign.end,
                                    keyboardType: TextInputType.numberWithOptions(),
                                    inputFormatters: [
                                      FilteringTextInputFormatter(RegExp(r"[0-9\-\.]*"), allow: true),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ]
                      )
                      // entry box for K, one box for percentWeight with calc placeWeight, entry box for scale
                    ],
                  ),
                ),
              ),
              Expanded(
                child:
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text("Matches", style: Theme.of(context).textTheme.labelLarge),
                            IconButton(
                              icon: Icon(Icons.add),
                              color: Theme.of(context).primaryColor,
                              onPressed: () async {
                                var urls = await showDialog<List<String>>(context: context, builder: (context) {
                                  return EnterUrlsDialog();
                                });

                                if(urls == null) return;

                                for(var url in urls) {
                                  if(!matchUrls.contains(url)) {
                                    matchUrls.add(url);
                                  }
                                }

                                setState(() {
                                  // matchUrls
                                });
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        ...matchUrls.map((url) => Text(url)),
                      ],
                    ),
                  )
              )
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _generateActions() {
    return [
      Tooltip(
        message: "Save current project to local storage.",
        child: IconButton(
          icon: Icon(Icons.save),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sorry, not done yet")));
          },
        ),
      ),
      Tooltip(
        message: "Open a project from local storage.",
        child: IconButton(
          icon: Icon(Icons.folder_open),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sorry, also not done yet")));
          },
        ),
      )
    ];
  }
}
