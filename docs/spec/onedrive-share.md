# OneDrive's share dialog (Teams: Share outside Teams, Files' Share)

Teams opens OneDrive's own share dialog (`{site}/_layouts/15/sharedialog.aspx?clientId=teams`)
in a frame for a file's "Share outside Teams" (from Teams' "Share this file" ···), and its
Files app's Share. OST draws the same dialog natively and talks to the same SharePoint REST
service with a SharePoint token minted from OST's refresh token
(`auth::oauth::access_token_for("{host}/.default")`).

Measured on winpc 2026-11-11 (Teams 26288, OneDrive web `odsp-web-prod_2026-10-30.006`),
1280 x 720 CSS px. All sizes in CSS px; colours as Teams draws them.

## The service

Every call is `{site}/_api/web/lists/getbyid(@a1)/GetItemByUniqueId(@a2)/<Method>?@a1='{list}'&@a2='{item}'`
with `accept` / `content-type: application/json;odata=verbose`. The file's site, list and item
come from the search result (`SpWebUrl`/`SiteName`, `ListId`, `UniqueId`).

| Action | Method | Body |
|---|---|---|
| Open / refresh | `GetSharingInformation?$Expand=pickerSettings,permissionsInformation,sharingLinkTemplates` | `{"request":{"maxPrincipalsToReturn":100,"maxLinkMembersToReturn":100}}` |
| People picker | `{site}/_api/SP.UI.ApplicationPages.ClientPeoplePickerWebServiceInterface.ClientPeoplePickerSearchUser` | `{"queryParams":{"QueryString":q,"MaximumEntitySuggestions":30,"AllowEmailAddresses":true,"PrincipalType":13,"PrincipalSource":15,"UseSubstrateSearch":true,"QuerySettings":{"__metadata":{"type":"SP.UI.ApplicationPages.PeoplePickerQuerySettings"},"ExcludeAllUsersOnTenantClaim":false,"IsSharing":true}}}` (one per keystroke; the reply's `ClientPeoplePickerSearchUser` is a JSON string of entities) |
| Send | `ShareObject` | `{"peoplePickerInput":"[<picked entities>]","roleValue":"role:1073741827" (edit) / "role:1073741826" (view),"sendEmail":true,"emailBody":msg,"includeAnonymousLinkInEmail":false,"propagateAcl":true,"useSimplifiedRoles":true}` |
| Copy link (a new link) | `ShareLink` | `{"request":{"createLink":true,"settings":{"allowAnonymousAccess":scope==0,"linkKind":k,"expiration":null or ISO,"role":1 view / 2 edit,"restrictShareMembership":false,"updatePassword":false,"password":"","scope":s,"nav":""}}}`; the reply's `ShareLink.sharingLinkInfo.Url` is copied |
| Copy link (existing access) | none | copies `directUrl` from GetSharingInformation |
| Change a person's role | `UpdateDocumentSharingInfo` | `{"userRoleAssignments":[{"UserId":login,"Role":2 edit / 1 view / 0 remove}],"validateExistingPermissions":false,"additiveMode":false,"sendServerManagedNotification":false,"customMessage":null,"includeAnonymousLinksInNotification":false,"propagateAcl":true}` |
| Delete a link | `UnshareLink` | `{"linkKind":k,"shareId":id}` |
| Stop sharing | `UnshareObject` (Teams addresses it by `Lists(@a1)/GetItemById(@a2)`; OST by the unique id, which SharePoint accepts the same) | `{"url":"<the library's address>"}` (OST reads it from `lists(guid'…')/RootFolder`) |

Scopes: 0 Anyone, 1 the organisation, 2 specific people ("People you choose"); "Only people
with existing access" makes no link. Link kinds (SharePoint's SharingLinkKind): 2 org view,
3 org edit, 4 anyone view, 5 anyone edit, 6 specific people ("Flexible", its role in
`role`). Send's roles are SharePoint's Reader (`role:1073741826`, captured) and Contributor
(`role:1073741827`). The defaults come from
`defaultShareLinkScope` (0) / `defaultShareLinkPermission` (2 edit) /
`defaultShareLinkToExistingAccess`; the organisation's name from `tenantDisplayName`.

Who has access (Manage Access ▸ People): `permissionsInformation.siteAdmins` (role 3,
"Owner"), `principals` (direct access, role 2 "Can edit" / 1 "Can view") and each active
link's `linkMembers` (with the link's role). Links: `permissionsInformation.links` whose
`linkDetails.Url` is set (`IsEditLink`, `AllowsAnonymousAccess`, `LinkKind`, `ShareId`,
`Expiration`, `RequiresPassword`, `BlocksDownload`).

## Main view (480 wide, radius 8, padding 24, centred)

- Title `Share "<name>"` 20/600 #252424 at 24, 26.67 (356 wide; the name shortened in the
  middle: `ost-attachm...nt-test.txt`). Help (30 x 32) at 389, 24 and Close (32 x 32) at 424,
  24, 14 px glyphs #605E5C.
- Recipients box at 24, 66: 432 x 44, 0.67 #C8C8C8 border, radius 4; a 17 x 12 person glyph at
  12.67, 16; the input (14 px, "Add a name, group, or email") at 35.67; a 1 x 36.67 #D1D1D1
  divider at 362.33; the role button (68 wide) with a 16 px pencil (Can edit) or eye (Can view)
  and a 12 px chevron. Focused: a 2 px #5B5FC7 underline. Picked people become 28 px pills
  (#F3F2F1, radius 16: 28 px avatar, the name 14/20, a 32 x 28 dismiss in #5B5FC7) and the
  input moves under them ("Add more"); the box grows to 77.
- Suggestions under the box (432 wide): rows of 54 with a 40 px avatar at 12 and the name
  14/20 at 60; "Search directory" (12 px, a search glyph) at the bottom, 40 tall.
- Role menu (under the role button, right-aligned, 182 wide): "Can edit / Make any changes"
  and "Can view / Can't make changes", 52 tall each: a 12 px check at 8, the 16 px glyph at 32,
  the name 14/20 600 and the line 12/16 #605E5C at 60.
- Message box at 24, 122 (12 under the recipients): 432 x 105.67, 0.67 #C8C8C8, radius 4; a
  pencil-note glyph at 13, 13; the text (14/20, "Add a message", padding 10 8 6) at 27.67.
- Footer at y 261.67 (24 under the message): Manage access — the people with access as 20 px
  avatars 14 apart (24 px with a 2 px white ring) — at 24; Copy link (116.63 x 33.33, #F4F4F9,
  0.67 #696BAA, radius 4 0 0 4, link glyph and "Copy link" 14/600 #383966) at 199.71; Link
  settings (32.67 wide, a 15 px gear #5B5FC7, radius 0 4 4 0) beside it; Send (95 x 33.33,
  #5B5FC7, radius 3, white 14/600 with a send glyph) at 361. The dialog ends 24 under.
- After Copy link: a 432 x 31.33 #DFF6DD bar 12 under the footer: a green check, "Link
  copied." (600) and what the link does ("People with existing access can use the link.",
  "People in your organization with the link can view.", "Anyone with the link can edit.").
- After Send: "You've invited <names> to <edit|view>" over `"<name>"` (20/26 600, centred,
  middle-shortened) and the 40 px avatars of who was invited (Manage access), with Close.

From the Files app (Teams' OneDrive and channel Files) the form also has a ··· by Help with
"Send link in Outlook"; OST leaves it out until it can compose that mail. A file only its
owners have shows a 32 px grey lock instead of the avatars.

## Link settings (Copy link's gear)

- Back (32) at 24, 30.67; "Link settings" 20/600 at 65, 24 over the file name (14 px); Learn
  more (32) at 387 and Close at 424.
- "The link works for" (14/600) at 93.33, then four rows 48.67 apart (432 wide, a 0.67 white
  rule between): a 24 px round badge at 0 (Anyone: #F1F6F1 / #0B6A0B globe; the organisation:
  #F0F5F8 / #004E8C briefcase; Only people with existing access: #F4EFEB / #8E562E person;
  People you choose: #F2F2F2 / #393939 person-add), the name at 40 (14 px), an info glyph
  after it, and a 20 px radio at the right. The chosen row's name turns 14/700 #575454 with a
  12 px #605E5C line under it (and the info glyph goes): "Share with anyone, doesn't require
  sign-in"; "Share with people in <org>, organization account required."; "Reshare with
  people in your organization who already have access."; "Share with specific people you
  choose inside or outside of <org>, using their name, group, or email." Long organisation
  names are shortened in the middle ("Secure Coast...rk Solutions").
- "More settings" (14/600, 24 above, 8 below) — not for existing access: the role (42 tall,
  pencil / eye and "Can edit" / "Can view", a chevron; its list repeats the role menu 432
  wide), then "Set expiration date (MM/DD/YYYY)" with a calendar glyph and a clear ×, then
  (Anyone only) "Set password" with a lock glyph; each field has a 0.67 #F3F2F1 underline.
- Apply (96 x 32, #5B5FC7, radius 3) at the bottom right, 24 under the last row.

## Manage Access

- Back, "Manage Access" (20/600) at 65, Grant Access (person-add) and Close; the file's
  16 px icon and name (14 px) at 24, 62; "Stop sharing" (a minus-circle glyph, #5B5FC7) under.
- Tabs "People • n", "Groups", "Links • n" (14 px; the chosen one 600 with a 3 px #5B5FC7
  bar), 44 tall.
- People: "Search displayed names" (a search glyph, underlined), then rows of 88: a 48 px
  avatar, the name (16 px), and at the right "Owner" or the role ("Can edit" with a pencil,
  "Can view" with an eye), which opens the person's Access summary.
- Groups: "This file has not been shared with a group yet. Learn more" and "+ Share with a
  group" (#5B5FC7).
- Links: per link a 48 px badge (as above), the link in a read-only box with Copy, a gear
  (More link options) and a bin (Remove link), and "Anyone with the link can edit" / "People in
  <org> with the link can view" under it. None: "A sharing link hasn't been created for this
  file yet. Create a new link to start sharing with others." and "+ Create and share a new
  link".
- Access summary (a person's role): "Access summary" (14/600, info glyph), the person (48 px)
  "<name> can view" (20 px, the role 600), "Ways this person has access", and per way a
  collapsible "Direct Access: can view" whose radios are Can edit / Can view / No direct
  access ("Direct Access grants access permissions without the use of a link"); Apply and
  Cancel. No direct access asks "Want to remove <name>'s direct access?" ("They may still
  have access to this item through a group or link.") with Remove / Cancel.
- Stop sharing asks "Stop sharing?" ("Only owners of this item will still have access.") with
  Stop sharing / Cancel. Afterwards (and for any file only its owners have) Manage Access drops
  Stop sharing and the name search: the owners, then "This file has not been shared with anyone
  yet." and "+ Start sharing".
- A person's ways of access list their links first — "Anyone with this link: can edit"
  (600), opening to the link's badge, address, Copy, its settings and "How do I modify this
  link?" — then "Direct Access: none"; when a link already gives them access, Direct Access
  explains "Grant access is not available because this person can already edit this item."
  over greyed Can edit / Can view. (The wording for organisation and specific-people links
  follows the Anyone one; not yet seen in Teams.)
- Remove link asks "Delete link?" ("The link will not work for anyone anymore.") with
  Remove / Cancel.
