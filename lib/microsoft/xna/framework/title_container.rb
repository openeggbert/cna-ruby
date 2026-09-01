# frozen_string_literal: true

module Microsoft
  module Xna
    module Framework
      # Derived from the pinned Microsoft.Xna.Framework.dll IL (SHA-256 38e7093f…).
      #
      # `.class public abstract auto ansi sealed beforefieldinit` — a C# `static class` whose whole
      # public surface is `static Stream OpenStream(string name)`. The rest of the type is one
      # private static `char[]` and three non-public statics that do the path work.
      #
      # `OpenStream` is 213 bytes and every branch is derivable:
      #
      #     if (String.IsNullOrEmpty(name)) throw new ArgumentNullException("name");
      #     name = GetCleanPath(name);
      #     if (IsCleanPathAbsolute(name)) throw new ArgumentException(InvalidTitleContainerName);
      #     try   { new Uri(name.Replace('\\', '/'), UriKind.Relative); }
      #     catch (Exception e) { throw new ArgumentException(InvalidTitleContainerName, e); }
      #     try   { return File.OpenRead(Path.Combine(TitleLocation.Path, name)); }
      #     catch (Exception e)
      #     {
      #         if (e is FileNotFoundException || e is DirectoryNotFoundException ||
      #             e is ArgumentException)
      #             throw new FileNotFoundException(Format(OpenStreamNotFound, name));
      #         throw new InvalidOperationException(Format(OpenStreamError, name), e);
      #     }
      #
      # Two details a summary would lose. The `Uri` is constructed and **immediately discarded** —
      # `pop` follows the `newobj` — so it is a validation call and not a value. And the `catch`
      # maps three different CLR exception types onto one `FileNotFoundException`, so a missing
      # directory and a name the platform rejects are reported identically to an absent file.
      #
      # ## The producer, and the one deviation it forces
      #
      # `TitleContainer` reads read-only content shipped beside the title, which is a different
      # thing from `StorageContainer`'s save-game files. CNA keeps the same split:
      # `cna_title_container_read_ext` in `runtime.h` is the title reader, and `storage.h`'s stream
      # handles belong to a `StorageContainer` opened from a device selector. The audit is in
      # `docs/stream-projection-design.md`.
      #
      # DEVIATION, recorded rather than hidden: CNA's title reader delivers the **whole file**
      # through a count/copy pair, because — in its own header's words — "this ABI has no stream
      # handle for title content, and a title asset is read to use it". XNA's `File.OpenRead`
      # returns a `FileStream` that reads lazily. Every observable of the reached `Stream` surface
      # is identical; what differs is *when* the I/O happens, and therefore that a read error
      # surfaces from `OpenStream` rather than from a later `Read`. Opening the file with Ruby's
      # own `File` instead would be worse: it would bypass the runtime that owns the title location
      # and could resolve a different path than `cna_title_location_copy_path` reports.
      #
      # DEVIATION: XNA's `Uri` validation step is **not reproduced**. It would require projecting
      # `System.Uri`, which lives in `System.dll` — not mscorlib, and not an admitted BCL authority
      # here — and reconstructing which strings a relative `Uri` refuses would be a guess about a
      # type this binding has not measured. Every string `GetCleanPath` can produce that
      # `IsCleanPathAbsolute` does not already reject is passed to the reader.
      class TitleContainer
        # The seven bad characters, read out of the assembly's own static blob
        # (`3A 00 2A 00 3F 00 22 00 3C 00 3E 00 7C 00`) rather than remembered. Note what is *not*
        # here: neither separator is a bad character. The list rejects Windows path
        # metacharacters, and the absoluteness rules are the leading separator and the
        # parent-directory tests below.
        BAD_CHARACTERS = %w[: * ? " < > |].freeze

        # `FrameworkResources.InvalidTitleContainerName` is a localized resource string this binding
        # does not carry, so the message states the rule the resource names instead of inventing
        # Microsoft's wording.
        INVALID_NAME = "the title container name must be a relative path below the title location"

        class << self
          def new(*) = raise(TypeError, "TitleContainer is static")

          def OpenStream(name)
            raise ArgumentError, "name" if name.nil? || String(name).empty?

            clean = clean_path(String(name))
            raise ArgumentError, INVALID_NAME if clean_path_absolute?(clean)

            host = CNA::Runtime::Context.native_host("TitleContainer.OpenStream")
            CNA::Runtime::Stream.__send__(:over_bytes, read_title_file(host, clean), name: clean)
          end

          # `TitleLocation.Path` is `assembly` in XNA and therefore not an identity this binding
          # projects. It is exposed here only through the two evidence helpers below, which are
          # private: they exist so a test can prove the reader really resolved against the location
          # CNA reports, and so the missing-file message can name it.
          private

          # The absolute-path half of `ContentManager.OpenStream`. XNA opens a `FileStream` there
          # rather than going through `OpenStream`, precisely because `IsCleanPathAbsolute` would
          # reject the name; CNA's reader takes an absolute path, so the route is the same one and
          # only the validation is skipped. It is private and has exactly one caller.
          def open_unvalidated(path)
            host = CNA::Runtime::Context.native_host("ContentManager.OpenStream")
            CNA::Runtime::Stream.__send__(:over_bytes, read_title_file(host, String(path)), name: String(path))
          end

          def read_title_file(host, clean)
            library = CNA::Native.library
            view = CNA::Native::Layouts::StringView.new(clean.b)
            required = library.pointer_for("Q", 0)
            # The sizing call always writes `out_bytes`, and answers `CNA_RESULT_BUFFER_TOO_SMALL`
            # rather than success whenever the file is not empty -- a zero capacity is smaller than
            # any non-empty file. It is the documented answer, not a failure, so it is accepted
            # here and only a real `CNA_RESULT_IO` becomes the missing-file refusal.
            result = library.function("cna_title_container_read_ext")
                            .call(host.handle, view.read_u64(0), view.read_u64(8), nil, 0, required)
            raise not_found(clean) if result == CNA::Native::Library::RESULT_IO

            library.check(result, "cna_title_container_read_ext") unless result == CNA::Native::Library::RESULT_BUFFER_TOO_SMALL
            bytes = required[0, 8].unpack1("Q")
            return +"" if bytes.zero?

            buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
            library.call("cna_title_container_read_ext", host.handle,
                         view.read_u64(0), view.read_u64(8), buffer, bytes, required)
            buffer[0, bytes].b
          end

          # XNA collapses three CLR exception types into one `FileNotFoundException` whose message
          # is `FrameworkResources.OpenStreamNotFound` formatted with the name. CNA collapses the
          # same cases into `CNA_RESULT_IO`, "chosen deliberately so a missing file does not surface
          # as an internal failure", so the two collapses line up exactly.
          def not_found(clean)
            Errno::ENOENT.new("#{clean} could not be opened from the title location #{title_location}")
          end

          def title_location
            host = CNA::Runtime::Context.native_host("TitleContainer.OpenStream")
            library = CNA::Native.library
            size = library.pointer_for("Q", 0)
            library.call("cna_title_location_get_path_size", host.handle, size)
            bytes = size[0, 8].unpack1("Q")
            return "" if bytes.zero?

            buffer = Fiddle::Pointer.malloc(bytes, Fiddle::RUBY_FREE)
            required = library.pointer_for("Q", 0)
            library.call("cna_title_location_copy_path", host.handle, buffer, bytes, required)
            buffer[0, bytes].force_encoding(Encoding::UTF_8)
          end

          # `TitleContainer.GetCleanPath`, transcribed from the IL. The loop's `IndexOf` is its
          # *increment* and the index starts at 1, so a `"\..\"` at index 0 is never collapsed —
          # which is exactly what lets a leading `..\` survive into the absoluteness test and be
          # rejected there rather than silently escaping the title directory.
          def clean_path(path)
            path = path.tr("/", "\\")
            path = path.gsub("\\.\\", "\\")
            path = path[2..] while path.start_with?(".\\")
            while path.end_with?("\\.")
              path = path.length > 2 ? path[0, path.length - 2] : "\\"
            end
            index = 1
            while index < path.length
              index = path.index("\\..\\", index) || -1
              break if index.negative?

              index = collapse_parent_directory(path, index, 4)
              path = @collapsed
            end
            if path.end_with?("\\..")
              tail = path.length - 3
              if tail.positive?
                collapse_parent_directory(path, tail, 3)
                path = @collapsed
              end
            end
            path == "." ? "" : path
          end

          # `CollapseParentDirectory(ref string path, int position, int removeLength)`:
          #
          #     int start = path.LastIndexOf('\\', position - 1) + 1;
          #     path = path.Remove(start, position - start + removeLength);
          #     return Math.Max(start - 1, 1);
          #
          # Ruby has no `ref string`, so the rewritten path is handed back through `@collapsed`
          # while the return value stays the resume index the IL answers.
          def collapse_parent_directory(path, position, remove_length)
            found = path.rindex("\\", position - 1)
            start = found.nil? ? 0 : found + 1
            @collapsed = path.dup
            @collapsed[start, position - start + remove_length] = ""
            [start - 1, 1].max
          end

          # `IsCleanPathAbsolute`, transcribed from the IL. It answers true for a path that must be
          # *rejected*, not only for a rooted one, which is why `OpenStream` raises
          # `ArgumentException` on it rather than treating it as an absolute path.
          def clean_path_absolute?(path)
            return true if path.each_char.any? { |char| BAD_CHARACTERS.include?(char) }
            return true if path.start_with?("\\")
            return true if path.start_with?("..\\")
            return true if path.include?("\\..\\")
            return true if path.end_with?("\\..")

            path == ".."
          end
        end
        private_class_method :new
      end
    end
  end
end
