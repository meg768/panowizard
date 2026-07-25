# PanoWizard – aktuell projektkontext

## Produkt

PanoWizard är en återupplivning av en macOS-applikation från omkring år 2000.
Målet är en liten, elegant och native panoramaapp: mer Pixelmator än Photoshop.

- Native Swift 6 och SwiftUI
- Apple Silicon
- macOS 26 eller senare
- Ett panorama per dokument
- Dokumentformatet är ett `.pw`-paket
- Vänster sidopanel med resultat och källbilder
- Central bild-/panoramavy
- Import, Stitch och Export utan guider eller dialogtungt arbetsflöde

Projektmappen heter `panowizard`; appen och produkten heter `PanoWizard`.

## Git och omstart

Den misslyckade första prototypen är återställningsbart arkiverad på `main` i
commit `f6a6445` (`Archive PanoWizard prototype before clean restart`).
Den rena arbetsgrenen är `codex/restart`.

Omstartens dokumentredigerare finns i commit `6697f1b`. Den återställde
dokumentfönster, `.pw`-paket, import, metadata, sidopanel, bildvisning och
manuell källbildsmaskning, men ingen stitchkod.

Den gamla stitch-, riggcache- och nadirreparationsimplementationen ska inte
återinföras. Externa, ignorerade beroenden finns kvar i:

- `Vendor/Hugin`
- `Vendor/OpenCV`

## Dokumentformat

Formatversionen är 5 och är medvetet inte bakåtkompatibel.

```text
Projekt.pw/
  project.json
  masks/
    <bildens UUID>.png
  panorama/
    result.jpg
    nadir-overlay.png
```

Originalbilderna refereras externt. Maskerna är röda PNG-raster i
källbildens pixelstorlek. Grundpanoramat lagras som JPEG. En registrerad
nadirreparation lagras separat som en transparent PNG och får aldrig bakas in
i grundpanoramat under granskningsfasen.

Varje bild har två explicita egenskaper:

- riktning: `horizontal`, `zenith` eller `nadir`
- roll: `alignment` eller `fillOnly`

Bildantal eller filnamn får inte användas för att gissa nadir/utfyllnad.

## Ny, verifierad stitcharkitektur

Grundstitchningen byggdes först som fristående experiment och kopplades sedan
till appen. Den använder:

- OpenCV 5 SIFT för deterministiska kontrollpunkter
- Hugin för optimering, projektion och warping
- Enblend för sömmar och blending

Hugins gamla `cpfind 2019.2` används inte. Upprepade identiska körningar gav
olika kontrollpunkter och ibland helt olika geometri. OpenCV-matcharen kör med
en tråd och fast RNG-seed.

### Fas 1: fryst horisontell ring

1. Horisontella `alignment`-bilder fördelas jämnt över 360° i projektordning.
2. Varje fisheye-källa normaliseras till en grov equirektangulär arbetsbild.
3. SIFT jämför endast verkliga grannpar, inklusive sista→första.
4. Korsmatchning, deskriptorkvot, geometriskt avstånd och dubblettfilter
   reducerar träffarna till högst 60 punkter per skarv.
5. Källpunkterna räknas tillbaka till originalbildens pixelkoordinater.
6. Hugin kör `cpclean` och `autooptimiser -a -l -s`.

### Fas 2: zenit mot fryst ring

1. Ringens färdiga kamerageometri läses ur PTO-filen.
2. Zenitbilden provas i åtta fysiskt rimliga startlägen.
3. Läget med flest geometriskt samstämmiga träffar väljs.
4. Zenitbilden kopplas mot minst två ringbilder.
5. PTO-filen innehåller optimeringsvariabler endast för zenitbildens
   yaw/pitch/roll.
6. Efter `autooptimiser -n` jämförs ringens bildrader exakt. Stitchningen
   avbryts om zenitsteget ändrat någon ringbild.

### Fas 3: masker och rendering

Originalbilderna används alltid för feature-matchning och geometri.
Användarmasker får aldrig påverka dessa steg.

Efter att geometrin är färdig skapas temporära TIFF-kopior med alfa:

- användarens röda mask blir transparent,
- för Sigma 8 mm DX klipps de svarta optiska hörnen bort med objektivets
  cirkulära bildgräns.

Endast filsökvägarna byts i den färdigoptimerade PTO-filen. Sedan körs:

```text
pano_modify → nona → enblend
```

Resultatet är 4000×2000 JPEG, equirektangulärt 360×180°.

### Fas 4: separat nadirregistrering

En handhållen nadirbild måste vara `direction: nadir` och `role: fillOnly`.
Den deltar aldrig i ringens feature matching, bundle adjustment, zenitsteg,
`nona` eller `enblend`.

Efter att `result.jpg` är helt färdig:

1. En lokal 120° rectilinear nadirvy extraheras ur grundpanoramat.
2. Nadirbildens fisheyeprojektion rätas till en motsvarande lokal vy.
3. OpenCV SIFT och RANSAC beräknar en lokal homografi.
4. Nadirbilden warpas till en transparent lokal 1600×1600-overlay.
5. Homografin och träffantalet sparas i `project.json`.
6. Metal-förhandsvisningen projicerar den lokala overlayn över
   grundpanoramat och riktar kameran mot nadir.
7. I läget `Justera nadir` kan användaren flytta lagret med dragning, rotera
   med kommando-dragning och skala med rullning eller nypgest.
8. Den manuella korrigeringen lagras separat som flytt, rotation och skala i
   `project.json`. Grundpanoramat och den automatiska homografin ändras inte.

Overlayn visas halvgenomskinligt under positionering. När placeringen är
avslutad visas reparationslagret med full opacitet.

### Fas 5: reparationsmask

Nadirbilden använder samma röda exkluderingsmask som övriga källbilder:
användaren målar över pixlar som inte ska läggas in i panoramat.

Masken deltar inte i SIFT, homografin eller någon annan positionering.
Registreringen använder alltid hela nadirbilden. Därefter projiceras endast
maskens alfa genom fisheye→rectilinear och den redan sparade homografin.
En maskändring renderar därför bara om den lokala 1600×1600-overlayn; den
frysta panoramageometrin, `result.jpg`, Hugin och Enblend berörs inte.

Maskens antialiasade kant bevaras genom projektionen. Slutlig färgmatchning
och sömblandning görs i ett separat lokalt steg.

### Fas 6: lokal Enblend-förhandsvisning

När användaren avslutar placeringen eller väljer `Visa resultat` byggs en
slutlig lokal förhandsvisning utan att grundpanoramat stitchas om:

1. Den färdiga 120°-nadirvyn extraheras ur `result.jpg`.
2. Reparationsbildens sparade homografi, manuella flytt, rotation och skala
   bakas in i ett lokalt 1600×1600-TIFF-lager.
3. Reparationsmasken tvingar Enblend att använda reparationen i maskens inre
   område. Grundpanoramat är tvingande utanför masken, medan en bred
   överlappningszon lämnas åt Enblends sömval och multibandsblandning.
4. Enblend körs endast på dessa två lokala lager.
5. Resultatet sparas som en kanttonad transparent lokal overlay och visas
   över det fortfarande orörda equirektangulära grundpanoramat.

Det oblandade lagret används fortfarande under interaktiv placering. Därför
är dragning, rotation och skalning omedelbara. När justeringsläget avslutas
ersätts det med den lokalt Enblend-blandade förhandsvisningen. En flagga i
`nadirRepairPlacement` anger vilken sorts overlay som ligger i paketet så att
sparade dokument öppnas korrekt.

## Verifierat testmaterial

Det aktiva testprojektet är:

`/Users/magnus/Desktop/Lundalogik/Panorama.pw`

Källorna är:

- `1.tiff`–`4.tiff`: horisontell ring
- `5.tiff`: zenit
- `6.tiff`: handhållen nadirreparation

Objektivet är Sigma 8 mm på DX. Rätt startmodell är full-frame fisheye med
cirka 120° horisontell bildvinkel över bildens korta sida. Hugin optimerar den
till cirka 113° för detta exemplar.

Det fristående experimentet finns under `Experiments/`. Två fullständiga
körningar gav:

- identisk slutlig kamerageometri,
- samma kontrollpunktsantal i alla skarvar,
- samma valda zenitorientering,
- endast 0,68 % pixel-RMSE från Enblends renderingsvariation.

Swift-integrationen kördes därefter mot själva `.pw`-paketet via
`PanoramaEngineIntegrationTests` och gav ett visuellt granskat, sammanhängande
360×180-panorama. Byggnad, mark, wrap-skarv och zenit är stabila. Bord och
stativ finns kvar i själva grundpanoramat.

Projektets `project.json` korrigerades så att bild 5 är `zenith` och
Sigma-preseten är 120°.

Den separata nadirregistreringen testades först i en kopia av projektet med
bild 6 som `Nadir · Reparation`. Grundpipens logg var fortfarande exakt
bilderna 1–5; bild 6 förekom endast i `Local nadir repair registration`.
Overlayn granskades både equirektangulärt och som lokal 120° nadirvy.
Positioneringen av bord och mark är sammanhängande nog för nästa masketapp.

## Avsiktliga begränsningar just nu

Den nya motorn stöder:

- två eller fler horisontella `alignment`-bilder,
- högst en zenitbild,
- manuella exkluderingsmasker efter geometri,
- högst en separat `Nadir · Reparation`.

Den avvisar tydligt:

- `nadir` med rollen `alignment`,
- `fillOnly` som inte är nadir,
- flera zenitbilder.

Nadirlagret är halvgenomskinligt endast i läget `Justera nadir`. I normal
panoramavy visas den maskerade kompositionen med full opacitet.

## Bygg och kör

`Package.swift` har ett litet C++-target, `OpenCVBridge`.
`Scripts/build-app.sh`:

1. bygger release för arm64,
2. bäddar in OpenCVs `.500.dylib`,
3. bäddar in `Vendor/Hugin` i appens resurser,
4. ad hoc-signera och verifierar apppaketet.

Normal kontroll efter kodändringar:

```sh
swift test
./Scripts/build-app.sh
open build/PanoWizard.app /sökväg/till/Projekt.pw
```

Integrationstestet körs uttryckligen med:

```sh
PANOWIZARD_INTEGRATION_PROJECT=/sökväg/till/Projekt.pw \
  swift test --filter PanoramaEngineIntegrationTests
```

## Arbetsprinciper

- Gör små, kompletta inkrement som kompilerar.
- Skriv kompletta filer, inga platshållare.
- Granska alltid verkliga panoramapixlar visuellt.
- Ett grönt test eller processretur räcker inte för att kalla stitchningen bra.
- Håll panoramalösaren och reparationspipen strikt separerade.
- Bevara användarens filer och orelaterade ändringar.

## Överlämning till nästa konversation – 25 juli 2026

Användaren vill fortsätta härifrån i en ny konversation. Börja med att läsa
hela denna fil och ändra inte stitcharkitekturen utan ett konkret observerat
fel.

Senaste genomförda inkrement är den lokala Enblend-förhandsvisningen:

- `Visa resultat` i reparationsmaskläget skapar den blandade vyn.
- `Klar` efter `Justera nadir` gör samma sak.
- `Justera nadir` växlar tillbaka till den snabba, oblandade overlayn.
- Det färdiga grundpanoramat stitchas aldrig om av dessa åtgärder.
- Den manuella transformen bakas in endast i den lokala Enblend-vyn.
- `blendedPreview` i `NadirRepairPlacement` skiljer sparad blandad overlay
  från den oblandade justeringsoverlayn.

Ett första Enblend-försök lät basbilden täcka reparationsbilden helt. Det
åtgärdades avsiktligt i `OpenCVBridge.cpp`: reparationsmaskens inre kärna
tvingas komma från reparationsbilden, baspanoramat tvingas utanför masken och
en dynamisk överlappningszon lämnas åt Enblend. Ta inte bort denna
prioritering; utan den kan stativet komma tillbaka trots att körningen lyckas.

Den verkliga lokala 1600×1600-vyn från
`/Users/magnus/Desktop/Lundalogik/Panorama.pw` granskades visuellt efter
ändringen:

- stativet var borta,
- bordsskivan kom från bild 6,
- omgivningen kom från det frysta panoramat,
- den tidigare hårda maskkanten syntes inte.

Verifiering vid överlämningen:

- `swift test`: 10 tester passerade.
- Det separata testet
  `blendsRepairIntoFrozenLocalPanoramaView` passerade mot det verkliga
  projektpaketet på cirka tre sekunder.
- Releaseappen byggdes.
- Strikt `codesign --verify --deep --strict` passerade efter att
  `com.apple.FinderInfo` togs bort och appen signerades om.
- Appen startades med det aktiva `Panorama.pw`.

Aktiv gren är `codex/restart`. Senaste committade stabila punkt är
`3e43f1b Restore stable ring and zenith stitching`. All nadirfunktionalitet
efter den punkten är ännu okommittad och arbetskopian är medvetet smutsig.
Gör ingen reset eller checkout som kan kasta dessa ändringar. Användaren har
inte bett om en ny commit efter Enblend-inkrementet.

Naturligt nästa produktsteg, när användaren har granskat förhandsvisningen i
appen, är antingen små visuella korrigeringar av den lokala blandningen eller
Export till JPEG/TIFF. Export måste i så fall baka ihop grundpanoramat och den
lokalt blandade nadirreparationen i en ny 4000×2000 equirektangulär fil utan
att ändra `.pw`-projektets frysta grundpanorama.

### Viktigt om arbetsflödet och UI

Användaren sade vid avslutningen att arbetsflödet inte var begripligt.
Funktionerna finns, men de tre lägena och övergångarna mellan dem kommuniceras
inte tillräckligt tydligt i appen. Nuvarande avsedda ordning är:

1. `Justera nadir`: flytta, rotera och skala den halvgenomskinliga
   reparationsbilden.
2. `Klar`: lämna placeringsläget och skapa en lokalt Enblend-blandad
   förhandsvisning.
3. `Maskera reparation`: öppna källbilden och måla rött över pixlar som inte
   ska användas. Det område som ska ersätta stativet lämnas omålat.
4. `Visa resultat`: kör lokal Enblend igen och återgå till panoramats
   förhandsvisning.
5. Iterera med `Justera nadir` eller `Redigera reparationsmask`; `⌘S` sparar
   projektet.

`Visa resultat` betyder förhandsvisning, inte export eller permanent
slutförande. Det finns ännu inget särskilt slutförandesteg. Nästa konversation
bör först diskutera eller förbättra denna UX, exempelvis med ett tydligare
stegflöde och mer precisa knappnamn, innan fler reparationsfunktioner läggs
till.
