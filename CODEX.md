# PanoWizard – projektkontext

## Viktig omstartspunkt

Omstarten är nu genomförd. Prototypen är arkiverad i Git på `main` i commit
`f6a6445` (`Archive PanoWizard prototype before clean restart`). Den rena
arbetsgrenen heter `codex/restart`. All projektimplementation, alla tester,
byggskript, paketdefinitionen och det byggda app-paketet har tagits bort från
arbetsgrenen. En extra återställningsbar kopia ligger i macOS Papperskorg under
`panowizard-prototype-20260724-2338`.

De ignorerade mapparna `Vendor/` och `.vendor-cache/` har behållits. De
innehåller externa Hugin/OpenCV-beroenden och är inte en del av den gamla
PanoWizard-implementationen. Börja inte skriva ny appkod direkt. Första nya
artefakten ska vara den minsta möjliga, reproducerbara Hugin-körningen för
Lundalogiks bilder 1–4 enligt ordningen nedan.

På uttrycklig begäran har dokumentredigeraren därefter återinförts från det
tidigare arbetssättet, men utan den gamla stitchimplementationen. Appen är åter
en native, dokumentbaserad SwiftUI-app med vänster sidopanel och arbetsyta,
kan skapa/öppna/spara `.pw`-paket samt importera, visa och maskera källbilder.
`StitchingUnavailableEngine` är en avsiktlig och tydlig protokollgräns: den
arkiverade Hugin/OpenCV/cache/nadir-koden är inte länkad till appen. Nästa
stitchmotor ska utvecklas och verifieras separat innan den kopplas in där.

Den nuvarande implementationen har blivit för komplex. Arbetet har blandat
grundstitchning, riggcache, bildriktningar, masker, utfyllnadsbilder, lokal
nadirregistrering, blending och UI-förändringar innan den enklaste
stitchkedjan varit reproducerbart stabil. Det har lett till loopar där ett fel
har dolts eller ersatts av ett annat. Flera resultat har dessutom bedömts som
korrekta utan tillräcklig visuell verifiering.

Nästa arbetspass ska därför börja enklare. Rädda samma repo och dess historik,
men betrakta den nuvarande implementationen som ett arkiverat experiment.
Återanvänd ingen stitch-, cache-, mask- eller nadirkod utan ett uttryckligt och
visuellt verifierat skäl.

Obligatorisk ordning för omstarten:

1. Arkivera nuvarande tillstånd återställningsbart i Git.
2. Skapa en ren arbetsgren i samma repo.
3. Börja utan app-UI: endast en minimal Hugin-kedja och Lundalogiks bilder 1–4.
4. Använd fast Sigma 8 mm DX-profil och fasta startvinklar 0/90/180/270.
5. Spara varje PTO-mellansteg och den renderade bilden för inspektion.
6. Gå inte vidare förrän samma fyra bilder ger samma visuellt godkända
   360-gradersband vid upprepade körningar.
7. Lägg därefter till bild 5 som zenit och verifiera igen.
8. Lägg först sedan tillbaka ett minimalt SwiftUI-skal.
9. Projektformat och vanliga bildmasker kommer efter stabil stitchning.
10. Nadir/utfyllnad är ett separat, sista framtida steg.

Ingen riggcache, ingen automatisk specialbehandling och ingen
reparationspipeline får införas under grundtestet. Ett passerande enhetstest
eller en lyckad processretur räcker inte: bildresultatet måste alltid granskas
visuellt innan steget får kallas korrekt.

## Produktmål

PanoWizard återupplivar en macOS-applikation från omkring år 2000. Den var ett
grafiskt gränssnitt för Panorama Tools med målet att göra
panoramasammanfogning enkel.

Målet är inte att konkurrera med PTGui. Målet är att skapa den mest eleganta
native panoramaappen för macOS: enkel, vacker och snabb, mer Pixelmator än
Photoshop och med känslan av en förstapartsapp från Apple.

## Plattform och teknik

- Native macOS, endast Apple Silicon
- macOS 26 eller senare
- Swift 6 och SwiftUI
- Modern Swift-concurrency med `async`/`await`
- AppKit bara när det är absolut nödvändigt
- Följ Apple Human Interface Guidelines
- MVVM med små, modulära och testbara komponenter
- Dependency injection; undvik singletons och överarkitektur

Projektmappen heter `panowizard` med gemener. Produkt- och appnamnet är
`PanoWizard`.

## Version 1

Användaren drar in en mapp eller en uppsättning bilder. Appen ska automatiskt:

1. läsa EXIF,
2. sortera bilderna,
3. gruppera dem i panoramaset,
4. identifiera objektivtyp när det går,
5. sammanfoga panoramat,
6. visa en interaktiv förhandsvisning.

Användaren trycker sedan på Export. Inga guider eller komplicerade inställningar
behövs. Ett panorama motsvarar ett dokumentfönster och sparas som ett
`.pw`-filpaket. Formatet är medvetet inte bakåtkompatibelt med den tidigare
prototypens enkla JSON-fil. Paketet innehåller `project.json`, PNG-masker och
det senast sammanfogade panoramat; originalbilderna refereras externt.
Exportformaten i version 1 är JPEG och TIFF.

Gränssnittet består av en sidopanel med projektets källbilder och det
sammanfogade panoramat, en central interaktiv förhandsvisning, status och
förlopp längst ned samt en sparsam verktygsrad för Import, Stitch och Export.

## Nuvarande implementation

- OpenCV 5 används för vanliga, rectilineära panoraman.
- OpenCV gav otillräckligt stöd för kompletta 360×180-graders panoraman.
- Fisheye- och sannolikt fullsfäriska set går därför genom en paketerad
  Hugin-pipeline:
  `pto_gen → cpfind → cpclean → autooptimiser → pano_modify → nona → enblend`.
- Hugins fotometriska `autooptimiser -m` används inte för redan framkallade
  TIFF/JPEG-källor. Den kan annars skapa extrema vitbalans- och
  responskurvevärden. Enblend sköter övergångarna mellan oförändrade färger.
- Den fullsfäriska utmatningen är 4000×2000 JPEG med 360×180 graders
  equirektangulär projektion.
- Den interaktiva sfäriska förhandsvisningen använder Metal.
- Hugin- och OpenCV-beroenden bäddas in i det byggda app-paketet.

## Manuell källbildsmaskning

Det finns ingen automatisk nadirbehandling eller automatisk objektborttagning.
Användaren väljer en källbild i sidopanelen och målar en röd pixelmask över
sådant som inte ska användas, exempelvis stativ, fotograf eller dubbletter av
en person i rörelse. Verktygsraden innehåller maskera, återställ,
penselstorlek, ångra samt zoom. `⌘+` och `⌘−` zoomar källbilden mellan
anpassad storlek och 800 procent; en inzoomad bild kan rullas i båda
riktningarna. En röd penselindikator i sidopanelen visar vilka bilder som har
mask.

Originalbilderna används oförändrade för kontrollpunkter och geometrisk/
fotometrisk optimering. Inför Nona-renderingen skapar PanoWizard temporära
TIFF-källor där PNG-masken har överförts till alfakanalen och byter endast
filsökvägarna i den färdigoptimerade PTO-filen. Nona transformerar bild och
alfa tillsammans; Enblend väljer omaskerade pixlar från andra
överlappande bilder. Om ingen annan bild täcker ett maskerat område kan ett
hål uppstå — PanoWizard skapar inte artificiella pixlar.

`.pw`-paketet har denna struktur:

```text
Projekt.pw/
  project.json
  masks/
    <bildens UUID>.png
  panorama/
    result.jpg
```

Projektformatets aktuella versionsnummer är 5. Äldre enkla JSON-baserade
`.pw`-filer läses inte.

`project.json` kan innehålla `cachedRigImageLines`, en PTO-bildrad per
positioneringsbild. Efter en lyckad stitch sparas riggens geometri där. Vid
senare maskändringar återläggs dessa rader före kontrollpunktssökningen.
Cacheposterna har även en `cachedRigSignature` som omfattar bildordning,
riktningar, roller och stitchinställningar. Ändrad riktning, roll, bildlista,
objektivprofil, projektion eller FOV tömmer cachen. Poster utan matchande
signatur ignoreras; en felaktig rigg får aldrig återanvändas efter en sådan
ändring.

## Testmaterial och känt nuläge

Exempelbilderna finns i `/Users/magnus/Desktop/Panorama`. De elva bilderna är
ett fullsfäriskt fisheye-set från Lissabon.

Den nuvarande Hugin-lösningen ger ett komplett och i huvudsak väljusterat
360×180-panorama med jämn exponering. Den manuella maskkedjan har körts hela
vägen på de elva Lissabonbilderna:
PNG-mask → alfamaskerad TIFF → Nona → Enblend → 4000×2000 JPEG.

Ett andra testset finns i `/Users/magnus/Desktop/Lundalogik`. Det består av
sex stående TIFF-bilder tagna med Sigma 8 mm cirkulär fisheye på DX-sensor:
fyra bilder runt horisonten, zenit och en handhållen nadirbild. PanoWizard känner igen en
fisheye-bild från mörka optiska hörn när objektivmetadata saknas. PanoWizard
antar aldrig en layout från bildantal eller listindex. Varje bild har en
projektsparad riktning: `horizontal`, `zenith` eller `nadir`. Riktningen sätter
pitch-startvärdet. Horisontella positioneringsbilder fördelas jämnt runt 360°
i projektordning och `cpfind --prealigned` söker kontrollpunkter från dessa
stabila startlägen. Kontrollpunktssökningen använder en tråd och
`--ransacmode=rpy`; automatisk homografimodell gav ibland en helt annan,
felaktig lösning för samma sparade projekt. Hugin finjusterar därefter
geometrin. Alla bilder har
dessutom en oberoende, explicit roll:
`alignment` (Ingår i positionering, standard) eller
`fillOnly` (Endast utfyllnad). Användaren väljer rollen från verktygsraden
eller bildradens kontextmeny. En `fillOnly`-bild ingår aldrig i Hugins
`pto_gen`, kontrollpunktssökning, optimering, Nona-warpning eller
Enblend-körning. Hugin skapar först ett fryst panorama enbart från
`alignment`-bilderna. Därefter rektifieras en handhållen nadirbild och en lokal
nadirvy ur det färdiga panoramat. OpenCV registrerar hela reparationsbilden mot
den lokala vyn med en robust transform begränsad till rotation, skala och
förskjutning. Först vid kompositeringen används användarens mask. För
Lundalogik markerar användaren själv bild 6 som Endast utfyllnad. Ingen mapp,
något filnamn eller listindex specialbehandlas.

Hugins PTO-tal måste skrivas med lokalsäkra ASCII-tecken. Swift
`FloatingPointFormatStyle` skrev tidigare negativa startvinklar med Unicode-
minustecknet `−`; Hugin 2019 tolkade då `−90` som `0`. Det gjorde
kontrollpunktssökningen instabil och fick en ny stitch efter maskändring att se
ut som om masken hade påverkat geometrin. Startvinklar skrivs nu med
`String(Double)`, och ett regressionstest kräver ASCII `-`. Lundalogiks sparade
projekt har verifierats hela vägen med sina verkliga fem PNG-masker: all
positionering använder originalbilderna, medan maskerna tillämpas först på
Nona-lagren.

Hugins arbetskatalog använder projektets UUID men töms nu alltid före varje
stitch. Tidigare kunde ett Nona-lager från en borttagen bild ligga kvar och
felaktigt följa med i nästa Enblend-körning.
Lundalogiks sparade fem-bildsprojekt producerar exakt fem färska lager. Eftersom
de fyra riggbildernas stativområden är maskerade och nadirbilden har tagits bort
finns det avsiktligt ingen täckning längst ned; resultatet får därför ett äkta
transparent/svart nadirhål tills en utfyllnadsbild åter läggs till.

Ett tidigare Swift-byggfel orsakades av en gammal modulcache som innehöll både
den gamla sökvägen `PanoWizard` och den nya `panowizard`. `swift package clean`
löste problemet. Källkoden byggde därefter och alla tre befintliga tester
passerade.

## Arbetsrutin

- Gör små, kompletta inkrement som alltid ska kompilera.
- Skriv kompletta filer, inga platshållare.
- Förklara arkitekturbeslut kort.
- När det är relevant efter en ändring: kör testerna, bygg app-paketet med
  `./Scripts/build-app.sh` och starta `build/PanoWizard.app` automatiskt.
- Bevara användarens ändringar och gör inga destruktiva Git-operationer.
- Projektet saknade fortfarande sin första Git-commit när denna fil skapades;
  hela källträdet var då oversionshanterat.
