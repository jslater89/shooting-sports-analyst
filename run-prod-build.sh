mv ~/Downloads/shooting-sports-analyst-ci*.zip .
mv ~/Downloads/Shooting_Sports_Analyst.app.zip .

./build-linux.sh
./package-mac.sh
./package-windows.sh
