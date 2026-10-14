/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/data/booth/shooter_overrides.dart';
import 'package:shooting_sports_analyst/data/sport/match/match.dart';
import 'package:shooting_sports_analyst/data/sport/shooter/shooter.dart';
import 'package:shooting_sports_analyst/data/sport/sport.dart';

enum ShooterOverrideDialogResult { saved, cleared, cancelled }

class ShooterOverrideDialog extends StatefulWidget {
  const ShooterOverrideDialog({
    super.key,
    required this.match,
    required this.shooter,
  });

  final ShootingMatch match;
  final MatchEntry shooter;

  static Future<ShooterOverrideDialogResult?> show(
    BuildContext context, {
    required ShootingMatch match,
    required MatchEntry shooter,
  }) {
    return showDialog<ShooterOverrideDialogResult>(
      context: context,
      builder: (context) =>
          ShooterOverrideDialog(match: match, shooter: shooter),
    );
  }

  @override
  State<ShooterOverrideDialog> createState() => _ShooterOverrideDialogState();
}

class _ShooterOverrideDialogState extends State<ShooterOverrideDialog> {
  late PowerFactor _powerFactor;
  Division? _division;
  ShooterOverride? _existing;

  Sport get _sport => widget.match.sport;

  @override
  void initState() {
    super.initState();
    _powerFactor = widget.shooter.powerFactor;
    _division = widget.shooter.division;
    _existing = ShooterOverrideStore.instance.find(
      widget.match,
      widget.shooter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Edit ${widget.shooter.getName(suffixes: false)}"),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Local override. Reapplied after every broadcast refresh; not sent to the match source.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_sport.hasPowerFactors)
              DropdownButtonFormField<PowerFactor>(
                initialValue: _powerFactor,
                decoration: const InputDecoration(labelText: "Power factor"),
                items: _sport.powerFactors.values.map((pf) {
                  var label = pf.displayName;
                  if (pf.doesNotScore) {
                    label = "$label (does not score)";
                  }
                  return DropdownMenuItem(value: pf, child: Text(label));
                }).toList(),
                onChanged: (pf) {
                  if (pf != null) {
                    setState(() => _powerFactor = pf);
                  }
                },
              ),
            if (_sport.hasDivisions) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<Division>(
                initialValue: _division,
                decoration: const InputDecoration(labelText: "Division"),
                items: _sport.divisions.values.map((d) {
                  return DropdownMenuItem(value: d, child: Text(d.displayName));
                }).toList(),
                onChanged: (d) {
                  setState(() => _division = d);
                },
              ),
            ],
            if (_existing != null) ...[
              const SizedBox(height: 12),
              Text(
                "Override active"
                "${_existing!.originalPowerFactorName != null ? " (was ${_existing!.originalPowerFactorName})" : ""}.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_existing != null)
          TextButton(onPressed: _clear, child: const Text("CLEAR OVERRIDE")),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(ShooterOverrideDialogResult.cancelled),
          child: const Text("CANCEL"),
        ),
        TextButton(onPressed: _save, child: const Text("SAVE")),
      ],
    );
  }

  Future<void> _clear() async {
    var existing = _existing;
    if (existing != null) {
      ShooterOverrideStore.instance.revert(_sport, widget.shooter, existing);
      await ShooterOverrideStore.instance.remove(widget.match, widget.shooter);
    }
    if (!mounted) return;
    Navigator.of(context).pop(ShooterOverrideDialogResult.cleared);
  }

  Future<void> _save() async {
    var store = ShooterOverrideStore.instance;
    var override = buildOverride().forShooter(widget.shooter);
    if (!override.differsFromOriginal) {
      if (_existing != null) {
        store.revert(_sport, widget.shooter, _existing!);
        await store.remove(widget.match, widget.shooter);
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        _existing != null
            ? ShooterOverrideDialogResult.cleared
            : ShooterOverrideDialogResult.cancelled,
      );
      return;
    }
    store.applyOverride(_sport, widget.shooter, override);
    await store.upsert(widget.match, override);
    if (!mounted) return;
    Navigator.of(context).pop(ShooterOverrideDialogResult.saved);
  }

  ShooterOverride buildOverride() {
    var originalPf =
        _existing?.originalPowerFactorName ?? widget.shooter.powerFactor.name;
    var originalDiv =
        _existing?.originalDivisionName ?? widget.shooter.division?.name;
    return ShooterOverride(
      sourceId: widget.shooter.sourceId,
      entryId: widget.shooter.entryId,
      memberNumber: widget.shooter.memberNumber.isNotEmpty
          ? widget.shooter.memberNumber
          : null,
      firstName: widget.shooter.firstName,
      lastName: widget.shooter.lastName,
      powerFactorName: _powerFactor.name,
      divisionName: _division?.name,
      originalPowerFactorName: originalPf,
      originalDivisionName: originalDiv,
    );
  }
}
