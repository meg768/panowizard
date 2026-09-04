# PanoWizard – utvecklaranvisningar

## Produktgränser

- PanoWizard är en native SwiftUI-app för macOS.
- `TrialOpenCVPanoramaEngine` är den enda panoramamotorn.
- Panoramamotorn får bara använda originalbilder och individuella masker.
- Utdata ska alltid vara en komplett equirektangulär 360° × 180°-bild i 2:1.
- Bildimport, dokument, källsortering, masker, viewer, export, progress och
  avbrytning ska hållas oberoende av motorns interna feature-matchningar.
- Interna features, matchningar och linsparametrar är inte redigerbart UI.

AI-retuschering är ett uttryckligt, separat eftersteg och är aldrig en del av
panoramamotorn. Den får inte användas för stitchning, geometri, sömval eller för
att fylla maskerade områden.

## Arkitektur

- `Models/PanoProject.swift` definierar det kompakta projektformatet v7.
- `Services/TrialPanoramaEngine.swift` förbereder källor/masker, äger cache-id,
  vidarebefordrar progress/avbrytning och anropar C-bryggan.
- `Sources/OpenCVBridge/TrialPanoramaBridge.cpp` innehåller hela native-motorn.
- `Services/MaskedSourceImageWriter.swift` skriver orienterade TIFF-källor där
  röda masker ligger i alpha.
- gröna skyddsmasker skickas separat och påverkar sömprioriteringen.
- `ViewModels/AppModel.swift` kopplar motorn till dokument- och UI-livscykeln.

Motorkoden ska förbli fristående från SwiftUI och dokumentlagring. Lägg inte in
panorama-, kamera- eller testmappsspecifika specialfall.

## Projektkompatibilitet

Format v7 lagrar källor, aktivering, maskpaket, preview-vy och retuschprompt.
Avkodaren accepterar v6 och ignorerar okända föråldrade fält. Gamla dokument
ska öppnas utan att det tidigare arbetsflödet återkommer.

## Verifiering

Efter ändringar i motorn:

1. Kör `swift build`.
2. Kör berörda fokuserade tester.
3. Bygg appaketet med `./Scripts/build-app.sh` när paketering eller länkar ändras.
4. Beskriv alltid en större panoramaregression innan hela bildmaterialet körs.

Använd endast originalbilder som indata i bildregressioner. Filer som råkar ligga
i samma mapp men inte är källbilder ska aldrig autodetekteras som motordata.

Panorama C är det visuella regressionsankaret för parallax och sömmar. Läs
`TRIAL_ENGINE.md` före ändringar i GraphCut, central täckning eller feathering.
Ett godkänt C-resultat måste samtidigt behålla raka skidstavar och liftlinor,
en hel fotograf utan halo samt hela skidåkare i bakgrunden.

## Aktuell handoff (2026-09-04)

- Den native OpenCV-motorn använder cacheversion `trial-native-cycle-v1`.
- Cykelåterhämtningen i `TrialPanoramaBridge.cpp` ska lämnas orörd. MST är
  kandidat A. Kandidat B skapas bara när A:s outlier-filtrering bryter en stark
  cykel, använder samma frysta `TrialOptimizationSample`, optimeras med samma
  optimizer och jämförs mot samma ofiltrerade valideringsmängd. Flest
  observationer inom residualgränsen vinner, därefter lägst robust fel.
- Panorama L väljer kandidat B och är visuellt korrekt efter denna ändring.
  Backa inte L-fixen för att lösa andra problem.
- Panorama A aktiverar kontrollen för cykeln `0-6-5-9-0`, eftersom MST-kanten
  `5-9` går från 13 frysta observationer till 0 efter första fitten. B förlorar
  dock mot A: 796 mot 799 förklarade observationer. Återhämtningsgrenen kostar
  cirka 0,15 sekunder och orsakar inte A:s tidigare sömstopp.
- GraphCut-prestandafelet var att alla fulla 2048×1024-warpytor skickades med
  hörnet `(0,0)`. OpenCV byggde då en miljonnodsgraf för varje bildpar oavsett
  verklig masköverlapp. Varje källa beskärs nu oberoende till sin mask-support
  plus 10 pixlars kontext och skickas med sitt verkliga panoramahörn. Det är
  viktigt att inte beskära båda bilderna till samma överlappsrektangel: den
  gemensamma konstgjorda kanten kan då bli en synlig GraphCut-söm.
- Endast panorama A verifierades efter ROI-ändringen. Releasevärden med sparad
  alignment: sömberäkning 3,533 s, hela renderingen 19,145 s, coverage
  96,821296 %, 266649 maskorsakade hålpixlar. Debug- och releasebilderna var
  byte-identiska och resultatet såg visuellt korrekt ut.
- Inga andra panorama och ingen regressionstestsvit har körts efter ändringen.
  Användaren kör panorama manuellt och återkommer med problembarn; kör inte en
  bred bildregression utan uttrycklig begäran.
- Panorama D visade att centralitetsfiltret med tolerans 0,12 kan krympa
  bild 0/3:s sömkorridor så mycket att GraphCut går genom den parallaxade
  kustlinjen. Ett försök med den ursprungliga, obegränsade masköverlappningen
  gav sammanhängande kust men ett tydligare fotavtryck från den utfrätta
  källbilden och upplevdes som sämre. Den återhämtningskandidaten är helt
  borttagen igen. Gör ingen ny D-ändring utan att samtidigt hantera både
  geometrisk sömplacering och den utfrätta himlens radiometriska övergång.
- Senast byggda och lokalt signerade app finns i `build/PanoWizard.app`.
