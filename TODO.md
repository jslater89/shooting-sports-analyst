1. Connectedness
* Start with 100 connectedness.
* When you shoot with someone, gain 1% of (their connectedness - 1% of your connectedness)—i.e.,
  the part of their connectedness that isn't coming from you.
* Only the last N shooters you shoot with count.
* If you shoot with someone again while they're still on your list, move them to the front
  and update the amount gained to account for any changes in their connectedness.
1.1. Improved connectedness?
* Currently the slowest part of the rating algorithm. Some way to update everyone in one shot
without having to iterate over their connected shooters would be great.
* Or even just a more meaningful measure, like number of competitors you've shot against since time
X?

3. Option to require minimum N stages for display
4. Improve speed of deduplication

6. Fetch matches by club since date (maybe?)

7. Database!
* Isar? SQLite?
* The main goal, at this time, is to save ratings and later load them, so that large datasets
like the L2+ set aren't quite such a pain to use, with the recalculating every time.
* A future goal is to be able to lazily load ratings/histories from a database, to limit
memory pressure.
* Isar has speed on its side, it looks like.
* SQLite allows exporting the data in a format anyone who knows SQL can analyze, which is
community-focused.
* Let's do SQLite.

7.1. Preliminary work
1. Floor serializers/deserializers for everything.
    * alison-brie-everything.gif
    * Matches and related infrastructure, rating objects
    * DB value objects to convert to/from app objects
        * This also lets me JSONify them, in pursuit of Project Firehose
        * App objects 100% are not set up to be serialized
    * Schema/schemata
        * One big DB, or DBs per project with just the matches they need?
        * I'll want a way to export full project databases anyway, so I think I
        need to go with DBs per project.
            * Also saves me having to redo the match cache, for now.
2. Project Improved Projects

7.2 1/1/23 DB update
    *