
/// Round odds given in decimal format to the decimal odds that
/// produce the nearest whole-number moneyline odds.
double roundDecimalOddsToMoneyline(double decimalOdds) {
  if(decimalOdds == 2.0) {
    return 2.0;
  }
  else if(decimalOdds > 2.0) {
    // Convert to positive moneyline, round, convert back to decimal
    var moneylineOdds = ((decimalOdds - 1.0) * 100).round();
    return (moneylineOdds / 100.0) + 1.0;
  }
  else {
    // Convert to negative moneyline, round, convert back to decimal
    var moneylineOdds = (-100 / (decimalOdds - 1.0)).round();
    return 1.0 + (100.0 / moneylineOdds.abs());
  }
}