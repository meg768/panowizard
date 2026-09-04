# PanoWizard

PanoWizard är en native macOS-app för att importera och sortera fisheye-bilder,
maska varje källa, skapa ett komplett equirektangulärt panorama och visa eller
exportera resultatet. Panoramat är alltid 360° × 180° i proportionen 2:1.

## Panoramamotorn

Appen har en enda inbyggd motor: en native C++/OpenCV-port av Trial-motorn.
Användaren behöver inte installera Python, SciPy eller kommandoradsverktyg.

Motorn utför automatiskt:

- SIFT-featuredetektering och ömsesidig matchning
- rotationsbaserad RANSAC
- gemensam optimering av kamerarotationer och fisheye-linsmodell
- automatisk horisontutjämning
- sfärisk remapping till equirektangulär projektion
- GraphCut-sömmar, innehållsbevarande feathering och blending
- exponerings-, färg- och radiometrisk korrigering från överlappande pixlar
- återanvändning av alignment-cache

Individuella röda exkluderingsmasker och gröna skyddsmasker skickas direkt till
motorn. Maskerade pixlar används aldrig. Motorn genererar eller retuscherar inte
bildinnehåll och läser inte referensprojekt eller referensrenderingar.

Mer om avgränsningen finns i [TRIAL_ENGINE.md](TRIAL_ENGINE.md).

## Arbetsflöde

1. Öppna eller skapa ett PanoWizard-projekt.
2. Importera minst två överlappande originalbilder.
3. Måla vid behov en röd exkluderingsmask eller grön skyddsmask per bild.
4. Välj **Skapa panorama**.
5. Granska resultatet i 360°-vyn och exportera bild eller självständig HTML.

Äldre projektformat v6 kan öppnas. Föråldrade motor-, kontrollpunkts- och
objektivfält ignoreras vid migrering till format v7; källbilder, masker,
panorama och retuschdata bevaras.

## Bygga

Krav: macOS 26 SDK, Swift 6.2 och de versionslåsta OpenCV-biblioteken i
`Vendor/OpenCV`.

```sh
swift build
./Scripts/build-app.sh
```

Release-skriptet skapar `build/PanoWizard.app`, bäddar in OpenCV-biblioteken och
signerar appen lokalt. Panoramamotorn startar inga externa processer.

## Tester

Kör en avgränsad svit med exempelvis:

```sh
swift test --filter TrialPanoramaEngineTests
swift test --filter PanoProjectTests
```

Motortesterna verifierar bland annat 2:1-utdata, cacheåteranvändning,
masköverföring och källurval. Stora bildregressioner körs separat mot uttryckligt
valda originalbilder.
