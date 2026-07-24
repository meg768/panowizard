# PanoWizard

PanoWizard är en liten, native macOS-app för automatisk panoramasammanfogning.

Varje dokumentfönster innehåller ett panorama. Projekt sparas som
`.pw`-filpaket och kan öppnas igen med macOS vanliga dokumentkommandon.
Paketet innehåller `project.json`, användarens PNG-masker och det senast
sammanfogade panoramat. Originalbilderna ligger kvar på sina befintliga
platser och bäddas inte in i projektet.

## Krav

- macOS 26
- Apple Silicon
- Xcode 16 eller senare
- Swift 6

## Öppna och köra

Öppna `Package.swift` i Xcode och välj **PanoWizard** som körmål. Projektet kan
också verifieras från Terminal:

```sh
swift build
swift test
```

En körbar, ad hoc-signerad app byggs med:

```sh
./Scripts/build-app.sh
```

Resultatet skapas som `build/PanoWizard.app`.

## Arkitektur

Appen använder MVVM och små tjänster med protokollbaserade beroenden:

- `Views` innehåller SwiftUI-gränssnittet och en projektcentrerad sidopanel.
- `ViewModels` äger varje dokumentfönsters observerbara tillstånd.
- `PanoProjectDocument` läser och skriver det versionshanterade `.pw`-formatet.
- `ImageImportService` hittar bilder i filer och mappar.
- `ImageMetadataReader` läser EXIF via ImageIO.
- `PanoramaGroupingService` sorterar importerade bildserier.
- `OpenCVPanoramaEngine` sammanfogar bilder bakom protokollet `PanoramaEngine`.
- `HuginPanoramaEngine` använder CPFind och Nona för fullsfäriska fisheye-set.
- `PanoramaExporting` avgränsar export.

OpenCV 5 byggs lokalt och begränsat för ARM64/macOS 26 med:

```sh
./Scripts/build-opencv.sh
```

Det kräver `cmake` och `ninja`. `build-app.sh` kör automatiskt OpenCV-bygget
första gången och bäddar in biblioteken i appen. Appen har riktig
sammanfogning samt en zoombar och panorerbar förhandsvisning. Export aktiveras
i ett senare inkrement.

Hugins kommandoradsverktyg hämtas och förbereds med:

```sh
./Scripts/build-hugin-tools.sh
```

PanoWizard väljer automatiskt Hugin för fisheye-bilder och OpenCV för
rectilineära bilder.

Sammanfogningsinställningarna har profiler för Nikon 10,5 mm och Sigma 8 mm
på DX-sensor samt ett redigerbart horisontellt startsynfält. Varje bild märks
separat som Horisontell, Zenit eller Nadir och som Positionering eller
Utfyllnad. Inga antaganden görs utifrån bildantalet.

Varje källbild har en manuell, icke-destruktiv pixelmask. Välj bilden i
sidopanelen och måla rött över personer, stativ eller andra pixlar som inte ska
användas. Maskerna påverkar inte Hugins kontrollpunkter eller optimering. Inför
slutrenderingen förs masken över till källans alfakanal; Nona transformerar den
En lyckad positionering sparas dessutom i projektet och återanvänds, så att
maskändringar och utfyllnadsbilder inte kan flytta grundpanoramat.
med bilden och Enblend använder de återstående, omaskerade överlappningarna.
Det finns ingen automatisk nadirmaskning eller automatisk bildreparation.

En handhållen nadir- eller lagningsbild kan markeras **Endast utfyllnad** från
verktygsraden eller bildens kontextmeny. Normala bilder är
**Ingår i positionering**. Utfyllnadsbilder påverkar aldrig riggens geometri;
de passas in först efter att övriga bilders positioner har låsts. Rollen sparas
i projektet och ingen särskild listposition antas ha denna betydelse.
