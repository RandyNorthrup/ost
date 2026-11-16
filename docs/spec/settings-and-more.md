# Settings and more (title bar ···)

Measured on winpc on 2026-11-15, with ost-test1 on Teams Public Preview.

## The menu

- **Popover.** 238.47 wide, centred under the ··· button and 8 below it. Radius 4, padding 4, 0.67 transparent border, the depth-16 shadow.
- **Rows.** 32 tall and 2 apart, radius 4.
  - A 20 px icon sits 6 in, and the label (14/20, #424242) at 30.
  - Shortcuts (12/16, #616161) are right-aligned 8 in.
  - Dividers (#E0E0E0, 0.67) run across the whole popover, with 4 above and below.
- **Items in order:**
  1. Unlock Teams Premium (premium)
  2. divider
  3. Pin window on top (Ctrl+Shift+T)
  4. Settings (Ctrl+,)
  5. Cast (cast)
  6. Downloads (arrow-download)
  7. divider
  8. Zoom row
  9. divider
  10. Help (F1)
  11. Feedback ›
  12. Keyboard shortcuts (Ctrl+.)
  13. Get the mobile app (phone; label at 32), followed by the "New" pill (36.66 × 20, 12 semibold, white on #5B5FC7, fully round)
- **Zoom row.** 27.33 tall. "Zoom" sits 8 in. On the right, 8 apart and 8 from the edge: Zoom out (subtract), "(100)%", Zoom in (add) and Reset (page-fit). The buttons are 24 × 23.33.

## Zoom

- From 60% to 400% in 5% steps. Reset goes back to 100%. Ctrl+- zooms out and Ctrl+0 resets; Teams documents Ctrl+= for zoom in.
- The whole window scales, menus and dialogs included.
- OST does this by scaling the window's root item and laying it out at the window size divided by the zoom. The level is kept in the setting `zoomPercent`.

## Unlock Teams Premium

- **When it shows.** While Teams Premium's low-friction trial can be started. Teams checks this through its auth service:
  - `GET https://teams.microsoft.com/api/authsvc/v1.0/lfts/TeamsPremium/policies/selfserve` returns `{"PolicyValue":0}`, where 0 is ENABLED, 1 ONLY_TRIALS_WITHOUT_PAYMENT_METHOD and 2 DISABLED.
  - `GET …/eligibility/` returns `{"lowFrictionEntityDetails":null,"ineligibilityReason":null}`.
  - Both calls use the api.spaces.skype.com token.
- **Dialog layout.** 600 × 600, centred.
  - **Top:** the header picture (600 × 128) with Close (32 × 31.33, white at 50%, 24 in). The diamond (68) sits in a 108 px badge (a white to #C6B1DE gradient at 136°) at 74.
  - **Title:** "Start your free Teams Premium trial" (24/32 bold, #242424), centred at 197.
  - **Features:** More protected, More engaging and More intelligent. Each has a 52 px picture at 110 and a title (14 semibold) with text (12/16, #616161) at 177, 313 wide, at y 244, 311 and 378.
  - **Notes:** "Free 60-day trial, no card required." (12/20) and the "Microsoft Teams Trial Terms & Conditions." link (fwlink 2194722), centred at 460 and 480.
  - **Buttons:** "View all benefits" (subtle, fwlink 2227979) 24 in, and Start trial (primary, 96) 24 from the right, both at 544.67.
- **Start trial.** `POST …/acquire/` with `{}`, sending Prefer `exchange.behavior="ApplicationData,SubstrateFiles"` and ScenarioTag `acquireLowFrictionTrialLicense`.
  - Teams' strings for the steps: "Getting your trial ready...", "Your Teams Premium trial is now active!" with Got it, and "We ran into a problem setting up your trial. Let's try again." with Try again.
  - The layout of those steps isn't measured, because no trial was started on the test accounts.

## Cast

- **Window.** 626 × 713, always dark, under the child-window title row ("Cast").
  - A #292929 band (60 tall) holds the brand tile (32 px, #4F52B2, radius 4, with a white 20 px cast glyph) 20 in, and "Cast" (16.38/23.4 bold, white) at 64.
  - The body is #1F1F1F. "Select a nearby Teams Room" (16/22) is centred at 104 and the status line (14/20) at 141.
  - Next (96 × 32) sits 52 from the right and 20.33 from the bottom. It stays disabled until a room is picked.
- **Search.** "Searching for nearby Teams Rooms..." for about 20 s (measured 20.3 s), then "Didn't find any Teams Rooms nearby that we can cast to."
- Teams finds rooms by their proximity beacons. There is no Teams Rooms device here.

## Downloads

- **What it is.** Teams shows WebView2's own downloads hub (`edge://downloads-hub/`), a 360-wide flyout 13.33 from the window's right and 12 under the title bar.
- **Header.**
  - "Downloads" (16 semibold), labelled "Open downloads page".
  - Then 32 px buttons from x 216, 36 apart: Open downloads folder, Search downloads, More options (one item: "Clear all download history") and Close.
- **Rows.** Each download is 344 wide, 8 in and 4 apart.
  - The file's icon (20) and its name (14/20, up to 2 lines) come first, then "Open file" (12/16, #235CCF).
  - A file that is gone shows its name struck through and "Removed" (12/16, 56% black).
  - On hover: Open containing folder and Delete file (24 px).
- **Empty:** "When you download files from the web, they'll show up here." (14/20, 20 in); the hub is then 126 tall.
- **Search:** Back plus a "Search all files" box.
- **Clearing** asks "Remove all download history?" with "You can still get to the files from the downloads folder.", Remove all (#2169EB) and Cancel.
- **In OST:** the list is OST's own downloads (`api::downloads`, in `$XDG_STATE_HOME/ost/downloads.json`). Open containing folder uses the desktop file manager's ShowItems.

## Get the mobile app

- 600 wide, padding 24.67, centred.
- "Get the Teams mobile app" (16/22 bold), centred, with Close at the right.
- "Scan the code below with your mobile camera or with a QR reader app." (14/20).
- Teams' QR code (from its CDN) sits in a 160 px card (radius 32, depth-4 shadow).
- Below it, the App Store and Google Play badges (100 × 30, 8 apart) open aka.ms/iosteams and aka.ms/androidteams.
