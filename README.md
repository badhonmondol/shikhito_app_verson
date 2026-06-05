# shikhito_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
# shikhito_app

update github 
flutter build apk --release
gh release create vX.X.X "build/app/outputs/flutter-apk/app-release.apk" 

git add .github/workflows/ ; git commit -m "Remove workflow - using manual releases only" ; git push origin main
এখন থেকে app update করার সহজ নিয়ম:

1. Code change করো  
যেমন new page add, bug fix, design change, যেকোনো update।

2. কাজ শেষ হলে test/build করে দেখো  
```powershell
flutter analyze
flutter build apk --release
```

3. তারপর নতুন version দিয়ে release command চালাও  
আগের version যদি `1.0.7` হয়, তাহলে পরেরটা দাও `1.0.8`:

```powershell
.\scripts\release_update.ps1 -Version 1.0.8 -Message "নতুন পেজ যোগ করা হয়েছে।"
```

4. GitHub নিজে নিজে কাজ করবে  
এই command দিলে:
- app version update হবে
- `version.json` update হবে
- commit হবে
- GitHub-e push হবে
- নতুন tag তৈরি হবে
- GitHub Actions APK build করবে
- Release-এর ভিতরে `app-release.apk` upload হবে

5. User app open করলে update পাবে  
User app খুললে update popup আসবে।  
না আসলে app-er update button-এ click করলে update দেখাবে।

সবচেয়ে গুরুত্বপূর্ণ:
- একই version দুইবার দিও না।
- প্রতিবার নতুন version দেবে।
- যেমন:
```text
1.0.7 → 1.0.8 → 1.0.9 → 1.1.0
```

ছোট update হলে:
```powershell
.\scripts\release_update.ps1 -Version 1.0.8 -Message "ছোট বাগ ফিক্স করা হয়েছে।"
```

বড় update হলে:
```powershell
.\scripts\release_update.ps1 -Version 1.1.0 -Message "নতুন ফিচার যোগ করা হয়েছে।"
```# shikhito_app_verson
