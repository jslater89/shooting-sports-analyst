# Booth Mode
Booth mode is a way to follow a match in a way that is useful while broadcasting it.
The design goal is to show sufficient information to understand the flow of a match
across multiple divisions, stages, and zones, in a concise and compact way.

## UI Sketch
The UI I have in mind looks kind of like this:

1. A small top banner with match information:
    * Time since last refresh
    * Time to next refresh (and 'refresh now' button)
        * Mouseover on countup/countdown values for the above two items
          will show the actual time.
    * Match completion percentage?
    * Ticker showing interesting events since the last update
        * New stage wins
        * Lead changes on scorecards
        * Performances much higher or lower than average
        * Click to highlight shooters in current scorecards, or add
          to existing ones.
2. The main data display: one or more panes showing scorecards.
    * A scorecard is what it sounds like: a golf-style scorecard, showing a summary
      of scores for a list of shooters on all stages.
        * The scorecard has an 'options' button in the corner that sets up its scoring
          filters and its display filters.
        * Scoring filters are the filters used to calculate scores. Typically going to
          be something like "Open division" or "Carry Optics+Lady".
        * Display filters are a little more complicated: either a list of shooters, and/or
          a squad (or several squads), xor a FilterSet filter.
        * Display-filtered competitors are shown as rows, with place/percent/HF scores in
          the box corresponding to each stage.
            * Mouseover shows hits and time?
        * New data is highlighted in some way.
        * Interesting data is highlighted in another way.
    * Scorecards can be arranged in rows and columns on the main screen, and named.
        * Pick some sensible minimum sizes, and stretch if a minimum-size grid fits on
          the screen.

## Data
Because being able to save and restore a particular set of booth mode views is important
for multi-day matches, the booth mode screen model should be JSON-serializable. The model
should contain information about the shape of the UI. In particular, the arrangement and
content of scorecards should be restorable.

Build as a provider/consumer model; the model can maybe be @JsonSerializable. It may be
possible for it to parcel out sub-providers, or for sub-providers to be used for things
like the top banner—relatively independent of the scorecard section, whereas any changes
to the match or the scorecard section will require redrawing the whole thing anyway.

(Oh hey, context.select is just the thing)

On reflection, maybe we build it right the first time? There's plenty of time before PCSL.
A booth mode view is a database object, and we save its matches to the DB with a special
source code and a timestamp in source IDs?

e.g.
sourceCode: 'booth', sourceIds: ['booth-projectname-20241206T1022', '20241206T1022|psv2|<ps-uuid>']

The booth mode model can handle refreshing the match.