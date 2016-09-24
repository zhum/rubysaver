#!/usr/bin/ruby
# encoding: UTF-8

require 'gtk2'
require 'dbus'
require 'json'
require 'net/https'
require 'yaml'

SIGNAL_DRAW="expose_event"

# for gtk3
#SIGNAL_DRAW="draw"

DEF_IMG_PATH="/opt/rubysaver/iconsbest.com-icons/"
NA_IMAGE=50
TMOUT=100
X_SPEED=2
Y_SPEED=2
NP_SPEED=5
MAX_PLAY_LENGTH=48

$weather=nil
$drawing_area=nil

class RubyApp < Gtk::Window

  def initialize
    super
    
    set_title "Xscreensaver module"
    signal_connect "destroy" do 
      Gtk.main_quit 
    end


    init_ui
    realize

    ident = ENV['XSCREENSAVER_WINDOW']
    #warn "ident=#{ident}"
    if not ident.nil?
      self.window=Gdk::Window.foreign_new(ident.to_i(16))
      self.window.set_events (Gdk::Event::EXPOSURE_MASK | Gdk::Event::STRUCTURE_MASK)
      #warn "win=#{self.window}"
    end
    x, y, width, height, depth = window.geometry

    set_default_size width, height
    set_window_position :center

    show_all
  end

  def init_ui

    $drawing_area = @darea = Gtk::DrawingArea.new  
    @darea.signal_connect SIGNAL_DRAW do |widget,event|
      on_draw widget
    end

    add @darea 
  end

  def on_draw widget
    cr = widget.window.create_cairo_context

    do_draw cr, widget
  end

  def do_draw cr, widget
    x, y, width, height, depth = window.geometry
    #cr.save do
    #  cr.set_source_color(@bg_colour)
    #  cr.gdk_rectangle(Gdk::Rectangle.new(0, 0, width, height))
    #  cr.fill
    #end

    unless $weather.nil?
      $weather.draw_weather cr, width, height
    end

  end
end



class Weather

  DEF_CONF={
    'icon_path'=>DEF_IMG_PATH,
    'weather_font_size'=>20,
    'weather_big_font_size'=>38,
    'weather_clock_font_size'=>50,
    'yahoo_font_size'=>8,
    'weather_image_alpha'=>100.0,
    'weather_image_noalpha'=>255.0,
    'font_face'=>"Sans Serif",
    'font_weight'=>'bold',
    'font_face_clock'=>"Sans Serif",
    'font_weight_clock'=>'ultrabold',
    'font_face_play'=>"Mono",
    'font_weight_play'=>'normal',
    'play_font_size'=>40,
    'np_speed'=>NP_SPEED,
    'max_play_len'=>MAX_PLAY_LENGTH,
    'update_interval'=>1200,
    'short_update_interval'=>120,
    'min_tint_hour'=>6,
    'max_tint_hour'=>22,
    'xspeed'=>X_SPEED,
    'yspeed'=>Y_SPEED,
    'lang'=>'russian',
    'place' => "Moscow,RU",
    'place_index'=>1,
    'back_r'=>0,
    'back_g'=>0,
    'back_b'=>0,
    'use_fahr'=>0,
    
    'stop_mode'=>0,
  }

  def initialize(conf=nil)
    @face_colour=Gdk::Color.new 250,250,250
    @marks_colour=Gdk::Color.new 30,30,30
    @fill_colour=Gdk::Color.new 255,0,0
    @line_colour=Gdk::Color.new 0,0,255

    cnf=DEF_CONF
    begin
      cnf2=YAML.load(File.read(conf))
      cnf.merge! cnf2
    rescue Exception => e
      warn "Cannot load config! #{e}"
    end                
    cnf.each do |k,v|
      instance_variable_set "@#{k}", v
      #warn "#{k} -> #{v}"
    end

    @bg_colour=Gdk::Color.new(@back_r,@back_g,@back_b)

    @weather_image_h=120
    @weather_image_w=120

    @now_playing_height=0
    @time_now=Time.now
    @WEATHER_IMAGE_CHECKERS_COLOR=0
    @new_update=Time.new(0)
    @x=@y=0
    @weather_width=0
    @colon_color=[0.1, 0.1, 0.0, 0.0, 1.0,
                  0.5, 0.8, 0.8, 0.8, 0.8]

    @weather_images_cache=[]
    0.upto(47) do |i|
      loader = Gdk::PixbufLoader.new
      File.open("#{@icon_path}/%02i.gif" % i, "rb") do |f|
        loader.last_write(f.read)
      end
      @weather_images_cache[i] = loader.pixbuf
    end
    loader = Gdk::PixbufLoader.new
    File.open("#{@icon_path}/na.gif", "rb") do |f|
      loader.last_write(f.read)
    end
    @weather_images_cache[NA_IMAGE] = loader.pixbuf

    @bus = DBus::SessionBus.instance

    @bus.proxy.ListNames[0].select do |service_name|
      service_name =~ /^org.mpris.MediaPlayer2/
    end.collect do |service_name|
      obj=@bus.service(service_name).object("/org/mpris/MediaPlayer2")
      obj.introspect
      #warn "Set on #{obj}"
      obj['org.freedesktop.DBus.Properties'].on_signal(@bus, "PropertiesChanged") do |player,meta,b|
        on_track_change player,meta,b
      end
    end

    setup

    get_track_name
  end

  def setup
    @sunrise_h=0
    @sunrise_m=0
    @sunset_h=0
    @sunset_m=0
    @now_celsium=-128
    @now_fahr=-128
    @now_image_index=47
    @now_weather_text1='not available'
    @now_weather_text2='not available'

    @today_celsium_low=0
    @today_celsium_high=0
    @today_fahr_low=0
    @today_fahr_high=0
    @today_image_index=0
    @today_forecast_text1='not available'
    @today_forecast_text2='not available'

    @tomorrow_celsium_low=0
    @tomorrow_celsium_high=0
    @tomorrow_fahr_low=0
    @tomorrow_fahr_high=0
    @tomorrow_image_index=0
    @tomorrow_forecast_text1='not available'
    @tomorrow_forecast_text2='not available'    
    
  end

  def get_track_name
    meta=nil
    @bus.proxy.ListNames[0].select do |service_name|
      service_name =~ /^org.mpris.MediaPlayer2/
    end.collect do |service_name|
      obj=@bus.service(service_name).object("/org/mpris/MediaPlayer2")
      obj.introspect
      player=obj['org.mpris.MediaPlayer2.Player']
      return if player.nil?
      meta=player['Metadata']
      if meta.nil?
        @playing=false
      else
        parse_meta meta
        @playing=true
      end
    end
  end

  def parse_meta m
    @title=m["xesam:title"].to_s
    @artist=m["xesam:artist"].to_a.join(';').to_s
    @url=m["xesam:url"].to_s.gsub /.*\//, ''
    @url.gsub! '.mp3', ''        
  end

  def on_track_change player,meta,b
    if meta["PlaybackStatus"].to_s=="Paused"
      @playing=false
      return
    end
    m=meta["Metadata"]
    if m.nil?
      get_track_name
      return
    end
    @playing=true

    parse_meta m
  end

  def escape_str s
    s.gsub(/([<>])/){|x| "\\#{x}"}.gsub('&','&amp;')
  end

  def read_now_playing
    return nil unless @playing
    return nil if "#{@title}#{@artist}" == ''
    "#{@title} // #{@artist}"
  end

  def show_play_line cr, x,y, text, sh=1.0
    a=get_image_alpha
    r=(@face_colour.red*a/255).to_i
    g=(@face_colour.green*a/255).to_i
    b=(@face_colour.blue*a/255).to_i
    cut=4
    max_len=0
    if text.length < 8
      cut=(text.length / 2).to_i
    elsif text.length > @max_play_len
      max_len=@max_play_len
    end
    txt="<span face=\"#{@font_face_play}\" size=\"#{@play_font_size*1000}\" weight=\"bold\">w</span>"
    l=cr.create_pango_layout
    l.markup=txt
    e,ext=l.pixel_extents
    width_one=ext.width
    txt="<span face=\"#{@font_face_play}\" size=\"#{@play_font_size*1000}\" weight=\"bold\">"##{@font_weight_play}\">"
    1.upto(cut) do |i|
      color=(r/cut*(i-sh)).to_i*65536+(g/cut*(i-sh)).to_i*256+(b/cut*(i-sh)).to_i
      txt="#{txt}<span foreground=\"##{'%06X' % color}\">#{escape_str text[i-1]}</span>"
    end
    color=r*65536+g*256+b
    txt="#{txt}<span foreground=\"##{'%06X' % color}\">#{escape_str text[cut .. max_len-cut-1]}</span>"
    cut.downto(1) do |i|
      color=(r/cut*(i+sh-1)).to_i*65536+(g/cut*(i+sh-1)).to_i*256+(b/cut*(i+sh-1)).to_i
      txt="#{txt}<span foreground=\"##{'%06X' % color}\">#{escape_str text[max_len-i]}</span>"
    end
    txt="#{txt}</span>"
    l=cr.create_pango_layout
    l.markup=txt
    cr.move_to x-width_one*sh,y
    cr.show_pango_layout l
  end

  def draw_now_playing cr, text_x,text_y

    text=read_now_playing

    return if text.nil?

    np_read,sh=make_cycled text

    first_char=np_read[0]

    show_play_line cr, text_x, text_y, np_read[0 .. -1], sh
  end

  def draw_clock cr, x, y
    txt="<span face=\"#{@font_face_clock}\" size=\"#{@weather_clock_font_size*1000}\" weight=\"#{@font_weight_clock}\">"

    time_str1=get_time_str1
    time_str2=get_time_str2

    col=@colon_color[@time_now.usec/100000]*get_image_alpha/256
    a=get_image_alpha/256
    color="#{'%02X' % (@face_colour.red*a).to_i}#{'%02X' % (@face_colour.green*a).to_i}#{'%02X' % (@face_colour.blue*a).to_i}"
    color2="#{'%02X' % (@face_colour.red*col).to_i}#{'%02X' % (@face_colour.green*col).to_i}#{'%02X' % (@face_colour.blue*col).to_i}"

    txt="#{txt}<span foreground=\"##{color}\">#{time_str1}</span><span foreground=\"##{color2}\">:</span><span foreground=\"##{color}\">#{time_str2}</span></span>"
    l=cr.create_pango_layout
    l.markup=txt

    e,extents=l.pixel_extents
    @clock_width=extents.width
    @clock_height=extents.height

    cr.move_to x, y
    cr.show_pango_layout l

  end

  def get_temp tm
    case tm
    when :now
      @use_fahr==0 ? @now_celsium : @now_fahr
    when :today_low
      @use_fahr==0 ? @today_celsium_low : @today_fahr_low
    when :today_high
      @use_fahr==0 ? @today_celsium_high : @today_fahr_high
    when :tomorrow_low
      @use_fahr==0 ? @tomorrow_celsium_low : @tomorrow_fahr_low
    when :tomorrow_high
      @use_fahr==0 ? @tomorrow_celsium_high : @tomorrow_fahr_high
    end
    
  end

  def draw_picture cr

    #return unless @now_image_index

    w_now=w_today=w_tomorrow="Unknown..."
    if @now_celsium
      w_now="%+3d %s" % [get_temp(:now), @now_weather_text1]
      w_today="%+3d..%+3d %s" % [get_temp(:today_low), get_temp(:today_high), @today_forecast_text1]
      w_tomorrow="%+3d..%+3d %s" % [get_temp(:tomorrow_low), get_temp(:tomorrow_high), @tomorrow_forecast_text1]        
    end

    # @now_image_index ||= 1
    # @today_image_index ||= 1
    # @tomorrow_image_index ||= 1

    image = @weather_images_cache[@now_image_index]
    image1 = @weather_images_cache[@today_image_index]
    image2 = @weather_images_cache[@tomorrow_image_index]

    img=image.composite @weather_image_w, @weather_image_h,
    Gdk::Pixbuf::InterpType::BILINEAR, get_image_alpha,
    @weather_image_w, 
    @WEATHER_IMAGE_CHECKERS_COLOR, @WEATHER_IMAGE_CHECKERS_COLOR

    cr.set_source_pixbuf img, @x, @y

    cr.paint

    x=@x
    y=@y+@weather_image_h

    img=image1.composite @weather_image_w/2, @weather_image_h/2,
    Gdk::Pixbuf::InterpType::BILINEAR,
    get_image_alpha,
    @weather_image_w,
    @WEATHER_IMAGE_CHECKERS_COLOR, @WEATHER_IMAGE_CHECKERS_COLOR

    cr.set_source_pixbuf img, x, y

    cr.paint

    y=@y+@weather_image_h*3/2;
    img=image2.composite @weather_image_w/2, @weather_image_h/2,
    Gdk::Pixbuf::InterpType::BILINEAR,
    get_image_alpha,
    @weather_image_w,
    @WEATHER_IMAGE_CHECKERS_COLOR, @WEATHER_IMAGE_CHECKERS_COLOR

    cr.set_source_pixbuf img, x, y

    cr.paint

    a=get_image_alpha/256
    color="##{'%02X' % (@face_colour.red*a).to_i}#{'%02X' % (@face_colour.green*a).to_i}#{'%02X' % (@face_colour.blue*a).to_i}"

    yahoo="<span size=\"#{@yahoo_font_size*1000}\">\nYahoo!Weather</span>"
    txt="<span face=\"#{@font_face}\" size=\"#{@weather_big_font_size*1000}\" weight=\"#{@font_weight}\" foreground=\"#{color}\">#{w_now}\n#{@now_weather_text2}#{yahoo}</span>"
    l=cr.create_pango_layout
    l.markup=txt

    e,extents=l.pixel_extents
    now_t_w=extents.width
    cr.move_to @x+@weather_image_w, @y
    cr.show_pango_layout l

    txt="<span face=\"#{@font_face}\" size=\"#{@weather_font_size*1000}\" weight=\"#{@font_weight}\" foreground=\"#{color}\">#{w_today}\n#{@today_forecast_text2}</span>"
    l=cr.create_pango_layout
    l.markup=txt

    e,extents=l.pixel_extents
    today_f_w=extents.width
    cr.move_to @x+@weather_image_w, @y+@weather_image_h
    cr.show_pango_layout l

    txt="<span face=\"#{@font_face}\" size=\"#{@weather_font_size*1000}\" weight=\"#{@font_weight}\" foreground=\"#{color}\">#{w_tomorrow}\n#{@tomorrow_forecast_text2}</span>"
    l=cr.create_pango_layout
    l.markup=txt

    e,extents=l.pixel_extents
    tomorrow_f_w=extents.width
    cr.move_to @x+@weather_image_w, @y+@weather_image_h*3/2
    cr.show_pango_layout l

    @weather_width=[now_t_w,today_f_w,tomorrow_f_w].max+@weather_image_w

  end

  def draw_weather cr, width, height

    @time_now=Time.now

    cr.set_source_color(@bg_colour)
    cr.gdk_rectangle(Gdk::Rectangle.new(0, 0, width, height))
    cr.fill

    count_clock_height cr if @weather_height.nil?
    try_update

    max_width=[@clock_width.to_i,@weather_width.to_i].max
    
    if @stop_mode!=0  # just center image
      @x=(width-max_width)/2
      @y=(height-@weather_image_w*2.5)/2
    else              # move image around
      if @x+max_width>width || @x<0
        @xspeed=-@xspeed
      end
      if @y+@weather_image_w*2.5>height || @y<0
        @yspeed=-@yspeed
      end
      @x+=@xspeed
      @y+=@yspeed
    end
    
    draw_picture cr
    draw_clock cr, @x, @y+@weather_image_h*2
    draw_now_playing cr, @x, @y+@weather_image_h*2.5
  end


  def get_image_alpha
    ((@time_now.hour*60+@time_now.min<=@sunrise_h*60+@sunrise_m)||
      (@time_now.hour*60+@time_now.min>=@sunset_h*60+@sunset_m)) ?
    @weather_image_alpha : @weather_image_noalpha
  end

  def get_time_str
    set_locale
    @time_now.strftime "%a %d %b %H %M"
  end

  def get_time_str1
    #set_locale
    @time_now.strftime "%a %d %b %H"
  end

  def get_time_str2
    #set_locale
    @time_now.strftime "%M"
  end

  def make_cycled text
    text2="#{text} | #{text} | "
    len=text.size+3

    shift=10*(@time_now.sec+(@time_now.usec/1000000.0))/@np_speed
    pos=shift % (len>3 ? len : 1)
    shift-=shift.to_i.to_f
    return text2[pos .. pos+len],shift
  end


  def count_clock_height cr

    cr.select_font_face @font_face_CLOCK, @CAIRO_FONT_SLANT_NORMAL,
    @font_weight
    cr.set_font_size @weather_clock_font_size
    cr.set_font_options(Cairo::FontOptions.new.set_antialias(Cairo::ANTIALIAS_SUBPIXEL))        

    extents=cr.text_extents get_time_str
    @weather_height=@weather_image_h*2+extents.height
  end

  def get_time_str
    Time.now.strftime "%a %d %b %H %M"
  end

  def try_update
    if @new_update < @time_now
      if update_weather
        @new_update=@time_now+@update_interval
      else
        @new_update=@time_now+@short_update_interval
      end
    end
  end

  def backup_weather
    @back=OpenStruct.new
    @back.sunrise_h=@sunrise_h
    @back.sunrise_m=@sunrise_m
    @back.sunset_h=@sunset_h
    @back.sunset_m=@sunset_m
    @back.now_celsium=@now_celsium
    @back.now_fahr=@now_fahr
    @back.now_image_index=@now_image_index
    @back.now_weather_text1=@now_weather_text1
    @back.now_weather_text2=@now_weather_text2

    @back.today_celsium_low=@today_celsium_low
    @back.today_celsium_high=@today_celsium_high
    @back.today_fahr_low=@today_fahr_low
    @back.today_fahr_high=@today_fahr_high
    @back.today_image_index=@today_image_index
    @back.today_forecast_text1=@today_forecast_text1
    @back.today_forecast_text2=@today_forecast_text2

    @back.tomorrow_celsium_low=@tomorrow_celsium_low
    @back.tomorrow_celsium_high=@tomorrow_celsium_high
    @back.tomorrow_fahr_low=@tomorrow_fahr_low
    @back.tomorrow_fahr_high=@tomorrow_fahr_high
    @back.tomorrow_image_index=@tomorrow_image_index
    @back.tomorrow_forecast_text1=@tomorrow_forecast_text1
    @back.tomorrow_forecast_text2=@tomorrow_forecast_text2
  end

  def restore_weather
    sunrise_h=@back.sunrise_h
    sunrise_m=@back.sunrise_m
    sunset_h=@back.sunset_h
    sunset_m=@back.sunset_m
    now_fahr=@back.now_celsium
    now_image_index=@back.now_image_index
    now_weather_text1=@back.now_weather_text1
    now_weather_text2=@back.now_weather_text2
    today_celsium_low=@back.today_celsium_low
    today_celsium_high=@back.today_celsium_high
    today_fahr_low=@back.today_fahr_low
    today_fahr_high=@back.today_fahr_high
    today_image_index=@back.today_image_index
    today_forecast_text1=@back.today_forecast_text1
    today_forecast_text2=@back.today_forecast_text2
    tomorrow_celsium_low=@back.tomorrow_celsium_low
    tomorrow_celsium_high=@back.tomorrow_celsium_high
    tomorrow_image_index=@back.tomorrow_image_index
    tomorrow_forecast_text1=@back.tomorrow_forecast_text1
    tomorrow_forecast_text2=@back.tomorrow_forecast_text2
  end

  def update_weather
    uri=URI.parse("https://query.yahooapis.com/v1/public/yql?q=select%20*%20from%20weather.forecast%20where%20woeid%20in%20(select%20woeid%20from%20geo.places(#{@place_index})%20where%20text%3D%22#{@place}%22)%20and%20u%3D%22c%22&format=json&env=store%3A%2F%2Fdatatables.org%2Falltableswithkeys")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(uri.request_uri)

    answer=nil
    backup_weather
    ok=false
    begin
      a = http.request(request)
      if a.is_a? Net::HTTPSuccess
        answer=JSON.load(a.body)
      else
        warn "Bad answer: #{a.code}/#{a.message}"
        return
      end
      @sunrise=answer["query"]["results"]["channel"]["astronomy"]["sunrise"]
      @sunset=answer["query"]["results"]["channel"]["astronomy"]["sunset"]

      if /(\d+):(\d+)/ =~ @sunrise
        @sunrise_h=$1.to_i
        @sunrise_m=$2.to_i
      else
        @sunrise_h=@min_tint_hour
        @sunrise_m=0
      end
      if /(\d+):(\d+)/ =~ @sunset
        @sunset_h=$1.to_i+12
        @sunset_m=$2.to_i
      else
        @sunset_h=@min_tint_hour
        @sunset_m=0
      end

      @now_celsium=answer["query"]["results"]["channel"]["item"]["condition"]["temp"].to_i
      @now_fahr=@now_celsium*9/5+32
      @now_image_index=answer["query"]["results"]["channel"]["item"]["condition"]["code"].to_i
      @now_weather_text1=COND[@lang][@now_image_index][0]
      @now_weather_text2=COND[@lang][@now_image_index][1]

      @today_celsium_low=answer["query"]["results"]["channel"]["item"]["forecast"][0]["low"].to_i
      @today_celsium_high=answer["query"]["results"]["channel"]["item"]["forecast"][0]["high"].to_i
      @today_fahr_low=@today_celsium_low*9/5+32
      @today_fahr_high=@today_celsium_high*9/5+32
      @today_image_index=answer["query"]["results"]["channel"]["item"]["forecast"][0]["code"].to_i
      @today_forecast_text1=COND[@lang][@today_image_index][0]
      @today_forecast_text2=COND[@lang][@today_image_index][1]

      @tomorrow_celsium_low=answer["query"]["results"]["channel"]["item"]["forecast"][1]["low"].to_i
      @tomorrow_celsium_high=answer["query"]["results"]["channel"]["item"]["forecast"][1]["high"].to_i
      @tomorrow_fahr_low=@tomorrow_celsium_low*9/5+32
      @tomorrow_fahr_high=@tomorrow_celsium_high*9/5+32
      @tomorrow_image_index=answer["query"]["results"]["channel"]["item"]["forecast"][1]["code"].to_i
      @tomorrow_forecast_text1=COND[@lang][@tomorrow_image_index][0]
      @tomorrow_forecast_text2=COND[@lang][@tomorrow_image_index][1]
      ok=true
    rescue => e
      warn "Oooops! #{e.message}"
      restore_weather
    end
    ok
  end

  private
  COND={
    'english' =>
    [
      ["tornado",""],
      ["tropical","storm"],
      ["hurricane",""],
      ["severe","thunderstorms"],
      ["thunderstorms",""],
      ["mixed rain","and snow"],
      ["mixed rain","and sleet"],
      ["mixed snow","and sleet"],
      ["freezing","drizzle"],
      ["drizzle",""],

      ["freezing","rain"],
      ["showers",""],
      ["showers",""],
      ["snow","flurries"],
      ["light snow showers",""],
      ["blowing snow",""],
      ["snow",""],
      ["hail",""],
      ["sleet",""],
      ["dust",""],

      ["foggy",""],
      ["haze",""],
      ["smoky",""],
      ["blustery",""],
      ["windy",""],
      ["cold",""],
      ["cloudy",""],
      ["mostly cloudy",""],
      ["mostly cloudy",""],
      ["partly cloudy",""],

      ["partly cloudy",""],
      ["clear",""],
      ["sunny",""],
      ["fair",""],
      ["fair",""],
      ["mixed rain and hail",""],
      ["hot",""],
      ["isolated thunderstorms",""],
      ["scattered thunderstorms",""],
      ["scattered thunderstorms",""],

      ["scattered showers",""],
      ["heavy snow",""],
      ["scattered snow showers",""],
      ["heavy snow",""],
      ["partly cloudy",""],
      ["thundershowers",""],
      ["snow showers",""],
      ["isolated thundershowers",""]
    ],
    'francais' => [
      ["tornade",""],
      ["tropical","orage"],
      ["ouragan",""],
      ["sérieux","orages"],
      ["orages",""],
      ["pluie et","neige mélée"],
      ["pluie et","neige fondue"],
      ["neige et","neige fondue"],
      ["gel","bruine"],
      ["bruine",""],

      ["gel","pluie"],
      ["averses",""],
      ["averses",""],
      ["neige","averse"],
      ["legeres chute de neige",""],
      ["tempête de neige",""],
      ["neige",""],
      ["grêle",""],
      ["neige fondue",""],
      ["poussiere",""],

      ["brumeux",""],
      ["brume",""],
      ["brouillard",""],
      ["tempête",""],
      ["Venteux",""],
      ["froid",""],
      ["couvert",""],
      ["nuageux",""],
      ["nuageux",""],
      ["partiellement nuageux",""],

      ["partiellement nuageux",""],
      ["clair",""],
      ["ensoleillé",""],
      ["beau",""],
      ["beau",""],
      ["pluie et grêle",""],
      ["chaud",""],
      ["orages isolés",""],
      ["orages épars",""],
      ["orages épars",""],

      ["pluies éparses",""],
      ["fortes chutes de neige",""],
      ["chutes de neiges éparses",""],
      ["fortes chutes de neige",""],
      ["partiellement nuageux",""],
      ["orages",""],
      ["chute de neige",""],
      ["orages isolés",""]
    ],

    'russian' =>
    [

      ["Торнадо",""],
      ["Шторм",""],
      ["Ураган",""],
      ["Временами","грозы"],
      ["Грозы",""],
      ["Снег","с дождём"],
      ["Дождь,","слякоть"],
      ["Снег,","слякоть"],
      ["Морось","с гололедицей"],
      ["Моросящий","дождь"],

      ["Дождь","с гололедицей"],
      ["Дождь",""],
      ["Дождь",""],
      ["Снегопад",""],
      ["Лёгкий","снег"],
      ["Ветер","со снегом"],
      ["Снег",""],
      ["Град",""],
      ["Слякоть",""],
      ["Пыль",""],

      ["Туман",""],
      ["Лёгкий","туман"],
      ["Дым",""],
      ["Ветренно",""],
      ["Ветер",""],
      ["Холод",""],
      ["Облачно",""],
      ["Преимущественно","облачно"],
      ["Преимущественно","облачно"],
      ["Временами","облачно"],

      ["Временами","облачно"],
      ["Ясно",""],
      ["Солнечно",""],
      ["Преимущественно","ясно"],
      ["Преимущественно","ясно"],
      ["Дождь","с градом"],
      ["Жара",""],
      ["Местами","грозы"],
      ["Местами","грозы"],
      ["Местами","грозы"],

      ["Местами","дожди"],
      ["Снегопад",""],
      ["Местами","снег с дождём"],
      ["Снегопад",""],
      ["Местами","облачно"],
      ["Гроза",""],
      ["Снег","с дождём"],
      ["Местами ","грозы"]
    ]
  }
end


Gtk.init
DBus::SessionBus.instance.glibize

conf_file="#{ENV['HOME']}/.config/rubysaver.conf"
$weather=Weather.new(conf_file)
window = RubyApp.new

GLib::Timeout.add(TMOUT){
    $drawing_area.queue_draw
    true
}

Gtk.main
