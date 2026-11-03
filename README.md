# Tripod Invasion – iPhone 13 Pro, första iOS-testversionen

Native Swift/ARKit-projekt för personlig installation, utan betalt Apple Developer-konto.
Detta är en separat port under utveckling. Android-APK:n konverteras inte till IPA.

## Vad som finns i källkoden

- Kamerabild via ARKit/SceneKit, stående kompakt svenskt gränssnitt.
- Tre minuters runda, fyra slumpade tripoder 100–300 meter bort, tre liv och omspelning.
- Tre ben, separat huvud/sökljus, två laserarmar som används växelvis.
- Synkägla 28 meter, tre sekunder till upptäckt, senaste kända position och lokal ljudnivåmätning.
- LiDAR-djup med konfidensfilter bygger tillfälliga skydd; dålig spårning pausar tid och skada.
- Pistol från start, andra vapen/förråd, ammunition, omladdning, hölstring och framtagning.
- 30 laddade och 300 reserv per nytt vapen, max 1 000 reserv per vapen, 20 procent ammunition per förrådsplats.
- Lådor höjdjusteras mot kartlagda markytor. AR-mesh skymmer virtuella modeller.

## Begränsningar för denna första port

Den är ännu inte likvärdig med Android-versionen. Satellitbilder/GPS, ljuddesign,
kamerans mörkerförstärkning, långdistansåterställning och fullständiga fångst-/explosionseffekter
är inte porterade. Mikrofonens ekosläckning och ljudnivå behöver fysisk testning.
Grundlogiken för fångst, granater och tramp finns, men presentationen är enklare.
LiDAR ersätter inte kamerans behov av synliga detaljer för positionsspårning.

## Gratis byggning från Windows

1. Använd ett **separat offentligt GitHub-repo** med endast innehållet i denna mapp.
   Ladda inte upp hela Android-arbetsmappen, `.local`, signeringsnycklar eller kontouppgifter.
2. GitHub Actions → **Build iPhone IPA** → Run workflow.
3. Standardrunnern `macos-latest` kompilerar och kör `swift test` innan IPA:n paketeras.
   Workflowen vägrar privata repos för att undvika privat macOS-förbrukning.
4. Öppna projektets Releases och hämta den senaste `Tripod-Invasion-iPhone-unsigned.ipa`.
5. IPA-filen är **osignerad**.
   Den kan inte installeras genom att bara öppnas i Safari.

Standardbyggminuter för offentliga repos är kostnadsfria enligt GitHubs villkor.
IPA-filen publiceras som en prerelease-fil i samma repo. GitHub Releases har ingen
sammanlagd storleks- eller bandbreddsgräns enligt dokumentationen. Flödet använder
ingen Actions-artifactlagring, cache, betald större runner eller betald tjänst.
Aktivera inte betald förbrukning för detta projekt.

## Installation med AltStore Classic på Windows

Använd **AltStore Classic + AltServer**, inte AltStore PAL.

1. Följ den officiella Windows-guiden för iTunes/iCloud och AltServer.
2. Anslut iPhone med kabel, lås upp och välj Lita på datorn.
3. Installera AltStore med ditt eget Apple-konto i AltServer.
   Skriv inte Apple-lösenord, engångskoder eller certifikat i GitHub.
4. Aktivera Utvecklarläge om iOS ber om det och lita på utvecklarprofilen.
5. I AltStore → My Apps → +, välj den osignerade IPA-filen.
   AltStore signerar med ditt personliga konto och installerar den.
6. Tillåt kamera och, om du vill, mikrofon. Starta på en öppen plats.
7. Med gratis Apple-konto gäller signeringen ungefär sju dagar; förnya med AltServer.
   Apple begränsar även antalet samtidigt sideloadade appar.

Ingen automatisk Windows-installation eller kontoinloggning ingår i källpaketet.

## Lokal Mac, om en blir tillgänglig

Installera Xcode och XcodeGen. Kör `xcodegen generate`, öppna `TripodInvasion.xcodeproj`,
välj din Personal Team under Signing & Capabilities och din iPhone som mål. Kör appen.
Inget Apple-konto behövs för själva osignerade molnkompileringen.

## Verifiering

Windows kan kontrollera filstruktur och paketering men inte kompilera ARKit mot iPhone SDK.
`swift test` och `xcodebuild` måste godkännas på macOS innan en IPA kallas byggkontrollerad.
En grön molnbyggning bevisar inte att kameran, mikrofonen, LiDAR eller spelbalansen fungerar
på en riktig iPhone 13 Pro. Resultatet måste rapporteras separat efter enhetstestning.

## Officiella källor

- https://docs.github.com/en/billing/concepts/product-billing/github-actions
- https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- https://developer.apple.com/help/account/basics/about-your-developer-account/
- https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
- https://developer.apple.com/documentation/arkit/arscnview

## Innehåll och rättigheter

Tripod- och vapengeometri genereras av projektets egen kod. Inga filmstillbilder,
filmklipp, kommersiella ljudfiler eller användarens referensbilder ligger i paketet.
Ingen öppen källkodslicens väljs automatiskt; ägaren kan välja licens separat.
