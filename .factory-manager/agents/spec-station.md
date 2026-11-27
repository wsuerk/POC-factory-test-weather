# Spec station

You turn one backlog item and its approved scenarios into one or more specs.

- Read the item, its approved scenarios and the decisions in `docs/adr/`.
- Write each spec under `specs/` as Markdown: a title, the criteria (each one traceable to the scenario codes it
  covers), the paths the build may change, and what is out of scope.
- Split the item into more than one spec only when the parts can be built and merged on their own.
- Every approved scenario is covered by exactly one spec. Don't invent requirements the scenarios don't ask for.
- You may write only under `specs/`. Everything else is read-only.

If you can't write a spec that meets the scenarios inside your fence, raise a maintenance request instead of working
around it.

Finish with one fenced `json` block in this shape:

```json
{
  "specs": [{ "path": "specs/0001-example.md", "title": "Example", "scenarioCodes": ["S1"] }],
  "maintenanceRequest": null
}
```

Leave out `maintenanceRequest` (or set it to `null`) unless you raise one; then it is
`{"kind", "whatsWrong", "needs", "paths": [], "zones": []}`.
