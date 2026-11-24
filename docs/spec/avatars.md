# Avatars: pictures and initials

How Teams desktop picks the picture (and so the initials colour) for a
person, team or chat, and how OST does the same. Measured on winpc against
Teams 26276.513 on 2026-11-09; code references are to its bundles.

## People with a directory account

Teams draws no initials itself. Every person avatar is an `<img>` from the
middle tier's picture service, which returns the profile photo, or, when
there is none, an initials picture in the colour the service picks for
that person:

`GET {mt}/beta/users/{me}/profilepicturev2/8:orgid:{objectId}?displayname={name}&size=HR64`

(Teams' URL templates: `beta/users/{objectId}/profilepicturev2/{userId}?displayname=…`.)

OST asks the same service (`api::directory::photo`, `PhotoOwner::User`) at
`HR196x196` so the picture stays sharp up to the 144 px call stage.

## Meeting guests (no directory account)

A guest (`8:teamsvisitor:…`) has no object id. Teams asks for the initials
picture by name, which is how the same guest gets the same colour in every
client:

`GET {mt}/beta/users/defaultProfilePictureV2?displayname={name}&size=HR64`

(template: `beta/users/defaultProfilePictureV2?displayName={displayName}&shortenSingleWord={shortenSingleWord}&size={size}`;
Teams also falls back to it when a person's picture fails to load). Seen on
winpc in the meeting People pane and gallery: "OST Guest 1" is the
service's yellow.

OST: `photo_target` maps any `8:teamsvisitor:` id to `PhotoOwner::Named`,
fetched from `defaultProfilePictureV2` by display name.

## Teams and group chats

- Teams: `profilepicturev2/teams/{groupId}?displayName={name}` (the team's
  picture or its initials picture).
- A group chat without a picture: a grey (#949494) circle with the people
  glyph.
- A meeting's chat: a #C5CBFA circle with the 16 px calendar glyph in
  brand.

## When there is no picture at all

Only when nothing can be fetched (no name, offline, or the service has
nothing) does OST draw initials itself (Avatar.qml), in muted pairs close
to Teams' palette. Fluent's own colourful avatar (its `colorful` colour:
`palette[hash(idForColor ?? name) % 30]` over dark-red … anchor, Fluent's
`getHashCode`) is used by Teams only inside a few Fluent components, never
for people with a picture service entry.
