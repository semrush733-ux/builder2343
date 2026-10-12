### Emulator test (remote-control keys, mock IPTV server)

20 checks, 17 failed  - STOPPED after 28 minutes: the test ran far too slowly, the remaining steps were not run

```
PASS  app installs  [Performing Streamed Install
Success]
PASS  app starts on the sign-in screen
PASS  sign in with the remote opens the home screen
FAIL  Live TV shows categories and channels  [browse live items=5]
FAIL  channel 1 plays (.ts stream)  [not ready, position -1s]
FAIL  video picture is decoded
FAIL  live keeps playing for 25 s on a real-time stream without reconnecting  [position -1s, opened 0 time(s)]
FAIL  channel list and options open inside the live player
FAIL  the Quality button lists the other version of the channel
FAIL  channel change + fallback to the second stream format  [not ready, position -1s]
FAIL  a channel can be picked from the list in the player  [not ready, position -1s]
FAIL  dead channel ends with a message instead of hanging
FAIL  holding OK adds a favourite
FAIL  search finds the channel
FAIL  Favourites lists the saved channel
FAIL  Movies shows categories and titles
FAIL  the movie details page shows plot, cast and trailer from the server
FAIL  cast photos and stills are added from the film database
FAIL  movie plays  [position -1s]
FAIL  the whole test finishes in time
```
