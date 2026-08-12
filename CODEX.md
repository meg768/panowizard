# PanoWizard – aktuell projektkontext

## Sparat slutläge 2026-08-12 – kompakt automatisk nadirreparation i H

Detta checkpoint innehåller dagens import-, GUI-, test- och nadirändringar.
Huvudmålet är fortsatt att alla Panorama A–H ska kunna genereras automatiskt
utan större skarvar; GUI:t är sekundärt.

Panorama H avslöjade ett särskilt Enblend-fall. Ringpanoramat hade inget
verkligt svart hål vid nadircentrum. PanoWizard tvingade därför korrekt bara
en central reparationskärna med 96 px radie, men lät samtidigt hela den
registrerade nadirbilden vara valbar för Enblend. Enblend valde då en mycket
stor lågkostnadssöm genom de mörka kläderna och reparationspatchen blev för
stor.

I den automatiska grenen utan verkligt täckningshål begränsas nu även det
valbara reparationslagret till en cirkel med 224 px radie runt nadircentrum.
Det lämnar 128 px överlapp utanför den tvingade 96-pixelskärnan men hindrar
sömmen från att vandra genom hela den lokala 1600×1600-vyn. Logiken för ett
verkligt svart hål är oförändrad: hålet plus 160 px överlapp används, så de
tidigare godkända resultaten i bland annat C och D påverkas inte.

H återskapades huvudlöst från originalbilderna med fyra ringbilder, bild 5
som zenitreparation och bild 6 som nadirreparation. Före ändringen omfattade
pixlar med mer än 16 nivåers färgskillnad cirka 294 569 pixlar och nådde 655
px från centrum. Efter ändringen var motsvarande siffror 45 719 pixlar och
170 px, alltså drygt 80 procent mindre bildpåverkan. Användaren provade den
nya versionen och bedömde resultatet som perfekt. Tillfällig diagnostikkod och
diagnostikbilder är borttagna.

Samtliga 53 tester passerar. Releaseappen är ombyggd och ad hoc-signerad i
`/Users/magnus/Documents/GitHub/panowizard/build/PanoWizard.app`. Codex har
inte startat appen eller styrt musen.

Bildmenyn i vänsterpanelen är numera godkänd: varje källbildsrad har en tydlig,
rund och högerjusterad `…`-knapp med hover och en meny för `Ingår i
positionering`, `Zenit · Reparation` och `Nadir · Reparation`. Valet är
borttaget från toolbaren. Den separata `Panorama`-sektionen är också
implementerad med `Inställningar`, `Förhandsvisa` (ögonikon) och `Exportera`.

Produktimporten accepterar endast bildfiler som användaren uttryckligen väljer
eller drar in; mappar genomsöks inte och filväljaren erbjuder inte mappar.
Det huvudlösa A–H-testet listar endast bildfiler direkt i panoramamappens rot.
PTGui-facit ligger konsekvent i respektive `PTGui/`-undermapp och importeras
inte av PanoWizard.

## Aktivt läge 2026-08-11 – konservativ dödkodsrensning

Kod utan produktionsreferenser har tagits bort efter Swift- och C-bryggeaudit:
den övergivna Hugin-analysatorn, äldre dubblettvyer, oanvända
kontrollpunkts-/polregistreringsspår samt deras tre exporterade OpenCV-API:er.
Avsiktliga automatiska reservvägar är kvar. `swift build` och samtliga 52
tester passerar; en ny huvudlös körning av Panorama D passerar hela kedjan
inklusive lokal nadirreparation. Release-appen bygger och dess ad hoc-signatur
är strikt verifierad.

## Aktivt läge 2026-08-11 – ren automatisk polblandning i Panorama C

Panorama C består av åtta Sigma 8-JPEG-bilder: sex ringbilder, en zenit och
en nadir. Ett helt nytt integrationsprojekt skapades från exakt dessa åtta
kamerafiler, utan PTGui-resultat, tidigare `.pw`, masker eller manuella
justeringar. Ringen fick 109 slutliga CP med medianfel 0,60 px, medelfel
0,83 px och maxfel 3,06 px. Den automatiska zenitplaceringen hade 102
matchningar och nadirplaceringen 2 431.

Den gamla lokala Enblend-kedjan gjorde baslagret transparent över nästan hela
polbildens 1600×1600-yta. Därmed tvingades zenit eller nadir ersätta fullt
giltiga ringpixlar långt utanför själva polen. I C gav detta en tydlig rak söm
genom zenitens skidstavar och en diagonal söm genom nadirens snö.

Automatisk polblandning begränsar nu reparationslagret till det sammanhängande
mörka täckningshålet vid den exakta polen plus 160 px överlapp. Gränsen för
JPEG-komprimerade hålpixlar är luma 48; endast den komponent som innehåller
polens centrum används, så andra mörka motivdelar räknas inte som hål. Om
ringen redan täcker själva polen tvingas endast en central cirkel med 96 px
radie in, varefter Enblend får välja en lågkostnadssöm i resten av överlappet.
Så snart användaren gjort en geometrisk poljustering bevaras det tidigare
bredare reparationsbeteendet, så manuellt arbete ändrar inte innebörd.

Den nya rena C-körningen är visuellt ren vid både zenit och nadir i Codex
granskning. Samma automatiska nadirblandning har kontrollerats på de sparade
D- och H-placeringarna utan synliga nya sömmar. C ska ändå inte märkas som en
slutlig PTGui-fullträff förrän Magnus själv har granskat den sfäriska vyn.
Alla 52 tester passerar efter ändringen.

## Sparat slutläge 2026-08-11 – automatisk fullträff i Panorama B

Commit `a5d520c` (`Improve automatic control points and editor workflow`) är
pushad till `origin/codex/restart` och utgör aktuell baseline. Den innehåller
den bredare CP-spridningen, rörelsekonsistensfiltret, GUI-utrensningen och den
dokumenterade CP-strategin. Alla 52 tester passerade före committen.

Panorama B består nu av fem Sigma 8 DX-TIFF-bilder. Både PTGui och PanoWizard
kördes helt från originalbilderna utan manuella kontrollpunkter, masker eller
korrigeringar. PanoWizard skapade 162 CP med medianfel 1,03 px och medelfel
1,27 px. Användarens noggranna visuella jämförelse bedömer resultaten som
identiska; båda väljer dessutom samma skarv på exakt samma ställe. B är därför
den första tydliga automatiska fullträffen och ska betraktas som ett godkänt
regressionsfall. Enstaka högre CP-fel ska inte trimmas bort enbart för att
förbättra statistiken när slutresultatet redan är korrekt.

PanoWizards sparade resultat är fortfarande fast 4000×2000 medan PTGui B är
8602×4301. Det är en separat framtida export-/upplösningsfråga, inte ett fel i
B:s geometri eller skarvning. Den automatiska A–H-testlöparen är uttryckligen
uppskjuten; tills vidare görs kontrollerna manuellt mot alla fyllda mappar.

## Överordnat mål 2026-08-11 – A–H är regressionskorpuset

PanoWizards produktmål är att från endast originalbilder och bildmetadata ge
minst lika bra resultat som PTGui-referensen, utan manuella kontrollpunkter,
masker, rolländringar eller geometriska korrigeringar. Den manuella editorn är
ett diagnostik-/reservverktyg och ingår inte i godkännandeflödet.

`/Users/magnus/Desktop/Panorama/A`–`H` är det permanenta lokala
regressionskorpuset för kluriga panorama: handhållet, monopod eller stativ,
med zenit/nadir tagna med eller utan stativ. Aktuell inventering är A=10,
B=5, C=8, D=5, E=0, F=6, G=13 och H=6 originalbilder. Tomma mappar hoppas
över. Varje kontroll ska börja från originalbilderna; befintliga `.pw`,
PTGui-filer, masker och sparade CP är endast facit/diagnostik och får inte
användas som indata. En algoritmändring måste kontrolleras mot samtliga
icke-tomma mappar och får inte godkännas enbart på lägre RMS eller förbättring
av ett enda panorama. Det fullständiga kontraktet står i
`CONTROL_POINT_STRATEGY.md`.

PTGui-facit är nu isolerat i `PTGui/` under varje icke-tom A–H-mapp. Varje
sådan undermapp innehåller `Panorama.pts` och `Panorama.jpg`; originalbilderna ligger
ensamma kvar i panoramamappens rot. De 53 relativa bildreferenserna i
projekten har ändrats till `../filnamn`, och D:s absoluta utfil pekar på
`D/PTGui/Panorama.jpg`. E är fortfarande tom.

## Aktiv kontext 2026-08-10 – bredare CP-spridning för Nikkor

Panorama A visade att kontrollpunkterna i bland annat bildpar 2–3 blev
onödigt klustrade. Grundfelet var inte främst sluturvalet: Nikkor 10,5 mm
verifierades som om överlappet följde en plan homografi. För en roterad
full-frame-fisheye beskriver homografin bara en lokal yta och lämnade därför
nästan enbart fasad-/statypunkter till spridningssteget.

OpenCV-bryggan får nu den valda objektivprofilen explicit. Nikkor- och
Sigma-profilerna verifierar råa SIFT-matchningar med varsin kalibrerad
fiskeögeprojektion och en gemensam 3D-rotation; plan homografi är kvar för
rektlinjära/egna profiler. Samma modell används av helprojektsgenerering och
`Föreslå för aktuellt bildpar`.

Det spatiala sluturvalet använder dessutom ett robust 5–95-percentilområde
för det verkliga överlappet och ett 5×5-rutnät relativt detta område, i
stället för ett grovt rutnät över hela källbilden. Det behåller högst 25
punkter per genererat par men fördelar dem över den yta som faktiskt kan
matchas. Ett hårt minimiavstånd på 5 procent av bildens kortsida gäller i
båda källbilderna. För D70-materialets 2000×3008-bilder motsvarar det 100 px.
Generatorn fyller aldrig upp till 25 med närliggande punkter; ett svagare
par får i stället färre, ärligt separerade punkter.

På A:s bildpar 2–3 ökade den geometriskt verifierade kandidatmängden från
240 till 1 026 och rutnätstäckningen från 16,7 till 33,3 procent, fortfarande
med 25 valda råpunkter. Efter hela Hugin-kedjan återstod 24 punkter med
1,45 px medelfel och 3,45 px maxfel. Deras vertikala spann i bild 2 ökade
från cirka 1 079 till 1 477 pixlar. Ett fullständigt, visuellt granskat
Nikkor-test av alla tio bilder i `/Users/magnus/Desktop/Panorama/A` skapade
ett sammanhängande 360×180-resultat och passerade integrationstestet.
I bildpar 4–5 hade den föregående körningen 14 punktpar där åtminstone ena
bildens avstånd var under 100 px, med 73/77 px som minsta avstånd. Efter den
hårda regeln återstår 24 optimerade punkter, minsta avstånd är 100,4/100,1 px
och antalet överträdelser är noll. Samma helkörning av A passerar fortfarande.

Generatorn har nu även en enkel rörelsekonsistensregel utan semantisk AI.
RANSAC:s tidigare fasta 1,5°-gräns används bara för att hitta den dominerande
kamerarotationen. Median och MAD för dessa residualer ger därefter en robust
gräns mellan 0,25° och 0,75°; rotationen anpassas om och endast kandidater
inom denna bildspecifika gräns går vidare till spridningsurvalet. Därmed
sorteras tydlig vindrörelse och parallax bort som geometriska avvikelser,
utan regler för människor, palmblad eller parasoller. Strategin, felbeteendet
och gränserna är dokumenterade i `CONTROL_POINT_STRATEGY.md`.

## Aktiv kontext 2026-08-10 – CP-kommandon i toolbar och meny

Den stora lokala knappraden i kontrollpunktseditorn är borttagen. Editorn
visar nu bara en kompakt instruktionsrad ovanför bilderna; Lägg till,
Föreslå, Radera och Optimera ligger som kontextuella verktyg i fönstrets
toolbar. Föreslå och Radera är menyer så att par-, projekt- och
omgenereringsnivåerna är synliga utan en extra valdialog. Massradering och
full omgenerering har fortfarande bekräftelse eftersom de kan förstöra
manuellt arbete.

En ny appmeny `Kontrollpunkter` exponerar samma funktioner. Kortkommandon är
⌥A för Lägg till/Avbryt ny punkt, ⌥F för förslag i aktuellt bildpar,
⇧⌥F för hela projektet, ⌥O för Optimera och Delete för markerad punkt.
Destruktiv massradering och full omgenerering har medvetet inga kortkommandon.
Menykommandona använder det aktiva dokumentets fokuserade editor och är
inaktiva utanför kontrollpunktsvyn.

Sidopanelens separata Panorama-sektion är också borttagen; panelen är nu
reserverad för källbilderna som faktiskt behöver ständig överblick. En ny
appmeny `Panorama` innehåller Inställningar (⌥,), Förhandsvisning (⌥P) och
Exportera (⌥E). Förhandsvisning och export är inaktiva tills ett renderat
panorama finns. Menyn innehåller även Skapa panorama (⌥R) och Börja om
automatiskt; det destruktiva omstartsflödet saknar medvetet kortkommando.
De två globala renderingsknapparna döljs när CP-editorn är aktiv så att dess
toolbar bara visar de kontextuella CP-verktygen. Samtliga menykommandon riktas
till det aktiva dokumentet.

Ett försök med en infällbar CP-inspektör till höger togs bort. SwiftUI gör
inte den högra inspektören visuellt och strukturellt identisk med den vänstra
NavigationSplitView-panelen, vilket var det önskade beteendet. CP-fellistan
ligger tills vidare kvar som en enkel fast kolumn i editorn. Toolbaren,
menyerna och kortkommandona påverkas inte av detta beslut.

## Aktiv kontext 2026-08-10 – EXIF styr objektivprofilen

Det nya verkliga provet `/Users/magnus/Desktop/Panorama/A` består av tio
stående JPEG-bilder från Nikon D70 med AF DX Fisheye-Nikkor 10,5 mm. Den
automatiska kontrollpunktsgenereringen gav 411 brett spridda punkter och ett
mycket bra panorama, enligt användaren möjligen bättre än PTGui i detta fall.

Projektet hade dock felaktigt sparats med profilen Sigma 8 mm. JPEG-filerna
innehåller det fullständiga objektivnamnet i ImageIO:s auxiliary EXIF-del,
medan PanoWizard bara läste den vanliga EXIF-delen och därför föll tillbaka
till Sigma. Metadataläsaren hämtar nu även
`kCGImagePropertyExifAuxLensModel` och föredrar fysisk brännvidd framför
35-mm-ekvivalenten. När bildmetadata entydigt identifierar en profil skriver
den alltid över en felaktigt sparad eller manuellt vald profil. Det gamla
riggcachet rensas men befintliga kontrollpunkter bevaras. Äldre A-projekt utan
sparat objektivnamn känns igen som Nikon genom brännvidden 10,5 mm.

Inställningsvyn visar en EXIF-styrd profil som låst metadata i stället för ett
manuellt val. Manuell profil finns kvar endast när bilderna saknar tillräcklig
metadata. Idén att generellt prioritera kontrollpunkter nära kameran är
avskriven: nära motiv ger mer parallax och ska inte tillåtas dominera den
globala geometrin. Den nuvarande breda rumsliga fördelningen behålls.

Efter ändringen passerar 52 tester och `git diff --check` är ren. Ny signerad
app finns i `build/PanoWizard.app`.

## Aktiv kontext 2026-08-09 – breda kontrollpunkter för fyrbildsring

Panorama H:s fyrbildsring isolerade ett konkret fel i CP-generatorn.
Autogenererade `B.pw` hade 54 punkter med cirka 0,12 px medelfel, men nästan
alla låg i ett smalt horisontellt band. PTGui-projektet `Panorama.pts` hade 86
punkter över nästan hela fisheyeytan och gav rena skarvar. Ett separat
kontrollprov finns i `H/C.pw`: PTGuis punkter kördes genom PanoWizards egen
linsoptimering och rendering och bekräftade att felet låg i punktgeneratorn,
inte i renderaren.

Fyrbilders Sigma-vägen använder nu kalibrerade fisheye-strålar och robust
3D-rotationsanpassning i stället för en plan homografi. Det är rätt modell för
stativmaterial och behåller matchningar mot både zenit och nadir. Urvalet
balanserar varje bildände separat; det gamla medelvärdet av två motstående
bildkoordinater koncentrerade falskt punkterna till mitten. En ny spärr
underkänner fyrbildsringar där någon ringskarv har färre än tio punkter eller
mindre än 20 procent separat 6×4-ruttäckning.

Den nya rena H-körningen finns i `H/D.pw`. Generatorn valde 87 punkter före
Hugins robusta rensning och sparade 79 slutpunkter, jämfört med PTGuis 86.
De slutliga punkterna når ungefär y=600–3384; B låg huvudsakligen kring
y=1750–2892. Medelfelet är cirka 0,74 px, maxfelet cirka 4,77 px och den
renderade ringen är visuellt i nivå med PTGui-kontrollprovet.

PTGuis uppgift 174,18° och PanoWizards visade 165,38° är inte direkt
jämförbara. Sigma-optimeringen använder i verkligheten cirka 113,4° över den
stående TIFF-bildens korta sida och optimerar därefter FOV, a/b/c och d/e;
PTGui redovisar den logiska långa bildaxeln med sin generella fisheye-modell.
Det visade 165,38° är ett matchningspreset och bör senare göras tydligare i UI.

Efter ändringen passerar 40 tester och `git diff --check` är ren. Ny
ad hoc-signerad app finns i `build/PanoWizard.app`; Finder/provenance-xattrs
rensades och den slutliga strikta signaturverifieringen passerade.

## Aktiv kontext 2026-08-08 – Panorama H och skarvar

Aktuellt verkligt test är `/Users/magnus/Desktop/Panorama/H`. Referensen
`Panorama.pts` från PTGui 13.9 ger enligt användaren ett helt perfekt panorama.
PanoWizard-projektet är `A.pw`; det har inte skrivits över under analysen.

PTGui-referensen använder sex bilder: de fyra ringbilderna `14.46.16`–`.42`,
den verkliga zenitbilden `14.47.04` samt den kompletterande, uppåtriktade
`14.53.38`. PTGui placerar den sistnämnda ungefär vid yaw 78°, pitch +11°;
den är alltså inte en femte jämnt fördelad ringriktning. PTGui-projektet har
231 kontrollpunkter totalt, varav 136 mellan de fem bilder som PanoWizard för
närvarande behandlar som ringbilder.

`A.pw` har åtta importerade bilder men bara fem aktiva: fyra vanliga
ringbilder plus `14.53.38`. Zenit och båda nadirbilderna är avstängda. A har
49 ringkontrollpunkter med medelfel cirka 2,29 px, p90 cirka 5,46 px och max
cirka 7,73 px. Den stora svarta öppningen upptill är därför väntad och inte
en Enblend-skarv: zenitbilden är avstängd.

Diagnosen isolerades med flera reproducerbara prov:

- PanoWizard hittar trots den ovanliga femte bilden nästan exakt PTGuis
  yaw/pitch/roll, så grundfelet är inte primärt kamerans slutpose.
- Samma PanoWizard/Hugin/Enblend-kedja blir renare när den diagnostiskt får
  PTGuis 136 ringpunkter. PTGui-punkterna användes endast för att isolera
  orsaken och har inte sparats i A eller i produktkoden.
- Den gamla automatiska OpenCV-selekteringen behöll bara 5–17 punkter per
  användbart överlapp, 78 totalt, och koncentrerade dem i texturrika fläckar.
  Det gav för svag rumslig låsning av distortion och optiskt centrum.
- `Sources/OpenCVBridge/OpenCVBridge.cpp` använder nu den befintliga
  rutbalanserade selekteringen även för ringar med fler än fyra bilder.
  H genererar därefter 105 egna punkter utan PTGui-data och behåller rättvänd,
  rimlig geometri. Ett försök att höja minimiantalet ytterligare till 20 gav
  en numeriskt giltig men upp-och-ned-vänd lösning; gränsen 15–25 ska därför
  ligga kvar tills plausibilitetskontrollen kan avvisa globala 180°-lösningar.
- Enblend `--fine-mask` provades men gav tydliga hårda cirkelskarvar och är
  åter borttaget. Coarse multibandmask är bättre för detta handhållna material.

Zenit är ännu inte färdig. Om `14.47.04` aktiveras som vanligt
positioneringslager fyller den hålet, men Enblend kan lägga sömmen genom
byggnaden eftersom bilden innehåller stor parallax. A har den i rollen
Reparation med en kraftig exkluderingsmask, men den är avstängd. Nästa steg är
att först bedöma den nya 105-punktsringen i en kopia av A via
`Börja om automatiskt`, därefter aktivera och verifiera zenitreparationen
separat. `Skapa panorama` på befintliga A återanvänder de gamla 49 punkterna
och testar alltså inte fixen.

Efter ändringen passerar `swift test` med 38 tester och `git diff --check` är
ren. Ny ad hoc-signerad app finns i
`/Users/magnus/Documents/GitHub/panowizard/build/PanoWizard.app`. Byggscriptet
passerade sin signaturkontroll; eftersom repot ligger under Documents kan
File Provider senare återlägga Finder/provenance-xattr, så appen signerades
och verifierades även en sista gång efter xattr-rensning.

## Aktiv kontext 2026-08-08 – editorer, masker och polkontrollpunkter

Arbetskopian är fortsatt avsiktligt smutsig på `codex/restart`; återställ inga
befintliga ändringar. Senast byggda signerade app finns i
`build/PanoWizard.app`. Testsviten passerar med 38 tester och
`git diff --check` är ren.

### Gemensamma musgester

CP-editorn och maskeditorn ska följa samma Mac-mönster:

- två fingrar panorerar bilden horisontellt och vertikalt,
- Shift + två fingrar zoomar kring pekaren,
- fysisk fingerriktning normaliseras mot macOS-inställningen Naturlig
  rullning: två fingrar ned zoomar in och två fingrar upp zoomar ut,
- pinch-zoom finns kvar.

Maskeditorns särskilda hand-/panläge är borttaget. I verktygsfältet finns bara
pensel och fylld rektangel; cirkelverktyget är borttaget från gränssnittet.
Penseln är alltid 48 skärmpunkter bred. Zoom ändrar därför hur många
källbildspixlar den täcker: inzoomning ger finare målning och utzoomning
grövre målning. Reglaget för penselstorlek är borttaget.

### Masker och lagerprioritet

Pågående ocommittat arbete lägger till en grön skyddsmask utöver röd
exkluderingsmask och orange CP-mask. Skyddade områden projiceras per lager och
ska prioriteras framför konkurrerande lager vid Enblend. Projektpaketet sparar
gröna masker i `protected-masks`. Den nya tjänsten
`ProjectedLayerMaskService.swift` är ännu ospårad i Git.

### Kontrollpunkter för zenit, nadir och reparationer

Senaste produktbeslutet ersätter den äldre regeln att pol-/reparationsbilder
inte får ha CP. Följande gäller nu:

- horisontell positioneringsbild ↔ positionerande zenit/nadir får dela CP,
- horisontell positioneringsbild ↔ zenit/nadir med rollen Reparation får dela
  CP,
- pol ↔ pol tillåts inte,
- en horisontell reparationsbild tillåts inte,
- lokala automatiska punktförslag fungerar för tillåtna polpar,
- projektets automatiska ringgenerering arbetar fortfarande enbart på de
  horisontella positioneringsbilderna.

Stitchningen löser och fryser först den horisontella ringen. CP mot en
positionerande polbild optimerar därefter endast polbildens yaw/pitch/roll och
får aldrig flytta ringen. För en bild med rollen Reparation används minst fyra
CP mot ringen för sfärisk Hugin-placering av reparationslagret; om tillräckliga
CP saknas används den tidigare OpenCV-registreringen som reserv. Detta behöver
fortfarande verifieras visuellt på verkliga zenit-/nadirmaterial, inte bara
med enhetstester.

## Produktordning efter Panorama F

Användaren skrev ursprungliga PanoWizard för Windows 2006; den nuvarande
macOS-appen är den uttryckliga uppföljaren. Produktmålet är systemkamerans
bildkvalitet och kontroll med ett arbetsflöde som så småningom närmar sig
moderna ettklickskameror.

Arbetsordningen är beslutad och ska hållas strikt:

1. Slutför mardrömspanorama F. Trollstaven ska från ett helt nytt projekt
   reproducera `I.pw` utan manuella eller ärvda CP.
2. Testa den kommande 360 Precision Atome för Sigma 8 mm på stativ. Verifiera
   att den borttagna handhållna parallaxen ger stabil, upprepningsbar automatik.
3. Jämför Sigma 8 mm och Nikkor 10,5 mm avseende detalj, antal riktningar,
   sömmar, projektion och automatisk reproducerbarhet.
4. Först därefter byggs lekfulla/sekundära funktioner.

Planerade senare funktioner, inte aktuella innan 1–3 fungerar:

- Kubexport till sex förlustfria bilder: front, höger, bak, vänster, zenit och
  nadir. Syftet är att kunna retuschera den plana nadirbilden i Photoshop.
- Återimport av retuscherad nadirkubsida och exakt återprojektion utan att
  bygga om resten av panoramat.
- Little Planet/stereografisk export med rotation, centrum och planetstorlek.

Användarens formulering sammanfattar prioriteringen: en sak i taget – först
mardrömspanorama, sedan stativ, därefter kan vi leka.

## Förtydligande 2026-08-03 kl. 23:20 – reproducerbarhet

Användaren skapade ett helt nytt projekt med samma nio F-bilder och klickade
på trollstaven. Automatiken stoppade korrekt med meddelandet:
`Ringen saknar kontrollpunkter mellan bildgrupp 4 och 5.` Detta bekräftar att
ett nytt projekt ännu inte reproducerar `I.pw` autonomt.

`I.pw` är fortsatt den enda visuellt lyckade referensen. För samma bilder kan
man duplicera I, behålla dess 442 CP och använda vanliga `Skapa panorama`.
Man ska inte klicka trollstaven i kopian, eftersom den ersätter punktnätet.

Viktigt: försöken M–S skapades genom att kopiera I som testskal. När de
automatiska körningarna misslyckades låg I:s gamla `panorama/result.jpg` och
442 CP kvar i paketen. Att M–S ser lika bra ut är därför inte bevis på
reproducerbarhet; de är missvisande ärvda resultat. Använd dem inte som
referenser. Överväg att rensa dem kontrollerat nästa gång efter användarens
godkännande och använd beskrivande testnamn i stället för alfabetet.

Den återstående nyckeln är CP-generatorn, inte en ny panoramamotor. Koden har
redan ändrats för exaktare Sigma-projektion, optiskt centrum och tätare nät,
men den autonoma generatorn behöver:

1. identifiera saknade övergångar mellan verkliga vygrupper,
2. göra en riktad maskmedveten all-pairs-sökning mellan just de grupperna,
3. globalt validera och rensa kandidaterna,
4. optimera om från nominella kamerariktningar, aldrig från kollapsad geometri,
5. underkänna lösningar med orimlig FOV/pose eller utan faktisk duk­täckning,
6. bevisa resultatet genom ett helt nytt projekt utan CP eller cachad panorama.

Slutkriteriet är uttryckligt: trollstaven ska från ett tomt projekt med de nio
original-TIFF-filerna skapa ett resultat i nivå med I. Fram till dess behövs
fortfarande handpåläggning i CP-generatorns kod.

## Avslutande läge 2026-08-03 kl. 23:15 – Panorama F

Panorama F (`/Users/magnus/Desktop/Panorama/F`) är fortfarande projektets
viktigaste mardrömstest: nio stående Sigma 8 mm/DX-bilder, fyra verkliga
kamerariktningar med dubbelexponeringar, mycket rörliga personer och en
regelbunden stenläggning som avslöjar små projektions- och sömfel.

Det bästa resultatet är `I.pw`. Det är visuellt mycket nära, och enligt
användaren nästan bättre än, PTGui-referensen. Stenläggningen är betydligt
jämnare än i tidigare A–H, den svarta Enblend-fliken vid nadir försvann och
lagerurvalet blev renare. Nadir- och zenithålen är avsiktliga och ska inte
fyllas.

I använder 442 egna kontrollpunkter över 25 bildpar. Medelfelet är cirka
0,865 px och 90-percentilen cirka 1,555 px. Inga PTGui-kontrollpunkter har
kopierats. PTGui-projektet `Panorama.pts` användes endast för att förstå
modellen: 565 CP över 26 par, fisheye-faktor -0,526971, optimerat optiskt
centrum och multibandssöm över alla nio lager.

Följande förbättringar finns nu permanent i koden:

- Sigma-källor förwarpas från PTGuis generella fisheye-faktor -0,526971 till
  Hugins equisolidmodell -0,5. Kontrollpunktskoordinater transformeras fram
  och tillbaka så editorn fortfarande använder originalbildens koordinater.
- OpenCV-bryggan har `PWWarpFisheyeFactor`; punkttransformationen har ett
  roundtrip-regressionstest.
- Sigma-linsförfiningen optimerar även optiskt centrum `d/e` utöver FOV och
  `a/b/c`.
- Sigma-vägen behåller ett redundant tätt CP-nät i stället för att alltid
  reducera det till en minimal ringryggrad.
- Ett nytt rått all-pairs-SIFT/homografi/RANSAC-förstapass finns för att
  upptäcka dubbelexponeringar och överlapp utan antagandet att nio filer är
  nio jämnt fördelade kamerariktningar.
- Global residualrensning kan starta om Sigma-optimeringen från nominella
  riktningar, och CP-jämförelser tolererar Hugins avrundning.

Viktig begränsning: trollstaven reproducerar ännu inte I autonomt från ett
helt nytt projekt. Flera rena noll-CP-försök (J–S) hittade mer av nätet men
kunde fortfarande ge en numeriskt giltig, geometriskt kollapsad lösning,
sakna en ringövergång eller få alla lager utanför renderingsduken. I:s 442 CP
kommer från den interaktiva kedjan: 566 egna råa kandidater, en första
kollapsad optimering, global felmätning, filtrering och en ny optimering från
scratch. Projektion och optimering är alltså kodade; det återstår att ersätta
den sista visuella/plausibilitetsbedömningen med deterministisk kod.

Nästa steg ska vara:

1. Lägg till en explicit plausibilitetskontroll efter varje Sigma-lösning:
   fyra riktningar runt 360°, rimlig FOV/lins, begränsad pitch/roll, faktisk
   bildtäckning på 4000×2000-duken och CP-förbindelse mellan varje vygrupp.
2. Om lösningen underkänns: återstarta från ursprungliga nominella riktningar
   med nästa robusta CP-urval, inte från den kollapsade PTO-geometrin.
3. Bevisa autonomin genom att skapa ett helt nytt `.pw` från de nio TIFF-filerna,
   utan CP från I, klicka `Börja om automatiskt` och visuellt jämföra samma
   stenläggningsvy mot I och PTGui.
4. Först när det testet håller får man säga att trollstaven reproducerar I.

Ordinarie testsvit passerar med 27 tester och `git diff --check` är ren.
Den signerade app som byggdes före de sista autonoma CP-experimenten finns i
`build/PanoWizard.app`; bygg om efter nästa kodpass innan appverifiering.

## Aktiv kontext 2026-08-03 kl. 03:00

Arbeta i `/Users/magnus/Documents/GitHub/panowizard` på branch
`codex/restart`. Arbetskopian innehåller stora avsiktliga ändringar och får
inte återställas destruktivt. Efter ändringar: kör `swift test`,
`git diff --check`, `./Scripts/build-app.sh` och verifiera appen i
`build/PanoWizard.app`. För närvarande passerar 25 tester.

### Aktuellt testprojekt F

Projektet är `/Users/magnus/Desktop/Panorama/F/Panorama.pw` med nio stående
Sigma 8 mm/DX-ringbilder. Inga PTGui-punkter får användas. Materialet består
av fyra verkliga handhållna kamerariktningar med dubbelexponeringar. Orange
CP-masker finns på alla nio bilder och ska utesluta rörliga personer från
punktmatchningen.

Senaste goda ringresultatet krävde manuella CP över den saknade övergången
mellan bildgrupperna 3–4 och 5–6. Utan den övergången drev vinkeln till cirka
100° och samma blå bod och flaggstång projicerades två gånger. Motorn stoppar
nu rendering om en övergång mellan verkliga ringvyer helt saknar CP och anger
vilka bildgrupper som behöver kompletteras.

Ringen är därefter visuellt betydligt bättre. Återstående kända brist är
polblandningen: urvalet av en representant per dubbelexponerad riktning är bra
mot dubbla människor vid horisonten, men kastar bort alternativa lager som
PTGui använder för ren stenläggning vid nadir/zenit. Resultatet kan därför få
ett litet svart hål vid nadir trots att PTGui klarar samma nio ringbilder utan
reparationsbild. Rätt framtida lösning är polspecifikt lagerurval/blandning:
representanter vid horisonten, alternativa exponeringar nära polerna.
Nadirreparation ska vara valfri retuschering, inte ett krav för grundtäckning.

### Fastslaget arbetsflöde

- Kontrollpunkter tillåts endast mellan horisontella ringbilder. Nadir och
  zenit med rollen Reparation får inga CP och grovplaceras med OpenCV mot det
  frysta ringpanoramat.
- Orange CP-mask påverkar både nya förslag och giltigheten hos den befintliga
  punktlösningen. Projektet sparar en SHA-256-signatur av CP-maskerna. Ändras
  maskerna ogiltigförklaras hela gamla CP-nätet; ett nytt sammanhängande nät
  skapas från scratch. Enstaka maskerade CP får inte bara plockas bort eftersom
  det gav ett glest, kollapsat nät.
- Trollstaven heter `Börja om automatiskt`: ersätter alla CP, genererar nya
  med aktuella masker, optimerar och renderar.
- Den separata mittenknappen `Skapa panorama` (lagerikon) renderar med exakt
  nuvarande/redigerade CP utan att generera om dem.
- `Föreslå punkter…` kompletterar befintliga CP lokalt eller i projektet;
  `Optimera` använder exakt nuvarande CP.
- CP-fellistan sorteras fallande på pixelfel men behåller ursprungligt nummer
  och färg så markörerna fortfarande motsvarar bilderna.

### Bildborttagning

Delete eller `Ta bort källbild` tar bort vald bild och endast CP som berör
den. Övriga CP bevaras och bildindex räknas om. Masker, placeringar, cachad
rigg och inaktuella panoramaresultat rensas. Pågående stitchresultat har en
operationsidentitet och får inte skriva tillbaka efter att en bild raderats.
En tidigare crash vid tom nadir/zenitplacering och samtidig borttagning är
fixad; inga optional-värden tvångsuppackas där längre.

### Masker och poler

Källmasker har frihand och fylld cirkel för nadir/zenit; ingen ellips.
Rektangel med skarpa hörn är en senare idé, inte implementerad. Sigma/Nikkor
poldefish använder optimerad ring-HFOV via
`NadirRepairPlacement.sourceHorizontalFieldOfView`; stående/liggande
sensoraxlar hanteras. Valfri manuell poljustering har flytt, rotation, skala
20–800 % och hörnperspektiv.

### Diskutrymmesbugg

Varje stitch lämnade tidigare hela arbetsmappen med warpade TIFF-lager kvar i
`.../T/PanoWizard/Stitches`. Det hade vuxit till 75 GB. Äldre övergivna
mappar raderades 2026-08-03; endast senaste aktiva mappen (cirka 275 MB)
behölls och total PanoWizard-temp sjönk från 76 GB till 1,4 GB. Motorn har nu
`defer`-rensning av arbetsmappen och kopierar endast slutpanorama samt
eventuella polöverlägg till `PanoWizard/Results/<UUID>` före retur. Ingen
källbild eller `.pw`-fil raderades. `PanoWizard/Repairs` är fortfarande cirka
1 GB med många gamla PNG-förhandsvisningar och bör saneras i den planerade
cleanup-rundan.

### Senare cleanup

När funktionerna är stabila vill användaren uttryckligen rensa ut överlappande
kod och gamla specialfall. Prioritera först korrekt beteende och verklig
visuell verifiering; gör sedan en separat, kontrollerad saneringsrunda.

## Produktbeslut 2026-08-02 kl. 20:40

Kontrollpunkter tillåts endast mellan horisontella positioneringsbilder i
ringen. Nadir och zenit med rollen Reparation får inte öppnas i CP-editorn,
får inga punktförslag och påverkas inte av CP-optimeringen. Punkter som berör
en polbild rensas ur projektmodellen; ringens punkter lämnas orörda.

Polbilder grovplaceras enbart med den tidigare fungerande OpenCV-registreringen
mot det frysta panoramat. Finjustering ska ske visuellt med flytt, rotation,
skala och hörn/perspektiv. Ingen bakåtkompatibilitet för det borttagna
pol-CP-arbetsflödet behövs. Planerade men inte implementerade maskverktyg är
frihand, cirkel (inte ellips) och rektangel med skarpa hörn.

## Avslutande läge 2026-08-02 kl. 01:30

Projekt J finns i `/Users/magnus/Desktop/Panorama/J/Panorama.pw`. Den
horisontella sexbildsringen är nu visuellt perfekt med autogenererade
kontrollpunkter och ska betraktas som färdig. Reparationspunkter får aldrig
påverka denna ring.

CP-editorn visar de verkliga valda källbilderna och behandlar horisontella,
nadir och zenit lika. Reparations-CP sparas och används endast som ledtråd för
hur den handhållna polbilden ska ligga. Markörer, lupp och koordinater följer
bildrotationen. En projicerad motpunkt som hamnar utanför bilden placeras i
mitten så att den alltid går att flytta.

Den nya polkedjan använder Hugins kalibrerade `f21`-projektion även för
reparationsbilderna, fryser ringen och optimerar polens yaw/pitch/roll från CP.
Liggande nadir får eget HFOV beräknat från samma kalibrerade brännvidd som de
stående ringbilderna. Källans användarmask avgör ensam vilken reparationsyta
som används; ingen automatisk cirkel- eller feather-mask får läggas ovanpå.

Både nadir och zenit är handhållna från en annan kameraposition. Därför räcker
inte enbart sfärisk yaw/pitch/roll: efter Hugin-projektionen görs en lokal
CP-baserad perspektiv-/skaljustering. Första fulla homografiförsöket blev
degenererat för nadir: endast fyra av sju lokalt användbara punkter blev
inliers, projektiv horisont korsade patchen och en jättelik skev matta
skapades. Detta är nu spärrat genom krav på minst 65 % inliers och kontroll av
den homogena nämnaren i alla fyra hörn. Vid instabil homografi används en
sexparameters affine-modell som säker reserv. Denna senaste stabilisering är
byggd, signerad och startad men ännu inte visuellt verifierad efter ett nytt
klick på trollstaven.

Projekt J kan fortfarande innehålla den senast sparade, degenererade
nadirplaceringen från körningen före spärren. Ett nytt trollstavsklick med den
senaste appen ska ersätta den. Ändra inte J:s masker eller manuella
justeringar direkt i projektfilen utan uttrycklig begäran.

Aktuell app finns i `build/PanoWizard.app`. Alla 22 tester passerar. Nästa pass
ska fokusera uteslutande på att visuellt verifiera och förbättra automatisk
nadir/zenitplacering; ringgeometrin ska lämnas orörd.

## Avslutande läge 2026-08-01

Projekt I fungerar nu mycket bra med en fryst horisontell ring samt valfria,
handhållna nadir- och zenitreparationer. Båda polerna kan maskas, placeras,
färgmatchas, Enblend-blandas och justeras med kontrollpunkter mot en lokal
120°-projektion av den frysta ringen. Poljusteringen får aldrig ändra ringens
geometri. Förhandsvisningen minns yaw, pitch och FOV. HTML-exporten bäddar in
både nadir och zenit, men interaktiv HTML i rå e-postbilaga är opålitlig på
grund av Mail/Safaris säkerhetsmodell; ingen ytterligare e-postlösning ska
forceras tills en elegant metod finns.

Nikkor 10,5 mm på Nikon D7200 och 360 Precision Atome har gett ett automatiskt
resultat i nivå med PTGui utan manuell input. Nästa viktiga fälttest blir en
beställd Atome för Sigma 8 mm. Testa flera verkliga panoraman och kontrollera
reproducerbarhet, sömmar, polplacering och att samma material alltid ger samma
geometri. Aktuell signerad app finns i `build/PanoWizard.app`; 19 tester
passerar. Arbetskopian är fortsatt omfattande och får inte återställas
destruktivt.

## Polkontrollpunkter 2026-08-01 kl. 01:36

Nadir- och zenitreparationer kan nu anpassas mot en lokal 120°-projektion av
den färdiga, frysta ringen. Kommandona finns under `Justering` som
`Anpassa zenit/nadir mot ringen…`. Editorn visar reparationsbilden till vänster
och ringreferensen till höger, med högst 30 automatiska redigerbara CP.
`Anpassa` löser endast polbildens lokala homografi; ringens bilder, CP och
Hugin-geometri berörs aldrig. Punkterna och residualerna sparas per pol i
projektet. Verifierat mot projekt I. Totalt 19 tester passerar och signerad app
finns i `build/PanoWizard.app`.

## Nikkor-projektion 2026-07-31 kl. 20:15

Panorama G visade med exakt samma 150 PTGui-kontrollpunkter att den återstående
skillnaden låg i grundprojektionen. PTGui-profilen använder fisheye factor
`-0,599227`; PanoWizard använde Hugins equidistant full-frame-fisheye `f3`
(motsvarande faktor 0). Hugin kan inte uttrycka en godtycklig faktor, men
equisolid `f21` (faktor `-0,5`) tillsammans med de kalibrerade `a/b/c`-värdena
är en nära motsvarighet.

På samma 150 punkter gav `f21` 4,65 px medelfel, 3,74 px median och 8,03 px
90-percentil, jämfört med mycket stora avvikelser för `f3`. Helrenderingen
ligger visuellt mycket nära PTGui-referensen. Den automatiska CP-vägen har
också helrenderats och verifierats. Ett regressionstest kräver nu `f21` för
Nikkor-profilen. Totalt 16 tester passerar och signerad app finns i
`build/PanoWizard.app`.

## CP-bevarande 2026-07-31 kl. 19:30

`Sammanfoga` använder nu projektets befintliga/redigerade kontrollpunkter när
sådana finns. Automatisk nystart sker bara när punktlistan är tom. Full
omgenerering finns som ett separat destruktivt val under `Föreslå punkter…`
och kräver en extra bekräftelse som varnar för att manuella ändringar ersätts.
Den befintliga punktlistan lämnas orörd om den nya sökningen misslyckas.

CP-editorns aspect-fit-marginaler är inte längre svarta utan använder den
adaptiva macOS-fönsterbakgrunden. Bilderna beskärs inte. Alla 15 tester
passerar och den signerade appen finns i `build/PanoWizard.app`.

## GUI-läge 2026-07-31 kl. 18:40

Den separata trädsektionen `Kontrollpunkter` är borttagen. Sidopanelen har nu
fasta, icke utfällbara titlar för `Källbilder` och `Panorama`. Ett vanligt
klick på en källbild gör den till huvudbild och visar den vanliga bild- och
maskvyn. Shift-klick på en annan källbild behåller huvudbilden till vänster,
visar den Shift-klickade bilden till höger och öppnar CP-editorn. Ytterligare
Shift-klick ersätter endast högerbilden; ett vanligt klick lämnar editorn.

Sidopanelen använder en ogenomskinlig adaptiv macOS-fönsterbakgrund i stället
för material/genomlysning. Huvudbilden markeras blått och högerbilden med en
orange helradsmarkering. Alla valbara rader markeras över hela listbredden.
Knappen `Generera` i Panorama-rubriken är borttagen; sammanfogning startas från
verktygsraden. Under Panorama finns `Inställningar` och `Förhandsvisning`.
Förhandsvisning aktiveras när ett genererat panorama finns. CP-fellistan visar
nu samma cirkulära, färgade nummer som bildmarkörerna. Interaktionsflödet har
ett riktat regressionstest. Totalt 15 tester passerar och den signerade appen
är byggd i `build/PanoWizard.app`.

## Senaste läget 2026-07-31 kl. 17:55

Nikkor 10,5 mm-profilen har verifierats mot stativprojektet
`/Users/magnus/Desktop/Panorama/G/Panorama.pw` och PTGui-referensen i samma
mapp. Den gamla generella full-frame-fisheyevägen gav 77 kontrollpunkter med
21,8 px medelfel och 74,4 px maxfel samt kraftigt deformerad geometri.

Profilen använder nu PTGui-kalibreringen som stabil startmodell: 87,44°
horisontell bildvinkel, full-frame fisheye, `a/b/c` =
`-0,022975 / 0,068365 / -0,054732` och det uppmätta optiska centrumet.
Nikkor-ringen får en egen poseoptimering från jämna riktningar. Distortion och
centrum hålls fasta; endast bildvinkel och poser finjusteras.

En automatisk omkörning av G gav 106 punkter med 4,06 px medelfel, 6,36 px
vid 90:e percentilen och 9,82 px maxfel. Det renderade helpanoramat är visuellt
nära PTGui-resultatet. Svarta områden vid zenit och nadir är väntade eftersom
G-projektet bara innehåller de sex horisontella ringbilderna. Alla 13 tester
passerar och den signerade appen är byggd i `build/PanoWizard.app`.

## Senaste läget 2026-07-30 kl. 23:45

Dagens arbete har främst gällt kontrollpunktseditorn. Optimeringens återstående
geometriproblem ska inte angripas vidare innan CP-arbetsflödet känns färdigt.

### Produktbeslut

PanoWizard kommer sannolikt behöva leva med en riktig CP-editor. Automatiken
behöver ge en användbar grund men behöver inte ensam nå PTGui-kvalitet.
`Panorama A.pw` visar att samma handhållna nio-bildersmaterial kan ge en bra
stitch när kontrollpunkterna är bra. Stitchmotorn och bildmaterialet är alltså
i grunden kapabla; kontrollpunktsgrafen och punkturvalet är den stora
osäkerheten.

Ett senare helt automatiskt försök med orange CP-masker och omkring 249 punkter
gav faktiskt en ganska bra fullsfärisk grund utan manuella punkter. Det svarta
stativhålet var då ett separat reparationsproblem. Andra automatiska
punktuppsättningar har fortfarande gett kraftigt trasig geometri. Antal punkter
eller låg residual är därför inte ensamt ett kvalitetsmått.

### Nuvarande CP-editor

- Kontrollpunkter är ett utfällbart träd under Panorama i vänsterspalten.
- Trädet visar samma radformat som Källbilder: bildnummer, thumbnail, filnamn
  och `Bild N · Horisontell`.
- Hela bildraden är klickbar.
- De två senast klickade bilderna visas i editorn; föregående val ligger till
  vänster och det senaste till höger.
- De två aktiva raderna har helblå macOS-lik markering.
- Editorn visar två stora bilder och en fellista till höger.
- Punkter kan markeras, dras, mikrojusteras med lupp, läggas till och raderas.
- DEL ska radera markerad punkt, numrera om och markera nästa så att flera
  punkter kan raderas i följd.
- `Radera…` erbjuder markerad punkt, alla punkter i aktuellt bildpar eller alla
  punkter i projektet.
- `Föreslå punkter…` erbjuder aktuellt bildpar eller hela projektet.
- Förslag lägger till högst tio nya punkter per matchande bildpar och bevarar
  befintliga punkter.
- Knappen animeras inte under sökning. Den inaktiveras och statusraden visar
  `Söker kontrollpunkter…`.
- `Optimera` kör om optimeringen med de redigerade punkterna.

### Masker och automatiska punktförslag

Orange masker används nu även av den interaktiva `Föreslå punkter…`-vägen.
OpenCV arbetar på tillfälliga maskerade TIFF-kopior. Varje föreslaget punktpar
efterkontrolleras dessutom mot originalmaskerna med 24 pixlars säkerhetsradie
i båda bilderna. Om någon ände träffar masken kasseras hela paret.

Automatiska punkter valdes tidigare i OpenCV:s kvalitetsordning, vilket kunde
ge åtta–nio punkter i samma lilla kluster. Urvalet använder nu greedy
farthest-point sampling: efter första kandidaten väljs varje ny punkt så långt
som möjligt från redan valda och befintliga punkter, normaliserat i båda
bilderna. Dubblettkontrollen jämför nu endast punkter inom samma bildpar.
Detta är implementerat och byggt men behöver bedömas visuellt på riktiga
projekt.

### Övrigt från dagens pass

- Fönsterstorlek, position och maximerat läge sparas mellan appstarter.
- Efter varje kodändring ska den riktiga signerade appen byggas automatiskt
  med `./Scripts/build-app.sh`, inte bara Swift-paketet.
- Aktuell app finns i `build/PanoWizard.app`.
- Alla 13 Swift-tester passerade efter senaste ändringen.
- Arbetskopian innehåller fortfarande omfattande användarändringar och får
  inte återställas destruktivt.

## Senaste läget 2026-07-28 kl. 03:31

Det senaste arbetspasset gällde extremfallet:

- `/Users/magnus/Desktop/Panorama/F/Panorama 2.pw`
- nio porträttorienterade TIFF-bilder från Sigma 8 mm på Nikon D80
- `/Users/magnus/Desktop/Panorama/F/PTGui/Panorama.pts`
- `/Users/magnus/Desktop/Panorama/F/PTGui/Panorama.jpg`

PTGui ger med samma nio källbilder ett geometriskt mycket bra panorama där
stenläggningens rutnät är sammanhängande. Olika personer får synas i olika
överlappningar; den statiska markgeometrin är facit.

### Viktig slutsats

Den nuvarande PanoWizard-lösningen är **inte godkänd**. Senaste appresultatet
har kollapsad/otillräcklig sfärtäckning med ett mycket stort svart område.
En tidigare lokal nadirprojektion såg bra ut, men detta var ett otillräckligt
test och ledde till ett felaktigt påstående om att problemet var löst.
Hela 360×180-resultatet måste alltid granskas innan en lösning godkänns.

Den sista byggda koden använder för Sigma-fallet:

- `cpfind` med all-par-matchning, homografi-RANSAC och `--ncores=1`
- automatisk gruppering av nästan identiska kamerariktningar
- filtrering av geometriskt orimliga bildpar
- Hugin `f21` (equisolid)
- 113,4° kortsides-FOV
- fryst `a=b=c=0`
- fast linsförskjutning `d=-26.093`, `e=-46.95`
- poseoptimering, `cpclean`, ny poseoptimering och horisontnivellering

Det gav en snygg lokal nadirvy och cirka 3,08 px kontrollpunkts-RMS, men
appens fullständiga sfärresultat var ändå katastrofalt. Varken låg RMS eller
en vald lokal vy får därför användas som kvalitetsbevis.

### PTGui

Ett tillfälligt läge som körde en separat installerad PTGui via dess
kommandorad implementerades och fungerade, men var produktmässigt meningslöst:
det krävde en redan skapad och optimerad `Panorama.pts`. Integrationen har tagits
bort ur användarflödet och gamla dokument med `engine: "ptGui"` normaliseras
till PanoWizards egen motor när de öppnas. Ingen PTGui-kod eller binärfil har
kopierats in i appen. `Panorama.pts` och `Panorama.jpg` används bara som diagnostiskt
facit.

### Kontrollpunkter och diagnostik

En kontrollpunktsinspektör finns nu i appen. Den visar råa punkter från
`cpfind` och punkter efter `cpclean`, grupperade per bildpar.

För nio-bildersfallet har experiment gett ungefär:

- tidigare pipeline: cirka 223 punkter över 18 par
- tätare all-par-matchning: cirka 500–560 punkter över 27–28 par
- PTGui: 565 punkter över 26 par

Matchtäthet ensam löser alltså inte problemet. Linsmodell, startposer,
felaktiga grafkanter, global sfärtäckning och robust optimering måste
utvärderas tillsammans.

### Nästa omtag

Nästa arbetspass ska börja metodiskt från mätdata, inte från ännu en renderad
gissning:

1. Återställ eller isolera en känd stabil helring innan fler linsförsök.
2. Lägg till automatisk validering av verklig 360°-täckning före rendering.
3. Logga varje grafkant med punkter, residual och uppskattad relativ rotation.
4. Avvisa poser som viker/kollapsar sfären eller lämnar stora täckningshål.
5. Jämför alla nio bilders relativa yaw/pitch/roll och linsmodell numeriskt
   mot `Panorama.pts`.
6. Rendera och jämför flera fasta kubsidor plus nadir, inte bara en vald vy.
7. Kör samma pipeline minst två gånger och kräv identisk geometri.

### Separat observerad prestandafråga

Klick på källbilder i vänsterpanelen känns trögt. Trolig orsak är att stora
2600×3888-TIFF-filer och masker avkodas/rasteriseras om på huvudtråden och att
panoramavyn invalidieras trots att bara markeringen ändras. Detta är ännu inte
profilerat eller åtgärdat.

### Arbetskopian

Grenen är `codex/restart` och arbetskopian innehåller många ändringar, inklusive
användarens tidigare arbete. Inget ska återställas destruktivt. Senaste
appbygget finns i `build/PanoWizard.app`, men ska inte betraktas som en bra
stitchversion för nio-bildersprojektet.

> Avsnitten längre ned beskriver tidigare milstolpar och innehåller delvis
> äldre arkitekturpåståenden. Vid konflikt gäller alltid detta senaste läge.

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

## Inkrement efter överlämningen – Förhandsvisning och perspektivjustering

Efter en lyckad stitch går appen nu direkt till `Förhandsvisning`. Om en
nadirreparation finns körs den lokala Enblend-blandningen automatiskt;
statusraden visar `Blandar nadirreparation med Enblend…` medan detta pågår.
Det halvtransparenta redigeringsläget öppnas endast uttryckligen via
`Justering`.

`Justering` har fyra gula hörnhandtag. De sparar en manuell
fyrhörnstransform utöver befintlig flytt, rotation och skala. Samma
perspektivtransform används direkt av Metal-previewn och därefter av OpenCV
när Enblends lokala reparationslager byggs. `Förhandsvisning` kör Enblend och
lämnar justeringsläget.

## Kontext 2026-07-26 – Panorama/F och kontrollpunktsmask

Aktivt stresstest är
`/Users/magnus/Desktop/Panorama/F/Panorama.pw`. Det innehåller nio
horisontella fisheyeexponeringar med stor överlappning och en zenitbild.
Användaren har avsiktligt tagit fler horisontella bilder än vad som krävs;
de är successiva kamerariktningar, inte fyra återanvända kamerastationer.

En separat orange masktyp, `Ignorera för kontrollpunkter`, har lagts till.
Den sparas i projektpaketets `control-point-masks/` och ska endast utesluta
rörliga motiv ur geometrimatchningen. Röd mask i `masks/` är ensam om att
avgöra vad som inte renderas i slutpanoramat. Användaren har målat orange
över rörliga människor på rätt sätt.

Två felaktiga experiment gjordes och har återtagits:

- orange kontrollpunktsmask användes som renderingsurklipp,
- bilderna grupperades felaktigt som fyra kamerastationer.

Nuvarande provkod håller, när orange masker finns, samtliga nio bilder vid
jämnt seedade vinklar runt 360 grader. Det undviker den tidigare kollapsade
geometrin men är fortfarande inte korrekt: senaste visuella resultatet visar
en dubblerad LEGOLAND-portal. Det bevisar att de verkliga vridningsstegen inte
är exakt jämna. Detta är ett geometri-/optimeringsproblem, inte ett fel i
användarens orange maskning.

Nästa tekniska steg måste därför estimera varje successiv kameras verkliga
rotation från fasta, omaskerade strukturer, samtidigt som bildordning och
ringens 360-gradersslutning bevaras. Varken helt fri `autooptimiser` (som
kollapsar ringen på felaktiga matchningar) eller helt låsta jämna yaw-vinklar
(som dubblerar fasta byggnader) är godtagbart. Lägg inte tillbaka
fyrastationsmodellen eller orange renderingsurklipp.

Den senaste användarbilden med dubblerad portal finns på:
`/var/folders/3t/lrgc1m3n52l350gm_r34yk1w0000gn/T/codex-clipboard-4b925dec-61c8-454b-a3de-5b23c49a4746.png`.

Arbetskopian är fortfarande medvetet smutsig på grenen `codex/restart`.
Ingen reset får göras. Releaseappen byggdes och startades efter senaste
inkrementet; `swift test` rapporterade 11 passerade tester.

### Slutläge efter Panorama/F-stresstestet

Styckena ovan om låsta jämna vinklar beskriver ett passerat mellanläge.
Detta är det aktuella och verifierade slutläget:

- Ringmatcharen provar nu **alla horisontella bildpar**, inte bara närmaste
  eller näst närmaste granne. Bild 1 kan därmed kopplas direkt till bild 9
  eller vilket annat bildfält som faktiskt överlappar.
- Ett par accepteras endast om det ger minst 12 rotationskonsistenta och
  geografiskt spridda kontrollpunkter.
- Den resulterande överlappsgrafen måste förbinda samtliga horisontella
  bilder; annars avbryts stitchningen med ett begripligt fel.
- Hugin optimerar åter de verkliga kameravinklarna fritt. Inga jämna
  vridningssteg eller påhittade kamerastationer används som slutgeometri.
- Nästan identiska fulla renderingslager dedupliceras före Enblend. De extra
  exponeringarna kan fortfarande stärka geometrin utan att Enblend avbryter
  med `excessive image overlap`.
- Orange mask är strikt en kontrollpunktsmask: området får synas men får inte
  styra geometrin. Röd mask styr vad som inte ska synas i slutresultatet.

Panorama/F ger nu en enda sammanhängande LEGOLAND-portal, sluten mark och
rimlig horisont. Användarens sista granskning var mycket positiv. De små
kvarvarande lokala felen förklaras sannolikt av att serien togs handhållet
kring ett lod i ett snöre, alltså med parallax och utan exakt rotation runt
objektivets nodalpunkt. Röd mask och Enblends sömval används för lokal
upprensning.

Den slutligt godkända användarbilden finns på:
`/var/folders/3t/lrgc1m3n52l350gm_r34yk1w0000gn/T/codex-clipboard-f8a05852-af1d-43b2-aedb-3853dce3e4e0.png`.

Verifierat efter all-pairs-ändringen:

- verklig integration mot Panorama/F passerade och granskades visuellt,
- verklig integration mot Panorama/C passerade inklusive nadirreparation,
- `swift test`: 11 tester passerade,
- releaseappen byggdes och startades med Panorama/F.

Nästa produktsteg enligt användaren är att **rensa upp GUI:t**. Funktioner
och verktyg har tillkommit successivt och gränssnittet känns nu
`kaka på kaka`. Börja nästa konversation med inventering och förenkling av
verktygsrad, masklägen, Förhandsvisning/Justering och bildroller. Ändra inte
stitchlogiken igen utan ett konkret reproducerat fel.

Arbetskopian är fortsatt medvetet smutsig på `codex/restart`; gör ingen reset
eller checkout som kastar ändringar. De senaste funktionerna är inte
committade eller pushade.

### Kontext sparad 2026-07-27: gröna tvångsmasker i Panorama/F

Fortsätt från detta läge; den tidigare uppgiften att först rensa GUI:t har
skjutits upp medan Panorama/F färdigställs.

Maskmodellen är nu åter tre separata masktyper:

- **Röd – Göm i panorama:** pixelområdet får inte hämtas från bilden.
- **Grön – Måste vara med:** pixelområdet måste hämtas från just den bilden.
- **Orange – Ignorera för kontrollpunkter:** påverkar endast geometrin.

`Invertera mask` är borttagen. Gröna masker lagras separat i projektpaketets
`inclusion-masks/`; röda ligger i `masks/` och orange i
`control-point-masks/`. `PanoProjectDocument`, `AppModel`, projektkopplingen
och maskeditorn har uppdaterats för detta.

Panorama/F innehåller nu sex horisontella bilder och användaren har målat en
liten grön mask runt sin dotter i samtliga sex. Det finns inga röda masker
kvar. Alla sex har orange kontrollpunktsmask. Maskerna är korrekta:
grön täckning är cirka 4–7 procent per bild.

Enblend kan inte ta de två nästan identiska helbildsparen som vanliga
bakgrundslager och avbryter då med `excessive image overlap`. Aktuell
renderingsmodell är därför:

1. kontrollpunkter och geometri använder samtliga bilder,
2. bakgrunds-Enblend använder en helbild per nästan identisk kamerariktning,
3. varje grön mask renderas som ett separat, projekterat lager,
4. dessa lager kompositeras ovanpå den kompletta bakgrunden.

Den gröna kantblandningen finns i `ForcedLayerCompositor.swift`. Efter några
förkastade experiment används nu en skarp, eroderad kärna och en cirka fem
pixel bred Gaussian-fjäder endast runt kanten. Försöket att fjädra före Nona
gav svarta halon och är återtaget. Försöket att blura hela lagret gjorde
personen oskarp och är också återtaget.

Senaste verifierade integrationen mot F:

`/var/folders/3t/lrgc1m3n52l350gm_r34yk1w0000gn/T/PanoWizard/Stitches/53C72238-35FC-4F68-9176-A0116A894A44/panorama.jpg`

Den bilden innehåller alla sex versionerna av dottern, utan svarta hål eller
mörka halon. Kärnorna är skarpa och kanterna betydligt mjukare. Användaren
har ännu inte lämnat sin egen visuella bedömning av just denna sista
fjädring; börja där nästa gång.

Integrationstestet `stitchesConfiguredProjectWhenRequested` läser nu även
`inclusion-masks/` och passerade mot riktiga F på cirka 40 sekunder. De
vanliga 11 testerna passerade tidigare. Releaseappen byggdes och startades
med Panorama/F efter senaste ändringen.

Arbetskopian är fortfarande avsiktligt smutsig på `codex/restart`. Gör ingen
reset eller checkout som kastar ändringar. Ändringarna är inte committade
eller pushade.

### Kontext sparad 2026-07-27: tillbaka till automatisk Enblend

PSD-spåret och hela funktionen **Manuella sömmar** är förkastade och helt
borttagna. Det finns ingen PSD-export/import, inga sparade manuella TIFF-lager
och ingen separat OpenCV-blandare.

Gröna tvångsmasker är också borttagna. Kvar finns:

- röd mask för absolut renderingsuteslutning,
- orange mask enbart för kontrollpunkter/geometri,
- vanlig automatisk Nona/Enblend-rendering.

Panorama/F är nu utan röda eller gröna renderingsmasker. Den verkliga
integrationen passerade och Enblend skapade en sammanhängande 4000×2000-bild
med alla sex versionerna av dottern synliga. Resultatet finns på:

`/var/folders/3t/lrgc1m3n52l350gm_r34yk1w0000gn/T/PanoWizard/Stitches/0AC1272A-DE05-43CD-9862-A436A2901394/panorama.jpg`

`swift test` är åter 11 tester och samtliga passerar. Arbetskopian är fortsatt
avsiktligt smutsig och inte committad eller pushad.

### Kontext sparad 2026-07-29: kontrollpunktseditor

Fokus har flyttats från att försöka nå PTGuis automatiska CP-kvalitet till
att bygga en kontrollpunktseditor som går att leva med. Användaren vill
fortsätta med detta i nästa konversation.

Editorn är en vanlig del av huvudfönstret, inte en modal sheet. Vänsterpanelen
har en enda rad `Redigera kontrollpunkter`; själva bildvalet sker med två
oberoende horisontella miniatyrremsor ovanför bilderna, inspirerat av PTGui.
Före/efter-cpclean-vyerna är borttagna. Punkterna är nu den redigerbara
sanningen.

Följande beteende finns:

- cirkulära, numrerade CP-markörer med halvtransparent fyllning,
- vald punkt och dess motpunkt ritas överst,
- klick markerar, drag mikrojusterar,
- håll/drag på en befintlig punkt visar PanoWizards parade förstoringsglas,
- Delete/backspace raderar båda ändarna och markerar nästa punkt,
- Tab går framåt och Shift-Tab bakåt,
- Command visar endast förstoringsglaset under musen; nästa klick skapar en
  punkt och en lokalt projicerad motpunkt,
- vanlig `Lägg till punkt` gör samma sak stegvis,
- `Radera alla` kräver ett andra bekräftande klick,
- `Optimera igen` använder exakt de manuellt redigerade punkterna och hoppar
  över cpclean,
- bildminiatyrer och editorbilder har asynkron cache så bildparsbyte inte ska
  blockera på upprepad TIFF-avkodning,
- SwiftUI:s stora blå fokusram runt hela editorn är borttagen utan att
  tangentbordsstyrningen försvann.

`DiagnosticControlPoint` är nu identifierbar, kodbar och muterbar.
`PanoProject.controlPoints` sparar den redigerade listan. Viktig semantik:

- `nil` betyder att CP aldrig har genererats,
- `[]` betyder att användaren uttryckligen har raderat alla.

En bugg där tom lista ignorerades vid återöppning och nya CP kunde dyka upp
är rättad. Vanliga `Sammanfoga` använder sparade manuella punkter och får
inte autogenerera efter `Radera alla`. Ett regressionstest
`explicitlyRemovedControlPointsStayEmptyWhenProjectIsRestored` täcker detta.

Det finns nu en knapp `Föreslå punkter` i editorn. Den kör en ny
parspecifik OpenCV/SIFT-funktion endast för de två synliga bilderna, behåller
befintliga CP, filtrerar närliggande dubletter och lägger till högst tolv
förslag. Den körs aldrig automatiskt. C-bryggan heter
`PWGeneratePairControlPoints`.

Aktuell invändning från användaren: `Föreslå punkter` läser just nu
original-TIFF-filerna direkt med OpenCV. Filerna skrivs aldrig till, men om
de ligger i iCloud kan macOS materialisera dem och visa en förvirrande
fil-/molnindikator. Användaren kallade detta `lite skumt`. Nästa lämpliga
steg är att låta CP-editorn och parmatcharen använda lokala cache-/arbetskopior
i stället för originalens URL:er. Original ska bara behöva läsas när cachen
skapas och vid slutrendering. Undersök gärna om befintliga 3000-pixels
editorcachebilder kan återanvändas eller om matcharen behöver en separat
lokal bildcache. Ändra inte original-TIFF-filerna.

Orange CP-mask påverkar nu faktiskt matchningsgeometrin genom temporära,
normaliserade TIFF-kopior; original används fortfarande för rendering.
OpenCV-ringmatcharen använder rotations-RANSAC samt spatial uttunning
(`minimumSeparation = 20`, högst 20 punkter per par). Stora täta kluster ska
undvikas.

Senast verifierat:

- `swift test`: 12 tester i 3 sviter passerar,
- releaseappen bygger till `build/PanoWizard.app`,
- appen startades inte efter de senaste ändringarna enligt användarens
  uttryckliga önskemål.

Arbetskopian är fortfarande avsiktligt mycket smutsig på `codex/restart`.
Ingen reset eller checkout som kastar ändringar. Ingenting från detta
CP-editorarbete är committat eller pushat.

### Kritisk temp-läcka upptäckt 2026-07-29

macOS varnade för nästan full disk. APFS-behållaren på 245 GB hade bara cirka
3,3 GB ledigt. En skrivskyddad inventering visade att PanoWizard hade lämnat
cirka **41 GB temporära arbetsfiler** under:

`/var/folders/3t/lrgc1m3n52l350gm_r34yk1w0000gn/T/PanoWizard`

Fördelningen var ungefär:

- `Stitches`: 39 GB,
- `Hugin`: 1,1 GB,
- `Repairs`: 1,0 GB,
- övrigt: cirka 0,1 GB.

Användaren godkände att hela denna tempmapp raderas. Det betyder att äldre
diagnostiska resultatvägar i tidigare kontextstycken inte längre kan antas
finnas kvar. Original-TIFF, sparade `.panowizard`-projekt och repo påverkas
inte.

Detta är en produktbugg som ska åtgärdas: PanoWizard måste städa gamla
jobbmappar efter lyckad eller misslyckad stitch/reparation och även ha en
rimlig upprensningspolicy vid appstart. Behåll bara filer som krävs av en
aktiv session eller har kopierats in i projektpaketet. Använd säkra,
jobbunika temporärkataloger och `defer`-baserad cleanup så att även felvägar
städas.

### Kontext sparad 2026-07-29: PTGui-kalibrering och nytt CP-GUI

Detta avsnitt ersätter äldre uppgifter ovan om horisontella bildremsor i
kontrollpunktseditorn.

Panorama F är det aktiva referensprojektet:

- PanoWizard: `/Users/magnus/Desktop/Panorama/F/Panorama.pw`
- PTGui-projekt: `/Users/magnus/Desktop/Panorama/F/PTGui/Panorama.pts`
- PTGui-resultat: `/Users/magnus/Desktop/Panorama/F/PTGui/Panorama.jpg`
- installerad PTGui: `/Applications/PTGui.app`

PTGui-binären har ingen användbar publik kommandoradsoptimerare; `--help`
startar GUI:t. `.pts`-filen är däremot JSON och innehåller ett fullständigt
kalibreringsfacit. Viktiga PTGui-parametrar:

- projektion `circularfisheye`,
- fisheye factor `-0.526971` (nära equisolid),
- brännvidd `8.285697037340027 mm`,
- cropcirkelradie `11.30455 mm`,
- sensor diagonal `28.400704216621108 mm`,
- `a=-0.18159452333583262`,
- `b=0.33241501020519315`,
- `c=-0.18028126365236766`,
- PTGui optimerar även linsförskjutning.

Huvudfelet var att PanoWizard valde Hugins equisolid-projektion `f21`, men
nollställde `a/b/c` och aldrig anropade den redan existerande
`configuringSigmaLensRefinement`. Bra kontrollpunkter kunde därför inte
kompensera för den felaktigt låsta linsformen.

PTGui och Hugin normaliserar distortionen olika. PTGui-värdena får inte
kopieras direkt; det gav tidigare NaN och 10 000 optimizeriterationer.
PTGui-koefficienterna har nu räknats om från cropcirkelradien till Hugins
normalisering mot halva kortsidan. Följande säkra startvärden används för
Sigma 8 mm/DX i `configuringSigmaPoseOptimization`:

- `a=-0.06164565246503961`
- `b=0.16155732903077044`
- `c=-0.12544199818788626`

Optimeringen sker nu i två steg:

1. kamera-yaw/pitch/roll med den omräknade linskalibreringen fast,
2. gemensam FOV och `a/b/c` plus positionerna via
   `configuringSigmaLensRefinement`.

Verifiering på användarens 127 aktuella CP i Panorama F:

- tidigare Hugin-RMS cirka `4.229 px`,
- nytt Hugin-RMS cirka `2.967 px`,
- tidigare värsta CP cirka `29.5 px`,
- nytt värsta CP cirka `8.8 px`,
- de flesta CP ligger nu kring `1–5 px`,
- optimering utan rendering tog cirka 5,8 sekunder och gav endast ändliga
  residualer,
- full stitch tog cirka 36 sekunder och Nona/Enblend lyckades.

Senaste fulla diagnostiska resultatet skapades i en tempmapp och kan försvinna
vid upprensning:

`/var/folders/3t/lrgc1m3n52l350gm_r34yk1w0000gn/T/PanoWizard/Stitches/8E637B7B-AA15-42D4-979F-F355B9089670/panorama.jpg`

Enblend får **inte** alla nio Nona-lager. Bild 1/2/9, 3/4, 5/6 och 7/8 är
nästan samma kamerariktningar. Alla bilder ska användas för CP/geometri, men
bara en bild per nästan identisk vy ska skickas till Enblend. När alla nio
skickades in avbröt Enblend med:

`excessive image overlap detected; too high risk of defective seam line`

Urvalet med `representsSameView` och `backgroundLayerIndices` är därför
återställt och ska inte tas bort utan en annan stack-/exponeringsstrategi.

Den svarta fyrkanten vid nadir är inget mask- eller Metal-fel. Det är det
otäckta svarta sydpolsbandet i den equirektangulära bilden som förstoras när
sfärvisaren riktas rakt ned. Även PTGui-resultatet har ett motsvarande svart
band; användaren vet att bildserien inte täcker hela sfären.

Kontrollpunkts-GUI:t är omgjort:

- källbildslistan är åter en vanlig källbildslista,
- de två horisontella thumbnail-remsorna ovanför editorn är borttagna,
- `Redigera kontrollpunkter` är ett utfällbart diagnostikträd,
- barnraderna är bildpar sorterade efter största residual,
- rött betyder över 15 px, orange över 8 px och grönt högst 8 px,
- klick på ett bildpar öppnar det direkt,
- valt par markeras,
- tooltip visar största fel och medelfel.

Senast verifierat efter dessa ändringar:

- `swift test`: 12 tester i 3 sviter passerar,
- full integration för Panorama F passerar,
- releaseappen byggdes,
- Documents/GitHub ligger under en filprovider som ibland återlägger
  `com.apple.FinderInfo` under signering; vid behov kopiera appen till en ren
  `/tmp/PanoWizard-run.XXXXXX`-mapp, kör `xattr -cr`, signera och starta där.

Arbetskopian är fortfarande avsiktligt mycket smutsig på `codex/restart`.
Ingen reset eller checkout som kastar ändringar. Ingenting är committat eller
pushat.

### Kontext sparad 2026-07-30: automatisk pipeline är ännu inte godkänd

Det nya automatiska testprojektet är:

- `/Users/magnus/Desktop/Panorama/F/A.pw`

Användaren har uttryckligen fastslagit produktmålet: **PanoWizard ska vara ett
automatiskt stitchprogram.** Manuell CP-redigering får finnas som avancerad
diagnostik/nödläge, men användaren ska normalt aldrig behöva förstå, lägga
till eller radera kontrollpunkter. Tidigare positiva formuleringar om att
resultatet “satt” var felkalibrerade. Resultatet är bättre än total kollaps
men fortfarande långt från PTGui visuellt, framför allt i stenläggningen.
Lågt RMS är inte ett tillräckligt kvalitetsmått.

Följande har implementerats under den senaste sessionen:

- Grov OpenCV-passning används för att upptäcka fyra riktningar och grupperna
  `1/2/9`, `3/4`, `5/6`, `7/8`.
- Gruppningen använder complete-link-liknande krav; transitiv union fick
  tidigare bild 5–8 att felaktigt bli en enda riktning.
- Därefter skapas ett kalibrerat, grovt förorienterat Sigma/Hugin-projekt och
  `cpfind --prealigned` söker produktions-CP med samma linsmodell som
  optimeraren.
- Orimliga icke-överlappande bildpar filtreras.
- En geometrisk ring-backbone väljer en representativ exponering per riktning
  för länkarna mellan riktningar. Dubbelexponeringar kopplas inom sin riktning
  men får inte övervikta själva 360°-ringen.
- Efter första optimeringen tas robusta CP-avvikare bort. Minst fyra punkter
  per kvarvarande par bevaras.
- Slutpasset låser den redan lösta linsen och finjusterar bara
  yaw/pitch/roll. Att åter frigöra linsen efter outlierborttagning gav en
  numeriskt låg men visuellt degenererad lösning.
- Huvudknappen `Sammanfoga` regenererar alltid automatiska CP från början.
- `canStitch` tillåter nu sammanfogning även när den sparade CP-listan är tom.
- CP-editorn har två permanenta bildväljare så man kan skapa den första
  manuella punkten även efter `Radera alla`.
- Bildvalet för Enblend viktar CP i nedre bildhalvan högre för att prioritera
  stenläggningen.

Senaste fulla automatiska backbone-testet:

- 369 CP från `cpfind`,
- 280 CP efter ring-backbone,
- 259 CP efter optimering/outlierstädning,
- Hugin-RMS cirka `1.55 px`,
- representativa Enblend-bilder i testet: 2, 4, 6, 8.

Senare markviktat renderingstest valde 2, 4, 6, 7. Fullupplösta/fina
Enblend-masker testades men gav stora synliga tonplattor och ska **inte**
användas; standard multibandsblandning behölls.

Trots siffrorna är automatiken **inte godkänd**. Stenläggningen har fortfarande
lokala brott/skiftningar som PTGui inte har. Nästa session ska inte fortsätta
med fler lokala heuristiker eller försöka lösa detta med manuella CP. Gör i
stället en systematisk, stegvis jämförelse mellan PanoWizards och PTGuis
facit:

1. exakt linsprojektion och crop,
2. optiskt centrum/shift och teckenkonventioner,
3. varje bilds yaw/pitch/roll,
4. samma CP projicerade genom båda modellerna,
5. skillnaden mellan geometrifel, parallax och seam/blending.

Målet är att hitta den fundamentala modellskillnaden mot
`/Users/magnus/Desktop/Panorama/F/PTGui/Panorama.pts`, inte att optimera vidare mot
ett missvisande globalt RMS. PTGui-resultatet
`/Users/magnus/Desktop/Panorama/F/PTGui/Panorama.jpg` är det visuella facit.

Senast verifierat:

- `swift test`: 13 tester i 3 sviter passerar,
- releaseappen byggdes och öppnades med `A.pw`,
- arbetskopian är fortfarande avsiktligt mycket smutsig på `codex/restart`;
  kasta inga befintliga ändringar.

### Kontext sparad 2026-07-30 03: resultatet isolerar CP-generatorn

Ett kontrollerat experiment har nu gjorts med **exakt alla kontrollpunkter
från PTGui**, men med PanoWizards egen Hugin-baserade linsmodell, optimering,
projektion och rendering:

- facitprojekt: `/Users/magnus/Desktop/Panorama/F/PTGui/Panorama.pts`,
- testprojekt: `/Users/magnus/Desktop/Panorama/F/A.pw`,
- 565 PTGui-CP av typ `t=0`,
- 26 bildpar,
- PTGui-koordinaterna importerades direkt från endpoint-arrayerna
  `[imageIndex, 0, x, y]`,
- A.pw har `stitching.engine == "ptGui"` som särskilt jämförelseläge,
- PanoWizards optimering landade på cirka `5.04 px RMS`.

Det avgörande visuella resultatet är att stenläggningen blir klart acceptabel
och i stora drag sammanhängande med PTGui:s CP. Den blir inte exakt identisk
med PTGui, men skillnaden är liten jämfört med felen från PanoWizards
automatiska CP. Användarens korrekta slutsats är därför:

> Huvudfelet ligger i PanoWizards automatiska CP-generering/urval, inte i
> stitchmotorn eller linsmodellen.

Prioritera nästa session därefter. PTGui:s 565 punkter ska användas som facit
för att analysera varför PanoWizard missar:

1. exakt fisheye-normalisering före feature detection,
2. vilka bildpar som söks och deras verkliga överlapp,
3. geografisk spridning över hela överlappet, särskilt marken,
4. subpixelprecision,
5. rörliga motiv och andra falska matchningar,
6. hur många och vilka PTGui-punkter PanoWizard också hittar.

Gör en punkt-för-punkt-/områdesjämförelse mot PTGui-facit innan fler
heuristiker läggs till. Lågt RMS från PanoWizards egna punkter är inte bevis
på bra CP; de kan vara självkonsekventa men dåligt fördelade.

Kodändringar för experimentläget:

- `AppModel` konverterar inte längre `.ptGui` tillbaka till `.automatic`.
- `Sammanfoga` använder projektets sparade CP när engine är `.ptGui`; vanlig
  PanoWizard-automatisk körning använder fortfarande `controlPoints: nil`.
- importerade/manuella CP passerar utan PanoWizards plausibility-filter,
  ring-backbone eller robusta outlierborttagning.

`A.pw/project.json` innehåller efter körningen 565 CP med PanoWizards
beräknade fel. Den installerade PanoWizard-resultatbilden är 4000×2000 och
är skapad från PanoWizards optimerade geometri, inte från PTGui-renderingen.
Under blendtestet måste en representativ bild per dubbelexponerad riktning
användas eftersom Enblend vägrar nästan fullständigt överlappande dubletter.

En tidigare felaktig mellanåtgärd kopierade PTGui:s färdiga rendering till
A.pw. Den återställdes och ska inte förväxlas med det riktiga experimentet.
Original-PTGui-renderingen finns separat som
`/Users/magnus/Desktop/Panorama/F/PTGui/Panorama.jpg`.

Senast verifierat efter experimentändringarna:

- `swift test`: 13 tester i 3 sviter passerar,
- releaseappen byggdes,
- A.pw visar 565 punkter och PanoWizard-resultatet,
- arbetskopian är fortfarande avsiktligt mycket smutsig på `codex/restart`;
  kasta inga befintliga ändringar.

### Kontext sparad 2026-07-31 20: panorama G och Nikkor 10,5 mm

Panorama G isolerade två separata problem. Nikkor 10,5 mm ska modelleras som
Hugin `f21` (equisolid), inte `f3` (equidistant). En kalibrering mot samtliga
150 PTGui-CP gav Hugin-koefficienterna `a=-0.0252155339841942`,
`b=0.0605540979849503`, `c=-0.055438892095899`, `d=4.19324585683399` och
`e=-1.00751194420142`. Med exakt PTGui-punkterna blev medelfelet `0.223 px`,
medianen `0.191 px`, p90 `0.444 px` och maxfelet `0.861 px`.

Den automatiska körningen fick därefter god geometri men en stor svart kil.
Orsaken var inte CP utan global yaw: equirektangulär 360°-skarv låg genom
centrum av en fisheye-bild och Enblend rapporterade att Dijkstra-sömmen
slutade utanför kostnadsbilden. Renderingen roterar nu hela den färdiga
geometrin så skarven ligger mitt emellan första och sista ringbilden. Det
ändrar inga relativa poser eller CP-fel. Full automatisk G-körning gav en
ren sammanhängande bild utan kil.

Projekt I verifierar dessutom en handhållen zenit och nadir tillsammans med
ringen. Bilder märkta `Reparation + Zenit` går nu genom den befintliga
zenitregistreringen mot den frysta ringen; endast zenitbildens egen pose
optimeras och körningen avbryts om någon ringpose ändras. `Reparation + Nadir`
fortsätter som lokal overlay. Full I-körning lyckades och nadirregistreringen
hittade 68 lokala träffar. Oönskat innehåll vid kanterna (person, stativ,
fötter och mörka föremål) måste maskas i respektive reparationsbild.

### Kontext sparad 2026-07-31 21: beslut om valfria polreparationer

Användaren har bekräftat att en handhållen zenit ska behandlas enligt samma
princip som en handhållen nadir. Nuvarande implementation är fortfarande
asymmetrisk:

- `Nadir + Reparation` registreras som ett separat overlay och kan flyttas,
  roteras, skalas och perspektivjusteras i Förhandsvisning.
- `Zenit + Reparation` accepteras för närvarande, men går genom Hugins frysta
  zenitregistrering och bakas in i panoramat. Den kan bara påverkas med mask
  och ny stitchning.

En första snabb ansats att återanvända nadirkoden för zenit backades helt
innan leverans, eftersom den bara kunde bära ett overlay och zenit/nadir då
skulle skriva över varandra. Lämna inte en sådan halv lösning.

Beslutad korrekt arkitektur:

1. `Zenit + Reparation` är valfri; utan en sådan bild ändras ingenting.
2. Ringen är alltid fryst och får aldrig påverkas av någon polreparation.
3. Zenit registreras lokalt mot `+90°`, nadir mot `-90°`.
4. Projektet måste kunna lagra två oberoende placements och två overlayfiler.
5. Båda ska ha samma mask-, flytt-, rotations-, skal- och
   perspektivkontroller i Förhandsvisning.
6. Båda lagren ska kunna visas samtidigt och följa med i projektfil och
   HTML-export.
7. Befintliga projekt med endast den gamla nadirreparationen måste fortsätta
   fungera utan migreringsproblem.

Detta är **beslutat men ännu inte implementerat**. Nästa session ska göra en
ren generalisering till polreparationer, inte bara duplicera nadirknapparna.

Senaste färdiga relaterade GUI-funktion är `Invertera mask` (`⇧⌘I`), som
fungerar för röd panoramamask och orange CP-mask, använder ett ångrasteg och
är med i den signerade appen. Full testsvit hade då 17 godkända tester.

### Kontext sparad 2026-08-09 18: riktning borttagen från positionering

Bildriktning används inte längre för bilder med rollen `alignment`. Alla
aktiva positionerande bilder skickas tillsammans till samma CP-generering och
globala bundle adjustment; motorn avgör själv yaw, pitch och roll. Det gamla
`direction`-fältet ligger kvar i JSON för bakåtkompatibilitet men ingår inte i
riggsignaturen och påverkar inte positioneringsgeometrin.

Zenit/Nadir visas endast för rollen `fillOnly`, där valet betyder
reparationsområde. Äldre projekt med `fillOnly + horizontal` normaliseras till
nadir. Kontrollpunkter får delas mellan alla positionerande bilder och mellan
en positionerande bild och en reparationsbild, men inte mellan två rena
reparationsbilder.

Verifiering mot `/Users/magnus/Desktop/Panorama/H/A.pw` gjordes genom att
tvinga den femte positionerande bilden till det gamla värdet `zenith`. Samtliga
fem bilder gick ändå genom samma globala matchning/optimering och den femte
bilden löstes automatiskt till pitch `89.67°`. Resultatet var visuellt likvärdigt
med användarens perfekta körning där samma bild råkade vara `horizontal`.
Efter ändringen passerade 41 tester.

### Kontext sparad 2026-08-09 19: sfärisk CP-matchning med zenit

När en positionerande zenitbild lades till ökade alignment-mängden från fyra
till fem bilder. OpenCV-bryggan använde då åter plan homografi eftersom den
sfäriska Sigma-vägen felaktigt krävde exakt fyra bilder. Det gav åter smala
CP-band trots ett visuellt bra panorama; exempelvis täckte par 1–2 bara
`59.8–68.9 %` av bildhöjden.

Den kalibrerade 3D-rotations-RANSAC-vägen används nu för alla breda
Sigma-bildpar (`HFOV >= 110°`) oavsett antal positionerande bilder. Det gäller
även ring–zenit. Varje endpoints punkturval balanseras separat. Extrapar med
färre än tio valda punkter eller spatial täckning under `0.2` tas bort; ett
sådant redundant par i H/A hade sex punkter och täckning `0.125`.

Verifieringsprojektet
`/Users/magnus/Desktop/Panorama/H/A-spherical-test-2.pw` skapades från nya
H/A utan att skriva över originalet. Det har 148 slutliga CP på sju bildpar.
Ringparen täcker nu typiskt 31–87 procent av bildhöjden och ring–zenit-paren
har bred spridning över sina verkliga överlapp. Medelfelet är `1.166 px` och
maxfelet `6.657 px`; panorama och nadirreparation renderades klart. Den första
ofilterade diagnoskopian flyttades till Papperskorgen. Full testsiffra före
releasebygget är 42 godkända tester.

### Kontext sparad 2026-08-09 21: falska CP vid Sigma-cirkeln

Ett helt nytt fyrbildsprojekt, Panorama F/C, reproducerade att bara tre
riktningar syntes. Alla fyra bilder var aktiva. Efter Hugins rensning fanns
23 CP för bild 1–2, 23 för 2–3 och fem falska CP för 2–4. De fem falska
punkterna låg på den identiska svarta Sigma-cirkelkanten och hade nästan
samma koordinater i två bilder som egentligen var tagna cirka 90° isär.
Bild 4 placerades därför ovanpå bild 2.

Den råa SIFT-detekteringen maskar nu bort en 2,5-procentig säkerhetsmarginal
innanför den kalibrerade Sigma-bildcirkeln. På C gick de två falska paren
därefter från 14–15 geometriska träffar till noll, medan de fyra verkliga
grannparen behöll 25 punkter vardera. De lösta yaw-vinklarna blev 112,88°,
-154,43°, -64,41° och 23,87°, alltså fyra riktningar med cirka 90° steg.
Resultatet finns i
`/Users/magnus/Desktop/Panorama/F/C-circle-test.pw` och innehåller alla fyra
bilder utan Enblend-specialfall.

Efter optimeringen finns dessutom en fyrbildsspärr: varje Sigma-bild måste ha
minst två tillförlitliga grannar med minst åtta kvarvarande CP per par. Ett
svagt stjärnnät av den typ som förstörde C avbryts nu med ett konkret fel i
stället för att renderas som tre riktningar.

Panorama H verifierades separat i
`/Users/magnus/Desktop/Panorama/H/A-circle-regression.pw`. Dess fem
positioneringsbilder, zenit (pitch 89,69°), nadirreparation och slutrendering
fungerar fortfarande. Originalprojekten C och H skrevs inte över.

### Kontext sparad 2026-08-09 22: Enblend-söm runt automatisk polbild

Panorama H/A var geometriskt korrekt men standardgeneratorn `graph-cut`
valde en lång synlig söm mellan den automatiskt lösta zenitbilden och
ringbilderna. Fler multibandsnivåer hjälpte inte; Enblend använde redan de nio
nivåer som lagergeometrin tillät. Separat vinjetteringsoptimering ändrade
ljusfallet men lämnade kanten på exakt samma plats.

När den lösta geometrin innehåller en positioneringsbild med minst 60 graders
absolut pitch använder den enda ordinarie Enblend-körningen nu
`nearest-feature-transform`, samma robusta sömgenerator som redan användes vid
källmasker. Bildriktning i projektet används fortfarande inte. Enblend får
i stället den automatiskt optimerade pitchen från Hugin.

Verifieringsprojektet
`/Users/magnus/Desktop/Panorama/H/A-seam-fix.pw` skapades med helt nya CP.
Zenit löstes till pitch 89,69°, den vertikala himmelskanten försvann och
nadirreparationen lyckades. Originalet skrevs inte över. Alla 44 tester
passerar och releaseappen är byggd i `build/PanoWizard.app`.

Samma relativa CP-geometri kan av Hugin representeras i två globala lägen:
rättvänd med ringbildernas roll nära 0° eller upp-och-ned med roll nära 180°.
Det senare inträffade när den sparade CP-mängden i H/A återanvändes, trots att
punkterna i praktiken var identiska med den rättvända körningen. Efter
optimeringen normaliseras därför ett läge där majoriteten av icke-polära
positioneringsbilder har mer än 90° absolut roll genom en global 180° rotation.
Det bygger enbart på löst geometri, inte bildens manuella riktning.

Regressionen `/Users/magnus/Desktop/Panorama/H/A-upright-test.pw` använder
exakt de 148 sparade punkterna från den upp-och-nedvända A-körningen. Den blev
rättvänd, sömfri och fick lyckad nadirreparation. Testsviten omfattar nu 46
tester.

### Kontext sparad 2026-08-09 22: synliga bildnummer i CP-varningar

I Panorama F/A är projektbilderna 2 och 3 avmarkerade, så matcharen arbetar
med projektbilderna 1, 4, 5 och 6. Den interna fyrbildslistan numrerades ändå
1–4 i varningen och sade felaktigt att den svaga överlappningen var mellan
bild 1 och 2. Både trollstaven och stitchmotorn skickar nu med de synliga
projektbildnumren till matcharen. Direkt verifiering mot F/A ger korrekt text:
`mellan bild 1 och 4`. Avmarkerade bilder deltar fortfarande inte. Alla 47
tester passerar.

### Kontext sparad 2026-08-09 22: tätt men smalt verkligt överlapp i F/B

Panorama F/B består av bilderna 20.23.55, 20.24.02, 20.24.18 och 20.24.28.
Matcharen hittade 25 geometriskt verifierade CP mellan B:s bild 2 och 3 men
kastade bort hela paret eftersom punkterna täckte 12,5 procent av bildytan och
den generella gränsen var 20 procent. Detta var inte Sigma-cirkelns gamla
falska kantträffar: de hade bara fem punkter och själva kanten maskas numera
bort före SIFT.

Ett brett fisheyepar underkänns nu om det har färre än tio punkter eller mindre
än tio procents täckning. Därmed accepteras B:s täta smala verkliga överlapp,
medan den tidigare 18-punktsregressionen vid åtta procent och glesa falska par
fortfarande stoppas. `/Users/magnus/Desktop/Panorama/F/B-cp-upright-test.pw`
har 25 CP på vart och ett av de fyra grannparen, cirka 90 graders yaw-steg och
ett visuellt korrekt panorama. Flickan upprepas naturligt eftersom hon flyttat
sig mellan exponeringarna.

Under B-verifieringen korrigerades även rättvändningskontrollen: små negativa
rollvärden som -4° får inte normaliseras till 356° och misstolkas som ett
upp-och-nedvänt panorama. Alla 48 tester passerar.

### Kontext sparad 2026-08-09 23: batchverifiering Panorama C–H

Mapparna `/Users/magnus/Desktop/Panorama/C`, `D`, `F`, `G` och `H` har nu ett
visuellt verifierat `Panorama.pw`. Tomma A, B och E lämnades orörda. C använder
sex ringbilder samt separata zenit- och nadirreparationer. D använder fyra
ringbilder och en nadirreparation. F:s stabila ring är projektbilderna 2, 4,
5 och 6. G använder projektbilderna 1, 3, 5, 7, 8, 9, 10 och 11 med en
handkuraterad grannring; övriga exponeringar är sparade men avmarkerade. H
använder bilderna 1–5 för geometri och bild 6 som nadirreparation.

D:s fyra horisontella bilder ger bara fem råa CP mot ena grannen och fyra mot
den andra. En tillfällig reserv accepterade därför en öppen CP-kedja, men den
gav en dåligt låst 360°-skarv och har tagits bort. Den femte, nedåtriktade
bilden ska i stället delta i den vanliga geometrin: den ger 25 verifierade
punkter mot båda sidor av skarven och löses automatiskt till pitch −85,6°.
Slutprojektet D använder därför alla fem bilder som positioneringsbilder och
har 143 rensade CP i ett slutet, redundant nät.

Enblends `nearest-feature-transform` används nu för alla Sigma 8 mm-projekt,
inte bara när masker eller polära positioneringsbilder finns. Graph-cut
skapade breda vertikala tonkanter i jämn himmel i C och D och ett svart
sömområde när G:s många vidvinkellager sammanföll. Den avståndsbaserade sömmen
tog bort dessa artefakter utan att ändra geometrin. Samtliga fem slutprojekt
renderades om efter ändringen.

Det miljöstyrda integrationstestet
`stitchesImageFolderWhenRequested` kan skapa ett projekt från en hel bildmapp
och stöder avmarkerade bilder, sista bild som nadirreparation, valfri
zenitreparation och en explicit lista av manuellt verifierade bildpar. Utan
miljövariabler är testet ett snabbt no-op och påverkar inte den ordinarie
testsviten.

### Kontext sparad 2026-08-10 02: projektmapp vid export och separata ikoner

JPEG- och HTML-exporternas `NSSavePanel` öppnas nu alltid i samma mapp som
den öppna `.pw`-projektfilen. `PanoWizardApp` skickar projektfilens
föräldramapp via `ContentView` till `PanoramaExportView`; ett osparat dokument
utan känd URL använder fortfarande systemets normala standardmapp.

App- och dokumentikoner är avsiktligt separata:

- `Resources/Icons/PanoWizardApp.png` och `PanoWizardApp.icns` är appikonen:
  en blå panoramavy med en stor orange trollstav och två stjärnor, utan papper,
  dokumentblad eller vikt hörn.
- `Resources/Icons/PanoWizardProject.png` och `PanoWizardProject.icns` är
  `.pw`-projektikonen: motsvarande motiv på ett vitt dokumentblad.
- `CFBundleIconFile` pekar på `PanoWizardApp.icns`.
- dokumenttypen `se.egelberg.panowizard.project` har
  `CFBundleTypeIconFile = PanoWizardProject.icns`.
- `Scripts/build-app.sh` kopierar båda `.icns`-filerna till appaketets
  `Contents/Resources`.

Bundle-buildnumret är 4 för att tvinga LaunchServices att läsa om ikonerna.
Releaseappen är byggd i
`/Users/magnus/Documents/GitHub/panowizard/build/PanoWizard.app` och registrerad
med `lsregister`. Kontroll via `NSWorkspace.icon(forFile:)` visar den separata
appikonen för appaketet och dokumentikonen för verkliga `Panorama.pw`-projekt.
LaunchServices visar projekt-UTI:n som aktiv, exporterad och betrodd med rätt
relativa ikonfil. Finder visade ändå först sin cachelagrade vita standardikon;
Finder-processen startades om utan att projektfilerna ändrades. Om ikonen ändå
är gammal är nästa diagnostiska steg att ladda om macOS ikonservice, inte att
ändra projektformat eller projektpaket.

Senaste fulla testkörningen passerade 49 tester. Ikonarbetet ändrade bara
resurser, plist och byggscript; efteråt byggdes releaseappen framgångsrikt.
Arbetskopian är fortsatt avsiktligt smutsig med många tidigare ändringar och
ska inte återställas eller rensas brett.
