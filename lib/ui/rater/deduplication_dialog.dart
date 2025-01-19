import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:intl/intl.dart';
import 'package:shooting_sports_analyst/ui/widget/constrained_tooltip.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/deduplication/blacklist.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/deduplication/data_entry_fix.dart';
import 'package:shooting_sports_analyst/ui/widget/dialog/deduplication/mapping.dart';

/// A dialog that accepts a list of deduplication collisions, displays them
/// and the relevant information to the user, and allows the user to approve,
/// edit, or reject the deduplication actions.
/// 
/// The provided collisions will be edited in place to include the user's
/// changes. The dialog will pop `true` if the user wants to apply all of the
/// collisions' proposed actions and continue with loading the project, or
/// `false` or `null` if the user wants to cancel project loading.
class DeduplicationDialog extends StatefulWidget {
  const DeduplicationDialog({super.key, required this.collisions});

  final List<DeduplicationCollision> collisions;

  @override
  State<DeduplicationDialog> createState() => _DeduplicationDialogState();

  static Future<bool?> show(BuildContext context, List<DeduplicationCollision> collisions) async {
    return showDialog<bool?>(
      context: context,
      builder: (context) => DeduplicationDialog(collisions: collisions),
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

  /// The index of the collision that is currently selected.
  int? _selectedCollisionIndex;

  DeduplicationCollision? get _selectedCollision => _selectedCollisionIndex != null ? widget.collisions[_selectedCollisionIndex!] : null;

  @override
  void initState() {
    super.initState();
    for(var collision in widget.collisions) {
      _originalActions[collision] = [...collision.proposedActions.map((e) => e.copy())];
      _requiresAttention[collision] = collision.causes.every((e) => e.canResolveAutomatically);
    }

    // We should never call this dialog if there are no collisions, but
    // just to be safe, check
    if(widget.collisions.isNotEmpty) {
      _selectedCollisionIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    var parentSize = MediaQuery.of(context).size;
    var width = parentSize.width * 0.8;
    var height = parentSize.height * 0.9;

    return AlertDialog(
      title: const Text("Resolve Conflicts"),
      content: SizedBox(
        width: width,
        height: height,
        // Dialog content: a side pane list of collisions, and a main pane showing
        // collision details.
        child: Row(
          children: [
            SizedBox(
              width: 300,
              child: ListView.builder(
                itemBuilder: (context, index) {
                  var collision = widget.collisions[index];
                  return ConflictListItem(
                    collision: collision,
                    originalActions: _originalActions[collision]!,
                    onTap: () => setState(() {
                      _selectedCollisionIndex = index;
                    }),
                  );
                },
                itemCount: widget.collisions.length,        
              ),
            ),
            Expanded(
              child: ConflictDetails(collision: _selectedCollision),
            )
          ]
        ),
      )
    );
  }
}

class ConflictListItem extends StatelessWidget {
  const ConflictListItem({super.key, required this.collision, required this.originalActions, this.onTap});

  final DeduplicationCollision collision;
  final List<DeduplicationAction> originalActions;
  final VoidCallback? onTap;

    @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(collision.deduplicatorName),
      subtitle: Text(collision.flattenedMemberNumbers.join(", "), softWrap: false, overflow: TextOverflow.ellipsis),
    );
  }
}

class ConflictDetails extends StatefulWidget {
  const ConflictDetails({super.key, required this.collision});

  final DeduplicationCollision? collision;

  @override
  State<ConflictDetails> createState() => _ConflictDetailsState();
}

class _ConflictDetailsState extends State<ConflictDetails> {
  @override
  Widget build(BuildContext context) {
    var c = widget.collision;
    if(c == null) {
      return const Center(child: Text("No collision selected"));
    }

    ProposedActionType? _proposedActionType;
    
    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            children: [
              Text("Issues", style: Theme.of(context).textTheme.titleMedium),
              ConstrainedTooltip(
                waitDuration: const Duration(seconds: 1),
                message: "The detected causes of this collision.",
                constraints: const BoxConstraints(maxWidth: 300),
                child: const Icon(Icons.help_outline),
              )
            ],
          ),
          for(var issue in c.causes)
            IssueDescription(issue: issue),
          Row(
            children: [
              Text("Member Numbers", style: Theme.of(context).textTheme.titleMedium),
              ConstrainedTooltip(
                waitDuration: const Duration(seconds: 1),
                message: "Member numbers in this conflict arranged by type. Numbers that apear in the proposed fixes " +
                  "are highlighted in green. All numbers must appear in green before the conflict can be resolved.",
                constraints: const BoxConstraints(maxWidth: 300),
                child: const Icon(Icons.help_outline),
              )
            ],
          ),
          Row(
            children: [
              for(var type in c.memberNumbers.keys)
                MemberNumberTypeColumn(type: type, collision: c),
            ],
          ),
          Row(
            children: [
              Text("Proposed Actions", style: Theme.of(context).textTheme.titleMedium),
              ConstrainedTooltip(
                waitDuration: const Duration(seconds: 1),
                message: "Proposed actions to resolve this collision.\n\n" +
                  "Use a BLACKLIST to indicate that two numbers refer to different competitors.\n" +
                  "Use a DATA ENTRY FIX when a competitor has entered their member number incorrectly\n" +
                  "Use a MAPPING to indicate that one member number belongs to the same competitor as another. " +
                  "Mappings detected by the deduplicator are labeled 'Automatic Mapping'. Mappings specified by " +
                  "the user are labeled 'User Mapping'. Mappings that appear in project settings but do not fully " +
                  "resolve a conflict are labeled 'Preexisting Mapping'.",
                constraints: const BoxConstraints(maxWidth: 300),
                child: const Icon(Icons.help_outline),
              )
            ],
          ),
          for(var action in c.proposedActions)
            ProposedAction(action: action, onRemove: () => setState(() {
              c.proposedActions.remove(action);
            })),
          Row(
            children: [
              DropdownButton<ProposedActionType>(
                items: ProposedActionType.values.map((e) => DropdownMenuItem(value: e, child: Text(e.uiLabel))).toList(),
                onChanged: (value) => setState(() {
                  if(value != null) {
                    setState(() {
                      _proposedActionType = value;
                    });
                  }
                }),
              ),
              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _proposedActionType == null ? null : () async {
                if(_proposedActionType != null) {
                  var memberNumbers = c.memberNumbers.values.flattened.toList();
                  var coveredNumbers = c.proposedActions.map((e) => e.coveredNumbers).flattened.toList();
                  DeduplicationAction? newAction;
                  switch(_proposedActionType!) {
                    case ProposedActionType.blacklist:
                      newAction = await AddBlacklistEntryDialog.show(context, memberNumbers, coveredMemberNumbers: coveredNumbers);
                      break;
                    case ProposedActionType.dataEntryFix:
                      newAction = await AddDataEntryFixDialog.show(context);
                      break;
                    case ProposedActionType.mapping:
                      newAction = await AddMappingDialog.show(context);
                      break;
                  }

                  if(newAction != null) {
                    var na = newAction;
                    setState(() {
                      c.proposedActions.add(na);
                    });
                  }
                }
              }),
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
  const IssueDescription({super.key, required this.issue});

  final ConflictType issue;

  @override
  Widget build(BuildContext context) {
    return switch(issue) {
      MultipleNumbersOfType(deduplicatorName: var name, memberNumberType: var type, memberNumbers: var numbers) => _buildMultipleNumbersOfType(name, type, numbers),
      FixedInSettings() => Text("Fixed in settings (should never appear)"),
      AmbiguousMapping() => _buildAmbiguousMapping(issue as AmbiguousMapping),
    };
  }

  Widget _buildMultipleNumbersOfType(String deduplicatorName, MemberNumberType memberNumberType, List<String> memberNumbers) {
    var text = "Multiple ${memberNumberType.infixName} numbers: ${memberNumbers.join(", ")}";
    return Text(text);
  }

  Widget _buildAmbiguousMapping(AmbiguousMapping issue) {
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
    return Text("Ambiguous mapping from $sourceNumbers to $targetNumbers");
  }
}

class MemberNumberTypeColumn extends StatelessWidget {
  const MemberNumberTypeColumn({super.key, required this.type, required this.collision});

  final MemberNumberType type;
  final DeduplicationCollision collision;

  @override
  Widget build(BuildContext context) {    
    return Column(
      children: [
        Text(type.uiName),
        for(var number in collision.memberNumbers[type]!)
          Text(number, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: collision.coversNumber(number) ? Colors.green.shade600 : Colors.grey.shade400)),
      ],
    );
  }
}

class ProposedAction extends StatelessWidget {
  const ProposedAction({super.key, required this.action, required this.onRemove});

  final DeduplicationAction action;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(action.descriptiveString),
        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: onRemove),
      ],
    );
  }
}