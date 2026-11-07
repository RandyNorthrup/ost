# Teams desktop parity references

These are the references OST is built and checked against. The goal is to work
exactly like the Teams desktop app for Windows, natively.

- `docs/spec/*.md`: exact behaviour, read from the Teams client's own code
  (module ids cited) and from the live Windows app (winpc, test account
  ost-test1). These are authoritative.
- `docs/parity/*.md`: feature inventories from Microsoft's documentation
  (Microsoft Learn and Microsoft Support; each item has its source).
  Use them as checklists of what exists. Where an inventory and a spec
  disagree, the spec wins.
- `winpc-diff.md`: first side-by-side notes. These are observations only,
  each superseded by the spec for its area.
