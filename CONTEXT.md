# PanoWizard — projektkontext

Senast uppdaterad: 2026-10-05.

Läs denna fil när arbetet i projektet återupptas. Uppdatera den vid relevanta
beslut, ändringar och verifieringar så att den beskriver projektets aktuella läge.

## Mål och omfattning

Detta är ett nytt repository för nästa generation av PanoWizard. Målet är att
bygga om appen på en ren, konventionell native macOS-grund i Xcode för framtida
distribution via Mac App Store.

Nuvarande steg är endast att etablera och verifiera Xcode/App Store-grunden.
Appen visar fortfarande standardvyn med en glob och ”Hello, world!”. Ingen
PanoWizard-funktionalitet har implementerats eller migrerats.

Det äldre projektet finns i `../panowizard`. Det har inte modifierats. Migrera
inte kod eller beroenden därifrån utan en ny uttrycklig instruktion. Enda
återanvändningen hittills är den befintliga appikonen, enligt användarens begäran.

## Projekt och inställningar

- Xcode-projekt: `PanoWizard/PanoWizard.xcodeproj`.
- Scheme och produktnamn: `PanoWizard`.
- En native macOS-app-target, Swift och SwiftUI.
- Skapat med Xcode 26.5:s standardmall för macOS App.
- Deployment target: macOS 26.5, mallens standardvärde.
- Organization identifier: `se.egelberg`.
- Bundle identifier: `se.egelberg.panowizard` i Debug och Release.
- Xcode-managed automatic signing (`CODE_SIGN_STYLE = Automatic`).
- Befintligt utvecklarteam: Magnus Egelberg, team-ID `52A6FA9VB5`.
- App Sandbox och Hardened Runtime är aktiverade.
- Mallens åtkomst till användarvalda filer är read-only.
- Genererad Info.plist via Xcode; ingen separat handskriven Info.plist.
- Kategori: `public.app-category.photography`, satt med
  `INFOPLIST_KEY_LSApplicationCategoryType` i Debug och Release.
- Inga tester, storage framework, externa beroenden eller package dependencies.
- Ingen `Package.swift`, egna app-bundle-skript, signeringsskript eller alternativ
  byggmekanism. Fortsätt använda det vanliga Xcode-projektet.

Källkod: `PanoWizard/PanoWizard/PanoWizardApp.swift` och `ContentView.swift`.
Assets: `PanoWizard/PanoWizard/Assets.xcassets`.
`.gitignore` exkluderar `xcuserdata/`, `.DS_Store` och `DerivedData/`.

## Appikon och App Store-validering

Användaren rapporterade att App Store-valideringen nådde App Store Connect men
misslyckades med exakt två problem: saknad `LSApplicationCategoryType` och
saknad Mac-appikon med 512pt @2x. Båda har åtgärdats lokalt.

Ikonen importerades från `../panowizard/Resources/Icons/PanoWizardApp.icns` genom
att extrahera de befintliga representationerna med Apples `iconutil` och kopiera
dem till `AppIcon.appiconset`. Ikonen har inte designats om eller ändrats.
Alla tio importerade PNG-filer verifierades som byte-identiska med de extraherade
representationerna i originalets ICNS.

`AppIcon.appiconset/Contents.json` mappar samtliga Mac-storlekar korrekt:
16, 32, 128, 256 och 512pt, vardera i 1x och 2x. Därmed finns även 512pt @2x,
1024×1024 pixlar. Den äldre appens `PanoWizardApp.png` är också 1024×1024,
men det är ICNS-representationerna som importerats.

I den byggda appen ligger större ikonrepresentationer i `Assets.car`.
Att enbart extrahera den byggda `AppIcon.icns` visar därför inte alla storlekar.
`xcrun assetutil --info` verifierade att den byggda `Assets.car` innehåller
`AppIcon` med 1024×1024 pixlar och scale 2.

App Store Connect-valideringen har **inte** körts om efter dessa korrigeringar.
Lokal verifiering ska inte tolkas som en bekräftad godkänd App Store-validering.

## Utförda verifieringar

- Initiala Debug- och Release-byggen lyckades med normal Apple Development-signering.
- Efter kategori- och ikonfixen lyckades ett rent Release-bygge.
- `codesign --verify --deep --strict` godkände de byggda apparna.
- Debug-appens entitlements verifierades innehålla App Sandbox.
- Byggd Info.plist verifierades med korrekt bundle identifier och Photography-kategori.
- Byggd Info.plist refererar till `AppIcon`.
- Alla tio ikonrepresentationer finns i den kompilerade asset-katalogen, inklusive 1024×1024.
- Xcode gav endast varningen ”Metadata extraction skipped. No AppIntents.framework
  dependency found.” från App Intents-metadataextraktionen; inga byggfel.

Exempel på standardbygge, från repositoryroten:

```sh
xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/panowizard-next-gen-derived-data clean build
```

## Git och fortsatt arbete

- Remote: `https://github.com/meg768/panowizard-next-gen.git`.
- Branch: `main`.
- Tidigare instruktion var att inte committa, tagga eller pusha.
- Användaren har nu uttryckligen begärt `CONTEXT.md` samt commit och push av
  nuvarande projektgrund inklusive kategori- och ikonfixarna.
- Inga taggar har begärts.
- Nästa utvecklingssteg är ännu inte beslutat. Stanna efter dokumentation,
  commit och push; påbörja ingen migration automatiskt.
