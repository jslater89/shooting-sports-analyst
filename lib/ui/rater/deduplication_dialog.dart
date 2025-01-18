import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/action.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/conflict.dart';
import 'package:shooting_sports_analyst/data/ranking/deduplication/shooter_deduplicator.dart';
import 'package:intl/intl.dart';

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
    
    return SingleChildScrollView(
      child: Column(
        children: [
          Text("Issues", style: Theme.of(context).textTheme.titleMedium),
          for(var issue in c.causes)
            IssueDescription(issue: issue),
          Text("Member Numbers", style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              for(var type in c.memberNumbers.keys)
                MemberNumberTypeColumn(type: type, collision: c),
            ],
          )
        ],
      ),
    );
  }
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