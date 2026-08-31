# frozen_string_literal: true

require_relative "../framework"

module Microsoft
  module Xna
    module Framework
      # The pure managed XNA Media enum contracts, and the one Media type that is fully
      # constructible without a media stack. No MediaPlayer, MediaLibrary, Song, Video or playback
      # route is implemented or implied.
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

        # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
        #
        # `.class public auto ansi beforefieldinit` over four fields -- two `assembly float32[]` and
        # two private `ReadOnlyCollection`1<float32>` -- and three identities: a **public**
        # parameterless constructor and two get-only properties, each one `ldfld`.
        #
        # Its frontier deferral was `RUNTIME_DATA`, "filled by MediaPlayer.GetVisualizationData from
        # live playback". That is a statement about the **filler**, not the type: the constructor
        # allocates everything it needs and reaches nothing. Foundation 24 settled the same case for
        # `AudioListener` and `AudioEmitter` -- managed holders a consumer can build and set,
        # whose effect nothing here ever hears -- and Foundation 50 for `RendererDetail`.
        #
        # The constructor is seventy-five bytes and does exactly four things:
        #
        #     frequencies = new float[0x100];
        #     samples     = new float[0x100];
        #     frequenciesCollection = new ReadOnlyCollection<float>(frequencies);
        #     samplesCollection     = new ReadOnlyCollection<float>(samples);
        #
        # So both collections are **256 elements long from construction**, every element the CLR
        # `Single` default of zero, and each is a live **view** over the array behind it rather than
        # a snapshot -- which is precisely what `CNA::Runtime::ReadOnlyCollection` projects, and what
        # would let a filler's writes show through. Nothing in this binding is that filler.
        class VisualizationData
          # `new float[0x100]` -- two hundred and fifty-six, twice.
          SIZE = 0x100
          private_constant :SIZE

          def initialize
            @frequencies = ::Array.new(SIZE) { CNA::Runtime::Numeric.f32(0.0) }
            @samples = ::Array.new(SIZE) { CNA::Runtime::Numeric.f32(0.0) }
            @Frequencies = FloatCollection.new(@frequencies)
            @Samples = FloatCollection.new(@samples)
          end

          # Two `ldfld` getters, each answering the same wrapper for the life of the object.
          attr_reader :Frequencies, :Samples

          # `ReadOnlyCollection<float>` closed over `System.Single`. A Ruby class is not statically
          # generic, so the CLR type argument is carried as metadata the API verifier measures.
          class FloatCollection < CNA::Runtime::ReadOnlyCollection
            projects_elements "System.Single"
          end
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
