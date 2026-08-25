# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # Only the pure managed XNA Media enum contracts are projected. No MediaPlayer,
      # MediaLibrary, Song, Video or playback route is implemented or implied.
      module Media
        # Pinned CLR declaration order is Paused, Playing, Stopped; the raw values are not ascending.
        class MediaState < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Paused" => 2,
            "Playing" => 1,
            "Stopped" => 0
          })
        end

        class MediaSourceType < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "LocalDevice" => 0,
            "WindowsMediaConnect" => 4
          })
        end

        class VideoSoundtrackType < CNA::Runtime::EnumValue
          extend CNA::Runtime::EnumType
          define_values({
            "Music" => 0,
            "Dialog" => 1,
            "MusicAndDialog" => 2
          })
        end
      end
    end
  end
end
