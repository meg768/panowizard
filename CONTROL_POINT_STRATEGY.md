# Geometri- och kontrollpunktsstrategi

Det här dokumentet beskriver PanoWizards avsiktliga regler för automatisk
positionering. Det är en designspecifikation, inte en logg över enskilda
felsökningspass.

## Produktkontrakt

Det automatiska acceptansflödet börjar med originalbilder och metadata och ska
ge ett visuellt korrekt 360°-panorama utan importerade PTGui-punkter eller
manuella korrigeringar. Manuella verktyg finns för diagnos och räddning, men får
inte döljas som en del av ett påstått automatiskt resultat.

Ett osäkert bildset ska stoppas med en begriplig orsak hellre än att godkännas
med en trasig 3D-startpose. Samtidigt ska specialfall vara konservativa: en
ovanlig bildvinkel eller ett tidsavstånd räcker aldrig ensamt för att klassa en
bild som reparation.

## Geometri och bildinnehåll är olika steg

PanoWizard håller isär tre problem:

1. **Geometri** – kontrollpunkter, linsmodell och kameraposer.
2. **Söm/blandning** – vilken redan projicerad källa som syns i överlappet.
3. **Retusch** – ett eftersteg som ersätter lokalt bildinnehåll utan att flytta
   kameror eller kontrollpunkter.

En snygg söm bevisar inte att geometrin är korrekt, och en AI-retusch får inte
användas som argument för att kontrollpunktsnätet fungerar.

## Bildroller

Alla nya bilder börjar som **Automatisk positionering**. Den effektiva rollen
blir antingen:

- **Ingår i positionering**: bilden deltar i den gemensamma
  rotations-/linsmodellen.
- **Reparation**: bilden hålls utanför riggen och registreras lokalt mot ett
  redan löst panorama.

Nadir och zenit beskriver riktning, inte geometrisk roll. Bilder från ett stativ
eller panoramahuvud kan peka mot polerna och ändå höra till positioneringen.

## Automatisk kontrollpunktskedja

1. Läs EXIF och välj kalibrerad objektivprofil när det går.
2. Matcha verkliga överlapp med OpenCV.
3. Filtrera med ömsesidig descriptor-kontroll och robust geometri.
4. Sprid punkterna över överlappet i stället för att samla dem i ett texturrikt
   hörn.
5. Bygg en sammanhängande graf med en trovärdig 360°-ryggrad.
6. Lös först poser och finjustera därefter de linsparametrar som profilen tillåter.
7. Rensa automatiska residualuteliggare utan att bryta en verkligt gles cykel.
8. Rendera först när den lösta grafen klarar kvalitetskontrollerna.

För fyrbildsringar prioriteras de fyra verkliga grannövergångarna. Diagonala
länkar får inte introducera en motsägelsefull genväg genom fisheye-bilden.
Ringstängning bedöms från grafens topologi, inte enbart från filordningen.

## Befintliga punkter är auktoritativa

Manuellt redigerade, importerade eller redan sparade kontrollpunkter är heliga:

- vanlig regenerering av panoramat återanvänder dem;
- maskändringar får inte tyst ersätta dem;
- automatisk residualrensning får inte behandla dem som nya maskinpunkter;
- endast ett uttryckligt kommando för nya automatiska punkter ersätter nätet.

Nya punktförslag för ett synligt bildpar läggs till inkrementellt och får inte
radera andra par.

## Automatisk reparationsklassning

En automatisk reparation kräver evidens för att bilden inte delar riggens
gemensamma kameracentrum. Den strikta vägen använder en välansluten CP-graf,
mäter rotationsresidualer och gör en verklig leave-one-out-lösning. Kandidaten
accepteras bara när riggen utan bilden blir materiellt bättre.

Några smala reservfall finns för de verifierade panoramafamiljerna:

- en fördröjd slutbild nära en pol kan stödja ett redan tydligt geometriskt
  avvikarfall;
- en helt isolerad, handhållen polbild kan provas lokalt när den kvarvarande
  fisheye-riggen redan är sammanhängande och redundant;
- dessa inferenser gäller bara färska automatiska punkter, aldrig ett manuellt
  auktoritativt nät.

Tid, filordning och pitch är stödbevis. Inget av dem får ensamt flytta en bild
ur positioneringen. Vid osäkerhet stannar bilden i riggen och ett eventuellt fel
ska förklaras för användaren.

## Registrering av reparationer

Riggen löses och fryses innan en reparation placeras. Reparationsbilden får
aldrig dra i panoramats kameraposer.

- Tillräckligt bred och balanserad CP-support kan ge en sfärisk registrering.
- Tvåbildssupport med handhållen parallax kan i stället välja lokal plan
  registrering mot det redan renderade panoramat.
- En isolerad automatisk polbild får använda den lokala reservvägen endast när
  den frysta riggen uppfyller de konservativa villkoren ovan.

Masken och blandningen bestämmer vilket innehåll som används; de ändrar inte
den frysta geometrin.

## Sömstrategi

Enblend kör alltid
`--primary-seam-generator=nearest-feature-transform`. Valet är generellt för
alla objektiv, bildantal och masker. Det ger en enda förutsägbar sömväg och ska
inte blandas ihop med CP-kvalitet eller poseoptimering.

## Regression

Det finns två kompletterande nivåer:

- `swift test` kontrollerar deterministiska regler, lagring, matematik och
  utvalda motorintegrationer.
- Panorama A–R granskas manuellt i den sfäriska appvyn för sömmar, riktning,
  lokala strukturer, poler och visuell kontinuitet.

En grön automatisk testsvit betyder inte att A–R har visuell regressionstestats.
När geometri eller reparationsklassning ändras ska relevanta problemfall köras
först och därefter hela det manuella korpuset innan ändringen betraktas som ny
produktbaslinje.

## Regler för framtida ändringar

- Föredra en generell geometrisk förklaring framför panoramaspecifika namn eller
  filnamn.
- Lägg bara till ett reservfall när det har tydliga positiva och negativa grindar.
- Behåll manuella punkter och användarens uttryckliga roller.
- Mät geometri före blending; bedöm slutbilden separat.
- Dokumentera om ett resultat är automatiskt, manuellt eller AI-retuscherat.
- Låt AI-reparationer vara icke-destruktiva overlays ovanpå ett fryst panorama.
