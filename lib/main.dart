// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:math';
import 'dart:convert';


import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_results_viewer/data/model.dart';
import 'package:uspsa_results_viewer/data/results_file_parser.dart';
import 'package:uspsa_results_viewer/ui/filter_dialog.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Match Results Viewer',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

enum _SortMode {
  score,
  time,
  alphas,
  availablePoints,
  lastName,
}

extension _DisplayString on _SortMode {
  String displayString() {
    switch(this) {

      case _SortMode.score:
        return "Score";
      case _SortMode.time:
        return "Time";
      case _SortMode.alphas:
        return "Alphas";
      case _SortMode.availablePoints:
        return "Available Points";
      case _SortMode.lastName:
        return "Last Name";
    }
    return "INVALID SORT MODE";
  }
}

class _MyHomePageState extends State<MyHomePage> {
  static const _MIN_WIDTH = 1024.0;

  @override
  void initState() {
    super.initState();

    final Map<String, String> params = Uri.parse(window.location.href).queryParameters;
    debugPrint("iframe params? $params");
    final String resultsFileUrl = params['resultsFile'];

    if(resultsFileUrl != null) {
      debugPrint("getting preset results file $resultsFileUrl");
      _iframeResultsUrl = resultsFileUrl;
      _getFile();
    }
  }

  String _iframeResultsUrl;
  String _iframeResultsErr;

  BuildContext _innerContext;
  PracticalMatch _canonicalMatch;

  FilterSet _filters = FilterSet();
  List<RelativeMatchScore> _scores = [];
  Stage _stage;
  _SortMode _sortMode = _SortMode.score;

  bool _shouldShowUploadControls() {
    return _iframeResultsUrl == null;
  }

  void _getFile() async {
    if(_iframeResultsUrl != null) {
      try {
        var resultsString = await HttpRequest.getString(_iframeResultsUrl);
        _processScoreFile(resultsString);
      } catch(err) {
        setState(() {
          _iframeResultsErr = err.toString();
        });
      }
    }
    else {
      InputElement uploadInput = FileUploadInputElement();
      uploadInput.click();

      uploadInput.onChange.listen((e) {
        // read file content as dataURL
        final files = uploadInput.files;
        if (files.length == 1) {
          final file = files[0];
          FileReader reader = FileReader();

          reader.onLoadEnd.listen((event) {
            //String reportFile = AsciiCodec().decode(reader.result);
            //String reportFile = String.fromCharCodes(reader.result);
            String reportFile = Utf8Codec().decode(reader.result);
            _processScoreFile(reportFile);
          });

          reader.onError.listen((fileEvent) {
            Scaffold.of(_innerContext).showSnackBar(SnackBar(content: Text("File read error")));
          });

          reader.readAsArrayBuffer(file);
        }
      });
    }
  }

  void _processScoreFile(String fileContents) {
    String reportFile = fileContents.replaceAll("\r\n", "\n");
    List<String> lines = reportFile.split("\n");

    List<String> infoLines = [];
    List<String> competitorLines = [];
    List<String> stageLines = [];
    List<String> stageScoreLines = [];

    for (String l in lines) {
      l = l.trim();
      if (l.startsWith(r"$INFO"))
        infoLines.add(l);
      else if (l.startsWith("E "))
        competitorLines.add(l);
      else if (l.startsWith("G "))
        stageLines.add(l);
      else if (l.startsWith("I ")) stageScoreLines.add(l);
    }

    _canonicalMatch = processResultLines(
      infoLines: infoLines,
      competitorLines: competitorLines,
      stageLines: stageLines,
      stageScoreLines: stageScoreLines,
    );

    var scores = _canonicalMatch.getScores();

    setState(() {
      _canonicalMatch = _canonicalMatch;
      _scores = scores;
    });

  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    Widget sortWidget;
    Widget keyWidget;

    if(_canonicalMatch == null) {
      sortWidget = Container();
      keyWidget = Container();
    }
    else {
      sortWidget = Column(
        children: [
          _buildFilterControls(),
        ],
      );
      keyWidget = _stage == null ? _buildMatchScoreKey(size) : _buildStageScoreKey(size);
    }

    Widget listWidget;
    if(_canonicalMatch == null && _shouldShowUploadControls()) {
      listWidget = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _getFile,
        child: SizedBox(
          height: size.height,
          width: size.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 150),
              Icon(Icons.cloud_upload, size: 230, color: Colors.grey,),
              Text("Click to upload a report.txt file from PractiScore", style: Theme
                  .of(context)
                  .textTheme
                  .subtitle1
                  .apply(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    else if(_iframeResultsErr != null) {
      listWidget = Text("Error embedding widget: $_iframeResultsErr");
    }
    else {
      listWidget = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: _MIN_WIDTH,
            maxWidth: max(size.width, _MIN_WIDTH),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              keyWidget,
              Expanded(child: ListView.builder(
                  itemCount: (_scores?.length ?? 0),
                  itemBuilder: (ctx, i) {
                    if(_stage == null) return _buildMatchScoreRow(i);
                    else return _buildStageScoreRow(i, _stage);
                  }
              )),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_canonicalMatch?.name ?? "Match Results Viewer"),
        centerTitle: true,
        actions: (_canonicalMatch == null || !_shouldShowUploadControls() ? [] : [
          Tooltip(
            message: "Upload a new match file, replacing the current data.",
            child: IconButton(
              icon: Icon(Icons.cloud_upload),
              onPressed: () {
                _getFile();
              },
            ),
          )
        ])..add(
          IconButton(
            icon: Icon(Icons.help),
            onPressed: _showAbout,
          )
        ),
      ),
      body: Builder(
        builder: (context) {
          _innerContext = context;
          return Column(
            children: [
              sortWidget,
              Expanded(
                child: Center(
                  child: listWidget,
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("About"),
          content: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  style: Theme.of(context).textTheme.bodyText1,
                  text: "A Flutter web app for displaying USPSA scores. You can also embed this widget into "
                      "your match website to show your match results.\n\n"
                      "Visit the repository at "
                ),
                TextSpan(
                  text: "https://github.com/jslater89/uspsa-result-viewer",
                  style: Theme.of(context).textTheme.bodyText1.apply(color: Theme.of(context).colorScheme.primary),
                  recognizer: TapGestureRecognizer()..onTap = () async {
                    String url = "https://github.com/jslater89/uspsa-result-viewer";
                    window.open(url, '_blank');
                  }
                ),
                TextSpan(
                  style: Theme.of(context).textTheme.bodyText1,
                  text: " for more information."
                )
              ]
            )
          )
        );
      }
    );
  }

  Widget _buildFilterControls() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Sort by...", style: Theme.of(context).textTheme.caption),
                  DropdownButton<_SortMode>(
                    underline: Container(
                      height: 1,
                      color: Colors.black,
                    ),
                    items: _buildSortItems(),
                    onChanged: (_SortMode s) {
                      _applySortMode(s);
                    },
                    value: _sortMode,
                  ),
                ],
              ),
              SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Results for...", style: Theme.of(context).textTheme.caption),
                  DropdownButton<Stage>(
                    underline: Container(
                      height: 1,
                      color: Colors.black,
                    ),
                    items: _buildStageMenuItems(),
                    onChanged: (Stage s) {
                      setState(() {
                        _stage = s;
                        _scores = _scores;
                      });

                      _applySortMode(_sortMode);
                    },
                    value: _stage,
                  ),
                ],
              ),
              SizedBox(width: 10),
              FlatButton(
                child: Text("SET FILTERS"),
                onPressed: () async {
                  var filters = await showDialog<FilterSet>(context: context, builder: (context) {
                      return FilterDialog(currentFilters: _filters,);
                    }
                  );

                  if(filters != null) {
                    _filters = filters;
                    _applyFilters();
                  }
                },
              )
            ],
          )
        ),
      ),
    );
  }

  void _applyFilters() {
    List<Shooter> filteredShooters = _canonicalMatch.filterShooters(
      filterMode: _filters.mode,
      allowReentries: _filters.reentries,
      divisions: _filters.divisions.keys.where((element) => _filters.divisions[element]).toList(),
      classes: _filters.classifications.keys.where((element) => _filters.classifications[element]).toList(),
      powerFactors: _filters.powerFactors.keys.where((element) => _filters.powerFactors[element]).toList(),
    );

    if(filteredShooters.length == 0) {
      Scaffold.of(_innerContext).showSnackBar(SnackBar(content: Text("Filters match 0 shooters!")));
      setState(() {
        _scores = [];
      });
      return;
    }

    setState(() {
      _scores = _canonicalMatch.getScores(shooters: filteredShooters);
    });

    _applySortMode(_sortMode);
  }

  void _applySortMode(_SortMode s) {
    switch(s) {
      case _SortMode.score:
        _scores.sortByScore(stage: _stage);
        break;
      case _SortMode.time:
        _scores.sortByTime(stage: _stage);
        break;
      case _SortMode.alphas:
        _scores.sortByAlphas(stage: _stage);
        break;
      case _SortMode.availablePoints:
        _scores.sortByAvailablePoints(stage: _stage);
        break;
      case _SortMode.lastName:
        _scores.sortBySurname();
        break;
    }

    setState(() {
      _sortMode = s;
      _scores = _scores;
    });
  }

  List<DropdownMenuItem<_SortMode>> _buildSortItems() {
    return [
      DropdownMenuItem<_SortMode>(
        child: Text(_SortMode.score.displayString()),
        value: _SortMode.score,
      ),
      DropdownMenuItem<_SortMode>(
        child: Text(_SortMode.time.displayString()),
        value: _SortMode.time,
      ),
      DropdownMenuItem<_SortMode>(
        child: Text(_SortMode.alphas.displayString()),
        value: _SortMode.alphas,
      ),
      DropdownMenuItem<_SortMode>(
        child: Text(_SortMode.availablePoints.displayString()),
        value: _SortMode.availablePoints,
      ),
      DropdownMenuItem<_SortMode>(
        child: Text(_SortMode.lastName.displayString()),
        value: _SortMode.lastName,
      ),
    ];
  }

  List<DropdownMenuItem<Stage>> _buildStageMenuItems() {
    var stageMenuItems = [
      DropdownMenuItem<Stage>(
        child: Text("Match"),
        value: null,
      )
    ];

    for(Stage s in _canonicalMatch.stages) {
      stageMenuItems.add(
        DropdownMenuItem<Stage>(
          child: Text(s.name),
          value: s
        )
      );
    }

    return stageMenuItems;
  }

  Widget _buildMatchScoreKey(Size screenSize) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: _MIN_WIDTH,
        maxWidth: max(screenSize.width, _MIN_WIDTH)
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide()
          ),
          color: Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(2.0),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(flex: 1, child: Text("Row")),
              Expanded(flex: 1, child: Text("Place")),
              Expanded(flex: 3, child: Text("Name")),
              Expanded(flex: 1, child: Text("Class")),
              Expanded(flex: 3, child: Text("Division")),
              Expanded(flex: 1, child: Text("PF")),
              Expanded(flex: 2, child: Text("Match %")),
              Expanded(flex: 2, child: Text("Match Pts.")),
              Expanded(flex: 2, child: Text("Time")),
              Expanded(flex: 3, child: Tooltip(
                  message: "The number of points out of the maximum possible for this stage.",
                  child: Text("Points/${_canonicalMatch.maxPoints}"))
              ),
              Expanded(flex: 5, child: Text("Hits")),
            ],
          ),
        )
      ),
    );
  }

  Widget _buildMatchScoreRow(int i) {
    var score = _scores[i];
    return Container(
      color: i % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: [
            Expanded(flex: 1, child: Text("${i + 1}")),
            Expanded(flex: 1, child: Text("${score.total.place}")),
            Expanded(flex: 3, child: Text(score.shooter.getName())),
            Expanded(flex: 1, child: Text(score.shooter.classification.displayString())),
            Expanded(flex: 3, child: Text(score.shooter.division.displayString())),
            Expanded(flex: 1, child: Text(score.shooter.powerFactor.shortString())),
            Expanded(flex: 2, child: Text((score.total.percent * 100).toStringAsFixed(2))),
            Expanded(flex: 2, child: Text(score.total.relativePoints.toStringAsFixed(2))),
            Expanded(flex: 2, child: Text(score.total.score.time.toStringAsFixed(2))),
            Expanded(flex: 3, child: Text("${score.total.score.totalPoints} (${(score.percentTotalPoints * 100).toStringAsFixed(2)}%)")),
            Expanded(flex: 5, child: Text("${score.total.score.a}A ${score.total.score.c}C ${score.total.score.d}D ${score.total.score.m}M ${score.total.score.ns}NS")),
          ],
        ),
      ),
    );
  }

  Widget _buildStageScoreKey(Size screenSize) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          minWidth: _MIN_WIDTH,
          maxWidth: max(screenSize.width, _MIN_WIDTH)
      ),
      child: Container(
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide()
            ),
            color: Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Row(
              children: [
                Expanded(flex: 1, child: Text("Row")),
                Expanded(flex: 1, child: Text("Place")),
                Expanded(flex: 3, child: Text("Name")),
                Expanded(flex: 1, child: Text("Class")),
                Expanded(flex: 3, child: Text("Division")),
                Expanded(flex: 1, child: Text("PF")),
                Expanded(flex: 3, child: Tooltip(
                    message: "The number of points out of the maximum possible for this stage.",
                    child: Text("Points/${_stage.maxPoints}"))
                ),
                Expanded(flex: 2, child: Text("Time")),
                Expanded(flex: 2, child: Text("Hit Factor")),
                Expanded(flex: 2, child: Text("Stage %")),
                Expanded(flex: 2, child: Text("Match Pts.")),
                Expanded(flex: 4, child: Text("Hits")),
              ],
            ),
          )
      ),
    );
  }
  Widget _buildStageScoreRow(int i, Stage stage) {

    var matchScore = _scores[i];
    var stageScore = _scores[i].stageScores[stage];

    return Container(
      color: i % 2 == 1 ? Colors.grey[200] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(2.0),
        child: Row(
          children: [
            Expanded(flex: 1, child: Text("${i + 1}")),
            Expanded(flex: 1, child: Text("${stageScore.place}")),
            Expanded(flex: 3, child: Text(matchScore.shooter.getName())),
            Expanded(flex: 1, child: Text(matchScore.shooter.classification.displayString())),
            Expanded(flex: 3, child: Text(matchScore.shooter.division.displayString())),
            Expanded(flex: 1, child: Text(matchScore.shooter.powerFactor.shortString())),
            Expanded(flex: 3, child: Text("${stageScore.score.totalPoints} (${(stageScore.score.percentTotalPoints * 100).toStringAsFixed(1)}%)")),
            Expanded(flex: 2, child: Text(stageScore.score.time.toStringAsFixed(2))),
            Expanded(flex: 2, child: Text(stageScore.score.hitFactor.toStringAsFixed(4))),
            Expanded(flex: 2, child: Text((stageScore.percent * 100).toStringAsFixed(2))),
            Expanded(flex: 2, child: Text(stageScore.relativePoints.toStringAsFixed(2))),
            Expanded(flex: 4, child: Text("${stageScore.score.a}A ${stageScore.score.c}C ${stageScore.score.d}D ${stageScore.score.m}M ${stageScore.score.ns}NS")),
          ],
        ),
      ),
    );
  }
}
