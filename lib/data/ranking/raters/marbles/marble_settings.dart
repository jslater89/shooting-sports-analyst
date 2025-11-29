/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'package:shooting_sports_analyst/data/ranking/model/rating_settings.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/marble_model.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/ordinal_power_law_model.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/power_law_model.dart';
import 'package:shooting_sports_analyst/data/ranking/raters/marbles/model/sigmoid_model.dart';

const _modelNameKey = "mrModel";
const _startingMarblesKey = "mrMarbles";
const _anteKey = "mrAnte";
const _relativeScorePowerKey = "mrPower"; // for legacy reasons
const _sigmoidSteepnessKey = "mrSigmoidSteepness";
const _sigmoidMidpointKey = "mrSigmoidMidpoint";
const _ordinalPowerKey = "mrOrdinalPower";

class MarbleSettings extends RaterSettings {
  /// The model to use for distributing marbles.
  static const defaultModel = const PowerLawModel(power: 2.5);

  /// The number of marbles that each new entry starts with.
  static const defaultStartingMarbles = 200;

  /// The percentage of their marbles that each competitor antes up
  /// when entering a match.
  static const defaultAnte = 0.2;

  static const defaultRelativeScorePower = PowerLawModel.defaultPower;
  /// The power for relative score power law distribution.
  double relativeScorePower;

  static const defaultSigmoidSteepness = SigmoidModel.defaultSteepness;
  /// The steepness for sigmoid distribution.
  double sigmoidSteepness;

  static const defaultSigmoidMidpoint = SigmoidModel.defaultMidpoint;
  /// The midpoint for sigmoid distribution.
  double sigmoidMidpoint;

  static const defaultOrdinalPower = OrdinalPowerLawModel.defaultPower;
  /// The power for ordinal power law distribution.
  double ordinalPower;

  String modelName;

  MarbleModel? _model;
  MarbleModel get model => _model!;
  set model(MarbleModel v) {
    _model = v;
    modelName = model.name;
  }

  int startingMarbles;
  double ante;

  MarbleSettings({
    MarbleModel? model,
    this.startingMarbles = defaultStartingMarbles,
    this.ante = defaultAnte,
    this.relativeScorePower = defaultRelativeScorePower,
    this.sigmoidSteepness = defaultSigmoidSteepness,
    this.sigmoidMidpoint = defaultSigmoidMidpoint,
    this.ordinalPower = defaultOrdinalPower,
  }) : this._model = model ?? defaultModel, this.modelName = model?.name ?? defaultModel.name;

  void restoreDefaults() {
    startingMarbles = defaultStartingMarbles;
    ante = defaultAnte;
    relativeScorePower = defaultRelativeScorePower;
    sigmoidSteepness = defaultSigmoidSteepness;
    sigmoidMidpoint = defaultSigmoidMidpoint;
  }

  @override
  void encodeToJson(Map<String, dynamic> json) {
    json[_startingMarblesKey] = startingMarbles;
    json[_anteKey] = ante;
    json[_modelNameKey] = modelName;
    json[_relativeScorePowerKey] = relativeScorePower;
    json[_sigmoidSteepnessKey] = sigmoidSteepness;
    json[_sigmoidMidpointKey] = sigmoidMidpoint;
    json[_ordinalPowerKey] = ordinalPower;
  }

  @override
  void loadFromJson(Map<String, dynamic> json) {
    startingMarbles = json[_startingMarblesKey] ?? defaultStartingMarbles;
    ante = json[_anteKey] ?? defaultAnte;
    relativeScorePower = json[_relativeScorePowerKey] ?? defaultRelativeScorePower;
    sigmoidSteepness = json[_sigmoidSteepnessKey] ?? defaultSigmoidSteepness;
    sigmoidMidpoint = json[_sigmoidMidpointKey] ?? defaultSigmoidMidpoint;
    ordinalPower = json[_ordinalPowerKey] ?? defaultOrdinalPower;
    modelName = json[_modelNameKey] ?? defaultModel.name;

    model = MarbleModel.fromName(modelName, settings: this);
  }
}