The Rubysaver
=============

Features
--------

Works as Xscreensaver module. Shows current weather, forecast and tomorrow forecast. Shows clock. If your mpris.MediaPlayer2 compatible player (most of popular players) is playing, shows current track title and performer.

After sunset can display all darker (default) to disturb you less. If you don't want it, set weather_image_alpha and weather_image_noalpha to same value (e.g. 255.0).

Screenshots
-----------

![rus](rubysaver-ru.png)
![eng](rubysaver-eng.png)

Pre-requisites
--------------

- Ruby 1.9.1+
- ruby gems: gtk2, dbus
- xscreensaver or compatible

You can install them via packages. E.g. for debian/ubuntu: `apt-get install ruby ruby-gtk2 ruby-dbus`

Or you can install rbenv (`curl https://raw.githubusercontent.com/fesplugas/rbenv-installer/master/bin/rbenv-installer | bash`), then
install ruby (e.g. 2.2.0: `rbenv install 2.2.0; rbenv global 2.2.0`), and gems: `gem install gtk2; gem install dbus; gem install rcairo`.

Get your api key for DarkSky service (it is free): https://darksky.net/dev/register

Installing
----------

Just `mkdir /opt/rubysaver` (you can choose another directory), then copy rs.rb, rs.sh and apixu-weather there:
`cp -r rs.* apixu-weather /opt/rubysaver`. Make rs.rb and rs.sh executable: `chmod a+x /opt/rubysaver/rs.*`.
Edit /opt/rubysaver/rs.sh, fill in path to your homedir and change USE_RBENV to '0' if you dont use rbenv.
Go to `/opt/rubysaver` and execute `bundle install`, if you are using rbenv.

Copy rubysaver.conf-example to ~/.config/rubysaver.conf, and fill your localtion, e.g.:

```
place: Tokyo,JP
```

NB! Current version is using DarkSky service, which cannot use place name, only Latitude and Longitude.
To get your lat/long, go here https://www.latlong.net/ and find out your coordinates. Then fill them:

```
lat: 12.34567
long: -23.45678
```

Fill in your DarkSky api key:

```
dark_sky_key: 123abc456def789
```

If you prefer, change your language. Please, note, you should change TWO lines:

```
lang: English
lang_code: en
```

Edit ~/.xscreensaver, find line 'programs:' and put exactly after it: `/opt/rubysaver/rs.sh \n\`. Modify lines:

```
mode:           one
selected:       0
```

That's all! Just lock your screen or start xscreensaver. If you're using xscreensaver compatible saver,
specify /opt/rubysaver/rs.sh as active module.


Customizing
-----------

You can change many options in ~/.config/rubysaver.conf: (yaml format)

```
# path to icons
icon_path: /opt/rubysaver/apixu-weather
# name for weather font
font_face: Sans Serif
# weight for weather font
font_weight: bold
# font size for forecasts
weather_font_size: 20
# font size for current weather
weather_big_font_size: 38
# font name for clock
font_face_clock: Sans Serif
# font weight for clock
font_weight_clock: ultrabold
# font size for clock
weather_clock_font_size: 42
# font name for 'now playing' string. Use ONLY monosized fonts!
font_face_play: Mono
# font weight for 'now playing' string
font_weight_play: normal
# font size for 'now playing' string
play_font_size: 40
# font size for 'updated at...'
yahoo_font_size: 8

# alpha level for tinted image (after sunset)
weather_image_alpha: 100.0
# alpha level for normal image (after sunrise)
weather_image_noalpha: 255.0
# speed of sliding in x and y direction
xspeed: 2
yspeed: 2

place: Europe,Moscow
lat: 55.751244
long: 37.618423

# NOT WORKS NOW. Your place (see Yahoo!Weather)
place: Tokyo,JP
# Was actual for Yahoo weather, now is just for legacy
place_index: 1
# Change these two lines accordongly!
lang: english
lang_code: en

# speed of 'now playing' scrolling
np_speed: 5
# maximum 'now playing' string length
max_play_len: 48
# weather update interval in seconds. Don't ask Yahoo often!
update_interval: 1200
# weather update interval in seconds if last update failed
update_interval: 120
# sunrise time, if yahoo didn't say it
min_tint_hour: 6
# sunset time, if yahoo didn't say it
max_tint_hour: 22

# background color red 0..255 (default 0)
bg_red: 0
# background color green 0..255 (default 0)
bg_green: 0
# background color blue 0..255 (default 0)
bg_blue: 0

# if 1, then do not move image, just center it
stop_mode: 0

# if 1, use fahrenheight instead of celsius
use_fahr: 0

```

