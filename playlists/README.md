# despotlistback

* http://rjp.github.com/spotify-stuff/

## DESCRIPTION

Use despotify-gateway to backup your Spotify playlists into XSPF files.

## REQUIREMENTS

* A running despotify-gateway
* A premium Spotify account

## INSTALL

    gem install despotlistback

## PLAYLIST FILE NAMING OPTIONS

    %u => Username of the current session
    %c => Owner of the playlist
    %w => "username:owner" if they differ, else "username"
    %i => Hex variant of the playlist ID
    %s => Number of tracks in the playlist
    %d => "subscribed/" if username and owner differ, else blank
    %n => Sanitised version of the playlist name

## LICENSE

(Working on it.)

Copyright (c) 2012 rjp, andym
