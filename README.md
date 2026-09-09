# PanoWizard

PanoWizard är en native macOS-app för att skapa kompletta 360° × 180°-
panoraman från överlappande fisheye-bilder. Appen hanterar import, källurval,
maskning, automatisk geometrisk justering, sömval, färg- och tonutjämning,
förhandsvisning, retusch och export i ett sammanhållet projekt.

## Arbetsflöde

1. Skapa ett projekt och importera minst två överlappande bilder.
2. Kontrollera bildordningen och välj vid behov bildtyp: Automatisk,
   Panoramaring eller Reparationsbild.
3. Måla vid behov röda exkluderingsmasker eller gröna skyddsmasker på
   källbilderna.
4. Välj **Skapa panorama** och granska den equirektangulära 2:1-bilden i
   360°-förhandsvisningen.
5. Retuschera vid behov nadir eller zenit och exportera resultatet.

Röda masker tar bort källpixlar före geometri, radiometri och compositing.
Gröna masker skickas separat och ger källan prioritet vid sömval. Motorn
syntetiserar aldrig bildinnehåll där giltigt källunderlag saknas.

## Panoramamotorn

Appen har en enda inbyggd C++17/OpenCV-motor bakom en liten C-brygga till
Swift. Den körs i processen och startar inga externa verktyg.

Den faktiska huvudkedjan är:

1. Orienterade källbilder skrivs som TIFF med exkluderingsmasken i alpha.
2. En gemensam optisk bildcirkel detekteras.
3. SIFT-features matchas ömsesidigt och filtreras med rotationsbaserad RANSAC.
4. Kamerarotationer och fisheye-linsmodell optimeras robust och horisonten
   rätas upp.
5. Ringbilder projiceras sfäriskt till equirektangulära lager. Separata
   reparationsbilder registreras mot ringen och används endast för att fylla
   täckning.
6. Global överlappsradiometri, redundansundertryckning och central
   täckningsprioritet beräknas.
7. GraphCut väljer ägare och sömgeometri. Skyddsmasker och konfliktinformation
   ingår i beslutet.
8. Validerad sömlokal lågfrekevent färg- och tonkorrigering appliceras
   symmetriskt på de redan warpade källagren utan att ändra ownership.
9. Den innehållsanpassade compositorn kombinerar en smal detaljövergång med
   bredare lågfrekevent utjämning i konsekventa områden. Struktur och konflikt
   skyddas, med en upplösningsskalad och hårt begränsad minimum-feather för
   svåra högkonfliktsömmar.
10. Resultatet skrivs som en komplett equirektangulär JPEG och rapporterar
    täckningsgrad samt hålpixlar.

Alignment-cache nycklas av motorformat, källornas identitet och metadata,
bildroll, riktning och röda masker. Ändrad geometriindata eller
exkluderingsmask ger därför en ny lösning.

Källbilder i samma panorama måste ha samma pixelmått. Minst två aktiva,
överlappande bilder krävs.

## Retusch och export

PanoWizard kan exportera JPEG, PNG och TIFF samt en självständig interaktiv
HTML-fil. Little Planet skapar en separat stereografisk PNG från det redan
färdiga panoramat; rotation, planetstorlek, horisonthöjd och bakgrund kan
justeras i en live-förhandsvisning.

Nadir och zenit kan exporteras och importeras som plana 2048 × 2048-pixels
kubsidor för extern retusch. AI-retusch är ett valfritt eftersteg och påverkar
aldrig stitchning, geometri eller sömval. En valfri arbetsmask gör målade
pixlar transparenta i bilden som skickas till OpenAI; samma prompt används med
och utan mask och hela svaret används som retuschresultat. Prompt, arbetsmask
och godkänt resultat sparas i projektet.

## Projektformat

Projektformat v7 lagrar källor, roller, masker, färdigt panorama,
förhandsvisningsvy och retuschdata i projektpaketet. Format v6 kan fortfarande
öppnas och migreras; okända föråldrade fält ignoreras.

## Bygga och köra

Krav:

- macOS 26 SDK
- Swift 6.2
- de versionslåsta OpenCV-biblioteken i `Vendor/OpenCV`

Utvecklingsbygge och körning:

```sh
swift build
swift run PanoWizard
```

Lokalt signerat appaket:

```sh
./Scripts/build-app.sh
open build/PanoWizard.app
```

Skriptet skapar `build/PanoWizard.app`, bäddar in OpenCV-dylibs och signerar
appen ad hoc. Bilder i `Sources/PanoWizard/Resources/Backgrounds` (`jpg`,
`jpeg` eller `png`) paketeras automatiskt och används växelvis i välkomstvyn.

## Projektstruktur

- `Sources/PanoWizard/Application` – app- och dokumentlivscykel
- `Sources/PanoWizard/Models` – projekt-, käll- och maskmodeller
- `Sources/PanoWizard/Services` – motoradapter, import, export och retusch
- `Sources/PanoWizard/Views` – SwiftUI-gränssnitt och panoramavy
- `Sources/OpenCVBridge` – C-API och native panoramaimplementation
- `Sources/PanoWizard/Resources` – resurser som Swift Package Manager bäddar in
- `Resources` – appikon och `Info.plist` för appaketet
- `Scripts` – reproducerbar paketering av appen
- `Tests/PanoWizardTests` – fokuserade enhets- och motortester
- `Vendor/OpenCV` – versionslåsta headers och dynamiska bibliotek

## Tester

Kör i första hand den minsta relevanta sviten:

```sh
swift test --filter OpenCVPanoramaEngineTests
swift test --filter PanoProjectTests
swift test --filter LittlePlanetRendererTests
```

Motortesterna verifierar bland annat 2:1-utdata, cacheåteranvändning,
masköverföring och källurval. Visuella bildregressioner använder uttryckligt
valda originalprojekt och körs separat; de ingår inte i en vanlig build.
