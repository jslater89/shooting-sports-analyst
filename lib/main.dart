// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
      _loadFile();
    }
  }

  String _iframeResultsUrl;
  String _iframeResultsErr;

  BuildContext _innerContext;
  PracticalMatch _canonicalMatch;

  bool _operationInProgress = false;

  FilterSet _filters = FilterSet();
  List<RelativeMatchScore> _baseScores = [];
  String _searchTerm = "";
  List<RelativeMatchScore> _searchedScores = [];
  Stage _stage;
  SortMode _sortMode = SortMode.score;

  bool _shouldShowUploadControls() {
    return _iframeResultsUrl == null;
  }

  Future<void> _downloadFile() async {
    var matchUrl = await showDialog<String>(context: context, builder: (context) {
      var controller = TextEditingController();
      return AlertDialog(
        title: Text("Enter PractiScore match URL"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Copy the URL to the match's PractiScore results page and paste it in the field below.\n\nProcessing may take several seconds.", softWrap: true,),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "https://practiscore.com/results/new/...",
              ),
            ),
          ],
        ),
        actions: [
          FlatButton(
            child: Text("CANCEL"),
            onPressed: () {
              Navigator.of(context).pop();
            }
          ),
          FlatButton(
            child: Text("OK"),
            onPressed: () {
              Navigator.of(context).pop(controller.text);
            }
          ),
        ],
      );
    });

    var matchUrlParts = matchUrl.split("/");
    var matchId = matchUrlParts.last;

    var reportUrl = "";
    if(kDebugMode) {
      reportUrl = "https://cors-anywhere.herokuapp.com/https://practiscore.com/reports/web/$matchId";
    }
    else {
      reportUrl = "https://still-harbor-88681.herokuapp.com/https://practiscore.com/reports/web/$matchId";
    }

    debugPrint("Report download URL: $reportUrl");

    var responseString = "";
    try {
      var response = await http.get(reportUrl);
      if(response.statusCode < 400) {
        responseString = response.body;
        if (responseString.startsWith("\$")) {
          await _processScoreFile(responseString);
          return;
        }
      }
      if(response.statusCode == 404) {
        Scaffold.of(_innerContext).showSnackBar(SnackBar(content: Text("No match record exists at given URL.")));
        return;
      }

      debugPrint("response: ${response.body}");
    }
    catch(err) {
      debugPrint("download error: $err ${err.runtimeType}");
      if(err is ProgressEvent) {
        ProgressEvent pe = err;
        debugPrint(pe.type);
      }
      if(err is http.ClientException) {
        http.ClientException ce = err;
        debugPrint("${ce.uri} ${ce.message}");
      }
      Scaffold.of(_innerContext).showSnackBar(SnackBar(content: Text("Failed to download match report.")));
      return;
    }

    // If we've gotten this far, we probably have a match without a club name set.
    // Try a POST.

    try {
      var tokenLine = responseString.split("\n").firstWhere((element) => element.startsWith('<meta name="csrf-token"'));
      var token = tokenLine.split('"')[3];
      debugPrint("Token: $token");
      var body = {
        '_token': token,
        'ClubName': 'None',
        'matchId': matchId,
      };
      var response = await http.post(reportUrl, body: body);
      if(response.statusCode < 400) {
        var responseString = response.body;
        if (responseString.startsWith("\$")) {
          await _processScoreFile(responseString);
          return;
        }
      }

      debugPrint("Didn't work: ${response.statusCode} ${response.body}");
    }
    catch(err) {
      debugPrint("download error pt. 2: $err ${err.runtimeType}");
    }

    Scaffold.of(_innerContext).showSnackBar(SnackBar(content: Text("Error downloading match file.")));
  }

  Future<void> _loadFile() async {
    if(_iframeResultsUrl != null) {
      try {
        var response = await http.get(_iframeResultsUrl);
        if(response.statusCode < 400) {
          var responseString = response.body;
          if (responseString.startsWith("\$")) {
            await _processScoreFile(responseString);
            return;
          }
        }

        debugPrint("response: $response");
      } catch(err) {
        setState(() {
          _iframeResultsErr = err.toString();
        });
      }
    }
    else {
      InputElement uploadInput = FileUploadInputElement();
      uploadInput.click();

      setState(() {
        _operationInProgress = true;
      });

      uploadInput.onChange.listen((e) {
        // read file content as dataURL
        final files = uploadInput.files;
        if (files.length == 1) {
          final file = files[0];
          FileReader reader = FileReader();

          reader.onLoadEnd.listen((event) async {
            //String reportFile = AsciiCodec().decode(reader.result);
            //String reportFile = String.fromCharCodes(reader.result);
            String reportFile = Utf8Codec().decode(reader.result);
            await _processScoreFile(reportFile);

            setState(() {
              _operationInProgress = false;
            });
          });

          reader.onError.listen((fileEvent) {
            Scaffold.of(_innerContext).showSnackBar(SnackBar(content: Text("File read error")));

            setState(() {
              _operationInProgress = false;
            });
          });

          reader.readAsArrayBuffer(file);
        }
      });
    }
  }

  Future<void> _processScoreFile(String fileContents) async {
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
      listWidget = SizedBox(
        height: size.height,
        width: size.width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () async {
                await _loadFile();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 150),
                  Icon(Icons.cloud_upload, size: 230, color: Colors.grey,),
                  Text("Click to upload a report.txt file from your device", style: Theme
                      .of(context)
                      .textTheme
                      .subtitle1
                      .apply(color: Colors.grey)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () async {
                setState(() {
                  _operationInProgress = true;
                });
                await _downloadFile();
                setState(() {
                  _operationInProgress = false;
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 150),
                  Icon(Icons.cloud_download, size: 230, color: Colors.grey,),
                  Text("Click to download a report.txt file from PractiScore", style: Theme
                      .of(context)
                      .textTheme
                      .subtitle1
                      .apply(color: Colors.grey)),
                ],
              ),
            ),
          ],
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

    final primaryColor = Theme.of(context).primaryColor;
    final backgroundColor = Theme.of(context).backgroundColor;

    if(_operationInProgress) debugPrint("Operation in progress");

    var animation = (_operationInProgress) ?
    AlwaysStoppedAnimation<Color>(backgroundColor) : AlwaysStoppedAnimation<Color>(primaryColor);


    return Scaffold(
      appBar: AppBar(
        title: Text(_canonicalMatch?.name ?? "Match Results Viewer"),
        centerTitle: true,
        actions: (_canonicalMatch == null || !_shouldShowUploadControls() ? [] : [
          Tooltip(
            message: "Upload a new match file from your device, replacing the current data.",
            child: IconButton(
              icon: Icon(Icons.cloud_upload),
              onPressed: () async {
                await _loadFile();
              },
            ),
          ),
          Tooltip(
            message: "Download a new match file from PractiScore, replacing the current data.",
            child: IconButton(
              icon: Icon(Icons.cloud_download),
              onPressed: () async {
                setState(() {
                  _operationInProgress = true;
                });
                await _downloadFile();
                setState(() {
                  _operationInProgress = false;
                });
              },
            ),
          ),
        ]..add(
          IconButton(
            icon: Icon(Icons.help),
            onPressed: () {
              _showAbout(size);
            },
          ))
        ),
        bottom: _operationInProgress ? PreferredSize(
          preferredSize: Size(double.infinity, 5),
          child: LinearProgressIndicator(value: null, backgroundColor: primaryColor, valueColor: animation),
        ) : null,
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

