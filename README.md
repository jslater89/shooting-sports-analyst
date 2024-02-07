# Shooting Sports Analyst
![A line and bar chart on top of a silhouette target.](https://github.com/jslater89/uspsa-result-viewer/blob/develop/assets/icon.png?raw=true)

Shooting Sports Analyst is a desktop application for viewing, analyzing, and predicting shooting
match results.

## Rating Engine
The rating engine uses match results to generate ratings for shooters based on their performances,
which can be used to generate predictions for future matches. The rating engine uses multiplayer
Elo by default, with options for an experimental Bayesian rating system and a scoring engine for
club or section points series.

For more information on the rating engine, see [README-Elo.md](https://github.com/jslater89/uspsa-result-viewer/blob/develop/README-Elo.md).

## Result Viewer
The result viewer includes a number of features Practiscore lacks:
* Combining results for multiple divisions (e.g., all four locap divisions)
* Removing stages from the match: "Who would have won if we only shot stages 1 to 3 today?"
* Complex querying: e.g. `?revolver and gm or production or "bill duda"` to search for Production
shooters, Revolver grandmasters, and Bill Duda
* Optionally scoring DQed shooters on stages they completed
* Optionally filtering second entries from the results

## Building
This is a pretty standard Flutter desktop/web application. I use `fvm` to lock it to a tested
version of Flutter. No guarantees that other versions of Flutter will work.

Before building, use `flutter pub run flutter_launcher_icons:main` to generate icons, and
`flutter pub run build_runner build` to do any code generation steps required by whatever I happen
to be hacking on at the moment.

### Windows and Linux
Run the appropriate script for your platform.

On Linux, run the `linux-install.sh` script from within the assets directory in this repository
to install a GNOME application entry for the debug version, or run `linux-install.sh` from an
unzipped release to install a GNOME application entry for that version.

### MacOS
An unsigned MacOS release is available, if I seem like the trustworthy sort to you. Download the
release zip file, unzip it, right-click on the unzipped folder and select "New Terminal at Folder",
and enter `./install.sh`. This will copy Shooting Sports Analyst to your Applications folder, and
prompt you for your password or Touch ID to grant permission to run Shooting Sports Analyst.

After installing, Analyst should be available in Launchpad and Spotlight.

## Contributions
For result viewer issues, or Elo rater UI issues, open a pull request.

For Elo rater algorithm issues, please open an issue and attach an exported rater project that
demonstrates the issue first, and be prepared to discuss and/or justify any proposed changes to the
math.
