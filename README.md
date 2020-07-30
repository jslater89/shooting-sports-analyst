# USPSA Match Results Viewer

A web application for viewing USPSA match results, usable standalone at
[github.io](https://jslater89.github.io/uspsa-result-viewer), or embedded
into an iframe.

## Embedding

See [this example file](https://github.com/jslater89/uspsa-result-viewer/blob/master/embedded-index.html).

If embedding, it's best to host your own results file and link to that, rather
than linking to the PractiScore page. The PractiScore page scraper uses a free
Heroku service to serve as a CORS proxy, and as a free Heroku service, it takes
several seconds to start up if it hasn't been used in the last half hour.  

## Known Issues

* May not match PractiScore precisely on DQed shooters.

## Contributions

Open a pull request.

## Future Features

* 'What-If' editing.
* Simple query language for search box ("open AND d OR limited AND c").
