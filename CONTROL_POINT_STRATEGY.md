# Strategi för automatiska kontrollpunkter

PanoWizard försöker inte förstå om ett motiv föreställer en byggnad, person,
palm eller ett parasoll. En användbar kontrollpunkt definieras i stället som
en bilddetalj som följer panoramats gemensamma kamerageometri.

## Flöde

1. SIFT hittar lokala detaljer och ömsesidiga descriptor-matchningar.
2. Den valda objektivprofilen projicerar punkterna till kalibrerade 3D-strålar.
3. RANSAC hittar den dominerande rotationen med en generös gräns på 1,5°.
   Den gränsen används bara för att upptäcka modellen.
4. Residualernas median och MAD ger en robust, bildspecifik gräns. Den hålls
   mellan 0,25° och 0,75°. Rotationens slutmodell anpassas om med endast dessa
   konsistenta punkter. Vind, motivrörelse och parallax som avviker tydligt
   från kamerarörelsen faller bort här.
5. Kandidater väljs över det verkliga överlappets robusta 5–95-procentsområde,
   inte över hela bildrektangeln. Ett 5×5-rutnät och längst-från-tidigare-val
   ger täckning i båda bilderna.
6. Två valda punkter måste ligga minst 5 % av bildens kortsida från varandra
   i båda bilderna. Högst 25 punkter behålls per bildpar. Om materialet bara
   ger färre separerade punkter behålls det lägre antalet.
7. Hugins globala optimering och residualrensning gör den sista kontrollen i
   hela bildgrafen.

## Avsiktliga gränser

- Ingen semantisk objektdetektering eller panoramaspecifik ML-modell.
- Ingen regel som antar att en viss motivtyp alltid är statisk eller rörlig.
- Ingen utfyllnad med närliggande punkter för att nå ett önskat antal.
- Om den robusta modellen inte ger minst åtta punkter i tre spatiala celler
  avvisas bildparet. Ett tydligt fel är bättre än en falsk geometrisk länk.

Framtida förbättringar ska ersätta eller förbättra ett steg i detta flöde,
inte lägga till motivspecifika undantag. Minimikontrollen är hela Panorama A
(Nikkor, vind och monopod) samt en sammanhängande Sigma-referensmatchning.

## Produktmål och regressionskorpus

Målet är att PanoWizard från enbart originalbilder och bildmetadata ska skapa
ett panorama som är minst lika bra som PTGui-referensen, utan manuella
kontrollpunkter, masker, rolländringar eller geometriska korrigeringar.

Det lokala regressionskorpuset ligger i `/Users/magnus/Desktop/Panorama` och
består av mapparna A–H. I augusti 2026 innehåller det:

- A: 10 originalbilder
- B: 5 originalbilder; automatisk Sigma-ring, visuellt identisk med den
  helt automatiska PTGui-referensen och med samma skarvval
- C: 8 originalbilder; sexbildsring, zenit och nadir. En ren automatisk
  körning ger 109 ring-CP; polblandningen är tekniskt och visuellt verifierad
  av Codex men väntar på Magnus slutliga jämförelse mot PTGui
- D: 5 originalbilder; ring och nadir
- E: 8 originalbilder; automatisk Sigma-ring. En extern kartbild används
  endast i det separata manuella nadirretuschflödet och räknas inte som
  indata till den automatiska regressionen
- F: 6 originalbilder
- G: 13 originalbilder
- H: 6 originalbilder; ring och nadir

Materialet får vara handhållet eller taget med monopod eller stativ. Zenit
och nadir får också vara tagna med eller utan stativ. Tomma mappar hoppas över
tills de får källmaterial.

Varje regressionskörning skapar ett nytt projekt. Befintliga `.pw`-paket,
PTGui-projekt, referensrenderingar, masker och sparade kontrollpunkter används
inte som indata. PTGui-filerna är endast visuellt och geometriskt facit.

En förändring godkänns inte för att ett enskilt panorama eller ett aggregerat
felmått förbättras. Alla icke-tomma mappar ska kontrolleras, med följande
prioritet:

1. komplett och korrekt 360×180-täckning utan kollaps eller vikning,
2. sammanhängande statisk geometri och rimlig horisont,
3. automatisk hantering av ring, zenit och nadir,
4. skarvar minst i nivå med PTGui för samma rörliga bildmaterial,
5. därefter kontrollpunktsfel, täckning och punktantal som diagnostik.

Om PTGui också misslyckas med en vind- eller rörelseskarv är målet att inte
vara sämre; en låg RMS ensam räknas aldrig som ett godkänt panorama.
