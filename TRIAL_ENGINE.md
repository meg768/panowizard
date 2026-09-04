# Trial-motorn

## Integrationsform

Trial är portad till C++17 och OpenCV bakom en liten C-brygga som kan anropas
direkt från Swift. Det håller UI, projektformat och maskeditor fria från
algoritmdetaljer och gör att appaketet saknar separat runtime eller externa
processer.

Swift-adaptern gör tre saker:

1. skriver varje orienterad originalbild till en temporär TIFF med dess
   exkluderingsmask i alpha;
2. skickar skyddsmasker, cacheadress, progress och avbrytningssignal till C++;
3. behåller den färdiga JPEG-bilden för viewer, projektsparning och export.

## Geometrikedja

C++-motorn följer referensimplementationens kedja: gemensam optisk bildcirkel,
SIFT, ömsesidiga ratio-matchningar, rotations-RANSAC, gemensam robust optimering
av kamerarotationer och linsmodell, horisontutjämning och sfärisk remapping.

Linsmodellen innehåller radiella koefficienter, optiskt centrum och aspektterm.
Alla värden uppskattas internt från bilderna. EXIF kan behållas som metadata men
behövs inte som användarinställning.

Panoramaringen löses först och är ensam om att bestämma linsmodell, horisont och
ringkamerornas rotationer. En bild som är markerad som reparationsbild, eller en
tydligt nedåtriktad automatisk avvikare från en ring med minst tre horisontella
vyer, utesluts ur denna optimering. Den registreras därefter robust mot den
färdiga ringen och används bara som `fillOnly`. Bildtypen kan vid behov väljas
som Automatisk, Panoramaring eller Reparationsbild i källbildens snabbmeny.

## Sömmar och radiometri

Efter remapping beräknas överlappsgain, gemensam radiometrisk korrigering,
redundansundertryckning, GraphCut-etiketter och periodisk innehållsanpassad
feathering. Endast giltiga, omaskerade originalpixlar deltar. Skyddade pixlar
ges prioritet vid sömval men skapar inget nytt innehåll.

Den radiella korrigeringen beräknas bara från icke klippta överlappspixlar och
tonas därför ned när en källpixel närmar sig vitt. Den globala
per-bild-korrigeringen behålls så att en utfrätt bild fortfarande kan tonas ned
mot sina grannar. Vid bred blandning får en överlappande källa som har kvar
information i minst en färgkanal högre vikt än en helt utfrätt källa.

Alignment-cache nycklas av motorversion, källa, filstorlek, ändringstid och röd
mask. Ändrad geometri eller exkluderingsmask ger därför en ny lösning.

## Kända begränsningar

- Källbilderna måste ha samma pixelmått.
- Minst två överlappande aktiverade bilder krävs.
- Radiometrin kan ge för kraftigt cyan/grönt stick i vissa bildserier. Det är en
  känd färgbegränsning och påverkar inte den geometriska integrationen.
- Motorn fyller inte hål när inget originalpixelunderlag finns; coverage och
  antal hålpixlar rapporteras till appmodellen.

## Regressionsankare: Panorama C

Den 2 september 2026 godkändes Panorama C visuellt som det hittills starkaste
resultatet. Testet kördes endast från källorna i
`/Users/magnus/Desktop/Panorama/C/panowizard.pw` och gav 4096 × 2048 pixlar,
100 procent täckning, noll hål och träff i alignment-cachen.

Godkännandekriterierna är konkreta och ska bevaras vid framtida motorändringar:

- skidstavarna är raka;
- liftens linor är raka;
- fotografen i förgrunden är hel och saknar synliga sömmar;
- skidåkarna bakom fotografen är hela;
- ingen halo eller dubbelkontur syns runt örat eller hårkanten.

Det godkända resultatets SHA-256 är
`aee15da786b61d306955efa8d5b8679671b755bd876d3ed09e0f4912a147ba05`.
Resultatet bygger på en smal detalj-feathering om en pixel vid 4096 pixlars
panoramabredd. Den bredare radiometriska blandningen används fortfarande i
släta områden men tonas bort runt struktur. Att öka detalj-featheringen till
åtta pixlar återskapar halon bakom örat och är en känd regression.

Efter högdagerskyddet för Panorama D den 3 september 2026 kördes Panorama C
igen med samma projekt och alignment-cache. Resultatet var fortsatt 4096 ×
2048, 100 procent täckning och noll hål. En direkt beskärningsjämförelse mot den
godkända baslinjen bekräftade oförändrad öron-/hårkant och hela personer.

## Regression: Panorama D

Panorama D innehåller överlappande himmelpartier där samtliga RGB-kanaler är
utfrätta i en källa. Den tidigare radiella modellen extrapolerade trots detta
positiv förstärkning till källans bildkant och gjorde fisheye-fotavtrycket
synligt som en vit vertikal pelare.

Den avgränsade regressionen från
`/Users/magnus/Desktop/Panorama/D/panowizard.pw` visade även att den femte,
handhållna nadirbilden redan var sparad som `fillOnly`, men tidigare ändå hade
deltagit i gemensam geometri. Efter rollseparationen bestäms geometrin endast av
de fyra ringbilderna. Reparationsbilden registreras separat och får bara fylla
otäckt eller maskerat underlag. Resultatet blev 4096 × 2048, 100 procent
täckning och noll hål utan den hårda vita pelaren.

## Regression: Panorama S

Panorama S har fyra ringbilder, en zenitbild och två automatiskt identifierade
nadirkällor. Nadirkällorna innehåller panoramahuvudet och ska därför fortsätta
vara `fillOnly`; att låta dem konkurrera med ringbilderna tar bort tonstegen men
återinför stativarmarna i resultatet.

De synliga lodräta skarvarna i badrumsgolvet kom i stället från två
GraphCut-gränser mellan perifera ringbilder. Geometrin var korrekt, men en
källas lågfrekeventa ton låg ungefär 6–16 nivåer från sina grannar. Motorn
använder därför en nadirbegränsad tvåskaleblandning: den smala GraphCut-bilden
behåller kakelfogar och andra detaljer, medan endast den långsamma tonnivån
featheras över den befintliga sömmen. Ovanför nadirzonen är den tidigare
blendningen pixelidentisk.

Den avgränsade S-regressionen från
`/Users/magnus/Desktop/Panorama/S/panowizard.pw` gav 4096 × 2048, 100 procent
täckning, noll hål och träff i alignment-cachen. Resultatets SHA-256 är
`2a6976180d82e41078141258ef15c6b1ca53c74de6b07065d39b82b453be5630`.

## Regression: Panorama K

Panorama K har åtta ringbilder, två nadirbilder och en zenitbild, samtliga
tagna från monopod. Den tidigare automatiken behandlade varje nedåtriktad bild
som en ensam handhållen reparationsbild och tog därför bort båda nadirbilderna
ur geometrioptimeringen. Ringen tappade deras starka kontrollpunktsstöd och
komprimerades omkring 40 grader, med stora dubblerade byggnader som följd.

När minst två automatiska nadirbilder känns igen behålls de nu i den gemensamma
geometrin. I kompositionen är de fortfarande nadirbegränsade och konkurrerar
inte med ringbilderna. Den enda körda regressionen var K-projektet från
`/Users/magnus/Desktop/Panorama/K/panowizard.pw`: 16 276 observationer,
0,128 grader medianfel, 4096 × 2048, 100 procent täckning och noll hål.
Resultatets SHA-256 är
`dd692f96f81bff04edc7f02564bebc291ff603e299e1f67f1507c61bd0bbe2e6`.
