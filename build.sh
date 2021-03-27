rm USPSA\ Result\ Viewer*.msi
rm USPSA_Result_Viewer*.AppImage
flutter build web && cp -r build/web/* docs/ && ~/go/bin/hover build windows-msi && ~/go/bin/hover build linux-appimage
cp go/build/outputs/windows-msi-release/USPSA\ Result\ Viewer*.msi .
cp go/build/outputs/linux-appimage-release/USPSA_Result_Viewer-*-x86_64.AppImage .