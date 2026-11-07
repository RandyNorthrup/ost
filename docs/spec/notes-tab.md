# Channel Notes tab — Teams desktop behaviour (spec)

Sources:
- The OST Test Team General channel, provisioned by real Windows Teams on
  winpc on 2026-11-06 and then read back through Microsoft Graph.
- The channel's tab list from the middle tier (`GET {mt}/v1.0/channels/{thread}/tabs`).
- The Teams client's tab menu code (see channel-tabs.md).

## What the tab is
- A channel's Notes is a pinned tab in the middle tier's list:
  - `name: "Notes"`, `appId: 0d820ecd-def2-4297-adad-78056cde7c78` (OneNote).
  - `tabType: Configured`, `id: tab::<guid>`, order 10000.
  - `configuration.entityId: "NOTES"`.
  - `configuration.contentUrl`: `https://www.onenote.com/teams/ChannelNotes?ui={locale}&tenantId={tid}&upn={upn}&groupId={groupId}&theme={theme}&entityId={entityId}&subEntityId={subEntityId}&sessionId={sessionId}&ringId={ringId}&teamSiteUrl=…`
- Graph's `/teams/{id}/channels/{id}/tabs` also lists it, as app "OneNote".
- In the tab menu it is a `OneNoteTab`: About, Copy link, Reload and Expand
  are offered, and so is Remove with update rights. Rename is not
  offered for the OneNoteTab type, per channel-tabs.md.
  → Check this against Windows, which showed Rename for Notes; the tab may be typed `ExtensionTab` there.

## Backing data (Graph, verified)
- The notebook is the team's group notebook "`<Team name> Notebook`"
  (`isDefault: false`). It lives in the team site at
  `…/sites/<site>/SiteAssets/<Team name> Notebook`.
- Each channel has **one section named after the channel** ("General").
  It is created the first time the channel's Notes tab is opened; before
  that the group has no sections. Its id is `1-<guid>`. It sits
  directly under the notebook, not in a section group.
- While the section is being created, the tab shows "Please wait...the
  Notes tab will be ready soon." with the OneNote artwork and a spinner.
  That screen belongs to the OneNote service's page, not to Teams.
- Opening a new section shows an "Untitled Page" with today's date and
  time under its title. → Find out whether a page exists in Graph
  straight away. Listing the group's pages returned HTTP 500 (a Graph
  error on that endpoint). Use `/sections/{id}/pages` instead.

## Native implementation requirements
- **Provision**: if the team notebook has no section named after the
  channel, create it with `POST /groups/{g}/onenote/notebooks/{nb}/sections`
  (`displayName` = the channel name). If the team has no notebook,
  create "`<Team> Notebook`" first, the way Teams does. → Find out where
  Teams creates the notebook: in its site's SiteAssets, through Graph or
  SharePoint.
- **Editor**: page list (+ Add page, page titles, ordering), page
  title, date and time line, and the page body, read and written
  through the OneNote Graph API:
  - read: `GET /pages/{id}/content`;
  - create: `POST /sections/{id}/pages`, multipart HTML;
  - edit: `PATCH /pages/{id}/content` with append, insert, prepend or
    replace on `data-id` targets;
  - delete: `DELETE /pages/{id}`.
  → Get the exact editing capabilities and limits from the files and apps
  inventory (OneNote API docs).
- **Tab menu**: as channel-tabs.md, for type OneNoteTab.
