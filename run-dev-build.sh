mv ~/Downloads/shooting-sports-analyst-ci*.zip .
mv ~/Downloads/Shooting_Sports_Analyst.app.zip .

./build-linux-dev.sh
./package-mac-dev.sh
./package-windows-dev.sh
