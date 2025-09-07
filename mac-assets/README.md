# Mac Installation Instructions

1. Drag the Shooting Sports Analyst.app file to your Applications folder.
2. Attempt to open the application (using Finder, Spotlight, or the 'open' command in the terminal).
3. If Analyst fails to start, go to Privacy & Security in System Preferences, scroll to the bottom,
and allow the application to run.
4. Once allowed, the application should start until the next update.

## Mac-Specific Security Note
Because Apple does not allow unsigned applications to access Keychain, Analyst must store your
Practiscore credentials in a local file. This file is encryped with a key derived from your
Mac's name, your username, and a long random number. An attacker with terminal or desktop
access to your Mac and your user account, along with knowledge of Analyst's key derivation
function, can theoretically decrypt your stored Practiscore credentials.

By using Analyst, you agree to this risk.
