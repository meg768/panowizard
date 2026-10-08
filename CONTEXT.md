# PanoWizard — projekt- och utvecklingskontext

Senast uppdaterad: 2026-10-08.

## Aktuellt publiceringsläge — läs först (2026-10-08)

PanoWizard 1.0, build **202610080027**, är **inskickad till App Review**.
Användarens screenshot visar "1 Item Submitted"; Apple anger upp till 48 timmar
och e-post när granskningen är klar. Inget godkännande eller offentlig release
har ännu observerats. Nästa steg är att invänta Apples besked och hantera eventuell
feedback. Skicka inte in på nytt eller byt build utan användarens instruktion.

**Publiceringsbeslut:** PanoWizard är projektet Magnus vill publicera.
**LAN Scanner och Broker Explorer används endast privat/lokalt av Magnus.**
De ska inte förberedas för App Store, GitHub Releases, DMG eller annan offentlig
distribution utan en ny uttrycklig instruktion. Tidigare förslag om distribution
av dessa två verktyg avvisades av användaren.

Aktivt repository är /Users/magnus/Documents/GitHub/panowizard, origin
https://github.com/meg768/panowizard.git. Äldre next-gen-namn och formuleringar
om gamla ../panowizard längre ned är historik, inte aktuella sökvägsinstruktioner.

Läs denna fil innan arbetet återupptas. Uppdatera den när projektets struktur,
beteende, verifiering, distributionsgrund eller viktiga beslut ändras.

## Mål, facit och aktuell instruktion

`panowizard-next-gen` är nästa generation av PanoWizard, byggd som en vanlig
native macOS-app i Xcode för framtida Mac App Store-distribution.

`../panowizard` är den befintliga färdiga appen och är facit. Den får inte ändras.
Problemet som migrationen löser är projekt-/bygg-/distributionsgrunden, inte
applikationskod, algoritmer, arbetsflöden eller design. Gör ingen featureutveckling,
UI-redesign, generell refactoring eller förenkling som tar bort fungerande delar.

Steg 1 skapade en standard SwiftUI/Swift-app med Hello World, följt av Photography-
kategori och den exakt bevarade gamla appikonen. Användaren bekräftade därefter att
denna grund bygger, arkiverar och har passerat App Store Connect Validation.

Steg 2 är nu genomfört lokalt: hela applikationskoden, C++-motorn, nödvändiga
resurser, originalets OpenCV-bibliotek, tester och användarguide har migrerats.
Inga kända applikationsfunktioner har avsiktligt utelämnats.
Användaren har bekräftat lyckad App Store Connect validation av den migrerade
appen. Endast de 11 precompiled OpenCV-bibliotekens symbolvarningar återstår.

Aktuell instruktion (2026-10-06): slutför Tutorial-migrering till självförsörjande
/docs med lokala bilder. Tidigare förbud att röra Tutorial/ är ersatt av denna
nya instruktion. Ingen appkod ändras. Användaren har därefter begärt commit+push till origin/main.
Filåtkomst ska vara projektspecifik: återställ optional metadata inuti `.pw`,
kontrollera samtliga original och begär direkt native Grant Access-katalogåtkomst
per otillgänglig plats om permission saknas, utan preliminär app-alert. Spara
bookmarks i projektet för omstart. Legacy-projekt utan metadata ska kunna
auktoriseras och sedan uppgraderas genom vanlig Save. Originalbilder ska alltid
vara externa; kopiera eller flytta dem aldrig till `.pw`.

## Repository och checkpoint

- Remote: `https://github.com/meg768/panowizard-next-gen.git`.
- Branch: `main`.
- Senaste committade grund: `c3526fb820096b8eaaf46a7f68001e908fbd4798`.
- Taggen `pre-migration` pekar på denna commit och finns på origin.
- Migrationen och efterföljande verifierade korrigeringar ingår i checkpointen
  som användaren begärde att committa och pusha 2026-10-06.
- Det gamla projektet var rent vid start. Dess samtliga vanliga filers innehåll
  (även Vendor och befintliga byggfiler, exklusive Git-internals) jämfördes med
  SHA-256 före/efter och var oförändrat.

## Native Xcode-grund

- Projekt: `PanoWizard/PanoWizard.xcodeproj`.
- Delat scheme: `PanoWizard`, i `xcshareddata/xcschemes/PanoWizard.xcscheme`.
- App-target och produkt: `PanoWizard`, `PanoWizard.app`.
- Native macOS, SwiftUI, Swift 6 language mode, Xcode 26.5.
- Deployment target kvar på macOS 26.5, från den nya verifierade grunden.
- Organization identifier: `se.egelberg`.
- Bundle identifier: **`se.egelberg.panowizard`**, Debug och Release.
- Automatic Xcode-managed signing, team Magnus Egelberg, ID `52A6FA9VB5`.
- App Sandbox och Hardened Runtime kvar aktiverade.
- Photography-kategori: `public.app-category.photography`.
- Xcode-genererad Info.plist kompletteras med `PanoWizard/Info.plist`, som endast
  innehåller originalets dokumenttyp och exporterade UTI-deklarationer.
- Projektpaket: `.pw`, UTI `se.egelberg.panowizard.project`, Editor/Owner,
  originalets `PanoWizardProject.icns` som dokumentikon.
- App Store-version/build är fortfarande Xcode-inställningar: 1.0 / 1.
  Det gamla skriptets tidsbaserade versionsnummer har inte återinförts.
- Inga storage frameworks eller Swift package dependencies.
- Ingen `Package.swift` eller egna bundle-, signerings- eller distributionsskript.
- `.gitignore` exkluderar användarspecifik Xcode-state, `.DS_Store` och DerivedData.

Originalets Swift package använde standard Swift 6-konkurrens utan Xcode-mallens
MainActor-isolering som standard. Den inställningen togs därför bort från app-
targeten; källkodens befintliga explicita actor-annoteringar behölls. Algoritmer,
parametrar, maskvillkor, cacheidentiteter och bildbehandlingsordning ändrades inte.

## Struktur och beroenden

- `PanoWizard/PanoWizard/Application` — app-/dokumentlivscykel och menyer.
- `PanoWizard/PanoWizard/Models` — projektformat, originalbilder, masker, patches,
  justeringar och dokumentpaket.
- `PanoWizard/PanoWizard/Services` — import, metadata, stitchning, retusch,
  bildbehandling, Little Planet, exporter och sandboxens filåtkomst.
- `PanoWizard/PanoWizard/ViewModels` — AppModel och arbetsflöden.
- `PanoWizard/PanoWizard/Views` — hela befintliga SwiftUI/AppKit-gränssnittet.
- `PanoWizard/PanoWizard/Assets.xcassets` — originalets oförändrade appikon.
- `PanoWizard/OpenCVBridge` — originalets `PanoramaBridge.cpp` och C-header.
- `PanoWizard/Resources` — Backgrounds, dokumentikon och ThirdPartyLicenses.
- `PanoWizard/Vendor/OpenCV` — originalets OpenCV 5-headers och dylibs.
- `PanoWizard/PanoWizardTests` — samtliga 13 ursprungliga Swift Testing-filer.
- `docs` — självförsörjande GitHub Pages-help, illustrerade guider och bilder.
- `README.md` — befintlig funktionsbeskrivning med nya Xcode-bygginstruktioner.

`OpenCVBridge` är en native Xcode static-library-target med C++17. En liten
`module.modulemap` gör originalets C-API tillgängligt som `import OpenCVBridge`.
Header och C++-implementation är byte-identiska med facit. Xcode länkar libc++ och
OpenCV och använder en vanlig Copy Files-fas till Frameworks med CodeSignOnCopy.
Inga externa stitchningsverktyg eller hjälpprocesser används.

Originalets 11 distribuerade OpenCV 5-bibliotek finns med:
calib, core, features, flann, geometry, imgcodecs, imgproc, objdetect, photo,
stereo och stitching (`libopencv_*.500.dylib`). De kopierade Vendor-binarierna är
byte-identiska med originalen. Xcode signerar de inbäddade kopiorna normalt.
Samtliga transitiva `@rpath`-referenser kontrollerades finnas i appens Frameworks;
övriga referenser går till Apples systembibliotek. Inga lokala Vendor-sökvägar
behövs vid runtime.

**Slutligt arkitekturbeslut (2026-10-05): PanoWizard är avsiktligt Apple Silicon / arm64-only.**
Originalets verifierade OpenCV 5.0-binarier är endast arm64.
Lägg inte till Intel/x86_64-stöd, bygg inte om OpenCV och skapa inte universal
binaries. Acceptera inte Xcodes förslag om standard architectures.
`ARCHS = arm64` används därför för app, bridge och tester. Intel-stöd har inte
skapats; även det gamla byggskriptet byggde endast arm64. Byt inte OpenCV-version
eller algoritmer för att lösa detta utan en uttrycklig ny uppgift.

Bakgrunderna A.jpg, B.jpg och C.png kopieras som en vanlig Backgrounds-resursmapp.
Välkomstvyns enda resursändring är `Bundle.module` → `Bundle.main`.
Originalets OpenCV-/tredjepartslicenser följer med i appresurserna.

## Appikon

Den befintliga appikonen importerades i steg 1 från
`../panowizard/Resources/Icons/PanoWizardApp.icns` med Apples `iconutil`.
Alla tio PNG-representationer i AppIcon.appiconset är byte-identiska med de
extraherade originalrepresentationerna. Ingen redesign, färgändring eller
annan bildändring gjordes.

Alla Mac-slots finns: 16, 32, 128, 256 och 512pt, var och en i 1x/2x.
512pt @2x är 1024×1024 och verifierades i den kompilerade Assets.car.
Stora representationer ligger i Assets.car; extraktion av enbart den byggda
AppIcon.icns visar därför inte hela ikonuppsättningen.

## Sandbox och nödvändiga kodanpassningar

Signerade app-entitlements har verifierats innehålla:

- `com.apple.security.app-sandbox = true`.
- `com.apple.security.files.user-selected.read-write = true` — projekt,
  JPEG/PNG/HTML/Little Planet/manual patch-export och filhantering.
- `com.apple.security.files.bookmarks.app-scope = true` — åtkomst till externa
  originalbilder efter panelen stängts och efter omstart.
- `com.apple.security.network.client = true` — befintlig OpenAI AI-retuschering.

Ingen full-disk-access, sandboxexception, avstängd library validation eller
annan bred säkerhetsförsvagning har införts.

Originalets projekt sparar **referenser till externa originalbilder**, inte
inbäddade kopior av dem. Projektformat **10 är oförändrat**. Det ursprungliga
filåtkomstbeteendet var inte tillräckligt för en sandboxad app efter omstart.

`SourceFileAccess.swift` håller security-scoped åtkomst aktiv under körningen.
Den använder inte längre UserDefaults för source grants. Individuella grants från
ImageImportService lagras i minnet tills Save skriver optional projektmetadata.
Både första bildvalet och Add måste skapa en riktig bookmark innan bilden accepteras.
Native folder recovery håller vald katalog aktiv på samma sätt.

Projektet kan innehålla **`source-access.json`** som optional paketmedlem:

```json
{
  "version": 1,
  "bookmarks": {
    "/absolute/path/to/source-folder-or-file": "BASE64_OPAQUE_APP_SCOPED_BOOKMARK_DATA"
  }
}
```

Swift Codable Data är Base64 i JSON. Nycklarna är standardiserade absoluta
POSIX-sökvägar. Endast redan beviljade grants som täcker projektets source-URL:er
sparas. En beviljad katalog dedupliceras och ersätter redundanta individuella
filbookmarks i samma katalog. Ingen bredare katalogåtkomst skapas automatiskt.
Gamla paket utan filen får tom bookmarkmetadata och läses som tidigare.
`project.json` och dess formatVersion **10** är oförändrade.

Bookmarks är **app-scoped men lagras projektspecifikt i `.pw`**, inte i
appinställningar. Apple document-scoped bookmarks kräver både filanchor och
filtarget; de stöder inte katalogtargets. App-scoped bookmarks stödjer den
begärda native katalogauktoriseringen och behöver bara befintlig app-scope-
entitlement. Apple DTS-källa:
https://developer.apple.com/forums/thread/798402?answerId=855880022
Inget document-scope-entitlement eller tillfälligt sandboxundantag har införts.

Vid dokumentläsning återställs **endast det öppnade projektets bookmarks** med
`.withSecurityScope`, `.withoutUI` och startAccessingSecurityScopedResource,
innan source images eller metadata används av previews. Resolved bookmarkdata
återskapas i minnet och kan sparas vid nästa Save, inklusive stale refresh.
En process kan förstås fortfarande ha åtkomst från redan öppnade projekt; macOS
sandboxgrant är process-wide. Det är inte ett persistent globalt source-register.

Alla projektsources kontrolleras med riktig FileHandle-open/read. Permissionfel
samlas för hela projektet innan NSOpenPanel visas direkt med den förväntade
parentkatalogen. Panelens Grant Access är användarens bekräftelse. Efter varje
kataloggrant kontrolleras återstående sources; nästa nödvändiga katalog visas
direkt utan ytterligare Grant Access-alert. En katalog som täcker flera originals
eller subkataloger eliminerar deras ytterligare pickerbehov. Cancel avbryter.
Övriga I/O-fel har vanlig felhantering. Nekad åtkomst ska inte radera referenser.

Grants blir optional metadata i dokumentets working state och gör dokumentet
osparat tills Save. Save skriver metadata tillsammans med oförändrat övrigt
projekttillstånd. Save As inkluderar samma relevanta app-scoped grants och kräver
ingen document-anchor-rebind. Projektfönstrets sourceReloadRevision startar om
befintliga previews efter lyckad resolution. Revert följer samma läs-/recoveryväg.

En app-scoped bookmark är knuten till appens signeringsidentitet och lokala
filsystem. Ingen garanti om åtkomst efter flytt till annan dator/användare/annan
signeringsidentitet, eller externa file moves/stale-situationer som inte testats.
Otillgängliga grants kan återställas via samma recovery. Projektmetadata innehåller
inte source image bytes och duplicerar/flyttar aldrig original.

Jämförelse mot facit: **36 gamla Swift-filer migrerade**, varav 32 är
byte-identiska. De fyra med nödvändiga anpassningar är:

1. PanoramaWelcomeView.swift — Bundle.main för resurser.
2. ImageImportService.swift — behåll security-scoped originalbildsåtkomst.
3. PanoProjectDocument.swift — återställ sparad åtkomst innan missing-file-logik.
4. PanoWizardApp.swift — resolution i dokumentfönstrets livscykel och tydligt fel.

**Avsiktliga skillnader från gamla appen:** legacy-projekt utan tidigare sparade
åtkomstgrants kan behöva användarvald Grant Access för externa original. Ingen
mappdialog visas automatiskt för läsbara projekt. Sandboxen och lowercase bundle-ID ger
separata apppreferenser; gammal API-nyckel och UI-preferenser importeras inte
automatiskt. API-nyckeln anges i samma befintliga dialog. Ingen ny nyckellagrings-
lösning eller automatisk kopiering av känsliga inställningar har införts.

## Applikationsbeteende och invariants från facit

Behåll befintlig implementation av:

- En komplett överlappande horisontell fisheye-ring för 360° × 180°, inte multi-row.
- Delade kamera-/linsparametrar, separata repair images och optimerad geometri.
- Originalorientering med ImageIO följt av användarens quarter turns.
- Röda alpha-baserade exklusionsmasker och gröna seam-priority-masker.
- SIFT, rotation RANSAC, robust kamera/linsoptimering, horisontnivellering,
  spherical warp, radiometri, GraphCut/ägarskap, seam-korrigering och blending.
- Alpha-bevarande 2:1 PNG internt; transparenta pixlar är saknad täckning,
  ogenomskinligt svart är vanligt bildinnehåll.
- Panorama-preview, identisk drag/scroll/Command-zoom-navigation och maskverktyg.
- Manuella och AI-retouch patches med befintlig skapande-/redigeringslivscykel;
  patches påverkar inte stitchningsgeometrin. Nyare patch ligger ovanpå äldre.
- Befintlig alpha-härledd redigerbar AI-mask, prompt och sparade resultat.
- Globala icke-destruktiva justeringar efter retouch, gemensamma för preview/export.
- Little Planet stereografisk projektion med befintlig center/rotation/resize.
- JPEG, PNG och självständig HTML-export med samma implementation.
- Dokument-, Save/Save As/Revert-/stängningslivscykel, menyer, genvägar och filhantering.
- Engelskt gränssnitt och befintlig design; ingen ny språkväxlare eller UI-redesign.
- Produktionsmotorn läser bara uttryckligen valda original och masker.
  Ingen automatisk bildsökning eller fallberoende specialkod.
- Cacheformatnycklar och kopplade matematiska parametrar får inte ändras vid
  orelaterad migration, namnändring eller cleanup.

Den gamla `best-ever`-taggen är referens för visuellt verifierade panoramor A–S.
En lyckad kompilering eller ett syntetiskt test bevisar inte samma visuella
resultat för dessa verkliga fotopanorama. Ingen A–S-körning gjordes i migrationen.

## Lokal Build-mapp

Xcodes vanliga `CONFIGURATION_BUILD_DIR` är satt på projektnivå till
`$(HOME)/Library/Developer/Xcode/PanoWizardBuilds/$(CONFIGURATION)`.
Repositoryts Git-ignorerade `Build` är en lokal symlink till
`~/Library/Developer/Xcode/PanoWizardBuilds`. Apparna nås därför som
`Build/Debug/PanoWizard.app` respektive `Build/Release/PanoWizard.app`.
Där finns senaste lyckade bygge per konfiguration. Ingen egen kopierings-,
bundle- eller signeringsmekanism används; Xcode bygger och signerar normalt.

Anledningen till den externa lagringen är att repositoryt ligger i iCloud Documents.
Ett direkt appbygge under repositoryts Build fick FinderInfo/fileprovider-metadata
av iCloud och Xcodes codesign avvisade det. Byggprodukterna måste därför hållas
utanför iCloud. Release-bygget och `codesign --verify --deep --strict` lyckades efter denna ändring.
På en ny checkout kan Build-länken återskapas till ovanstående
lokala mapp; den maskinspecifika länken versionshanteras inte.

## Bygga, testa och arkivera

Använd alltid det vanliga Xcode-projektet och delade PanoWizard-schemat. Exempel
från repositoryroten:

```sh
xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/panowizard-migration clean build

xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/panowizard-migration-release clean build

xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -destination 'platform=macOS,arch=arm64' test

xcodebuild -project PanoWizard/PanoWizard.xcodeproj \
  -scheme PanoWizard -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath /tmp/panowizard-migration.xcarchive archive
```

PanoWizardTests är en native hosted test-target med originalets `@testable import`.
OpenCVBridge bygger normalt som ett targetberoende. Testtarget och bridge använder
SKIP_INSTALL och ska inte hamna som separata produkter i distributionsarkivet.

## Verifierat i migrationen

- Rena Debug- och Release-byggen lyckades.
- Native Release-arkivering lyckades.
- Samtliga 54 befintliga testfall i 13 suites rapporterade godkänt. De omfattar
  projektdokument, metadata/orientering, gruppering, native bridge-validering,
  syntetiskt 2:1-panorama och cacheåteranvändning, maskdispatch, retouch,
  patchredigering, justeringar, Little Planet, spherical math, UI-interaktionsmath
  och OpenAI request/response-hantering.
- Testet `panoramaFixture` returnerar utan arbete om
  `PANOWIZARD_PANORAMA_PROJECT` saknas. Det var inte konfigurerat här;
  de 54 rapporterade testen betyder därför inte att ett riktigt fotoprojekt testats.
- Tester kördes efter de slutliga kodanpassningarna.
- Originalets C++-motor/header är byte-identiska. Testfilerna var ursprungligen
  identiska; ImageMetadataReaderTests har senare fått faktisk filskapning i
  importfixture och kontroll av bookmarkfel enligt senaste filåtkomstuppgiften.
- Originalets resurser, licenser och Vendor-bibliotek har jämförts; alla
  transitiva bibliotek finns i den byggda appen utan externa Vendor-runtimekrav.
- `codesign --verify --deep --strict` godkände appen; signerade sandboxentitlements
  och Info.plist/UTI/kategori kontrollerades.
- Appikonen har erforderlig kompilerad 1024×1024-representation.
- Den signerade sandboxade Release-appen startades och provades via macOS-UI.
  Välkomstvy, originalbildens thumbnail och spherical preview visades.
- Ett enbart syntetiskt format-10-projekt öppnades med den nya mappdialogen.
  Save As sparade `.pw`, relativ källbildssökväg och panorama bytes oförändrat.
- Appen avslutades/startades om och det sparade projektet öppnades utan en ny
  mappauktorisering; originalbild och preview fanns kvar.
- JPEG och PNG exporterades i 1024×512; HTML innehöll sin inbäddade bild.
  Little Planet-dialog och PNG-export fungerade (512×512 för testpanoramat).
- Move Source File to Trash lyckades för den egna syntetiska testbilden.
  Inga gamla projektbilder användes för denna destruktiva teståtgärd.
- Gamla repositoryts filinnehåll är oförändrat enligt före/efter-manifest.
- Enda varningen i slutliga appbyggen/arkivering är Xcodes metadata extraction
  skipped för saknad AppIntents.framework, som också fanns i grundprojektet.

Initialt uppstod C++-länkningsproblem (library search path och libc++) som löstes
med vanliga build settings. Ett testförsök hade överblivna Xcode-testframework-
signeringsfiler från ett avbrutet bygge; ett rent testbygge löste det. Inga
signeringsskript eller undantag infördes för detta.

Lokala verifieringsloggar finns i `/tmp/panowizard-migration-debug.log`,
`/tmp/panowizard-migration-release.log`, `/tmp/panowizard-migration-final-tests.log`
och `/tmp/panowizard-migration-archive.log`. Testresultat finns i
`/tmp/panowizard-migration-final-tests.xcresult`. Dessa är temporära och ingår
inte i repositoryt. UI-provningens syntetiska filer låg under
`/tmp/panowizard-migration-fixture` och är inte produktresurser.

## Historik: första runtime-regressionen och tidigare legacy-workaround

Detta avsnitt beskriver en tidigare implementation/verifiering. Mappdialogen
togs senare bort enligt avsnittet om nya projekts bokmärken nedan.

Efter migrationen rapporterade användaren att ett befintligt `.pw`-projekt öppnas
med rätt bildnamn/dimensioner men visar ”The Image Could Not Be Read”. Felet
reproducerades i den vanliga signerade Release-appen med
`/Users/magnus/Desktop/Panorama/E/panowizard.pw`, format 10 och åtta externa PNG-filer.

Projektpaketet lagrar metadata och källbilds-URL:er i `project.json`. Originalen
är inte inbäddade. Den gamla skrivaren gör URL:erna relativa till mappen som
innehåller `.pw`-paketet (även `..` kan förekomma); den gamla läsaren stödjer även
absoluta file-URL:er och fallback till samma filename bredvid paketet. E-projektet
refererar exempelvis till `2009-06-25%2014-53-14.png` bredvid paketet, med URL-
avkodning till filnamnet med mellanslag. Inbäddat panorama/masker är separata
resurser i paketet. Bildlistans metadata visar inte att externa bildbytes går att
läsa. SourceImageRaster är oförändrad och använder ImageIO direkt på källbildens URL.

Rotorsak i migrationens åtkomstkod: SourceFileAccess kunde returnera utan ett
riktigt åtkomstgrant efter `isReadableFile`, inklusive bara kontroll av parent-
mappen. Filmetadata/permission bits och åtkomst till `.pw` ger inte sandboxrätt
att öppna de externa originalen. Därmed uteblev den nödvändiga mappdialogen.
Dessutom kunde källvyns `.task(id: image)` redan ha sparat en misslyckad läsning
innan åtkomst gavs; samma bildvärde startade inte om den läsningen.

Den smala korrigeringen ändrar två produktionsfiler:

- `Services/SourceFileAccess.swift`: kontrollera faktisk filöppning och läs en
  byte med FileHandle i stället för metadata-baserad `isReadableFile`.
  Vid nekad åtkomst används samma native NSOpenPanel för källmappen, samma
  app-scoped bookmarklagring och samma aktiva security-scoped åtkomst. Efter
  valet verifieras en faktisk källfilsöppning. En fil räknas som saknad först när
  parent faktiskt kan listas och filnamnet saknas, så nekad åtkomst inte tar bort
  källbildsreferenser. Ingen auto-import av andra bilder från mappen införs.
- `Application/PanoWizardApp.swift`: resolution avslutas först efter att åtkomst
  och modell är färdiga (`defer`), och ContentView får ny identitet när
  resolutionen avslutas. Det startar om befintliga source/thumbnail-läsningar
  efter åtkomstgrant utan ändring av bildloader eller UI-design.

Ingen ändring av `.pw`-format, URL-format, metadata, sparare, ImageIO-loader,
algoritmer, entitlements eller App Sandbox. Gamla format-10-projekt behöver inte
skrivas om; åtkomstgrant lagras i appens egna preferenser. Övriga äldre
projektformat omfattas fortfarande av facits befintliga versionspolicy.

Verifiering efter korrigering:

- Riktiga E-projektet öppnades i vanlig Release-app: en mappauktorisering,
  därefter synliga thumbnails och läsbara originalbilder, samtliga åtta valda
  genom UI utan bildläsningsfel. Första bildens riktiga pixels/mask visades visuellt.
- Efter avslut utan sparning och full omstart öppnades samma projekt utan ny
  mappfråga; originalbildsläsningen fungerade igen.
- SHA-256 före/efter bekräftade oförändrat project.json och alla åtta externa PNG-filer.
- Release-bygge och normal Debug-build lyckades. App Sandbox och app-scoped
  bookmarks är fortsatt aktiva; vanliga appbyggen har ingen full-filsystemexception.
- 56 tester i 14 suites passerade, inklusive de gamla 54 och två nya fokuserade
  tester för faktisk filöppning respektive en katalog som inte är källbildsinnehåll.
- Viktig testgräns: Xcode lägger automatiskt till en test-only read-only exception
  för `/` i den hosted test-appen. Hosted tester bevisar därför inte sandboxens
  nekade filåtkomst. Ett tillfälligt test av sådan nekad åtkomst visade detta och
  togs bort. Runtime-verifieringen ovan gjordes i den normala Release-appen med
  dess ordinarie, kontrollerade entitlements, utan denna exception.

Loggar: `/tmp/panowizard-source-access-release.log`,
`/tmp/panowizard-source-access-debug.log`, `/tmp/panowizard-access-final-tests.log`.
Resultatbundle: `/tmp/panowizard-access-final-tests.xcresult`.
Inget committat, taggat eller pushat.

## Historik: nya projekts filbookmarks — verifiering 2026-10-05

Denna verifiering gäller första versionen utan recovery. Den senare,
uttryckligen användarvalda Grant Access-recoveryn beskrivs nedan.

Användaren accepterar inte extra mappval och har uttryckligen slopat krav på
legacy-filåtkomst. Den tidigare legacy-mappworkarounden är borttagen. App-scoped
bookmarks från uttryckligt bildval räcker för begärt flöde utan formatändring.
Inga source images kopieras, dupliceras eller flyttas till projektpaketet.

Ändrade produktionsfiler i denna uppgift:

- SourceFileAccess: ta bort NSOpenPanel/AppKit/mappgrant; låt bookmarkskapande
  kasta fel i stället för att tyst ignorera det; balansera åtkomst om lagringen
  misslyckas. Restore använder sparade grants utan UI.
- ImageImportService: acceptera endast bilder vars bookmark sparats framgångsrikt.
- PanoProjectDocument: hantera throws från dokument-URL:ens befintliga retain.
- PanoWizardApp: återställ grants innan initiala källpreviews startar.

Runtime verifierades i normal signerad Release-app utan testhostens breda
filåtkomst. Tre nya syntetiska 640×320 PNG-bilder låg utanför sandboxcontainern i
`/Users/magnus/PanoWizardBookmarkVerification-20261005`: två i `Sources`, en i
`Added`. Projekt skapades med normalt Choose Source Images, tredje bilden lades
till via Add från den andra katalogen, och Save sparade
`Projects/BookmarkWorkflow.pw` i en separat katalog. Ingen överordnad mappgrant
valdes. UserDefaults innehöll tre individuella filbookmarks (852–856 bytes).
Paketet innehöll endast project.json och maskkataloger, inga originalbilder.

Release-processen avslutades med Quit och kontrollerades vara borta innan
omstart. Efter relaunch öppnades bara `.pw` via Open Panorama. Alla tre thumbnails
och individuellt valda bilder laddades utan ny åtkomst-/mappdialog eller bildfel.
Bildpixels verifierades visuellt. Originalen ligger kvar på ursprungliga platser.

Debug- och Release-build lyckades. App Sandbox och app-scope bookmarks är
aktiverade i signerad vanlig Release-app; inga filesystem exceptions infördes.
Loggar: `/tmp/panowizard-bookmarks-debug.log`,
`/tmp/panowizard-bookmarks-release.log`, `/tmp/panowizard-bookmarks-tests.log`.
Slutlig testslogg: `/tmp/panowizard-bookmarks-final-tests.log`.
Testresultat: `/tmp/panowizard-bookmarks-final-tests.xcresult`.
Samtliga 56 tester i 14 suites passerade. Första körningen upptäckte en gammal
importfixture med endast påhittade URL:er och stubbad metadata; scoped bookmarks
kräver faktiska filer. Testet skapar nu filer för stubben och verifierar även att
icke-existerande filer med bookmarkfel inte importeras. Den valfria panoramaFixture
hade ingen PANOWIZARD_PANORAMA_PROJECT och körde därför inte en verklig stitchfixture.
Vanlig Debug-app byggdes rent igen efter testkörningen så testhostens tillfälliga
filesystem exception inte finns kvar i senaste Debug-produkt.
Inget committat, taggat eller pushat. Gamla repositoryt har inte ändrats.

## Historik: Recoverable Grant Access via apppreferenser — verifiering 2026-10-05

Denna version ersattes av projektmetadata och ett enda alertflöde enligt nedan.

Aktuell permission-recovery ersätter den tidigare återvändsgränden:

- Titel: **Could Not Read Source Images**.
- Text: **PanoWizard needs permission to access the source images for this project.**
- Knappar: **Cancel** och **Grant Access**.
- Grant Access öppnar NSOpenPanel som sheet med endast katalogval, initialt
  `sourceURL.deletingLastPathComponent()`. Panelen visas först efter att alerten
  stängts, och endast efter användarens uttryckliga val.
- Vald katalog behålls security-scoped och sparas som app-scoped bookmark via
  befintlig SourceFileAccess. Samtliga projektreferenser läses om direkt.
- Om nästa permissionfel gäller en annan katalog visas samma recovery för den
  katalogen. Ingen individuell filauktorisering efterfrågas.
- Lyckad resolution återställer dokumentmodellen och ändrar ContentViews
  reloadrevision så tidigare misslyckade thumbnails/previews laddas igen.
- Cancel i alert eller panel avbryter recovery utan ändring av original/projekt.
- Revert använder samma permission-recovery. Andra fil-/sparfel har kvar vanlig
  felhantering och OK-knapp.

Ändrade produktionsfiler: SourceFileAccess.swift och PanoWizardApp.swift.
SourceFileAccess returnerar ett typat PermissionRequired med URL till nekad
källbild. En verklig FileHandle-read skiljer permissionfel från övriga I/O-fel;
Cocoa read/write-no-permission och POSIX EACCES/EPERM stöds. Runtime visade att
macOS rapporterade den nekade läsningen med Cocoa write-no-permission och en
missvisande "permission to save"-text; detta hanteras också av den nya recoveryn.
Bekräftat saknade filer följer fortfarande befintlig missing-file-policy.

Verifierat i vanlig signerad sandboxad Release-app:

1. Ny syntetisk format-10-fixture, `PanoWizardRecoveryVerification-20261005`, med
   tre externa PNG-bilder: två i Sources, en i Added; `.pw` i separat Projects.
   Katalogerna hade inte tidigare valts eller fått bookmarks.
2. Öppning av `Projects/Recovery.pw` gav exakt text och Cancel/Grant Access-knappar.
3. Grant Access öppnade native panelen direkt i Sources, med bildfiler disabled.
   Ett kataloggrant täckte båda dess bilder. Retry hittade nästa nekade katalog.
4. Nästa Grant Access öppnade direkt i Added. Efter dess katalogval försvann
   felet och alla tre thumbnails och källbildspreviews laddades.
5. Appen avslutades helt med Quit; Release-processen kontrollerades vara borta.
   Efter relaunch öppnades samma `.pw` utan ny permissionalert eller mappanel.
   Samtliga tre källor gick att välja utan bildfel; bildpixels verifierades visuellt.
6. UserDefaults innehåller katalogbookmarks för Sources och Added (740 bytes
   vardera), inte individuella recovery-filgrants. SHA-256 före/efter bekräftade
   oförändrat project.json och alla tre externa original. Paketet innehåller
   fortfarande bara project.json; inga bildkopior eller formatändringar infördes.

Release och rent vanligt Debug-build lyckades. Codesign och ordinarie
sandbox/bookmark-entitlements verifierades; inga filesystem exceptions infördes.
58 tester i 14 suites passerade, inklusive två nya fokuserade tester: verklig
permission-denial identifierar sourceURL och bekräftat saknad fil ger inte en
permission-recovery. Hosted test-appens breda test-only filåtkomst bevisar inte
sandboxgrants; därför provades hela recoveryn i vanlig Release-app.
Valfria riktiga panoramaFixture är fortsatt okonfigurerad. Cancel och felaktigt
valt foldergrant har inte provats manuellt i denna runtime-verifiering.

Loggar: `/tmp/panowizard-recovery-release.log`,
`/tmp/panowizard-recovery-debug.log`, `/tmp/panowizard-recovery-final-tests.log`.
Resultat: `/tmp/panowizard-recovery-final-tests.xcresult`.
Gamla repositoryt har inte ändrats. Inget committat, taggat eller pushat.

## Projektspecifika bookmarks och legacy-upgrade — verifiering 2026-10-05

Produktionsändringar begränsade till SourceFileAccess, PanoProjectDocument och
ProjectDocumentView i PanoWizardApp. Optional metadata enligt schemat ovan är
enda formatutökningen. Gamla appen ignorerar okända paketmedlemmar, men dess
vanliga Save skulle inte bevara bookmarkmetadata; ny app behövs för sandbox-
persistensen. Ursprungliga algoritmer, bildloader, resurser och UI är oförändrade
utöver det begärda recoveryflödet.

**Riktigt legacyprojekt U:** `/Users/magnus/Desktop/Panorama/U/panowizard.pw`.
Innehåller nio externa 2000×3008 PNG-original, två exklusionsmasker, tre
protection masks, panorama/result och två aktiva manuella retouchpatches.
Backup av endast det befintliga projektpaketet finns i
`/tmp/panowizard-legacy-U-before-project`; inga externa original kopierades.
SHA-256-manifest för befintliga projekt-/bildfiler:
`/tmp/panowizard-legacy-U-before.json`.

Vanlig signerad sandboxad Release-app verifierades via native UI:

1. Full processomstart före testet. Första Open av U utan bookmarkmetadata gav
   exakt en Could Not Read Source Images / Grant Access-alert.
2. Grant Access öppnade direkt i U. Ett native katalogval gav åtkomst till alla
   nio original. Projekt öppnades utan fler pickerfrågor.
3. Source pixels, befintlig grön protection-mask och senare röd exklusionsmask
   verifierades visuellt; retouchlistan visade båda aktiva manuella patches.
4. Vanlig Save lade till en source-access.json med en U-katalogbookmark.
   **Alla befintliga filer, inklusive project.json, var byte-identiska före/efter.**
   Detta verifierar bevarade inställningar/IDs/datum/metadata, mask- och
   patchbytes, panorama, protected masks, samt alla externa original.
5. Quit och kontroll att Release-processen verkligen försvann; relaunch och
   Open av samma U gav varken alert eller folder picker. Alla nio sources valdes
   individuellt utan bildfel; thumbnails/pixels/masker laddades.
6. U-katalogens grant finns inte i gamla UserDefaults-bookmarkregistret. Kod läser
   inte längre registret: persistensen kommer från projektets metadata.

**Flera kataloger:** `PanoWizardRecoveryVerification-20261005/Projects/Recovery.pw`,
tre syntetiska externa PNG-original (två Sources, en Added) utan metadata.
Även här en initial alert; Grant Access startade Added-picker och därefter direkt
Sources-picker, **utan en andra alert**. Sources valdes en gång för två filer.
Save lagrade exakt två katalogbookmarks; alla befintliga fixturebytes var
oförändrade. Efter full Quit/relaunch/Open laddades alla tre utan alert/picker.
Paketet innehåller endast project.json + source-access.json, inga originalbilder.

Debug- och Release-build lyckades; normal Debug-app byggdes rent efter testerna.
Codesign och signerade ordinarie sandbox/bookmark-entitlements verifierades.
62 tester i 14 suites passerade. Fyra ytterligare tester täcker optional metadata
med komplett projekt-/mask-/panorama-/retouch-roundtrip, legacy utan metadata,
insamling av samtliga denied sources, och endast relevanta deduplicerade grants.
Hosted test-only filesystem exception kan inte bevisa sandboxruntime, som därför
provades i vanlig Release. Valfria real panoramaFixture är fortsatt okonfigurerad.

Loggar: `/tmp/panowizard-project-bookmarks-release.log`,
`/tmp/panowizard-project-bookmarks-debug.log`,
`/tmp/panowizard-project-bookmarks-tests.log`.
Testresultat: `/tmp/panowizard-project-bookmarks-tests.xcresult`.
Gamla repositoryt är oförändrat. Endast det uttryckligen testade Desktop/U-projektet
har uppgraderats med optional metadata; övrigt befintligt innehåll bevarades exakt.
Inget committat, taggat eller pushat.

## Kvarstående verifieringsgränser

- Ingen ny App Store Connect Validation eller distribution har gjorts efter migrationen.
- Ingen full visuell panorama-regression mot gamla appen/A–S. Extern källbildsläsning
  i det riktiga E-projektet verifierades senare enligt avsnittet ovan.
- Inget skarpt AI-bildanrop med API-nyckel; network.client och befintliga
  request/response-tester är verifierade, inte tjänstens end-to-end-svar.
- Hela manuella export/extern redigering/import-flödet provades inte genom UI;
  dess implementation följer med och retouch-/patchredigeringstester passerar.
- Alla möjliga filflyttar, volymer, behörighetsändringar och stale-bookmark-
  situationer är inte manuellt testade. Otillgängliga grants rapporteras som fel;
  användaren kan välja Grant Access för att återställa saknade grants.
  Bookmarks lagras i projektet och är knutna till appidentitet/lokalt filsystem.
  Överföring till annan dator/konto är inte verifierad. Apppreferenser behövs inte.
- Inget Intel-stöd; originalets binära beroenden är arm64.
- Inga kända avsiktligt borttagna funktioner. Dessa verifieringsgränser får inte
  döljas eller ”lösas” genom att ta bort eller förenkla applikationsfunktioner.

## Direkt native permission-picker — verifiering 2026-10-05

Den preliminära Could Not Read Source Images / Grant Access-alerten är borttagen.
PermissionRequired startar befintlig folder recovery på nästa main-loop-varv.
Bookmarkhantering, projektmetadata, retry och sekventiella folder grants är oförändrade.
Övriga läsfel visar fortfarande vanlig fel-alert.

Debug och Release byggde med BUILD SUCCEEDED; loggar:
`/tmp/panowizard-direct-authorization-debug.log` och
`/tmp/panowizard-direct-authorization-release.log`.
Normal sandboxad Release-app verifierades med en ny testfixture:
`/Users/magnus/PanoWizardDirectAuthorizationVerification-20261005/Projects/Direct.pw`.
Tre externa PNG i två kataloger: öppning gick direkt till Added-katalogens native
picker, därefter Sources-katalogens picker, utan app-alert mellan stegen. Samtliga
bilder laddades. Save sparade två folder bookmarks i befintlig source-access.json
version 1. SHA256 för alla fyra tidigare filer (tre originals och project.json)
var oförändrade. Efter full quit (processen borta), relaunch och reopen laddades
alla tre bilder utan alert eller folder picker. Ingen formatändring, ingen
ändring av sandbox/capabilities. Befintliga tester kördes inte om för denna
UI-ändring; föregående körning hade 62 godkända tester. Inget commit/tag/push.

## Automatisk timestamp-baserad buildidentitet — 2026-10-05

Semantic version förblir manuellt styrd via MARKETING_VERSION = 1.0 i Debug och
Release. Ingen automatisk semantic increment och ingen persistent counter.
Native app-target har en alltid körd Run Script-phase Generate Build Metadata,
som använder ett enda lokalt date-anrop och skriver två preprocessormakron i
$(DERIVED_FILE_DIR)/PanoWizardBuildMetadata.h. CFBundleVersion blir YYYYMMDDHHmm
och optional PanoWizardBuildTimestamp blir YYYY-MM-DD HH:mm från samma tid.
Inga source/project/plist-filer ändras under byggningen.

Appens Info.plist använder Xcodes vanliga plist preprocessing med denna genererade
prefix header. GENERATE_INFOPLIST_FILE är NO för app-target (testtargets oförändrade),
eftersom genererad plist annars ersätter CFBundleVersion med CURRENT_PROJECT_VERSION.
Standard bundle keys finns därför uttryckligen i input-plisten med vanliga Xcode
variabelexpansioner. Photography, document types, icons och bundle identifier är
bevarade. Xcode sköter fortsatt plist processing, asset catalog, app bundling,
signing och Archive; ingen custom bundling/signing. CURRENT_PROJECT_VERSION = 1
är borttagen för att inte ange ett konkurrerande buildvärde.

About-kommandot öppnar standard native macOS About-panel med två rader:
Version 1.0 (202610052215) / Build 2026-10-05 22:15 (verifierade exempel).
Debug och Release byggde och deras bundle metadata samt About-paneler verifierades.
Archive till /tmp/PanoWizardTimestamp.xcarchive lyckades och innehöll
CFBundleShortVersionString 1.0, CFBundleVersion 202610052216 och lokal Build
2026-10-05 22:16. Native codesign --verify --deep --strict godkänd för Debug
och arkivet. Buildloggar /tmp/panowizard-timestamp-{debug,release,archive}.log.

CFBundleVersion följer aktuell Apple-dokumentations format (en till tre numeriska
heltal separerade med punkt; här ett heltal). App Store Connect validation/upload
kördes inte i detta steg. Minutupplösningen innebär att två builds inom samma
minut får samma nummer; ny distributionsbuild behöver ny minut. Lokal tid innebär
också att ändrad systemklocka/tidszon eller återgång vid vintertid kan ge tidigare
värde: ingen global monotonicitetsgaranti utan counter, enligt förenklat krav.
Inget commit/tag/push.

## Xcode Analyze och regressionstester — 2026-10-05

Arkitekturbeslutet ovan är slutligt för nu: arm64-only, inga Intel/universal-
ändringar eller OpenCV-rebuilds. Analyze kördes med delat PanoWizard-scheme,
Debug, platform=macOS,arch=arm64; app och native OpenCVBridge ingick.
Första Analyze blockerades av RetouchPatch.id: UUIDx i Models/PanoProject.swift.
Unknown type gav följdfel för Codable/Equatable. Återställt endast UUID, vilket
matchar initializer och originalets modell exakt. Ingen ändring av format,
retouch-/maskstate eller beteende.

Nästa körning träffade ett gammalt PanoWizardTests.xctest i delad Debug-output
vid codesign. Xcodes normala clean löste stale output utan sourceändringar.
Final clean Analyze lyckades: noll diagnostics i Clangs PanoramaBridge.plist.
Swift compiler rapporterade inga kodvarningar. Enda kvarvarande warning var
AppIntents metadata extraction skipped / No AppIntents.framework dependency
found; benign eftersom appen inte använder App Intents. Ingen dependency lades
till för att tysta den. Build metadata-phase always-run-notisen är avsiktlig.
Clang static analyzer analyserar C++; Swift kontrolleras av kompilatorn, och
precompiled OpenCV-dylibs analyseras inte som source.

Debug och Release byggde godkänt. Testresultat: 62 passed i 14 suites, 0 failed,
0 skipped, /tmp/panowizard-analyze-tests.xcresult. Hosted tests bevisar inte
sandboxpermission-runtime; inga nya UI-recoverytester behövdes för UUID-typo.
Normal Debug-app byggdes rent igen efter hosted tests för att lämna normal
sandbox/signing utan test-only exceptions. Loggar:
/tmp/panowizard-analyze-before.log (initial compilefel),
/tmp/panowizard-analyze-after.log (stale testbundle-signingfel),
/tmp/panowizard-analyze-final.log (Analyze godkänt),
/tmp/panowizard-analyze-{debug-build,release-build,tests}.log.
Inga ändringar i originalprojektet, OpenCV, algoritmer, UI, externa sourcebilder,
Grant Access/bookmarks, .pw-format, capabilities eller architectures.
Inget commit/tag/push.

## Appens dSYM i normal Archive — 2026-10-05

Enda buildsettingändringen: projektets Release-konfiguration har nu
DWARF_DSYM_FOLDER_PATH = "$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)".
DEBUG_INFORMATION_FORMAT = dwarf-with-dsym var redan korrekt och är oförändrat.
CONFIGURATION_BUILD_DIR och användarens Build/Debug samt Build/Release-genvägar
är bevarade. Xcode får generera appens dSYM i sitt normala BUILD_DIR; vid Archive
är detta ArchiveIntermediates/PanoWizard/BuildProductsPath, vilket native Archive
samlar in automatiskt. BUILT_PRODUCTS_DIR var inte tillräckligt eftersom det
också ärver den fasta CONFIGURATION_BUILD_DIR-sökvägen. Inga copy/signing-scripts.

Normal Release Archive /tmp/PanoWizardDSYMFinal.xcarchive lyckades.
Dess dSYMs/PanoWizard.app.dSYM/Contents/Resources/DWARF/PanoWizard och arkiverade
app-executable har båda UUID 63859E98-443B-319C-B2CB-AFB3EEE7F791 (arm64).
Arkivets codesign --verify --deep --strict godkänd. De 11 precompiled OpenCV-
biblioteken är oförändrade; inga dSYMs tillverkades och deras symbolvarningar
lämnas avsiktligt kvar. App Store Connect validation/upload kördes inte om.

Debug/Release byggdes och befintliga 62 tester i 14 suites passerade.
Resultat /tmp/panowizard-dsym-tests.xcresult. Normal Debug byggdes rent efter
hosted tests. Arkivet lämnade som tidigare en dangling native Xcode-symlink
i den fasta Release-outputmappen; endast den dangling länken togs bort inför
slutligt vanligt Release-build. Ingen appkod, architecture, sandbox, OpenCV
eller bildbehandling ändrad.
Loggar /tmp/panowizard-dsym-debug.log, /tmp/panowizard-dsym-release-final.log,
/tmp/panowizard-dsym-tests.log och /tmp/panowizard-dsym-archive-final.log.
Inget commit/tag/push.

## Enkel modellkonstruktion vid projektöppning — 2026-10-05

Endast ProjectDocumentView-livscykeln ändrades. model är optional State och init
lagrar dokument/bookmarks men skapar inte AppModel. ContentView visas först när
source resolution lyckats. Befintlig .task läser/återställer/auktoriserar sources
och skapar den slutliga fulla modellen en gång. Nya osparade projekt skapar sin
modell en gång i samma task. Ingen initial full modell, dubbel retouch-rebuild
eller initial thumbnailpass som därefter kastas bort. Normal öppning ökar inte
sourceReloadRevision; force-recovery behåller befintlig reset. Pending grants
utgår från savedDocument när modellen ännu saknas; Save/bookmarks behåller samma
format/semantik. Native Grant Access-dialogen och foldersekvensen är oförändrade.

Samma Release-app, U/panowizard.pw och sample 15 sekunder med 1 ms intervall:
före /tmp/panowizard-new-open.sample hade retouch rebuild 608 + 591 = 1199
samples under två model construction paths (view init och deferred resolution).
Efter /tmp/panowizard-opening-after.sample hade endast resolveSources-path och
646 retouch rebuild-samples; view init hade 1 sample och ingen model/rebuild.
46 procent mindre sampled retouch-arbete, cirka 0.55 s av den tidigare
uppskattningen eliminerat. Sampling är uppskattning, inte exakt end-to-end-
latens eller en exakt runtime invocation counter. Koden har en enda skyddad
konstruktion vid normal opening och profilen bekräftar en enda konstruktionpath.
Ingen rendering/OpenCV/cache/bildalgoritm/sandboxändring. U öppnades utan Save.

Recovery verifierades även med /Users/magnus/PanoWizardOpeningRecovery-20261005/
Projects/Opening.pw: tre externa testbilder i Added och Sources, direkt native
picker för vardera katalogen, därefter laddade samtliga tre. Save sparade två
folder bookmarks i source-access.json. SHA256 på de tre originals och project.json
oförändrad. Full quit (process borta), relaunch och reopen krävde ingen alert
eller picker. Debug/Release BUILD SUCCEEDED; 62 tester i 14 suites passerade.
/tmp/panowizard-opening-tests.xcresult; /tmp/panowizard-opening-{debug,release,tests}.log.
Debug byggdes rent efter hosted tests för normal sandbox/signing.
Inget commit/tag/push.

## Senaste distributionsstatus och OpenCV-symbolutredning — sparat 2026-10-06

Användaren har bekräftat att PanoWizard.app-dSYM-varningen är löst och App Store
validation lyckas. Kvarvarande Upload Symbols Failed-varningar gäller endast
de 11 precompiled OpenCV 5.0-dylibs. Arkivets native dSYM-outputfix beskrivs ovan.

Senaste uppgiften var enbart read-only-utredning om OpenCV-symboler kan erhållas
utan att ändra verifierat beteende. Inga bibliotek byggdes om eller ersattes.
Det finns INGEN auktorisering att implementera en OpenCV-rebuild; nästa beslut
återstår hos användaren. Rekommendationen är att lämna symbolvarningarna tills
förbättrad crash-symbolication motiverar en separat verifierad dependency-rebuild.
Arm64-only-beslutet är fortsatt slutligt för nu. Inget commit/tag/push är tillåtet.

### Lokalt återfunnet ursprung och byggkonfiguration

Originalets .vendor-cache innehåller opencv-5.0.0.tar.gz, opencv-5.0.0/ samt
opencv-build/ med CMakeCache.txt, build.ninja, compiler metadata och object files.
Source archive SHA256:
b0528f5a1d379d59d4701cb28c36e22214cc51cf64594e5b56f2d3e6c0233095
Samtliga 6905 jämförda extraherade sourcefiler var identiska med arkivet.
Embedded Version control är unknown; exakt upstream Git-commit/download-URL
fastställdes inte. Det lokala exakta sourcearkivet och byggkonfigurationen finns.

De 11 dylibs i originalets .vendor-cache/opencv-build/lib har samma UUIDs och
identiska __text-maskinkodsektioner som nuvarande Vendor/OpenCV/lib. Hela filernas
SHA256 skiljer sig, så påstå inte full byte-identitet mellan build-output och
Vendor; UUID + __text-jämförelsen visar samma länkningsursprung/maskinkod.

Konfiguration: Release, shared dylibs, arm64, C++17, -O3 -DNDEBUG, deployment
macOS 26.0; AppleClang 21.0.0.21000101, CMake 4.4.0 och Ninja.
BUILD_LIST = core,imgproc,imgcodecs,features,flann,calib,photo,stitching; dess
beroenden resulterar i exakt calib/core/features/flann/geometry/imgcodecs/
imgproc/objdetect/photo/stereo/stitching. Inga extra contrib-moduler.
Accurate algorithm hint, NEON/FP16/DOTPROD baseline och NEON_BF16 dispatch;
GCD, Accelerate/LAPACK, Eigen 5.0.1, Carotene och KleidiCV 26.03.
ENABLE_FAST_MATH=OFF, WITH_OPENCL=OFF, non-free=OFF.
Embedded codecstöd: zlib 1.3.2, libjpeg-turbo 3.1.2-70, PNG 1.6.57 (NEON,
EXIF/XMP/ICC/cICP), TIFF 4.7.1, JPEG2000/OpenJPEG 2.5.3 samt GIF/HDR/SUNRASTER/
PXM/PFM. AVIF saknas trots begärd WITH_AVIF: skilj önskade CMake-options från
faktiskt detected/built stöd. För exakt reproduktion måste även externa headers,
SDK/toolchain och CPU/dependency-autodetection pinnas, inte bara BUILD_LIST.

### Varför nuvarande dylibs inte kan få riktiga matching dSYMs

BUILD_WITH_DEBUG_INFO=OFF. Samtliga 871 kvarvarande Mach-O .o-filer kontrollerades:
0 hade __DWARF. Dylibs saknar också DWARF; dsymutil --dump-debug-map på core var
tomt på object/debug-info-poster. Ingen redan existerande OpenCV-dSYM hittades
i originalet, nya repot eller tidigare undersökta lokala build/archive-mappar.
Debuginformationen skapades aldrig, den är inte bara borttappad i paketering.
Genuina matching dSYMs kan därför inte återvinnas ur dessa artefakter.
Tillverka inte tomma/falska symbolfiler eller kopiera UUID till andra dSYMs.

### Minsta tänkbara framtida åtgärd — endast rekommendation, inte genomförd

En isolerad rebuild av exakt samma source/config/dependency/toolchain, med
Release-optimering kvar och endast debug-info påslagen, är plausibelt drop-in-
kompatibel men ännu INTE verifierad. OpenCV 5.0:s lokala
cmake/OpenCVCompilerOptions.cmake stödjer BUILD_WITH_DEBUG_INFO=ON och lägger
i denna toolchain till -g1 i Release utan att ta bort -O3. Generera dSYMs från
nya binaries/object files före stripping; de måste matcha nya dylib-UUIDs.
Jämför export-symboler/ABI/install names/transitiva deps, headers, CPU/backend-
konfiguration, codecstöd och maskinkod; verifiera PanoWizards bildresultat och
regressionstester innan någon replacement. Det skulle kräva ersättningsdylibs,
inte enbart en archive-settingfix. Att debug-info normalt inte ändrar beteende
är ingen garanti för byte-identisk kod eller identiskt beteende vid ny build.
Rör inte den nu verifierade native-stacken utan ny uttrycklig instruktion.

Källor: https://llvm.org/docs/CommandGuide/dsymutil.html och
https://docs.opencv.org/4.12.0/db/d05/tutorial_config_reference.html; exakt
OpenCV 5.0-optionbeteende verifierades även direkt i lokala CMake-sourcefilen.

Den senaste kodändringen är fortfarande enkel AppModel-konstruktion vid opening,
med verifierade Debug/Release, 62 tester och bevarad Grant Access-persistens enligt
avsnittet ovan. Bara CONTEXT.md uppdaterades vid denna kontextsparing.

## Commit/push-checkpoint — 2026-10-06

Användaren begärde commit+push av aktuellt arbete till origin/main. Checkpointen
omfattar hela native Xcode-migrationen, arm64 OpenCV-binaries och resurser,
sandbox/bookmark-recovery med optional projektmetadata, timestamp-identitet,
native archive-dSYM-setting, UUID-typofix, enkel AppModel-konstruktion vid opening,
tester, användarguide och kontext. Tidigare verifieringar beskrivs ovan; inga
nya kodändringar eller OpenCV-rebuilds görs som del av checkpointen. Ingen taggning.

## Minimal GitHub Pages-help för granskning — 2026-10-06

/docs/index.md skapad från scratch med kort användarhjälp på engelska: syfte,
create/open/save, externa sourcebilder och Grant Access, Add, Create-analys/
stitching, navigation/adjustments, masks, manual/AI patches, Little Planet och
JPEG/PNG/HTML-export. Faktaunderlag Tutorial/, README och aktuella UI-labels.
Analyze är inte en separat användaroperation; help förklarar att Create gör
analys och stitching. Inga assets duplicerades: initialversionen är text-only.
Inget framework, theme, JS, custom design/config eller navigationssystem.
Tutorial/ och appkod oförändrade. Användaren begärde därefter commit+push till
origin/main. Ingen GitHub Pages-konfiguration eller deployment utfördes.

## Tutorial-migrering till självförsörjande docs — 2026-10-06

Användaren stoppade den första flytten, bad om analys och auktoriserade sedan
slutförandet. Tutorial/README.md är nu docs/getting-started.md. Images/ och
HowTo/ flyttade till docs/; respektive guides README.md heter nu index.md.
Befintlig docs/index.md behålls med en panoramaillustration och länkar till fem
bildguider. Alla 17 bilder är byte-identiska med committat Tutorial-material;
inga dubbletter eller bildberoenden utanför docs. Alla interna sid-/bildlänkar
verifierade ligga inom docs och peka på befintligt innehåll. Publika sidlänkar
använder .html; varje detaljguide länkar tillbaka till startsidan. Inga framework,
theme, JS eller configändringar. Tutorial/ innehåller lokalt endast ignorerad
.DS_Store; dess tracked material är flyttat. Appkod är oförändrad.
README:s strukturuppgift uppdaterad. Inget commit/push eller deployment.

Användaren begärde commit+push av docs-migreringen 2026-10-06. Ingen taggning
eller separat deployment begärd.

## Native Help-meny — 2026-10-06

Help → PanoWizard Help läser PanoWizardHelpURL från appens Info.plist och öppnar
https://meg768.github.io/panowizard-next-gen/ via NSWorkspace.shared.open i
standardwebbläsaren. URL:ens dubbla slash är XML-entities i källplist eftersom
befintlig Xcode-plistpreprocessing annars tolkar dem som en kommentar; byggda
Debug/Release-plists innehåller den exakta normala URL:en. SwiftUI ersätter
.help-commandgruppen. AppKit helpMenu pekar på en kvarhållen off-menu NSMenu,
vilket enligt native API undertrycker den automatiska Spotlight Search-rutan.
Ingen WebView eller custom help-window. Docs och övrig appfunktion oförändrade.
Debug och Release build succeeded. Release kördes: Help innehåller enbart
PanoWizard Help, utan Search; klick öppnade rätt publicerad hjälpsida i Safari.
Ingen commit, taggning eller push enligt användarens instruktion.

Användaren auktoriserade därefter commit+push av Help-menyändringen till
origin/main. Ingen taggning begärd.

## Gemensam projektfönsterram utan efterföljande zoom — 2026-10-06

Användaren valde app-level storlek/position för alla projektfönster. Den gamla
WindowStateRestorer med två async-steg och explicit zoom(default true) ersatt
med NSView.viewDidMoveToWindow som synkront återställer den gemensamma ramen
PanoWizard.ProjectWindow via setFrameUsingName(force: true), och registrerar
native setFrameAutosaveName. Tidigare sparad ram återanvänds. Separat isZoomed
flagga används inte längre; defaultSize 1240x780 gäller utan sparad ram.
Ingen ändring av projektdata, laddning eller välkomstfönstrets separata zoom.
Debug/Release build succeeded. Release-verifiering: öppnade Opening.pw,
ändrade storlek med native Window → Move & Resize → Left (901x923 punkter),
quittade helt och återöppnade samma projekt; sparad mindre ram återkom.
Stängde och öppnade H/panowizard.pw; samma gemensamma ram användes, bilder och
preview laddade. Ingen efterföljande programmatisk projektzoom finns kvar.
UI-snapshots verifierar slutlig storlek; ingen bildruta-för-bildruta-mätning av
öppningsflimmer utförd. Ingen commit/tag/push.

## Om-fönstrets versionstext — 2026-10-06

På användarens begäran visar Om-fönstret nu endast Version 1.0 och Build med
lokalt datum/tid; numeriskt CFBundleVersion inom parentes borttaget från UI.
CFBundleVersion genereras fortfarande automatiskt och ingår oförändrat i
bundlemetadata. Manuell semantic version styrs av app-targetets Version /
MARKETING_VERSION (Debug och Release), för närvarande 1.0. Ingen commit/push.

Användaren bekräftade att projektfönstrets återställning fungerar och begärde
commit+push av aktuellt arbete. Xcode har även normaliserat project.pbxproj,
lagt till INFOPLIST_KEY_CFBundleDisplayName=PanoWizard i Debug/Release och
avlägsnat PanoWizard.entitlements från synchronized-group membershipExceptions.
MARKETING_VERSION är fortsatt 1.0. Om-textens Release-build succeeded.

## Topic-oriented GitHub Pages Help — 2026-10-06

Användaren begärde enklare visuell startsida och separata ämnen; struktur
föreslogs före implementation. docs/index.md har titel, befintlig 1800x900
(2:1) panorama, kort intro och 11 ämneslänkar grupperade Start / Create and
inspect / Correct / Export. Sex nya Markdown-sidor flyttar instruktioner från
startsidan: projects.md, source-images.md, creating-panorama.md, preview.md,
export.md, file-access.md. Befintlig getting-started.md och fyra HowTo-guider
behållna på samma URL:er. Masks-guiden kompletterad med befintlig varning om
recreate/retouch; AI-guiden med befintligt API-key-krav. Alla 17 bilder byte-
identiska; nya sidor refererar befintliga bilder utan kopior. 58 interna länkar
kontrollerade mot befintliga filer inom docs. Ordinary Markdown, ingen JS,
CSS/theme/framework/generator eller appändring. Publicerad rendering inte
verifierad (inget push/deployment). Ingen commit/push enligt instruktion.

Användaren begärde därefter commit+push av den ämnesorienterade hjälpsajten
till origin/main. Ingen taggning eller separat deployment begärd.

## Dölj automatisk repo-rubrik i Help — 2026-10-06

Användaren bad ta bort blå panowizard-next-gen-rubrik överst på alla sidor.
Verifierade publicerad HTML och standardtemat Primer: repo-rubriken renderas
bara om site.title är truthy och skiljer sig från page.title. docs/_config.yml
sätter title: false för att stänga av denna rubrik globalt utan CSS, eget layout,
JS eller ändring av sidornas Markdown-rubriker. Publicerad rendering kan inte
verifieras innan push/deployment. Ingen commit/push utförd.

Användaren begärde därefter commit+push av inställningen som döljer repo-rubriken
till origin/main. Ingen taggning begärd.

## Korrigering av repo-rubrik — 2026-10-06

Efter push verifierades att Pages deploy av 5f957c5 lyckats och publicerad HTML
ändå innehåller repo-rubriken; title:false räckte inte (metadata återfyller titel).
Ersatt med site title PanoWizard Help och minimal docs/_includes/head-custom.html
CSS: .markdown-body > h1:first-child:not([id]) { display: none; }. Primer inkluderar
head-custom i head. Selektorn träffar endast automatiska h1 utan id, inte Markdown-
rubriker som har id. Inget eget layout eller JavaScript. Lokalt verifierad mot
publicerad HTML; publicerad effekt kräver ny commit/push. Ingen commit/push ännu.

Användaren auktoriserade commit+push av korrigeringen (c+p) till origin/main.

## Help-granskning mot aktuell implementation — 2026-10-06

Alla 12 Markdown-help-sidor lästa och jämförda med aktuella SwiftUI-viewlabels,
AppModel, dokument/bookmark/import-kod, OpenCVBridge och export/retouch-services.
Korrigerat startflöde: Create Your Panorama väljer källbilder direkt, Add gäller
fler bilder i öppet projekt (också verifierat i körande UI och picker avbruten).
Source Images förtydligar högerklick/Image Type och lika pixelmått efter rotation.
Tidigare kategoriska påstående att multi-row är unsupported borttaget: ringmodell
finns, men inget explicit multi-row-rejection eller verifiering av sådana dataset;
rekommendationen om en överlappande ring behålls utan att lova multi-row-stöd.
Little Planet har Option-drag till center, drag/horizontal scroll till rotation;
befintlig shape-screenshot visar tidigare click-text/sliderlayout och märks tydligt
som äldre. Mask/Create-varning rättad: maskändringar invalidaterar panorama direkt,
clearar patches och neutraliserar adjustments; lyckad stitch gör samma reset.
API-key entry-button förtydligad från aktuell AI-sheet. Övriga topics behållna.
58 lokala länkar verifierade, alla 17 bilder oförändrade. Ingen full ny stitching/
AI-anrop/export benchmark eller reproduktion av illustrationernas scenresultat;
uppskattningar 'few minutes'/'most sequences' är inte styrkta av koden och har
inte omtestats. Ingen appkod/struktur/designändring. Ingen commit/push.

Användaren auktoriserade därefter commit+push (c+p) av Help-granskningens
korrigeringar till origin/main. Ingen taggning begärd.

## .pw-dokumentikon identisk med appikon — 2026-10-06

Användaren begärde exakt appikon-artwork för .pw utan paper treatment.
PanoWizard/Resources/PanoWizardProject.icns ersatt med den befintliga native
actool-genererade AppIcon.icns från byggda appen. AppIcon-assets oförändrade.
Befintlig CFBundleTypeIconFile=PanoWizardProject.icns och native resource-copy
behållna. Debug/Release build succeeded; i båda byggda bundles verifierades att
refererad dokumentikon är byte-identisk med deras AppIcon.icns och källresursen.
Ingen script/buildpipelineändring, ingen redesign. Finder-iconcache för redan
registrerade dokument verifierades inte; cache kan visa gammal ikon tills macOS
uppdaterar appregistrering. Ingen commit/push.

## Inga fönsterflikar och förenklad View-meny — 2026-10-06

Användaren begärde inga tabs och endast Zoom In / Zoom Out / Reset View i View.
NSWindow.allowsAutomaticWindowTabbing=false sätts före launch; appens fönster
får tabbingMode=.disallowed vid update. View-menyn identifieras via Zoom In-
titeln (SwiftUI använder intern menuAction, inte bildresponderns selector) och
filtreras till de tre kommandona, även vid native menu-update/open/tracking för
att undvika AppKit-injektion av fullscreen/tab-items. Native fullscreen-knappen
ändras inte. Debug/Release build succeeded. Efter full omstart av Release
verifierade native View-meny exakt tre poster, inga tab/fullscreen-menyposter.
Tidigare lokal dokumentikonändring är fortsatt kvar. Ingen commit/push.

## Återgå till standard för View/flikar — 2026-10-06

Användaren avvisade specialkoden för att begränsa View och stänga av tabs och
prioriterar SwiftUI/macOS-standard. Hela den nyss tillagda ViewMenuDelegateProxy,
menu tracking-observern och tabbing-overrides borttagna; appfil återställd till
committat läge. Befintliga Zoom In/Out/Reset commands och systemets standard-
poster/flikar behålls. Föregående avsnitts View/tab-implementation är därmed
ersatt. Dokumentikonändringen kvarstår. Ingen commit/push.

## Verifiering av native projektflikar — 2026-10-06

Användaren auktoriserade verifiering av tabs och befintlig Close/Save/quit,
med anpassningar kvar om inga konkreta fel hittas. Testkopior Tab-A.pw och
Tab-B.pw skapades i /tmp/PanoWizardTabVerification från Opening.pw; relativa
source-paths rebased till befintliga externa testbilder (bara kopior ändrade).
Native Merge All Windows fungerade, tabbar/new-tab/systemkommandon tillgängliga.
A roterades/sparades med Cmd-S; B:s bildmått kvar oförändrade. B roterades och
Cmd-W gav Save/Don't Save/Cancel; Cancel behöll fliken, Save sparade B och stängde
bara B. On-disk JSON verifierade separat rotation=1 för A/B. A ändrades igen,
annan flik aktiverades och Cmd-Q gav varning för osparat A. Cancel stoppade quit;
Don't Save avslutade testappen och disk-A behöll tidigare sparad rotation=1.
Original Opening.pw SHA256 oförändrad. Befintligt W-projekt ändrades inte.
Inget konkret tab-fel påvisat; ingen appkod ändrad. Ej heltäckande verifiering
av alla menyalternativ/Save As/många samtidiga dirty tabs. Tidigare ikonändring
kvar; ingen commit/push.

Användaren auktoriserade därefter commit+push (c+p) av dokumentikonändringen
och uppdaterad kontext, inklusive beslut/verifiering att följa native tabs.
Ingen tab-specialkod kvar i ändringarna; ingen taggning begärd.

## Tomt projekt med samma arbetsyta — 2026-10-06

Användaren auktoriserade första ändringen: tomt dokument ska se ut som vanligt
projekt utan bilder. ContentView använder nu alltid NavigationSplitView och
DetailWorkspace; den tidigare stora PanoramaWelcomeView i tomt dokument är
borttagen. Sidebar visar alltid Images/Add och Panorama/Create/Retouch/Preview/
Export; Create och navigationrows är disabled när underlag saknas. Sidebar-
No Images-overlay borttagen för att inte skymma posterna. Preview har enkel
No Source Images-text med Add/drop-instruktion. Ingen model/stitch/sandboxändring.
Debug/Release build succeeded. Release-UI verifierad via File New och native
flikradens +: båda visar samma sidebar/arbetsyta utan bildbakgrund. Add öppnar
native image importer, avbruten efter kontroll. Separata appstartens welcome-
scene/maximering lämnad kvar i detta första steg; bara tomma projektdokument
ändrade. Ingen commit/push.

## Enkel avstängning av automatisk tabbing — 2026-10-06

På användarens uttryckliga begäran sätts endast
`NSWindow.allowsAutomaticWindowTabbing = false` i befintliga appdelegatens
`applicationWillFinishLaunching`. Ingen menyfiltrering, egen fönsterhantering
eller annan tab-anpassning har lagts till. Debug och Release bygger utan fel
(loggar /tmp/panowizard-simple-tabbing-debug.log och release.log).
Runtime-verifieringen är ännu inte slutförd: den körande appens avslut visar
osparade ändringar. Avslutet avbröts för att bevara dem; användaren har tillfrågats
om att själv spara/stänga eller tillåta avslut utan att spara. En full omstart
krävs innan den nya launch-inställningen kan verifieras med två dokument.
Ingen commit/push.

## Commit/push och datumtaggar — 2026-10-06

Användaren har beslutat att framtida `c+p` / `commit+push` i detta projekt även
ska skapa och pusha en annoterad tagg på den slutliga commiten. Namnformat:
`YYYY-MM-DD-hh-mm`, med lokal tid i Europe/Stockholm (24-timmarsklocka). Detta är en
arbetsrutin för uttryckligen begärd commit+push, inte en build-hook eller
automatisk commit. Skapa inga commits/pushar när användaren förbjuder dem.
Commit ce238af med tom projektarbetsyta och enkel tab-inställning är pushad.
Runtime-verifiering av tab-inställningen efter omstart återstår enligt ovan.

## Sparad kontext — 2026-10-07

Användarens avsikt med datumtaggar är att varje uttryckligen begärd "check in"
(c+p) ska ge en lättidentifierad version att återgå till på GitHub. Commit är
själva versionen; push skickar commit och tagg till origin. Behåll det enkla
formatet YYYY-MM-DD-hh-mm; användaren önskar ingen extra precision eller
speciallösning för flera commits inom samma minut. Flytta inte befintliga
publicerade taggar om en namnkonflikt uppstår.
Senast pushade kodändring är ce238af. Efterföljande commits 3975097 och e91ddea
ändrar bara kontext/taggrutin. Befintliga taggar: pre-migration,
2026-10-06_23-15-44 och 2026-10-06-23-18. Ingen ytterligare appkod har ändrats.
Debug/Release lyckades för tab-inställningen; runtime-verifiering efter omstart
med två dokument återstår fortfarande. Osparade ändringar fick inte kastas.

## Buffrade UI-ändringar genomförda — 2026-10-07

Användaren godkände sju punkter med "Kör": Images-menyn har alltid Add...
(disabled utan aktiv projektmodell), separator och bildlista när bilder finns.
Focused scene action använder befintlig image importer. Sidebar Create-knappens
trailing padding korrigerad från 20 till 14 efter visuell kontroll mot Add.
Panorama-menyn heter nu Create, samma action/kortkommando. Välkomstbilden kvar;
WelcomeWindowZoomer borttagen, befintlig WindowStateRestorer återanvänd med
separat app-level frameName PanoWizard.WelcomeWindow. Normal default 1080x680,
projektframe oförändrad. Ingen ändring av start/reopen-flödet i övrigt.
Källbildens masktoolbar visar Clear mask och Rotate med ikon/text; Undo och
Invert-knapparna borttagna, Cmd+Z/underliggande maskfunktioner oförändrade.
Preview-tomläget har samma Create-knapp som Retouch/Export (disabled enligt
canStitch). Alla sex ContentUnavailableView använder nya gemensamma
OpticalEmptyStateLayout, intrinsisk meddelandegrupp centrerad vid höjd/3 och
klampad för små ytor; texter/typografi/interna avstånd oförändrade.
Debug/Release bygger utan fel. Release UI kontrollerad: Add... med tomt projekt,
import av befintlig docs JPG i ett osparat testdokument, maskknapparna, bildmenyn,
Create i Preview/Retouch/Export, tomlägets visuella höjd. Högerpadding slutjusterad
utifrån screenshot; slutlig justering ej verifierad i omstartad UI ännu.
Välkomstfönstrets resize/quit/relaunch-persistens ej manuellt verifierad denna gång.
Gamla Tab-A-fixturen saknar numera sina externa PNG och gav befintligt read-error;
inte ändrat eller sparat. Användarens separat körande installerade app orörd.
Ingen commit, tagg eller push.

## Andra buffrade UI-listan — 2026-10-07

Godkänd med "Kör": maskknappen heter nu Clear (samma ikon/action), JPEG-export
startar med befintliga Maximum-värdet 0.98 i stället för High 0.92, och No Source
Images-tomläget har Add-knapp. Add använder exakt samma importer-presentation
som sidopanel/Images-meny, utan ny filhantering. Knapptext Add, menytext Add...
Första UI-listans ännu ocommittade ändringar behållna. Ingen commit/tagg/push.
Debug och Release BUILD SUCCEEDED efter denna lista, diff --check utan fel.
Kodkopplingen till befintlig importer och Maximum-tag 0.98 verifierad; de tre
ändringarna har inte manuellt provkörts i omstartad app denna gång.

## Tredje buffrade UI-listan — 2026-10-07

Godkänd med "Kör": No Source Images actions innehåller en explicit centrerad
VStack med Add och hjälptext på egen rad (ContentUnavailableView actions lade
annars ut dem horisontellt). Beskrivningen för Preview utan bilder är nu
"To preview, first add source images and create a panorama." Retouch och Export
använder motsvarande godkända text och Add när images.isEmpty. Med bilder men
utan panorama behålls befintlig Create/text/canStitch. Alla Add-knappar använder
befintliga model.isImporterPresented; inga nya sandbox-/import-/stitchflöden.
Tidigare ocommittade UI-ändringar behållna. Ingen commit/tagg/push.
Debug och Release BUILD SUCCEEDED. diff --check utan fel. Brancherna och Add-
action kontrollerade i koden; slutlig visuell kontroll i omstartad app återstår.

## Bakgrunder och samlad check-in — 2026-10-07

Användaren ersatte/utökade välkomstbilderna: Backgrounds innehåller nu A.jpg–G.jpg,
C.png ersatt med C.jpg. Hela folder reference kopieras normalt av Xcode. Debug
 och Release byggda utan fel; exakt samma sju bildnamn och byte-identiska bilder
verifierade i båda app-paketen. Inga bildtransformationer utförda av Codex.
Användaren auktoriserade commit+push av samlade UI-listor och nya bakgrunder,
med datumtagg enligt etablerad rutin. Manuella verifieringsbegränsningar ovan
kvarstår; de har inte ersatts med påståenden om nya runtime-tester.


## Repositorynamn och hjälp-URL — 2026-10-08

Aktivt repository är nu /Users/magnus/Documents/GitHub/panowizard, origin
https://github.com/meg768/panowizard.git. Tidigare next-gen-namn i historiken
avser detta migrerade Xcode-projekt. PanoWizardHelpURL i Info.plist uppdaterad
till https://meg768.github.io/panowizard/ efter namnbytet. Native Help-action
läser fortfarande denna nyckel och öppnar standardwebbläsaren.

## Support och integritetspolicy — 2026-10-08

Inför App Store lade vi till docs/support.md och docs/privacy.md samt länkar
från hjälpens startsida. Användaren valde uttryckligen GitHub Issues som
supportkanal (aktiverat i meg768/panowizard). Ingen påhittad e-postadress.
Policyn baserad på nuvarande kod: lokal bildbehandling, externa källbilder,
projektmetadata/masks/panorama/patches och security bookmarks, frivillig
OpenAI image-edit-request direkt via HTTPS med egen API-nyckel. Nyckeln ligger
för närvarande i UserDefaults, inte Keychain och inte projektet. Inga påståenden
om OpenAI-retention eller träning; länkar till leverantörens datapolicy.
Support varnar för att GitHub Issues är offentliga och att .pw kan innehålla
bilder/sökvägar. Lokala Markdown/HTML-länkar verifierade. Ingen appkod ändrad.
Publicerade adresser efter nästa Pages-deploy: /panowizard/support.html och
/panowizard/privacy.html. Sidorna är ännu inte pushade/publicerade. App Store
Connect Privacy-formulär och appens AI-samtyckesflöde återstår separat; användaren
sköt tidigare upp AI-granskningen. Ingen commit/tagg/push denna gång.

## App Store Connect och TestFlight — 2026-10-08

Support-/policyändringarna ovan är därefter committade och pushade i e569164,
med annoterad tagg 2026-10-08-00-24. Föregående UI-/bakgrundscommit är 5bcd215,
tagg 2026-10-07-23-36. De äldre styckenas "inte pushade" gäller deras tidpunkt.

- App Store Connect Apple ID: 6819353008; bundle se.egelberg.panowizard.
- Archive/upload lyckades för 1.0 (202610080027). Bygget valdes också på
  distributionsversionen. Appens ikon visas korrekt i Connect.
- Internal TestFlight-gruppen "My Testing": en testare och ett build.
  Magnus installerade via TestFlight och bekräftade grundflödet: skapa projekt,
  lägga till bilder, skapa panorama, exportera, spara och återöppna. Detta är
  användarverifiering, inte nya automatiserade tester. AI-liveanrop ej verifierat.
- Gratis: Current Price-screenshot visar 0,00 kr i Sverige och nollpriser i
  övriga synliga marknader. Tillgänglighet 175 länder/regioner.
- Manuell release rekommenderades och användaren gick vidare efter instruktionen;
  slutligt sparat val har inte verifierats i screenshot. Kontrollera detta före
  framtida besked om automatisk/manuell publicering.
- Primärt språk English (U.S.); kategori Photo & Video, ingen sekundär kategori.
  Åldersformuläret gav 4+ (regionala undantag visas), Not Applicable som override.
  Content Rights sparat som inget tredjepartsinnehåll, efter villkoret att
  välkomstbilderna är Magnus egna. Apple's Standard License Agreement kvar.
- App Privacy publicerades via användarens stegvisa arbete. Deklarerade typer:
  Photos or Videos, Other User Content, User ID; App Functionality, linked to
  identity, ingen tracking. API-nyckel som User ID och kopplingen till identitet
  är vår bedömning, inte en uttrycklig Apple-klassificering av API-nycklar.
  Bakgrund: frivillig OpenAI image-edit med egen nyckel och leverantörens
  standardretention; lokal bildbehandling är i sig inte datainsamling.
- Privacy Policy URL: https://meg768.github.io/panowizard/privacy.html
  Support URL: https://meg768.github.io/panowizard/support.html
  Marketing URL: https://meg768.github.io/panowizard/
  Copyright: 2026 Magnus Egelberg. GitHub Issues är vald supportkanal.
- Beskrivning och keywords ifyllda. Promotional Text och Subtitle lämnades tomma.
- Sign-in required avmarkerat; Apple-kontaktuppgifter ifyllda av användaren.
  **API-nyckeln anges i själva AI-retuschgränssnittet, inte i Settings.**
  Användarens rättelse är styrande för framtida dokumentation/granskningsnoter.

Granskningsnoter sparade av användaren:

PanoWizard creates panoramas from overlapping source images. To test the main
workflow, add overlapping photos, click Create, and export the result. Image
stitching, masks, manual retouching, and previews run locally without signing in.

Optional AI retouching requires an OpenAI API key entered in the AI retouch
interface. It sends the selected panorama view and editing instructions directly
to OpenAI.

### Butiksskärmbild

En skärmbild är uppladdad och sparad, med Lunds Domkyrka i Preview och appens
sidopanel. Projektet var redan öppet från
/Users/magnus/Desktop/Panorama/U/panowizard.pw i /Applications/PanoWizard.app.
Native app-screenshot togs via CUA; inga kod- eller projektändringar gjordes.
Efter uttryckligt godkännande skalades den proportionellt med ImageMagick och
smala mörka sidomarginaler till exakt 2880 × 1800, utan beskärning/förvrängning.
Original: /Users/magnus/Desktop/PanoWizard-AppStore/01-preview.png
Uppladdad: /Users/magnus/Desktop/PanoWizard-AppStore/01-preview-2880x1800.png

### Kända kvarstående frågor

AI-disclosure/uttryckligt samtycke i appen sköts tidigare upp och har inte
granskats eller ändrats i denna session. Hur Apple ska testa valfri AI-retusch
utan egen API-nyckel diskuterades men löstes inte före användarens inskick.
Inskicket är bekräftat; det betyder inte att dessa frågor är verifierade eller
att Apple godkänt appen. Hantera konkret återkoppling när den kommer.

Kontext sparad lokalt på uttrycklig begäran; ingen ny commit/tagg/push begärd.
