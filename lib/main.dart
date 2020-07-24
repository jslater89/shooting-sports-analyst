// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:math';
import 'dart:convert';


import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uspsa_result_viewer/data/model.dart';
import 'package:uspsa_result_viewer/data/results_file_parser.dart';
import 'package:uspsa_result_viewer/data/sort_mode.dart';
import 'package:uspsa_result_viewer/ui/filter_controls.dart';
import 'package:uspsa_result_viewer/ui/filter_dialog.dart';
import 'package:uspsa_result_viewer/ui/score_list.dart';
import 'package:uspsa_result_viewer/version.dart';

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
  List<RelativeMatchScore> _baseScores = [];
  String _searchTerm = "";
  List<RelativeMatchScore> _searchedScores = [];
  Stage _stage;
  SortMode _sortMode = SortMode.score;

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
      _baseScores = scores;
      _searchedScores = []..addAll(_baseScores);
    });

  }

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;

    Widget sortWidget;

    if(_canonicalMatch == null) {
      sortWidget = Container();
    }
    else {
      sortWidget = FilterControls(
        filters: _filters,
        stages: _canonicalMatch.stages,
        currentStage: _stage,
        sortMode: _sortMode,
        onFiltersChanged: _applyFilters,
        onSortModeChanged: _applySortMode,
        onStageChanged: _applyStage,
        onSearchChanged: _applySearchTerm,
      );
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
      listWidget = ScoreList(
        baseScores: _baseScores,
        filteredScores: _searchedScores,
        match: _canonicalMatch,
        stage: _stage,
        minWidth: _MIN_WIDTH,
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
            onPressed: () {
              _showAbout(size);
            },
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

  void _showAbout(Size screenSize) {
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
                    style: Theme.of(context).textTheme.bodyText1.apply(color: Theme.of(context).colorScheme.primary),
                    recognizer: TapGestureRecognizer()..onTap = () async {
                      String url = "https://github.com/jslater89/uspsa-result-viewer";
                      window.open(url, '_blank');
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

  void _applyFilters(FilterSet filters) {
    _filters = filters;

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
        _baseScores = [];
        _searchedScores = [];
      });
      return;
    }

    setState(() {
      _baseScores = _canonicalMatch.getScores(shooters: filteredShooters);
      _searchedScores = []..addAll(_baseScores);
    });

    _applySortMode(_sortMode);
  }

  void _applyStage(Stage s) {
    setState(() {
      _stage = s;
      _baseScores = _baseScores;
      _searchedScores = []..addAll(_baseScores);
    });

    _applySortMode(_sortMode);
  }

  void _applySortMode(SortMode s) {
    switch(s) {
      case SortMode.score:
        _baseScores.sortByScore(stage: _stage);
        break;
      case SortMode.time:
        _baseScores.sortByTime(stage: _stage);
        break;
      case SortMode.alphas:
        _baseScores.sortByAlphas(stage: _stage);
        break;
      case SortMode.availablePoints:
        _baseScores.sortByAvailablePoints(stage: _stage);
        break;
      case SortMode.lastName:
        _baseScores.sortBySurname();
        break;
    }

    setState(() {
      _sortMode = s;
      _baseScores = _baseScores;
      _searchedScores = []..addAll(_baseScores)..retainWhere(_applySearch);
    });
  }

  void _applySearchTerm(String query) {
    _searchTerm = query;
    setState(() {
      _searchedScores = []..addAll(_baseScores);
      _searchedScores = _searchedScores..retainWhere(_applySearch);
    });
  }

  bool _applySearch(RelativeMatchScore element) {
    // getName() instead of first name so 'john sm' matches 'first:john last:smith'
    if(element.shooter.getName().toLowerCase().startsWith(_searchTerm)) return true;
    if(element.shooter.lastName.toLowerCase().startsWith(_searchTerm)) return true;
    return false;
  }
}
