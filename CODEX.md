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
```

Originalbilderna refereras externt. Maskerna är röda PNG-raster i
källbildens pixelstorlek. Resultatet lagras som JPEG i dokumentpaketet när
dokumentet sparas.

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

## Verifierat testmaterial

Det aktiva testprojektet är:

`/Users/magnus/Desktop/Lundalogik/Panorama.pw`

Källorna är:

- `1.tiff`–`4.tiff`: horisontell ring
- `5.tiff`: zenit

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
stativ finns avsiktligt kvar i nadir eftersom ingen reparationsbild används.

Projektets `project.json` korrigerades så att bild 5 är `zenith` och
Sigma-preseten är 120°.

## Avsiktliga begränsningar just nu

Den nya motorn stöder:

- två eller fler horisontella `alignment`-bilder,
- högst en zenitbild,
- manuella exkluderingsmasker efter geometri.

Den avvisar tydligt:

- `nadir` i grundlösaren,
- `fillOnly`,
- flera zenitbilder.

Nadir och handhållna utfyllnadsbilder ska senare bli en separat
panoramareparationspipeline. De får aldrig delta i ringens feature matching,
bundle adjustment, wave correction, warping eller Enblend-körning.

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
- Lägg inte till cache, nadir eller utfyllnad innan basmotorn är fortsatt stabil.
- Bevara användarens filer och orelaterade ändringar.
