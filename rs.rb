#!/usr/bin/ruby
# encoding: UTF-8

require 'gtk2'
require 'dbus'
require 'json'
require 'net/https'
require 'yaml'
require "logger"

require 'apixu'

SIGNAL_DRAW="expose_event"

# for gtk3
#SIGNAL_DRAW="draw"

OLD_DEF_IMG_PATH="/opt/rubysaver/iconsbest.com-icons/"
DEF_IMG_PATH="/opt/rubysaver/apixu-weather/"
CACHE_FILE='/tmp/weather_cache'

NA_IMAGE='00na.gif'
TMOUT=100
X_SPEED=2
Y_SPEED=2
NP_SPEED=5
MAX_PLAY_LENGTH=48

$weather=nil
$drawing_area=nil
$logger=Logger.new("/tmp/rubysaver-#{ENV['USER']}.log", 'monthly')

class RubyApp < Gtk::Window

  def initialize
    super
    
    set_title "Xscreensaver module"
    signal_connect "destroy" do 
      Gtk.main_quit
    end
    signal_connect "delete_event" do
      Gtk.main_quit
      false
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


class WeatherAPIXU

  def initialize(location,json,key)
    @location=location
    @client = Apixu::Client.new key
    f = File.read(json)
    begin
      @descr = JSON.load(f)    
    rescue Exception => e
      $logger.warn "Cannot load json. (#{f[0..64]} .. #{f[-64..-1]})"
      exit(1)
    end
  end

  def desc_by_code code,lang,variant='day_text'
    c = code.to_i
    d = @descr.select{|x| x['icon']==c}
    text = d[0]['languages'].select{|x| x['lang_name'] == lang}
    if text==[]
      text = [{'day_text' => d[0]['day'], 'night_text' => d[0]['night']}]
    end
    text=text[0][variant].split(/\s+/)
    l=text.length
    if l==1
      {
        now1: text[0],
        now2: ''
      }
    else
      {
        now1: text[0 .. l/2-1].join(' '),
        now2: text[l/2 .. -1].join(' ')
      }
    end
  end

  def get_weather lang
    begin
      weather = @client.forecast @location, 2    
    rescue => e
      $logger.warn "Get weather error: #{e}"
      return nil
    end

    astro = weather['forecast']['forecastday'][0]['astro']
    is_day = weather['current']['is_day']==1

    now_code = weather['current']['condition']['icon']
    /(\d+\.png)/ =~ now_code
    now_code = $1
    now_descr = desc_by_code(
      $1,
      lang,
      (is_day ? 'day_text' : 'night_text')
      )

    today_code = weather['forecast']['forecastday'][0]['day']['condition']['icon']
    /(\d+.png)/ =~ today_code
    today_code = $1
    today_descr = desc_by_code $1, lang

    #warn ">>> #{weather['forecast']['forecastday'][1]['day']['condition']}"
    tomorrow_code = weather['forecast']['forecastday'][1]['day']['condition']['icon']
    /(\d+.png)/ =~ tomorrow_code
    tomorrow_code = $1
    tomorrow_descr = desc_by_code $1, lang

    answer = {
      'code' => "#{is_day ? 'day' : 'night'}-#{now_code}",
      'is_day' => weather['current']['is_day']==1,
      'now_celsium' => weather['current']['temp_c'].to_f,
      'now_fahr' => weather['current']['temp_f'].to_f,
      'now_image_index' => now_code,
      'now_weather_text1' => now_descr[:now1],#     COND[@lang][@now_image_index][0]
      'now_weather_text2' => now_descr[:now2],# COND[@lang][@now_image_index][1]

      'today_celsium_low' => weather['forecast']['forecastday'][0]['day']['mintemp_c'],#     answer['forecast'][0]['low'].to_i
      'today_celsium_high' => weather['forecast']['forecastday'][0]['day']['maxtemp_c'],#     answer['forecast'][0]['high'].to_i
      'today_fahr_low' => weather['forecast']['forecastday'][0]['day']['mintemp_f'],#     @today_celsium_low*9/5+32
      'today_fahr_high' => weather['forecast']['forecastday'][0]['day']['maxtemp_f'],#,     @today_celsium_high*9/5+32
      'today_image_index' => "#{is_day ? 'day' : 'night'}-#{today_code}",#     answer['forecast'][0]['code'].to_i
      'today_forecast_text1' => today_descr[:now1],#     COND[@lang][@today_image_index][0]
      'today_forecast_text2' => today_descr[:now2],#     COND[@lang][@today_image_index][1]

      'tomorrow_celsium_low' => weather['forecast']['forecastday'][1]['day']['mintemp_c'],#     answer['forecast'][1]['low'].to_i
      'tomorrow_celsium_high' => weather['forecast']['forecastday'][1]['day']['maxtemp_c'],#     answer['forecast'][1]['high'].to_i
      'tomorrow_fahr_low' => weather['forecast']['forecastday'][1]['day']['mintemp_f'],#     @tomorrow_celsium_low*9/5+32
      'tomorrow_fahr_high' => weather['forecast']['forecastday'][1]['day']['maxtemp_f'],#     @tomorrow_celsium_high*9/5+32
      'tomorrow_image_index' => "#{is_day ? 'day' : 'night'}-#{tomorrow_code}", #     answer['forecast'][1]['code'].to_i
      'tomorrow_forecast_text1' => tomorrow_descr[:now1],#     COND[@lang][@tomorrow_image_index][0]
      'tomorrow_forecast_text2' => tomorrow_descr[:now2],#     COND[@lang][@tomorrow_image_index][1]
    }

  end
end

class WeatherCache

  def initialize path,tmout,weather_class,*args
    @path = path
    @tmout = tmout
    @weather_getter = weather_class.new *args
    @cached = nil
    @last_updated=0
  end
  
  def get_real_weather lang
    new_weather=@weather_getter.get_weather lang
    # @cached=new_weather
    # @last_updated=Time.now.to_i
    # File.open(@path,'w'){|f| f.write new_weather.to_json}
    #new_weather
  end

  def get_weather lang
    return get_real_weather lang
    # now=Time.now.to_i
    # if @last_updated+@tmout > now
    #   # update!
    #   get_real_weather lang
    # else
    #   # get from cache
    #   if @cached
    #     @cached
    #   else
    #     new_weather=begin
    #       data=File.open(@path, "r") { |f| f.read }
    #       JSON.load data
    #     rescue
    #       get_real_weather lang
    #     end
    #   end
    # end
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
    'api_key'=>'',
    'show_updated' => 1,
    
    'stop_mode'=>0,
  }

  def initialize(conf=nil)
    @face_colour=Gdk::Color.new 250,250,250
    @marks_colour=Gdk::Color.new 30,30,30
    @fill_colour=Gdk::Color.new 255,0,0
    @line_colour=Gdk::Color.new 0,0,255

    @c=DEF_CONF
    begin
      cnf2=YAML.load(File.read(conf))
      @c.merge! cnf2
    rescue Exception => e
      $logger.warn "Cannot load config! #{e}"
    end                

    @bg_colour=Gdk::Color.new(@c['back_r'],@c['back_g'],@c['back_b'])

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

    if @c['show_updated']==1
      @extratext=:updated
    end

    @weather_images_cache={}
    #warn "icon_path=#{@c['icon_path']}"
    Dir.glob("#{@c['icon_path']}/*") { |file|
      loader = Gdk::PixbufLoader.new
      File.open(file, "rb") do |f|
        loader.last_write(f.read)
      end
      /\/([^\/]+)$/ =~ file
      @weather_images_cache[$1] = loader.pixbuf
    }
    loader = Gdk::PixbufLoader.new
    File.open("#{@c['icon_path']}/00na.gif", "rb") do |f|
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

    @weather_cache=WeatherCache.new(
      CACHE_FILE,
      0,#@c['cache_tmout'],
      WeatherAPIXU,
      @c['place'],
      '/opt/rubysaver/conditions-apixu.json', #/opt/rubysaver/apixu.json',
      @c['api_key']
      )

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
    @now_image_index='00na.gif'
    @now_weather_text1='not available'
    @now_weather_text2='not available'

    @today_celsium_low=0
    @today_celsium_high=0
    @today_fahr_low=0
    @today_fahr_high=0
    @today_image_index='00na.gif'
    @today_forecast_text1='not available'
    @today_forecast_text2='not available'

    @tomorrow_celsium_low=0
    @tomorrow_celsium_high=0
    @tomorrow_fahr_low=0
    @tomorrow_fahr_high=0
    @tomorrow_image_index='00na.gif'
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
    elsif text.length > @c['max_play_len']
      max_len=@c['max_play_len']
    end
    txt="<span face=\"#{@c['font_face_play']}\" size=\"#{@c['play_font_size']*1000}\" weight=\"bold\">w</span>"
    l=cr.create_pango_layout
    l.markup=txt
    e,ext=l.pixel_extents
    width_one=ext.width
    txt="<span face=\"#{@c['font_face_play']}\" size=\"#{@c['play_font_size']*1000}\" weight=\"bold\">"##{@font_weight_play}\">"
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
    txt="<span face=\"#{@c['font_face_clock']}\" size=\"#{@c['weather_clock_font_size']*1000}\" weight=\"#{@c['font_weight_clock']}\">"

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
      @c['use_fahr'].to_i == 0 ? @now_celsium : @now_fahr
    when :today_low
      @c['use_fahr'].to_i == 0 ? @today_celsium_low : @today_fahr_low
    when :today_high
      @c['use_fahr'].to_i == 0 ? @today_celsium_high : @today_fahr_high
    when :tomorrow_low
      @c['use_fahr'].to_i == 0 ? @tomorrow_celsium_low : @tomorrow_fahr_low
    when :tomorrow_high
      @c['use_fahr'].to_i == 0 ? @tomorrow_celsium_high : @tomorrow_fahr_high
    end
    
  end

  def draw_picture cr

    w_now=w_today=w_tomorrow="Unknown..."
    if @now_celsium
      w_now="%+3d %s" % [get_temp(:now), @now_weather_text1]
      w_today="%+3d..%+3d %s" % [get_temp(:today_low), get_temp(:today_high), @today_forecast_text1]
      w_tomorrow="%+3d..%+3d %s" % [get_temp(:tomorrow_low), get_temp(:tomorrow_high), @tomorrow_forecast_text1]        
    end

    #warn "now_image_index=#{@now_image_index}"
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
      @WEATHER_IMAGE_CHECKERS_COLOR,
      @WEATHER_IMAGE_CHECKERS_COLOR

    cr.set_source_pixbuf img, x, y

    cr.paint

    a=get_image_alpha/256
    color="##{'%02X' % (@face_colour.red*a).to_i}#{'%02X' % (@face_colour.green*a).to_i}#{'%02X' % (@face_colour.blue*a).to_i}"

    extratext=case @extratext
    when :yahoo
      "<span size=\"#{@c['yahoo_font_size']*1000}\">\nYahoo!Weather</span>"
    when :updated        
      "<span size=\"#{@c['yahoo_font_size']*1000}\">\n#{@last_updated}</span>"
    else
      ''
    end
    txt="<span face=\"#{@c['font_face']}\" size=\"#{@c['weather_big_font_size']*1000}\" weight=\"#{@c['font_weight']}\" foreground=\"#{color}\">#{w_now}\n#{@now_weather_text2}#{extratext}</span>"
    l=cr.create_pango_layout
    l.set_alignment(Pango::ALIGN_RIGHT)
    l.markup=txt

    e,extents=l.pixel_extents
    now_t_w=extents.width
    cr.move_to @x+@weather_image_w, @y
    cr.show_pango_layout l

    txt="<span face=\"#{@c['font_face']}\" size=\"#{@c['weather_font_size']*1000}\" weight=\"#{@c['font_weight']}\" foreground=\"#{color}\">#{w_today}\n#{@today_forecast_text2}</span>"
    l=cr.create_pango_layout
    l.markup=txt

    e,extents=l.pixel_extents
    today_f_w=extents.width
    cr.move_to @x+@weather_image_w, @y+@weather_image_h
    cr.show_pango_layout l

    txt="<span face=\"#{@c['font_face']}\" size=\"#{@c['weather_font_size']*1000}\" weight=\"#{@c['font_weight']}\" foreground=\"#{color}\">#{w_tomorrow}\n#{@tomorrow_forecast_text2}</span>"
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
    
    if @c['stop_mode']!=0  # just center image
      @x=(width-max_width)/2
      @y=(height-@weather_image_w*2.5)/2
      #warn "do stop"
    else              # move image around
      if @x+max_width>width || @x<0
        @c['xspeed'] = -@c['xspeed']
      end
      if @y+@weather_image_w*2.5>height || @y<0
        @c['yspeed'] = -@c['yspeed']
      end
      @x+=@c['xspeed']
      @y+=@c['yspeed']
    end
    
    draw_picture cr
    draw_clock cr, @x, @y+@weather_image_h*2
    draw_now_playing cr, @x, @y+@weather_image_h*2.5
  end


  def get_image_alpha
    # ((@time_now.hour*60+@time_now.min<=@sunrise_h*60+@sunrise_m)||
    #   (@time_now.hour*60+@time_now.min>=@sunset_h*60+@sunset_m)) ?
    # @weather_image_alpha : @weather_image_noalpha
    @is_day ? @c['weather_image_noalpha'] : @c['weather_image_alpha']
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

    shift = 10*(@time_now.sec + (@time_now.usec / 1000000.0)) / @c['np_speed'] # sublime highliting bug/
    pos=shift % (len>3 ? len : 1)
    shift-=shift.to_i.to_f
    return text2[pos .. pos+len],shift
  end


  def count_clock_height cr

    cr.select_font_face @c['font_face_clock'],
                        @CAIRO_FONT_SLANT_NORMAL,
                        @c['font_weight']
    cr.set_font_size @c['weather_clock_font_size']
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
        @new_update=@time_now+@c['update_interval']
      else
        @new_update=@time_now+@c['short_update_interval']
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
    now_fahr=@back.now_fahr
    now_celsium=@back.now_celsium
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
    backup_weather
    answer=nil
    ok=false
    $logger.warn "Update weather"
    begin
      answer=@weather_cache.get_weather @c['lang']
      if answer.nil?
        $logger.warn "Bad answer!"
        restore_weather
        return false
      end
      @last_updated=Time.now
      @sunrise=answer['sunrise']
      @sunset=answer['sunset']

      if /(\d+):(\d+)/ =~ @sunrise
        @sunrise_h=$1.to_i
        @sunrise_m=$2.to_i
      else
        @sunrise_h=@c['min_tint_hour']
        @sunrise_m=0
      end
      if /(\d+):(\d+)/ =~ @sunset
        @sunset_h=$1.to_i+12
        @sunset_m=$2.to_i
      else
        @sunset_h=@c['min_tint_hour']
        @sunset_m=0
      end

      @is_day=answer['is_day']

      @now_celsium=answer['now_celsium']
      @now_fahr=answer['now_fahr'] #@now_celsium*9/5+32
      @now_image_index=answer['code']
      @now_weather_text1=answer['now_weather_text1'] #COND[@lang][@now_image_index][0]
      @now_weather_text2=answer['now_weather_text2'] #COND[@lang][@now_image_index][1]

      @today_celsium_low = answer['today_celsium_low'] #answer['forecast'][0]['low'].to_i
      @today_celsium_high = answer['today_celsium_high'] #answer['forecast'][0]['high'].to_i
      @today_fahr_low = answer['today_fahr_low'] #@today_celsium_low*9/5+32
      @today_fahr_high = answer['today_fahr_high'] #@today_celsium_high*9/5+32
      @today_image_index = answer['today_image_index'] #answer['forecast'][0]['code'].to_i
      @today_forecast_text1 = answer['today_forecast_text1'] #COND[@lang][@today_image_index][0]
      @today_forecast_text2 = answer['today_forecast_text2'] #COND[@lang][@today_image_index][1]

      @tomorrow_celsium_low  = answer['tomorrow_celsium_low'] #answer['forecast'][1]['low'].to_i
      @tomorrow_celsium_high = answer['tomorrow_celsium_high'] #answer['forecast'][1]['high'].to_i
      @tomorrow_fahr_low  = answer['tomorrow_fahr_low'] #@tomorrow_celsium_low*9/5+32
      @tomorrow_fahr_high = answer['tomorrow_fahr_high'] #@tomorrow_celsium_high*9/5+32
      @tomorrow_image_index = answer['tomorrow_image_index'] #answer['forecast'][1]['code'].to_i
      @tomorrow_forecast_text1 = answer['tomorrow_forecast_text1'] #COND[@lang][@tomorrow_image_index][0]
      @tomorrow_forecast_text2 = answer['tomorrow_forecast_text2'] #COND[@lang][@tomorrow_image_index][1]
      ok=true
    rescue => e
      warn "Oooops! #{e.message} (#{e.backtrace.join("\n")})"
      restore_weather
    end
    ok
  end

end


Gtk.init
DBus::SessionBus.instance.glibize

conf_file=ARGV[0] || "#{ENV['HOME']}/.config/rubysaver.conf"
$weather=Weather.new(conf_file)
window = RubyApp.new

GLib::Timeout.add(TMOUT){
    $drawing_area.queue_draw
    true
}

Gtk.main


__END__

OLD version (yahoo)



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
