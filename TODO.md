1. Connectedness
* Start with 100 connectedness.
* When you shoot with someone, gain 1% of (their connectedness - 1% of your connectedness)—i.e.,
  the part of their connectedness that isn't coming from you.
* Only the last N shooters you shoot with count.
* If you shoot with someone again while they're still on your list, move them to the front
  and update the amount gained to account for any changes in their connectedness.

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
2. Project Improved Projects