/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:audioplayers/audioplayers.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shooting_sports_analyst/config.dart';
import 'package:shooting_sports_analyst/data/database/schema/ratings.dart';
import 'package:shooting_sports_analyst/data/help/deduplication_help.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:shooting_sports_analyst/data/sport/builtins/uspsa.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';
import 'package:shooting_sports_analyst/logger.dart';
import 'package:shooting_sports_analyst/ui/text_styles.dart';
import 'package:shooting_sports_analyst/ui/widget/clickable_link.dart';
import 'package:shooting_sports_analyst/ui/widget/constrained_tooltip.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/confirm_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/deduplication/blacklist.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/deduplication/data_entry_fix.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/deduplication/mapping.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/help/help_dialog.dart';
import 'package:shooting_sports_analyst/ui/widget/maybe_tooltip.dart';
import 'package:url_launcher/url_launcher.dart';

var _log = SSALogger("DeduplicationDialog");

/// A dialog that accepts a list of deduplication collisions, displays them
/// and the relevant information to the user, and allows the user to approve,
/// edit, or reject the deduplication actions.
/// 
/// The provided collisions will be edited in place to include the user's
/// changes. The dialog will pop `true` if the user wants to apply all of the
/// collisions' proposed actions and continue with loading the project, or
/// `false` or `null` if the user wants to cancel project loading.
class DeduplicationDialog extends StatefulWidget {
  const DeduplicationDialog({super.key, required this.sport, required this.collisions, required this.group});

  final Sport sport;
  final List<DeduplicationCollision> collisions;
  final RatingGroup group;

  @override
  State<DeduplicationDialog> createState() => _DeduplicationDialogState();

  static Future<bool?> show(BuildContext context, {required Sport sport, required List<DeduplicationCollision> collisions, required RatingGroup group}) async {
    return showDialog<bool?>(
      context: context,
      builder: (context) => DeduplicationDialog(sport: sport, collisions: collisions, group: group),
      barrierDismissible: false,
    );
  }
}

class _DeduplicationDialogState extends State<DeduplicationDialog> {
  /// The original actions for each collision, so we can show a 'restore suggested actions'
  /// button.
  Map<DeduplicationCollision, List<DeduplicationAction>> _originalActions = {};

  /// Indicates whether the collision needs user attention. This is definitely true
  /// of any ambiguous or unresolvable mappings, and may be heuristically true for
  /// other kinds of collisions that the deduplicator is less sure about.
  Map<DeduplicationCollision, bool> _requiresAttention = {};

  /// Indicates whether the collision's actions have been approved. Adding or removing
  /// actions to a collision implicitly approves it.
  Map<DeduplicationCollision, bool> _approved = {};
  int get _approvedCount => _approved.values.where((e) => e).length;

  /// Indicates whether the collision has been edited.
  Map<DeduplicationCollision, bool> _edited = {};

  /// Indicates whether the collision has been viewed.
  Map<DeduplicationCollision, bool> _viewed = {};
  int get _viewedCount => _viewed.values.where((e) => e).length;
  /// The index of the collision that is currently selected.
  int? _selectedCollisionIndex;

  AudioPlayer? player;

  DeduplicationCollision? get _selectedCollision => _selectedCollisionIndex != null ? _sortedCollisions[_selectedCollisionIndex!] : null;

  List<DeduplicationCollision> _sortedCollisions = [];
  int get _totalCount => _sortedCollisions.length;
  ScrollController _sidebarScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _sortedCollisions = [...widget.collisions];
    _populateMaps();
    _defaultCollisionSort();

    // We should never call this dialog if there are no collisions, but
    // just to be safe, check
    if(widget.collisions.isNotEmpty) {
      _selectedCollisionIndex = 0;
      _viewed[_selectedCollision!] = true;
    }

    if(ConfigLoader().config.playDeduplicationAlert) {
      player = AudioPlayer();
      player?.play(AssetSource("audio/update-bell.mp3"));
    }
  }

  void _populateMaps() {
    for(var collision in _sortedCollisions) {
      _originalActions[collision] = [...collision.proposedActions.map((e) => e.copy())];
      _requiresAttention[collision] = collision.causes.any((e) => !e.canResolveAutomatically);
      _approved[collision] = _conflictIsGreen(collision, false);
    }
  }

  Map<Type, int> _actionTypeOrder = {
    DataEntryFix: 2,
    Blacklist: 1,
    Mapping: 0,
  };
  void _defaultCollisionSort() {
    _sortedCollisions.sort((a, b) {
      var aGreen = _approved[a] ?? false;
      var bGreen = _approved[b] ?? false;
      
      // Green conflicts should be sorted to the bottom.
      if(aGreen && !bGreen) {
        return 1;
      }
      else if(!aGreen && bGreen) {
        return -1;
      }
      // Collisions containing AmbiguousMappings should be sorted to the top.
      else if(_conflictIsRed(a, _approved[a] ?? false) && !_conflictIsRed(b, _approved[b] ?? false)) {
        return -1;
      }
      else if(!_conflictIsRed(a, _approved[a] ?? false) && _conflictIsRed(b, _approved[b] ?? false)) {
        return 1;
      }

      // Determine the most-likely-to-need-attention actions by type.
      var aScores = a.proposedActions.map((e) => _actionTypeOrder[e.runtimeType] ?? 0);
      var bScores = b.proposedActions.map((e) => _actionTypeOrder[e.runtimeType] ?? 0);
      var aScore = 0;
      var bScore = 0;
      aScores.forEach((e) {
        if(e > aScore) aScore = e;
      });
      bScores.forEach((e) {
        if(e > bScore) bScore = e;
      });

      // Sort scores from high to low.
      if(aScore > bScore) {
        return -1;
      }
      else if(aScore < bScore) {
        return 1;
      }

      return a.deduplicatorName.compareTo(b.deduplicatorName);
    });
  }

  /// Sort unapproved collisions to the top.
  void _approvedCollisionSort() {
    _sortedCollisions.sort((a, b) {
      var aGreen = _approved[a] ?? false;
      var bGreen = _approved[b] ?? false;
      if(!aGreen && bGreen) {
        return -1;
      }
      else if(aGreen && !bGreen) {
        return 1;
      }

      return a.deduplicatorName.compareTo(b.deduplicatorName);
    });
  }

  @override
  Widget build(BuildContext context) {
    var parentSize = MediaQuery.of(context).size;
    var width = parentSize.width * 0.8;
    var height = parentSize.height * 0.9;

    bool shouldAllowApply = _approvedCount == _totalCount;
    bool shouldGrayApply = _viewedCount < _totalCount;
    var applyText = !shouldAllowApply ? "PROGRESS: ${_approvedCount}/${_totalCount}" : "APPLY";
    String? applyTooltip;
    if(!shouldAllowApply) {
      applyTooltip = "You must review and approve all conflicts marked with red or yellow icons before continuing.";
    }
    else if(shouldGrayApply) {
      applyTooltip = "You should review all conflicts before continuing.";
    }

    return Provider.value(
      value: widget.sport,
      child: AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Resolve Conflicts (${widget.group.name})"),
            HelpButton(helpTopicId: deduplicationHelpId),
          ],
        ),
        content: SizedBox(
          width: width,
          height: height,
          // Dialog content: a side pane list of collisions, and a main pane showing
          // collision details.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 300,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Tooltip(
                            message: "You should review all conflicts before continuing.",
                            child: Text("Viewed: ${_viewedCount}/${_totalCount}", style: Theme.of(context).textTheme.bodyMedium)
                          ),
                          Tooltip(
                            message: "You must approve all conflicts before continuing.",
                            child: Text("Approved: ${_approvedCount}/${_totalCount}", style: Theme.of(context).textTheme.bodyMedium)
                          ),
                        ]
                      ),
                    ),
                    Divider(thickness: 1, height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemBuilder: (context, index) {
                          var collision = _sortedCollisions[index];
                          return ConflictListItem(
                            collision: collision,
                            selected: _selectedCollisionIndex == index,
                            originalActions: _originalActions[collision]!,
                            viewed: _viewed[collision] ?? false,
                            approved: _approved[collision] ?? false,
                            edited: _edited[collision] ?? false,
                            onTap: () => setState(() {
                              _conflictIsGreen(collision, _approved[collision] ?? false);
                              _selectedCollisionIndex = index;
                              _viewed[collision] = true;
                            }),
                          );
                        },
                        itemCount: _sortedCollisions.length,   
                        controller: _sidebarScrollController,     
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(thickness: 1, height: 1),
                    Expanded(
                      child: ConflictDetails(
                        sport: widget.sport,
                        collision: _selectedCollision,
                        originalActions: _originalActions[_selectedCollision] ?? [],
                        approved: _approved[_selectedCollision] ?? false,
                        onApprove: () => setState(() {
                          _approved[_selectedCollision!] = true;
                          if(_selectedCollisionIndex! < _sortedCollisions.length - 1) {
                            // observed extent is 64 pixels per row
                            _selectedCollisionIndex = _selectedCollisionIndex! + 1;
                            _viewed[_selectedCollision!] = true;
                            _sidebarScrollController.animateTo(_selectedCollisionIndex! * 64, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
                          }
                          else {
                            _selectedCollisionIndex = 0;
                            _viewed[_selectedCollision!] = true;
                            _sidebarScrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
                          }
                        }),
                        onRestore: () => setState(() {
                          _approved[_selectedCollision!] = false;
                        }),
                        onEdit: () => setState(() {
                          // refresh the conflict list tile
                          _approved[_selectedCollision!] = false;
                          _edited[_selectedCollision!] = true;
                        })
                      ),
                    ),
                    const Divider(thickness: 1, height: 1),
                  ],
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
            ]
          ),
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: "Sort collisions requiring approval to the top.",
                    child: TextButton(
                      child: const Text("SORT UNAPPROVED"),
                      onPressed: () => setState(() {
                        _approvedCollisionSort();
                      }),
                    ),
                  ),
                  Tooltip(
                    message: "Sort collisions by user attention required.",
                    child: TextButton(
                      child: const Text("SORT DEFAULT"),
                      onPressed: () => setState(() {
                        _defaultCollisionSort();
                      }),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,              
                children: [
                  TextButton(
                    child: const Text("CANCEL"),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  MaybeTooltip(
                    message: applyTooltip,
                    child: TextButton(
                      child: Text(applyText),
                      style: TextButton.styleFrom(foregroundColor: shouldGrayApply ? Colors.grey.shade500 : null),
                      onPressed: !shouldAllowApply ? null : () async {
                        if(shouldGrayApply) {
                          var confirm = await ConfirmDialog.show(
                            context,
                            title: "Review incomplete",
                            content: const Text("You have not reviewed all conflicts. Are you sure you want to continue?"),
                            positiveButtonLabel: "CONTINUE",
                            // TODO: SharedPreferences, troll James
                            width: 400,
                          );
                  
                          if(confirm == true) {
                            Navigator.of(context).pop(true);
                          }
                        }
                        else {
                          Navigator.of(context).pop(true);
                        }
                      }
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

bool _conflictIsGreen(DeduplicationCollision collision, bool approved, {bool edited = false}) {
  // A collision is green if it is not flagged for manual review, and it either can be automatically resolved
  // or has been user-approved.

  //A collision can be automatically resolved if it hasn't been edited, all proposed actions can be autoresolved,
  // and it doesn't contain an international number.
  bool autoResolve = 
    !edited 
    && collision.causes.every((e) => e.canResolveAutomatically) 
    && collision.memberNumbers[MemberNumberType.international] == null;

  // A collision requires manual review if it has not been approved, and it has a ManualReviewRecommended cause.
  bool manualReviewRequired = !approved && collision.causes.any((e) => e is ManualReviewRecommended);

  // A collision is user-approved the 'approve' button has been clicked and the proposed actions cover the conflict.
  bool userApproved = approved && collision.proposedActionsResolveConflict();

  return !manualReviewRequired && (autoResolve || userApproved);
}

bool _conflictIsRed(DeduplicationCollision collision, bool approved) {
  var green = _conflictIsGreen(collision, approved);
  var hasAmbiguousMapping = collision.causes.any((e) => e is AmbiguousMapping);
  var hasUncoveredNumbers = !collision.proposedActionsResolveConflict();

  return !green && (hasAmbiguousMapping || hasUncoveredNumbers);
}

class ConflictListItem extends StatelessWidget {
  const ConflictListItem({super.key, required this.collision, required this.originalActions, this.onTap, this.selected = false, this.viewed = false, this.approved = false, this.edited = false});

  final DeduplicationCollision collision;
  final List<DeduplicationAction> originalActions;
  final VoidCallback? onTap;
  final bool selected;
  final bool viewed;
  final bool approved;
  final bool edited;

  @override
  Widget build(BuildContext context) {
    Icon? statusIcon;

    if(_conflictIsRed(collision, approved)) {
      statusIcon = Icon(Icons.warning, color: Colors.red.shade600);
    }
    else if(_conflictIsGreen(collision, approved, edited: edited)) {
      statusIcon = Icon(Icons.check_circle, color: Colors.green.shade600);
    }
    else {
      statusIcon = Icon(Icons.help, color: Colors.yellow.shade700);
    }

    var fontWeight = selected ? FontWeight.bold : null;
    var color = viewed && _conflictIsGreen(collision, approved) ? Colors.grey.shade500 : null;
    var style = Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: fontWeight, color: color);

    // Show numbers in [source, target] format for DataEntryFixes and Mappings, which are
    // directional.
    List<String> numbers;
    if(collision.proposedActions.length == 1 && collision.proposedActions.first is DataEntryFix) {
      var action = collision.proposedActions.first as DataEntryFix;
      numbers = [action.sourceNumber, action.targetNumber, ...collision.flattenedMemberNumbers.where((e) => e != action.sourceNumber && e != action.targetNumber)];
    }
    else if(collision.proposedActions.length == 1 && collision.proposedActions.first is Mapping) {
      var action = collision.proposedActions.first as Mapping;
      numbers = [...action.sourceNumbers, action.targetNumber, ...collision.flattenedMemberNumbers.where((e) => !action.sourceNumbers.contains(e) && e != action.targetNumber)];
    }
    else {
      numbers = collision.flattenedMemberNumbers;
    }

    var subtitleText = numbers.join(", ");
    if(collision.proposedActions.isNotEmpty) {
      subtitleText += "\n(${collision.proposedActions.first.shortUiLabel}";
      if(collision.proposedActions.length > 1) {
        subtitleText += "+${collision.proposedActions.length - 1}";
      }
      subtitleText += ")";
    }
    
    return ListTile(
      onTap: onTap,
      visualDensity: VisualDensity.comfortable,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(collision.deduplicatorName, style: style),
          statusIcon,
        ],
      ),
      subtitle: Text(subtitleText, softWrap: false, overflow: TextOverflow.ellipsis),
    );
  }
}

class ConflictDetails extends StatefulWidget {
  const ConflictDetails({super.key, required this.sport, required this.collision, required this.onApprove, this.onRestore, required this.originalActions, this.onEdit, this.approved = false});

  final Sport sport;
  final DeduplicationCollision? collision;
  final List<DeduplicationAction> originalActions;
  final VoidCallback onApprove;
  final VoidCallback? onRestore;
  final VoidCallback? onEdit;
  final bool approved;

  @override
  State<ConflictDetails> createState() => _ConflictDetailsState();
}

class _ConflictDetailsState extends State<ConflictDetails> {
  ProposedActionType? _proposedActionType;
  var _actionNameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    var c = widget.collision;
    if(c == null) {
      return const Center(child: Text("No collision selected"));
    }

    var resolvesConflict = c.proposedActionsResolveConflict();
    String? tooltip;
    String approveText = "APPROVE";
    if(!resolvesConflict) {
      tooltip = "Proposed actions must contain all relevant member numbers to approve.";
    }
    else if(widget.approved) {
      tooltip = "You have already approved this conflict resolution.";
      approveText = "APPROVED";
    }

    
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text("${c.shooterRatings.values.first.name}", style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text("Issues", style: Theme.of(context).textTheme.titleMedium),
                      ConstrainedTooltip(
                        waitDuration: const Duration(milliseconds: 250),
                        message: "The detected causes of this collision.",
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: const Icon(Icons.help_outline, size: 20),
                        ),
                      )
                    ],
                  ),
                  for(var issue in c.causes)
                    IssueDescription(sport: widget.sport, issue: issue),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text("Member Numbers", style: Theme.of(context).textTheme.titleMedium),
                      ConstrainedTooltip(
                        waitDuration: const Duration(milliseconds: 250),
                        message: "Member numbers in this conflict arranged by type. Numbers that appear in the proposed fixes " +
                          "are highlighted in green. All numbers must appear in green before the conflict can be resolved.",
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: const Icon(Icons.help_outline, size: 20),
                        ),
                      )
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for(var type in c.memberNumbers.keys)
                        MemberNumberTypeColumn(type: type, collision: c),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text("Proposed Actions", style: Theme.of(context).textTheme.titleMedium),
                      ConstrainedTooltip(
                        waitDuration: const Duration(milliseconds: 250),
                        message: "Proposed actions to resolve this collision.\n\n" +
                          "Use a BLACKLIST to indicate that two numbers refer to different competitors.\n" +
                          "Use a DATA ENTRY FIX when a competitor has entered their member number incorrectly\n" +
                          "Use a MAPPING to indicate that one member number belongs to the same competitor as another. " +
                          "Mappings detected by the deduplicator are labeled 'Automatic Mapping'. Mappings specified by " +
                          "the user are labeled 'User Mapping'. Mappings that appear in project settings but do not fully " +
                          "resolve a conflict are labeled 'Preexisting Mapping'.",
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4.0),
                          child: const Icon(Icons.help_outline, size: 20),
                        ),
                      )
                    ],
                  ),
                  for(var action in c.proposedActions)
                    ProposedAction(
                      sport: widget.sport,
                      action: action,
                      onRemove: () => setState(() {
                        c.proposedActions.remove(action);
                        widget.onEdit?.call();
                      }),
                      onEdit: () async {
                        switch(action.runtimeType) {
                          case Blacklist:
                            action as Blacklist;
                            var newAction = await AddBlacklistEntryDialog.edit(context, action.copy(), c.memberNumbers.values.flattened.toList(), coveredMemberNumbers: c.proposedActions.map((e) => e.coveredNumbers).flattened.toList());
                            if(newAction != null) {
                              setState(() {
                                action.sourceNumber = newAction.sourceNumber;
                                action.targetNumber = newAction.targetNumber;
                              });
                              widget.onEdit?.call();
                            }
                            break;
                          case DataEntryFix:
                            action as DataEntryFix;
                            var newAction = await AddDataEntryFixDialog.edit(context, action.copy(), c.memberNumbers.values.flattened.toList(), coveredMemberNumbers: c.proposedActions.map((e) => e.coveredNumbers).flattened.toList());
                            if(newAction != null) {
                              setState(() {
                                action.sourceNumber = newAction.sourceNumber;
                                action.targetNumber = newAction.targetNumber;
                              });
                              widget.onEdit?.call();
                            }
                            break;
                          case UserMapping || AutoMapping:
                            UserMapping mapping;
                            if(action is AutoMapping) {
                              mapping = UserMapping(
                                sourceNumbers: action.sourceNumbers,
                                targetNumber: action.targetNumber,
                              );
                            }
                            else {
                              mapping = action as UserMapping;
                            }
                            var newAction = await AddMappingDialog.edit(context, mapping, c.memberNumbers.values.flattened.toList(), coveredMemberNumbers: c.proposedActions.map((e) => e.coveredNumbers).flattened.toList());
                            if(newAction != null) {
                              setState(() {
                                mapping.sourceNumbers = newAction.sourceNumbers;
                                mapping.targetNumber = newAction.targetNumber;
                                if(action is AutoMapping) {
                                  c.proposedActions.remove(action);
                                  c.proposedActions.add(mapping);
                                }
                              });
                              widget.onEdit?.call();
                            }
                            break;
                          default:
                            _log.w("Unhandled action type: ${action.runtimeType}");
                        }
                      }
                    ),
                  Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Focus(
                          onFocusChange: (hasFocus) {
                            if(!hasFocus) {
                              _actionNameController.text = _proposedActionType?.uiLabel ?? "(none)";
                            }
                          },
                          child: DropdownMenu<ProposedActionType>(
                            dropdownMenuEntries: ProposedActionType.values.map((e) => DropdownMenuEntry(value: e, label: e.uiLabel)).toList(),
                            onSelected: (value) => setState(() {
                              if(value != null) {
                                setState(() {
                                  _proposedActionType = value;
                                });
                              }
                            }),
                            label: const Text("Add action"),
                            initialSelection: _proposedActionType,
                            enableSearch: true,
                            controller: _actionNameController,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: IconButton(padding: const EdgeInsets.all(6), iconSize: 20, icon: const Icon(Icons.add_circle_outline), onPressed: _proposedActionType == null ? null : () async {
                          var memberNumbers = c.flattenedMemberNumbers;
                          var coveredNumbers = c.proposedActions.map((e) => e.coveredNumbers).flattened.toList();
                          DeduplicationAction? newAction;
                          switch(_proposedActionType!) {
                            case ProposedActionType.blacklist:
                              if(memberNumbers.length == 2) {
                                newAction = await AddBlacklistEntryDialog.edit(
                                  context,
                                  Blacklist(
                                    sourceNumber: memberNumbers[0],
                                    targetNumber: memberNumbers[1],
                                    bidirectional: true,
                                  ),
                                  memberNumbers,
                                  coveredMemberNumbers: coveredNumbers,
                                );
                              }
                              else {
                                newAction = await AddBlacklistEntryDialog.show(context, memberNumbers, coveredMemberNumbers: coveredNumbers);
                              }
                              break;
                            case ProposedActionType.dataEntryFix:
                              if(memberNumbers.length == 2) {
                                newAction = await AddDataEntryFixDialog.edit(
                                  context,
                                  DataEntryFix(
                                    sourceNumber: memberNumbers[1],
                                    targetNumber: memberNumbers[0],
                                    deduplicatorName: c.deduplicatorName,
                                  ),
                                  memberNumbers,
                                  coveredMemberNumbers: coveredNumbers,
                                );
                              }
                              else {
                                newAction = await AddDataEntryFixDialog.show(context, c.deduplicatorName, memberNumbers, coveredMemberNumbers: coveredNumbers);
                              }
                              break;
                            case ProposedActionType.mapping:
                              MemberNumberType? bestSingleNumberType;
                              for(var type in MemberNumberType.values) {
                                if(c.memberNumbers[type]?.length == 1) {
                                  bestSingleNumberType = type;
                                }
                              }
                              if(bestSingleNumberType != null) {
                                var targetNumber = c.memberNumbers[bestSingleNumberType]!.first;
                                var sourceNumbers = <String>{};
                                for(var number in c.flattenedMemberNumbers) {
                                  if(number != targetNumber) {
                                    sourceNumbers.add(number);
                                  }
                                }
                                for(var number in c.proposedActions.map((e) => e.coveredNumbers).flattened.toList()) {
                                  if(number != targetNumber) {
                                    sourceNumbers.add(number);
                                  }
                                }
                                newAction = await AddMappingDialog.edit(
                                  context,
                                  UserMapping(
                                    targetNumber: targetNumber,
                                    sourceNumbers: c.causes.any((e) => e is AmbiguousMapping) ? [] : sourceNumbers.toList(),
                                  ),
                                  memberNumbers,
                                  coveredMemberNumbers: coveredNumbers,
                                );
                              }
                              else {
                                newAction = await AddMappingDialog.show(context, memberNumbers, coveredMemberNumbers: coveredNumbers);
                              }
                              break;
                          }
                                  
                          if(newAction != null) {
                            var na = newAction;
                            setState(() {
                              c.proposedActions.add(na);
                            });
                            widget.onEdit?.call();
                          }
                        }),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if(c.uncoveredNumbers.isNotEmpty) Tooltip(
                message: "Blacklist all remaining uncovered numbers to every involved number.",
                child: TextButton(child: const Text("BLACKLIST REMAINING"), onPressed: () {
                  setState(() {
                    var uncovered = c.uncoveredNumbersList;
                    var covered = c.coveredNumbersList;

                    // first, add blacklist entries for all uncovered numbers to the
                    // other uncovered numbers.
                    for(int i = 0; i < uncovered.length; i++) {
                      for(int j = i + 1; j < uncovered.length; j++) {
                        c.proposedActions.add(Blacklist(sourceNumber: uncovered[i], targetNumber: uncovered[j], bidirectional: true));
                      }
                    }
                    
                    // next, add blacklist entries for each uncovered number to every covered number.
                    for(var number in uncovered) {
                      for(var coveredNumber in covered) {
                        c.proposedActions.add(Blacklist(sourceNumber: number, targetNumber: coveredNumber, bidirectional: false));
                      }
                    }
                  });
                }),
              ),
              TextButton(child: const Text("RESTORE ORIGINAL ACTIONS"), onPressed: () {
                 setState(() {
                  c.proposedActions = [...widget.originalActions];
                });
                widget.onRestore?.call();
              }),
              if(!widget.approved) TextButton(
                child: const Text("IGNORE"),
                onPressed: () async {
                  var confirm = await ConfirmDialog.show(
                    context,
                    title: "Ignore conflict",
                    content: const Text(
                      "Ignoring this conflict will result in the proposed actions being applied as-is. " +
                      "This conflict will be raised again on the next full recalculation. Do you want to ignore it?"
                    ),
                    positiveButtonLabel: "IGNORE",
                    width: 400,
                  );
                  if(confirm == true) {
                    widget.onApprove();
                  }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
              MaybeTooltip(
                message: tooltip,
                child: TextButton(
                  child: Text(approveText),
                  onPressed: (resolvesConflict && !widget.approved) ? widget.onApprove : null,
                ),
              ),
              if(widget.approved) TextButton(
                child: const Text("NEXT"),
                onPressed: widget.onApprove,
              )
            ],
          )
        ],
      ),
    );
  }
}

enum ProposedActionType {
  blacklist,
  dataEntryFix,
  mapping;

  String get uiLabel => switch(this) {
    ProposedActionType.blacklist => "Blacklist",
    ProposedActionType.dataEntryFix => "Data Entry Fix",
    ProposedActionType.mapping => "Mapping",
  };
}

class IssueDescription extends StatelessWidget {
  const IssueDescription({super.key, required this.sport, required this.issue});

  final Sport sport;
  final ConflictType issue;

  @override
  Widget build(BuildContext context) {
    return switch(issue) {
      MultipleNumbersOfType() => _buildMultipleNumbersOfType(context, sport, issue as MultipleNumbersOfType),
      FixedInSettings() => Text("• Fixed in settings (should never appear)", style: Theme.of(context).textTheme.bodyMedium),
      AmbiguousMapping() => _buildAmbiguousMapping(context, sport, issue as AmbiguousMapping),
      ManualReviewRecommended() => Text("• Deduplication engine recommends manual review")
    };
  }

  Widget _buildMultipleNumbersOfType(BuildContext context, Sport sport, MultipleNumbersOfType issue) {
    var dedup = sport.shooterDeduplicator;
    var probablyInvalidString = issue.probablyInvalidNumbers.isEmpty ? "" : " (probably invalid: ${issue.probablyInvalidNumbers.join(", ")})";
    var strdiffString = "";
    if(issue.stringDifference > 0 && issue.probablyInvalidNumbers.isEmpty) {
      strdiffString = " (similarity: ${issue.stringDifference}%)";
    }
    if(dedup != null) {
      var text = "• Multiple ${issue.memberNumberType.infixName} numbers: ${issue.memberNumbers.join(", ")}$probablyInvalidString$strdiffString";
      return RichText(text: dedup.linksForMemberNumbers(
        context: context,
        text: text,
        memberNumbers: issue.memberNumbers,
      ));
    }
    else {
      return Text("• Multiple ${issue.memberNumberType.infixName} numbers: ${issue.memberNumbers.join(", ")}$probablyInvalidString$strdiffString", style: Theme.of(context).textTheme.bodyMedium);
    }
  }

  Widget _buildAmbiguousMapping(BuildContext context, Sport sport, AmbiguousMapping issue) {
    var dedup = sport.shooterDeduplicator;
    late String sourceNumbers;
    late String targetNumbers;
    if(issue.sourceNumbers.length > 1) {
      sourceNumbers = "(${issue.sourceNumbers.join(", ")})";
    }
    else {
      sourceNumbers = issue.sourceNumbers.firstOrNull ?? "(null)";
    }
    if(issue.targetNumbers.length > 1) {
      targetNumbers = "(${issue.targetNumbers.join(", ")})";
    }
    else {
      targetNumbers = issue.targetNumbers.firstOrNull ?? "(null)";
    }
    if(dedup != null) {
      return RichText(text: dedup.linksForMemberNumbers(
        context: context,
        text: "• Ambiguous mapping from $sourceNumbers to $targetNumbers",
        memberNumbers: [...issue.sourceNumbers, ...issue.targetNumbers],
      ));
    }
    else {
      return Text("• Ambiguous mapping from $sourceNumbers to $targetNumbers", style: Theme.of(context).textTheme.bodyMedium);
    }
  }
}

class MemberNumberTypeColumn extends StatelessWidget {
  const MemberNumberTypeColumn({super.key, required this.type, required this.collision});

  final MemberNumberType type;
  final DeduplicationCollision collision;

  @override
  Widget build(BuildContext context) {
    var sport = Provider.of<Sport>(context, listen: false);
    bool uspsa = sport.name == uspsaName;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(type.uiName, style: Theme.of(context).textTheme.titleSmall),
          if(uspsa)
            for(var number in collision.memberNumbers[type]!)
              _USPSALink(number: number, collision: collision),
          if(!uspsa)
            for(var number in collision.memberNumbers[type]!)
              Text(number, style: TextStyles.bodyMedium(context).copyWith(color: collision.coversNumber(number) ? Colors.green.shade600 : Colors.grey.shade400)),
        ],
      ),
    );
  }
}

class _USPSALink extends StatelessWidget {
  const _USPSALink({super.key, required this.number, required this.collision});

  final String number;
  final DeduplicationCollision collision;

  @override
  Widget build(BuildContext context) {
    return ClickableLink(
      url: Uri.parse("https://uspsa.org/classification/$number"),
      child: Text(number, style: TextStyles.underlineBodyMedium(context).copyWith(color: collision.coversNumber(number) ? Colors.green.shade600 : Colors.grey.shade400)),
    );
  }
}

class ProposedAction extends StatelessWidget {
  const ProposedAction({super.key, required this.sport,required this.action, required this.onRemove, required this.onEdit});

  final Sport sport;
  final DeduplicationAction action;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    Widget textWidget;
    var dedup = sport.shooterDeduplicator;
    if(dedup != null) {
      textWidget = RichText(text: dedup.linksForMemberNumbers(
        context: context,
        text: action.descriptiveString,
        memberNumbers: action.coveredNumbers.toList(),
      ));
    }
    else {
      textWidget = Text(action.descriptiveString, style: Theme.of(context).textTheme.bodyMedium);
    }
    return Row(
      children: [
        textWidget,
        SizedBox(height: 30, child: IconButton(padding: const EdgeInsets.all(6), iconSize: 20, icon: const Icon(Icons.edit), onPressed: onEdit)),
        SizedBox(height: 30, child: IconButton(padding: const EdgeInsets.all(6), iconSize: 20, icon: const Icon(Icons.remove_circle_outline), onPressed: onRemove)),
      ],
    );
  }
}