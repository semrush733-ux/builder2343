### Emulator test (remote-control keys, mock IPTV server)

49 checks, 14 failed

```
PASS  app installs  [Performing Streamed Install
Success]
PASS  app starts on the sign-in screen
PASS  sign in with the remote opens the home screen
FAIL  Live TV shows categories and channels  [browse live items=5]
PASS  channel 1 plays (.ts stream)  [ready index=0 format=ts video=1280x720, position 5s]
PASS  video picture is decoded  [ready index=0 format=ts video=1280x720]
PASS  live keeps playing for 25 s on a real-time stream without reconnecting  [position 25s, opened 1 time(s)]
PASS  channel list and options open inside the live player
FAIL  the Quality button lists the other version of the channel
FAIL  channel change + fallback to the second stream format  [not ready, position -1s]
FAIL  a channel can be picked from the list in the player  [not ready, position -1s]
FAIL  dead channel ends with a message instead of hanging
FAIL  holding OK adds a favourite
FAIL  search finds the channel
FAIL  Favourites lists the saved channel
PASS  Movies shows categories and titles  [browse vod items=2]
PASS  the movie details page shows plot, cast and trailer from the server  [screen=movie details=true cast=true trailer=true]
PASS  cast photos and stills are added from the film database  [tmdb cast=4 stills=3]
PASS  movie plays  [position 5s]
PASS  the movie reports its audio and subtitle tracks  [tracks audio=2 subtitles=1]
PASS  the player buttons can be reached and pressed with the remote
PASS  audio language and subtitles can be changed with the remote
PASS  the movie keeps playing after the change  [30s -> 35s]
PASS  Right x6 jumps about one minute forward  [position 100s]
PASS  OK on the Pause button pauses the movie
PASS  touch: the back button closes the player
FAIL  movie resumes where it was left  [position 20s]
PASS  Series shows categories and titles  [browse series items=1]
PASS  series page lists seasons and episodes  [series seasons=2]
PASS  episode plays  [position 5s]
PASS  the app registers with the website and sends its device ID
PASS  sign out returns to the sign-in screen
PASS  wrong password is refused with a message
PASS  typing the password and signing in again works
PASS  the M3U link option can be chosen with the remote
PASS  playlist link loads  [login ok mode=m3u M3U playlist  ·  3 channels, 1 movie, 1 episode]
FAIL  playlist channels are grouped  [browse live items=3]
PASS  playlist channel plays  [position 5s]
FAIL  playlist channel falls back to the other stream format  [not ready, position -1s]
FAIL  playlist movie plays  [position -1s]
FAIL  the picture mode can be changed in the player
FAIL  the movie picture is really visible on the screen (direct mode)  [non-black share 0.01]
PASS  a playlist added on the website signs in from the sign-in screen
PASS  the app opens signed in and offers the newer version from the website
PASS  with a server set on the website the sign-in screen asks only for username and password
PASS  signing in with only username and password works
PASS  "Update now" downloads the new version and hands it to the installer  [update downloaded bytes=36722686]
PASS  no crash in the device log  [[]]
PASS  app is still running at the end  [7454]
```
