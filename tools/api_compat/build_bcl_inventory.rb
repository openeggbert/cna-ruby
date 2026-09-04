# frozen_string_literal: true

# Derives the Microsoft-free BCL inventory from the pinned Microsoft .NET Framework 4.0 assemblies.
#
# These are a **separate authority** from the XNA reference contract. Neither mscorlib nor System is
# an XNA assembly and none of their types is an XNA identity, so nothing they carry may enter
# REFERENCE_TYPES / REFERENCE_MEMBERS or the XNA IL inventory. They exist for one reason: several
# XNA public members name a BCL type, and this binding refuses to project a BCL type from memory.
#
# Point BCL_REFERENCE_ASSEMBLIES at a directory holding them and XNA_REFERENCE_ASSEMBLIES at the
# pinned XNA assemblies. Admission is by exact SHA-256, never by filename, and the pairing between
# the authorities is proved rather than assumed: a pinned XNA assembly that records an AssemblyRef
# to an admitted authority must name the exact version and public key token that binary carries.
# The public key token is *derived* from the assembly's own .publickey blob (SHA-1, last eight
# bytes, reversed) rather than trusted from a constant.
#
# **Each authority is admitted independently.** mscorlib came first, at Foundation 28, because
# `ReadOnlyCollection`1` was the first BCL identity with real behaviour. System.dll follows at
# Foundation 105 because the thirteen XNA `Design` converters reach `System.ComponentModel`, which
# mscorlib does not declare. The two are held to the same standard, and the standard is a property
# of the registry rather than of either assembly: nothing below is specific to one of them, and
# adding a third would be a table entry plus its demand.
#
# The inventory is demand-driven. A family is admitted only when the XNA reference contract really
# names it, or an already-admitted family's measured surface does; a family with neither is refused,
# which is what keeps this from becoming a reimplementation of the .NET Framework. Nothing
# Microsoft-owned is written: the output records identities, shapes and derived behavioural facts,
# never IL text and never a machine-local path.

require "digest"
require "json"

# The BCL authority registry. One entry per independently admitted Microsoft assembly, each
# recording the exact binary identity it expects, the Microsoft origin claim its PE version
# resource has to carry, the pinned XNA assemblies that must bind it, and why it is admitted at
# all. `xnaReferrers` is measured rather than assumed to be "all of them": four of the ten pinned
# XNA assemblies reference no System.dll, and demanding that they did would be a vacuous proof.
AUTHORITIES = {
  "mscorlib" => {
    "file" => "mscorlib.dll",
    "sha256" => "5634668d4775b0113f08ea31093b281fea69bfc4e99227f5ca761b4ed98acc63",
    "bytes" => 5196112,
    "assemblyName" => "mscorlib",
    "assemblyVersion" => "4.0.0.0",
    "fileVersion" => "4.0.30319.1",
    "publicKeyToken" => "b77a5c561934e089",
    "company" => "Microsoft Corporation",
    "description" => "Microsoft Common Language Runtime Class Library",
    "demand" => "the BCL every pinned XNA assembly binds, and the declaring assembly of every collection, stream, reflection, globalization and exception identity the selected XNA surface names",
    "xnaReferrers" => %w[
      Microsoft.Xna.Framework.dll Microsoft.Xna.Framework.Graphics.dll Microsoft.Xna.Framework.Game.dll
      Microsoft.Xna.Framework.Input.Touch.dll Microsoft.Xna.Framework.Xact.dll
      Microsoft.Xna.Framework.Storage.dll Microsoft.Xna.Framework.Video.dll
      Microsoft.Xna.Framework.Net.dll Microsoft.Xna.Framework.GamerServices.dll
      Microsoft.Xna.Framework.Avatar.dll
    ]
  },
  "System" => {
    "file" => "System.dll",
    "sha256" => "c3182e40f09a8d3a0167a833dc1ce7c3cb2bfddbd32031d8d3f41481d0467462",
    "bytes" => 3481928,
    "assemblyName" => "System",
    "assemblyVersion" => "4.0.0.0",
    "fileVersion" => "4.0.30319.1",
    "publicKeyToken" => "b77a5c561934e089",
    "company" => "Microsoft Corporation",
    "description" => ".NET Framework",
    "demand" => "the declaring assembly of System.ComponentModel, which the thirteen XNA Design converters extend, return, take as a parameter and special-case; mscorlib declares none of those identities",
    # Six of the ten. Input.Touch, Storage, Video and Avatar declare no AssemblyRef to System, and
    # requiring one of them would prove nothing about this binary.
    "xnaReferrers" => %w[
      Microsoft.Xna.Framework.dll Microsoft.Xna.Framework.Graphics.dll Microsoft.Xna.Framework.Game.dll
      Microsoft.Xna.Framework.Xact.dll Microsoft.Xna.Framework.Net.dll
      Microsoft.Xna.Framework.GamerServices.dll
    ]
  }
}.freeze

XNA_PINNED = %w[
  Microsoft.Xna.Framework.dll Microsoft.Xna.Framework.Graphics.dll Microsoft.Xna.Framework.Game.dll
  Microsoft.Xna.Framework.Input.Touch.dll Microsoft.Xna.Framework.Xact.dll
  Microsoft.Xna.Framework.Storage.dll Microsoft.Xna.Framework.Video.dll
  Microsoft.Xna.Framework.Net.dll Microsoft.Xna.Framework.GamerServices.dll
  Microsoft.Xna.Framework.Avatar.dll
].freeze

# The BCL families this binding is allowed to inventory, which authority declares each and why it
# is here. Every entry must be named by the XNA reference contract or by an already-admitted
# family's measured surface; the tool proves that below and aborts otherwise.
FAMILIES = {
  "System.Collections.ObjectModel.ReadOnlyCollection`1" => {"authority" => "mscorlib", "reason" =>
    "the CLR base of four XNA collection types and the declared return type of six XNA members"},
  "System.Collections.ObjectModel.Collection`1" => {"authority" => "mscorlib", "reason" =>
    "the CLR base of GameComponentCollection, and the mutable sibling ReadOnlyCollection`1 is measured against"},
  "System.Collections.Generic.Dictionary`2" => {"authority" => "mscorlib", "reason" =>
    "the CLR base of LaunchParameters, the one dependency-complete XNA type blocked on it alone"},
  "System.IO.Stream" => {"authority" => "mscorlib", "reason" =>
    "the declared return type of TitleContainer.OpenStream, ContentManager.OpenStream, StorageContainer.OpenFile/CreateFile and four Media getters, and the declared parameter of SoundEffect.FromStream, Texture2D.FromStream and Texture2D.SaveAsPng/SaveAsJpeg -- seventeen XNA members in all"},
  "System.IO.SeekOrigin" => {"authority" => "mscorlib", "reason" =>
    "the second parameter of System.IO.Stream::Seek, and the only identity a consumer of a stream this binding produces can name in order to seek; demanded transitively through Stream rather than directly by an XNA signature"},
  "System.IO.FileMode" => {"authority" => "mscorlib", "reason" =>
    "the second parameter of all three StorageContainer.OpenFile overloads"},
  "System.IO.FileAccess" => {"authority" => "mscorlib", "reason" =>
    "the third parameter of two StorageContainer.OpenFile overloads"},
  "System.IO.FileShare" => {"authority" => "mscorlib", "reason" =>
    "the fourth parameter of StorageContainer.OpenFile's widest overload"},
  "System.IAsyncResult" => {"authority" => "mscorlib", "reason" =>
    "the return of StorageDevice.BeginShowSelector and BeginOpenContainer and the argument of EndShowSelector and EndOpenContainer -- four XNA members"},
  "System.Threading.WaitHandle" => {"authority" => "mscorlib", "reason" =>
    "the declared type of IAsyncResult.AsyncWaitHandle, and the only identity a consumer holding a result this binding produces can name in order to wait; demanded transitively through IAsyncResult rather than directly by an XNA signature"},
  "System.IO.BinaryReader" => {"authority" => "mscorlib", "reason" =>
    "the CLR base of Content.ContentReader, whose ReadSingle and ReadDouble override it and whose ReadVector2/3/4, ReadMatrix, ReadQuaternion and ReadColor are each a sequence of calls back into it"},

  # ------------------------------------------------------------ Foundation 105: the Design family
  #
  # Seven System.dll families and five mscorlib ones, every one of them reached by the thirteen XNA
  # Design converters. `docs/generated/design-converter-inventory.json` derives that reach from the
  # same IL these are measured against, so the demand is a generated fact rather than this list.
  "System.ComponentModel.TypeConverter" => {"authority" => "System", "reason" =>
    "the root of the Design family: MathTypeConverter's CanConvertFrom and CanConvertTo each answer this class's implementation on their fallback path, and every public member it declares is inherited by all thirteen converters"},
  "System.ComponentModel.ExpandableObjectConverter" => {"authority" => "System", "reason" =>
    "the declared base type of Microsoft.Xna.Framework.Design.MathTypeConverter in the XNA reference contract, and therefore of all twelve converters that derive from it"},
  "System.ComponentModel.ITypeDescriptorContext" => {"authority" => "System", "reason" =>
    "the first parameter of thirty-eight XNA Design members -- every CanConvertFrom, CanConvertTo, ConvertFrom, ConvertTo, CreateInstance, GetProperties, GetPropertiesSupported and GetCreateInstanceSupported the family declares"},
  "System.ComponentModel.PropertyDescriptorCollection" => {"authority" => "System", "reason" =>
    "the declared return type of MathTypeConverter.GetProperties and the declared type of its protected propertyDescriptions field"},
  "System.ComponentModel.PropertyDescriptor" => {"authority" => "System", "reason" =>
    "the element type of PropertyDescriptorCollection and the CLR base of the three private XNA descriptor classes the converters build their collections out of; demanded transitively through the collection a consumer receives"},
  "System.ComponentModel.TypeDescriptor" => {"authority" => "System", "reason" =>
    "MathTypeConverter.ConvertToValues and ConvertFromValues both call GetConverter to convert each scalar element, so the string form of every converted value is this class's answer rather than the converter's own"},
  "System.ComponentModel.Design.Serialization.InstanceDescriptor" => {"authority" => "System", "reason" =>
    "the destination type MathTypeConverter.CanConvertTo special-cases and the object eleven of the twelve derived ConvertTo implementations construct"},
  "System.Globalization.CultureInfo" => {"authority" => "mscorlib", "reason" =>
    "the second parameter of every XNA Design ConvertFrom and ConvertTo, and the source of the list separator the family formats and parses with"},
  "System.Globalization.TextInfo" => {"authority" => "mscorlib", "reason" =>
    "the declared type of CultureInfo.TextInfo, whose ListSeparator is what the converters split and join on; demanded transitively through CultureInfo rather than by an XNA signature"},
  "System.Collections.IDictionary" => {"authority" => "mscorlib", "reason" =>
    "the second parameter of all twelve XNA Design CreateInstance members, which read the property values back out of it by descriptor name"},
  "System.Collections.ICollection" => {"authority" => "mscorlib", "reason" =>
    "the second parameter of InstanceDescriptor's constructor, which carries the arguments a reconstruction passes; demanded transitively through InstanceDescriptor"},
  "System.Reflection.MemberInfo" => {"authority" => "mscorlib", "reason" =>
    "the first parameter of InstanceDescriptor's constructor and the declared type of its MemberInfo property, and the base of everything Type's three admitted lookups answer; demanded transitively through InstanceDescriptor"},
  "System.Reflection.ConstructorInfo" => {"authority" => "mscorlib", "reason" =>
    "what Type.GetConstructor answers and what eleven ConvertTo implementations hand an InstanceDescriptor, comparing it against null before they do; demanded transitively through InstanceDescriptor"},
  "System.Reflection.FieldInfo" => {"authority" => "mscorlib", "reason" =>
    "what Type.GetField answers and what FieldPropertyDescriptor is constructed from; it is what PropertyDescriptor.PropertyType, GetValue and SetValue answer for eleven of the twelve converters, so a consumer observes it through every descriptor they produce"},
  "System.Reflection.PropertyInfo" => {"authority" => "mscorlib", "reason" =>
    "what Type.GetProperty answers and what PropertyPropertyDescriptor is constructed from; ColorConverter is the one converter whose descriptors read properties rather than fields, so its four descriptors observe this one instead"},

  # The scalar element converters. MathTypeConverter parses and formats no number itself: both of
  # its generic helpers call TypeDescriptor.GetConverter(typeof(T)) and delegate, so the string form
  # of every value the thirteen converters produce or accept is one of these three classes' answer,
  # down to which NumberStyles it parses with and whether it accepts hexadecimal.
  "System.ComponentModel.BaseNumberConverter" => {"authority" => "System", "reason" =>
    "the CLR base of the three element converters below, and where the shape they share lives: the hexadecimal prefixes, the culture resolution and the NumberFormatInfo lookup are all declared here rather than in any of them"},
  "System.ComponentModel.Int32Converter" => {"authority" => "System", "reason" =>
    "what TypeDescriptor.GetConverter answers for System.Int32, the element type PointConverter and RectangleConverter name in ConvertToValues<int32>"},
  "System.ComponentModel.SingleConverter" => {"authority" => "System", "reason" =>
    "what TypeDescriptor.GetConverter answers for System.Single, the element type the seven vector, quaternion, plane, ray, bounding and matrix converters name"},
  "System.ComponentModel.ByteConverter" => {"authority" => "System", "reason" =>
    "what TypeDescriptor.GetConverter answers for System.Byte, the element type ColorConverter alone names in ConvertToValues<uint8>"},

  # The two interfaces a consumer has to *construct* in order to use a projected member. Neither is
  # named by an XNA signature and both are named by an admitted one, so both are transitive demands
  # -- and both are measured here rather than collapsed on an assumption about how many members
  # they declare.
  "System.Collections.IComparer" => {"authority" => "mscorlib", "reason" =>
    "the second parameter of two PropertyDescriptorCollection.Sort overloads, which a consumer holding the collection MathTypeConverter.GetProperties answers can call; demanded transitively through that collection"},
  "System.EventHandler" => {"authority" => "mscorlib", "reason" =>
    "the second parameter of PropertyDescriptor.AddValueChanged and RemoveValueChanged, and what FieldPropertyDescriptor.SetValue's OnValueChanged call invokes; demanded transitively through the descriptors a consumer receives"}
}.freeze

# Support enums the collection families throw through. Their literal names are what make a derived
# throw fact readable; they are internal CLR plumbing, not surface.
SUPPORT_ENUMS = %w[System.ExceptionResource System.ExceptionArgument].freeze
THROW_HELPER = "System.ThrowHelper"

root = File.expand_path("../..", __dir__)
bcl_directory = ENV.fetch("BCL_REFERENCE_ASSEMBLIES") do
  abort "BCL_REFERENCE_ASSEMBLIES must name a directory holding the pinned Microsoft .NET Framework assemblies"
end
xna_directory = ENV.fetch("XNA_REFERENCE_ASSEMBLIES") do
  abort "XNA_REFERENCE_ASSEMBLIES must name a directory holding the pinned XNA 4.0 Windows assemblies"
end
unless ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |entry| File.executable?(File.join(entry, "ikdasm")) }
  abort "ikdasm is required and was not found on PATH (Debian package: ikdasm)"
end

# The PE version resource carries the Microsoft origin claim. Read it straight out of the file.
#
# A key appears in a PE more than once: once in the VS_VERSION_INFO string table beside its value,
# and again in the resource-name directory with nothing after it, and in a managed assembly a third
# time inside the string heap. Reading only the first occurrence is a token anchored on one side
# only -- the scanner defect this project keeps finding -- and for System.dll it answers the whole
# name directory rather than "Microsoft Corporation". So every occurrence is read and only the ones
# whose value is a plausible resource string are kept: the caller asserts against that set, which
# still fails loudly on a binary whose real CompanyName differs.
PLAUSIBLE = /\A[\x20-\x7E]+\z/.freeze

def version_resources(bytes, key)
  needle = key.encode("UTF-16LE").b
  found = []
  index = -1
  while (index = bytes.index(needle, index + 1))
    cursor = index + needle.bytesize
    cursor += 2 while bytes.byteslice(cursor, 2) == "\x00\x00".b
    out = +""
    while (unit = bytes.byteslice(cursor, 2)) && unit != "\x00\x00".b && unit.bytesize == 2
      out << unit
      cursor += 2
    end
    value = out.force_encoding("UTF-16LE").encode("UTF-8", invalid: :replace, undef: :replace)
    found << value if PLAUSIBLE.match?(value)
  end
  found.uniq
end

# ---------------------------------------------------------------------------------------------
# Admission. Each authority is admitted independently and to the same standard: exact bytes, an
# identity derived from the binary rather than asserted, a Microsoft origin claim read out of the
# PE, and a pairing proof against the pinned XNA assemblies that bind it.
# ---------------------------------------------------------------------------------------------

def admit(name, expected, bcl_directory, xna_directory)
  path = File.join(bcl_directory, expected.fetch("file"))
  abort "missing pinned #{expected.fetch("file")}" unless File.file?(path)
  actual_sha = Digest::SHA256.file(path).hexdigest
  unless actual_sha == expected.fetch("sha256")
    abort "SHA-256 mismatch for #{expected.fetch("file")}: expected #{expected.fetch("sha256")}, got #{actual_sha}"
  end
  abort "byte-length mismatch for #{expected.fetch("file")}" unless File.size(path) == expected.fetch("bytes")

  il = IO.popen(["ikdasm", path], &:read)
  abort "ikdasm produced no IL for #{expected.fetch("file")}" if il.nil? || il.empty?

  manifest = il[/^\.assembly #{Regexp.escape(expected.fetch("assemblyName"))}\b.*?^\}/m]
  abort "no .assembly #{name} manifest in the disassembly" if manifest.nil?
  public_key = manifest[/^\s*\.publickey\s*=\s*\(([0-9A-Fa-f\s]*)\)/m, 1]
  abort "no .publickey in the #{name} manifest" if public_key.nil?
  version = manifest[/^\s*\.ver\s+(\d+):(\d+):(\d+):(\d+)/, 0].to_s.sub(/\A\s*\.ver\s+/, "").tr(":", ".")
  # The CLR derives a public key token as the low eight bytes of the key's SHA-1, reversed. Deriving
  # it here is the point: the expected token is a conclusion drawn from the admitted bytes, never a
  # constant this tool trusts.
  derived_token = Digest::SHA1.digest([public_key.gsub(/\s+/, "")].pack("H*")).bytes.last(8).reverse
                        .map { |byte| format("%02x", byte) }.join
  unless derived_token == expected.fetch("publicKeyToken")
    abort "#{name} public key token mismatch: derived #{derived_token}, expected #{expected.fetch("publicKeyToken")}"
  end
  unless version == expected.fetch("assemblyVersion")
    abort "#{name} assembly version mismatch: found #{version}, expected #{expected.fetch("assemblyVersion")}"
  end

  # An independent tool, on the facts the whole gate turns on.
  #
  # `ikdasm` produced every value above, so a defect in *it* would go unnoticed by every check that
  # reads only its output -- which is the shape of the mistake this project has made before. The
  # cross-check reads the assembly table with `monodis`, a different disassembler over the same
  # bytes, and requires it to agree on the assembly name, the version and the public key blob. It
  # is skipped only when `monodis` is genuinely absent, and the inventory records which it was, so
  # "cross-checked" can never quietly mean "not run".
  cross_check = if ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
                     .any? { |entry| File.executable?(File.join(entry, "monodis")) }
                  table = IO.popen(["monodis", "--assembly", path], err: File::NULL, &:read).to_s
                  found_name = table[/^Name:\s*(\S+)/, 1]
                  found_version = table[/^Version:\s*([0-9.]+)/, 1]
                  found_key = table[/Dump:\n((?:0x[0-9a-fA-F]{8}:(?:\s+[0-9A-Fa-f]{2})+\s*\n)+)/, 1]
                              .to_s.gsub(/0x[0-9a-fA-F]{8}:/, "").split.map(&:downcase).join
                  unless found_name == expected.fetch("assemblyName")
                    abort "#{name}: monodis reads the assembly name as #{found_name.inspect}, ikdasm as #{expected.fetch("assemblyName").inspect}"
                  end
                  unless found_version == version
                    abort "#{name}: monodis reads the version as #{found_version.inspect}, ikdasm as #{version.inspect}"
                  end
                  unless found_key == public_key.gsub(/\s+/, "").downcase
                    abort "#{name}: monodis and ikdasm disagree on the public key blob"
                  end

                  {"tool" => "monodis", "agreesOn" => %w[assemblyName assemblyVersion publicKey]}
                else
                  {"tool" => nil, "reason" => "monodis is not on PATH; ikdasm is the only extraction"}
                end

  pe = File.binread(path)
  %w[CompanyName FileDescription].zip(%w[company description]).each do |resource, key|
    found = version_resources(pe, resource)
    unless found.include?(expected.fetch(key))
      abort "#{name} #{resource} mismatch: #{expected.fetch(key).inspect} not among #{found.inspect}"
    end
  end
  file_version = version_resources(pe, "FileVersion").find { |value| value.start_with?(expected.fetch("fileVersion")) }
  abort "#{name} FileVersion mismatch: no candidate starts with #{expected.fetch("fileVersion")}" if file_version.nil?

  # The pairing proof: this is the identity the pinned XNA assemblies that reference this authority
  # actually bind to. Which assemblies those are is itself asserted, so an XNA assembly that gained
  # or lost the reference fails the gate rather than passing it silently.
  referrers = []
  pairing = XNA_PINNED.filter_map do |assembly|
    assembly_path = File.join(xna_directory, assembly)
    abort "missing pinned XNA assembly #{assembly}" unless File.file?(assembly_path)
    table = IO.popen(["ikdasm", "--assemblyref", assembly_path], &:read).to_s
    entry = table.split(/^\d+: /).find { |chunk| chunk.include?("Name=#{expected.fetch("assemblyName")}\n") }
    next if entry.nil?

    referrers << assembly
    ref_version = entry[/Version=([0-9.]+)/, 1]
    ref_token = entry[/Public Key:\n0x00000000:\s*((?:[0-9A-Fa-f]{2}\s+){8})/, 1].to_s.split.map(&:downcase).join
    unless ref_version == version && ref_token == derived_token
      abort "#{assembly} binds #{name} #{ref_version}/#{ref_token}, not #{version}/#{derived_token}"
    end

    {"assembly" => assembly, "referencedVersion" => ref_version, "referencedPublicKeyToken" => ref_token}
  end
  unless referrers.sort == expected.fetch("xnaReferrers").sort
    abort "#{name} is referenced by #{referrers.sort.inspect}, not the expected #{expected.fetch("xnaReferrers").sort.inspect}"
  end
  abort "#{name} has no XNA referrer; the pairing proof would be vacuous" if pairing.empty?

  {"il" => il,
   "record" => expected.reject { |key, _| key == "xnaReferrers" }.merge(
     "derivedPublicKeyToken" => derived_token,
     "publicKeyTokenDerivation" => "SHA-1 of the assembly's own .publickey blob, low eight bytes, reversed",
     "observedAssemblyVersion" => version,
     "observedFileVersion" => file_version,
     "crossCheck" => cross_check,
     "pairing" => {
       "rule" => "every pinned XNA assembly that declares an AssemblyRef to this authority must name the exact version and public key token the admitted binary derives, and the set of assemblies that declare one is itself asserted",
       "xnaReferrers" => referrers.sort,
       "xnaNonReferrers" => (XNA_PINNED - referrers).sort,
       "assemblies" => pairing
     }
   )}
end

admitted = AUTHORITIES.to_h { |name, expected| [name, admit(name, expected, bcl_directory, xna_directory)] }

# ---------------------------------------------------------------------------------------------
# Demand: which XNA reference identities name each family.
# ---------------------------------------------------------------------------------------------

reference = JSON.parse(File.read(File.join(__dir__, "reference", "xna40-windows-runtime-contract.json")))
consumers = FAMILIES.keys.to_h { |family| [family, []] }
reference.fetch("types").each do |type|
  name = type.fetch("name")
  FAMILIES.each_key do |family|
    consumers[family] << "#{name} (base)" if type["baseType"].to_s.start_with?(family)
    type.fetch("members").each do |member|
      signatures = [member["type"], member["returnType"], *member.fetch("parameters", []).map { |p| p["type"] }]
      next unless signatures.compact.any? { |signature| signature.include?(family) }

      consumers[family] << "#{name}::#{member.fetch("name")}"
    end
  end
end
consumers.each_value do |list|
  list.uniq!
  list.sort!
end
# Demand is transitive, and has to be. A family can be reachable without any XNA signature naming
# it: `System.IO.SeekOrigin` is named by `System.IO.Stream::Seek` and by nothing in XNA, yet a
# consumer holding a stream this binding produced can name it. Admitting it is therefore demand,
# not scope creep -- the same reasoning the exception closure already follows, which walks into
# every exception an admitted family throws without any XNA signature naming those either.
#
# The transitive check needs the measured surface, so it runs after extraction; what happens here is
# only the split. A family with neither kind of consumer still aborts.
transitively_demanded = consumers.select { |_, list| list.empty? }.keys

# ---------------------------------------------------------------------------------------------
# IL extraction. Nested- and generic-aware, following the same conventions as the XNA inventory:
# a nested type is addressed Parent+Child, and a generic type keeps its CLR `N spelling.
# ---------------------------------------------------------------------------------------------

GENERIC_SUFFIX = /<[^<>]*>\z/.freeze
METHOD_NAME = /('[^']+'|[A-Za-z_.<>][A-Za-z0-9_.<>`]*)\s*\(/.freeze

def type_bodies(il)
  bodies = {}
  open = []
  il.each_line do |line|
    stripped = line.rstrip
    indent = line[/\A */].length
    leading = stripped.lstrip
    if leading.start_with?(".class ") && !leading.start_with?(".class extern")
      short = stripped.split(/\s+/).last.to_s.tr("'", "").sub(GENERIC_SUFFIX, "")
      open.pop while !open.empty? && open.last[:indent] >= indent
      open << {name: open.empty? ? short : "#{open.last[:name]}+#{short}", short: short,
               header: +"#{leading}\n", body: +"", indent: indent, declaring: open.last&.fetch(:name)}
      next
    end
    next if open.empty?

    if leading.start_with?("} // end of class ") && indent == open.last[:indent] &&
       leading.sub("} // end of class ", "").tr("'", "").sub(GENERIC_SUFFIX, "") == open.last[:short]
      frame = open.pop
      bodies[frame[:name]] = frame
      next
    end
    # Everything between the `.class` line and its opening brace is the declaration: `extends`,
    # `implements` and every continuation line of a multi-interface list.
    if !open.last[:header].include?("{")
      open.last[:header] << "#{leading}\n"
      next
    end
    open.last[:body] << line
  end
  bodies
end

LDC = {
  "ldc.i4.m1" => -1, "ldc.i4.0" => 0, "ldc.i4.1" => 1, "ldc.i4.2" => 2, "ldc.i4.3" => 3,
  "ldc.i4.4" => 4, "ldc.i4.5" => 5, "ldc.i4.6" => 6, "ldc.i4.7" => 7, "ldc.i4.8" => 8
}.freeze

def constant(op, operand)
  return LDC[op] if LDC.key?(op)
  return Integer(operand.strip) if %w[ldc.i4 ldc.i4.s].include?(op) && operand.to_s.strip.match?(/\A-?\d+\z/)

  nil
end

# Splits a type body into its `.method`, `.field` and `.property` declarations. Every member keeps
# the raw operand stream only long enough to derive facts from it; none of it is written out.
def members(body)
  found = []
  header = nil
  current = nil
  depth = 0
  body.each_line do |line|
    stripped = line.rstrip
    leading = stripped.lstrip
    indent = line[/\A */].length

    if current && current[:kind] == "property"
      # `ikdasm` wraps a `.property` whose type is long onto a second line, leaving the property
      # name there rather than on the `.property` line. Reading only the first line names it "".
      if current[:name].empty? && !leading.start_with?("{", "}", ".")
        current[:declaration] = "#{current[:declaration]} #{leading}"
        current[:name] = current[:declaration][/([A-Za-z_.<>'][^(\s]*)\s*\(/, 1].to_s.tr("'", "")
        next
      end
      # A `.property` block declares nothing but its accessors, and their accessibility is the
      # property's: a CLR property whose getter is public is a public property.
      if leading.start_with?("{")
        depth += 1
      elsif leading.start_with?("}")
        depth -= 1
        if depth <= 0
          found << current
          current = nil
        end
      elsif leading.start_with?(".get ", ".set ", ".other ")
        current[:accessors] << {"accessor" => leading.split(" ", 2).first.delete("."),
                                "method" => call_target(leading)}
      end
      next
    end
    if current
      # `ikdasm` closes a method with `} // end of method Type::Name`, never a bare brace, so the
      # nesting depth of `.try`/`catch`/`finally` blocks is what decides where the body ends.
      if leading.start_with?("{")
        depth += 1
      elsif leading.start_with?("}")
        depth -= 1
        if depth <= 0
          found << current
          current = nil
        end
      elsif (match = /^\s+IL_[0-9a-f]{4}:\s+(\S+)\s*(.*)$/.match(stripped))
        current[:ops] << [match[1], +match[2]]
      elsif !current[:ops].empty? && !leading.empty? && !leading.start_with?(".")
        # `ikdasm` wraps a long operand -- a multi-parameter call signature, a switch table -- onto
        # continuation lines. Reading only the first line loses half of a two-argument throw helper
        # signature, so continuations are folded back onto the operand they belong to.
        current[:ops].last[1] << " " << leading
      end
      next
    end
    if header
      header[:text] << " " << leading
      if header[:text].match?(/\bcil managed\b|\bruntime managed\b/) || leading.end_with?("{")
        current = finish_header(header)
        depth = leading.end_with?("{") ? 1 : 0
        header = nil
      end
      next
    end
    if leading.start_with?(".method ")
      header = {kind: "method", text: +leading.sub(".method ", ""), indent: indent}
      next
    end
    if leading.start_with?(".field ")
      found << field_member(leading)
      next
    end
    next unless leading.start_with?(".property ")

    current = {kind: "property", name: leading[/([A-Za-z_.<>'][^(\s]*)\s*\(/, 1].to_s.tr("'", ""),
               declaration: leading.sub(".property ", ""), static: !leading.include?(" instance "),
               accessors: [], ops: []}
    depth = 0
  end
  found
end

def finish_header(header)
  text = header[:text].gsub(/pinvokeimpl\s*\([^)]*\)/, " ").gsub(/marshal\s*\([^)]*\)/, " ")
  match = METHOD_NAME.match(text)
  name = match ? match[1].tr("'", "") : "?"
  before = match ? text[0...match.begin(1)] : text
  after = match ? text[match.end(1)..] : ""
  parameters = after[/\((.*)\)\s*(?:cil|runtime)\s+managed/m, 1] || after[/\((.*)\)/m, 1] || ""
  flags = before.split(/\s+/)
  access = %w[public family private assembly famorassem famandassem].find { |token| flags.include?(token) } || "public"
  {kind: name == ".ctor" || name == ".cctor" ? "constructor" : "method",
   name: name,
   access: access,
   static: !flags.include?("instance"),
   abstract: flags.include?("abstract"),
   virtual: flags.include?("virtual"),
   returnType: return_type(before),
   parameters: split_parameters(parameters),
   ops: []}
end

MODIFIERS = %w[
  public family private assembly famorassem famandassem hidebysig newslot virtual final abstract
  specialname rtspecialname instance static cil managed runtime pinvokeimpl reqsecobj strict
].freeze

def return_type(before)
  tokens = before.split(/\s+/).reject(&:empty?)
  tokens = tokens.drop_while { |token| MODIFIERS.include?(token) }
  tokens.join(" ").strip
end

def split_parameters(text)
  return [] if text.nil? || text.strip.empty?

  parts = []
  depth = 0
  buffer = +""
  text.each_char do |char|
    case char
    when "<", "[", "(" then depth += 1
    when ">", "]", ")" then depth -= 1
    end
    if char == "," && depth.zero?
      parts << buffer
      buffer = +""
    else
      buffer << char
    end
  end
  parts << buffer
  parts.map { |part| part.strip.gsub(/\s+/, " ") }.reject(&:empty?).map do |part|
    tokens = part.split(" ")
    name = tokens.length > 1 ? tokens.last.tr("'", "") : nil
    type = tokens.length > 1 ? tokens[0..-2].join(" ") : part
    {"type" => type, "name" => name}
  end
end

def field_member(leading)
  declaration = leading.sub(".field ", "").sub(/\s*$/, "")
  # A `literal` field carries its constant after an `=`, so the *name* is the last token before it.
  # Reading `tokens.last` unconditionally names an enum member `int32(0x00000000)` -- the value --
  # for every constant in the assembly. That is the scanner defect this project has hit before:
  # a token bounded on one side only. The declaration is split at the assignment first, and the
  # value is recorded rather than discarded, because for an enum the value *is* the member.
  signature, value = declaration.split(/\s+=\s+/, 2)
  tokens = signature.split(/\s+/)
  access = %w[public family private assembly famorassem famandassem].find { |token| tokens.include?(token) } || "public"
  member = {kind: "field", name: tokens.last.to_s.tr("'", ""), access: access,
            static: tokens.include?("static"), declaration: declaration, ops: []}
  member[:literal] = value.strip if value
  member
end

# One body table per authority, never one merged table. Twelve identities are declared by **both**
# admitted assemblies -- `System.ThrowHelper`, `System.ExceptionResource` and `System.ExceptionArgument`
# among them -- and they are different types with different members. Merging would silently resolve
# a System.dll member's throw against mscorlib's helper and derive a fact about the wrong class.
bodies_by_authority = admitted.transform_values { |entry| type_bodies(entry.fetch("il")) }

# Resolution order for an identity: the authority that is asking first, then the rest in registry
# order. A System.dll family that throws `System.NotSupportedException` resolves it in mscorlib,
# which declares it; a System.dll family that calls `System.ThrowHelper` resolves its own.
def resolve(bodies_by_authority, identity, preferred)
  ordered = ([preferred] + bodies_by_authority.keys).uniq.compact
  ordered.each do |authority|
    frame = bodies_by_authority.fetch(authority, {})[identity]
    return [authority, frame] if frame
  end
  [nil, nil]
end

BRANCHES = /\A(?:br|brtrue|brfalse|beq|bge|bgt|ble|blt|bne|switch|leave)/.freeze

# A constructed generic operand -- `class System.Collections.Generic.ICollection`1<!T>::get_Count()`
# -- defeats a plain Type::Method regex, which happily matches the `T>` at the end of the argument
# list instead of the declaring type. Removing the balanced generic argument lists first leaves the
# CLR definition spelling the rest of this binding uses.
def strip_generic_arguments(text)
  out = +""
  depth = 0
  text.to_s.each_char do |char|
    case char
    when "<" then depth += 1
    when ">" then depth -= 1 if depth.positive?
    else out << char if depth.zero?
    end
  end
  out
end

def call_target(operand)
  match = /(?:\[[^\]]+\])?([A-Za-z_][A-Za-z0-9_.`+'\/]*)::([A-Za-z_.<>'][A-Za-z0-9_.<>`]*)/
          .match(strip_generic_arguments(operand))
  match && "#{match[1].tr("'", "").tr("/", "+")}::#{match[2].tr("'", "")}"
end

# Support tables, all derived, and built **per authority** because both admitted assemblies declare
# their own `System.ThrowHelper`, `System.ExceptionResource` and `System.ExceptionArgument`.
# ExceptionResource / ExceptionArgument turn a bare `ldc.i4.s 28` into the literal
# `NotSupported_ReadOnlyCollection`; ThrowHelper turns a `call ThrowNotSupportedException` into the
# exception identity it actually constructs.
def support_table(bodies, authority)
  SUPPORT_ENUMS.to_h do |enum|
    frame = bodies[enum]
    next [enum, {}] if frame.nil?

    literals = {}
    frame[:body].each_line do |line|
      match = /\.field public static literal valuetype #{Regexp.escape(enum)} ('[^']+'|\S+) = int32\(0x([0-9A-Fa-f]+)\)/.match(line)
      literals[Integer(match[2], 16)] = match[1].tr("'", "") if match
    end
    abort "#{enum} in #{authority} has no literals" if literals.empty?
    [enum, literals]
  end
end

def throw_helper_table(bodies)
  frame = bodies[THROW_HELPER]
  return {} if frame.nil?

  resolved = {}
  edges = {}
  members(frame[:body]).each do |member|
    next unless member[:kind] == "method"

    # A generic helper is declared `Name<T>` and called `Name<!!0>`; both reduce to `Name`.
    helper_name = strip_generic_arguments(member[:name])
    exception = member[:ops].filter_map do |op, operand|
      operand[/\A\s*instance void ([A-Za-z_][A-Za-z0-9_.`]*Exception)::\.ctor/, 1] if op == "newobj"
    end.first
    if exception
      resolved[helper_name] = exception
      next
    end
    # A guard helper such as IfNullAndNullsAreIllegalThenThrow constructs nothing itself; it forwards
    # to the helper that does. Resolving through that edge is what keeps a derived throw fact from
    # falling back on the helper's name.
    forwarded = member[:ops].filter_map do |op, operand|
      next unless op == "call"

      target = call_target(operand)
      target.split("::").last if target&.start_with?("#{THROW_HELPER}::")
    end
    edges[helper_name] = forwarded.uniq unless forwarded.empty?
  end
  loop do
    added = false
    edges.each do |helper, targets|
      next if resolved.key?(helper)

      answers = targets.filter_map { |target| resolved[target] }.uniq
      next unless answers.length == 1

      resolved[helper] = answers.first
      added = true
    end
    break unless added
  end
  resolved
end

support_by_authority = bodies_by_authority.to_h { |authority, bodies| [authority, support_table(bodies, authority)] }
throw_helper_by_authority = bodies_by_authority.transform_values { |bodies| throw_helper_table(bodies) }
# mscorlib is where the collection families' throws are derived, so its tables must be non-empty;
# an authority that declares no ThrowHelper at all is fine and simply derives no helper facts.
SUPPORT_ENUMS.each do |enum|
  abort "#{enum} not found in mscorlib IL" if support_by_authority.fetch("mscorlib").fetch(enum).empty?
end
abort "#{THROW_HELPER} not found in mscorlib IL" if throw_helper_by_authority.fetch("mscorlib").empty?

# ---------------------------------------------------------------------------------------------
# Derived behavioural facts. Never IL text: what a member delegates to, what it throws, and
# whether the throw is unconditional.
# ---------------------------------------------------------------------------------------------


def behaviour(member, throw_helper, support_literals)
  ops = member[:ops]
  return nil if ops.empty?

  throws = []
  pending = []
  ops.each do |op, operand|
    value = constant(op, operand)
    # A throw helper's arguments are the constants pushed immediately before the call. Anything
    # else in between -- a comparison operand, a field read -- ends the window, so an unrelated
    # `ldc.i4.0` from a bounds test can never be read as an ExceptionResource.
    pending.clear if value.nil? && !%w[call callvirt newobj].include?(op)
    pending << value unless value.nil?
    if op == "newobj" && (exception = operand[/\A\s*instance void ([A-Za-z_][A-Za-z0-9_.`]*Exception)::\.ctor/, 1])
      throws << {"exception" => exception, "via" => "newobj"}
      pending.clear
      next
    end
    next unless op == "call" || op == "callvirt"

    target = call_target(operand)
    next unless target&.start_with?("System.ThrowHelper::")

    helper = target.split("::").last
    resource = nil
    argument = nil
    if operand.include?("System.ExceptionResource")
      resource = support_literals.fetch("System.ExceptionResource")[pending.last]
      argument = support_literals.fetch("System.ExceptionArgument")[pending[-2]] if operand.scan("valuetype").length > 1
    elsif operand.include?("System.ExceptionArgument")
      argument = support_literals.fetch("System.ExceptionArgument")[pending.last]
    end
    throws << {"exception" => throw_helper.fetch(helper, "unresolved:#{helper}"), "via" => "System.ThrowHelper::#{helper}",
               "resource" => resource, "argument" => argument}.compact
    pending.clear
  end

  opcodes = ops.map(&:first)
  facts = {}
  facts["throws"] = throws unless throws.empty?
  facts["throwsUnconditionally"] = true if !throws.empty? && opcodes.none? { |op| BRANCHES.match?(op) }
  # A pure forward: load self, read one instance field, push the arguments in order, make one call,
  # return. This is the shape that decides whether a wrapper is a view or a snapshot.
  field = ops.find { |op, _| op == "ldfld" }&.last
  calls = ops.select { |op, _| %w[call callvirt].include?(op) }
  if field && calls.length == 1 && throws.empty? && opcodes.none? { |op| BRANCHES.match?(op) } &&
     opcodes.first == "ldarg.0" && opcodes.last == "ret" &&
     opcodes.all? { |op| op.start_with?("ldarg", "ldfld", "call", "ret", "ldc.i4") }
    facts["delegatesTo"] = call_target(calls.first.last)
    facts["viaField"] = field.to_s.split("::").last.to_s.strip
  end
  facts["storesConstructorArgumentToField"] = ops.any? { |op, _| op == "stfld" } if member[:kind] == "constructor"
  facts.empty? ? nil : facts
end

ACCESS_RANK = {"public" => 3, "family" => 2, "famorassem" => 1}.freeze

# A `.property` declaration carries no accessibility of its own; the CLR reads it from the accessor
# methods. Resolving it here is what lets a property be filtered by the same surface rule as
# everything else instead of being silently dropped.
def annotate_properties(list)
  by_name = list.select { |member| member[:kind] == "method" }.to_h { |member| [member[:name], member] }
  list.each do |member|
    next unless member[:kind] == "property"

    accessors = member[:accessors].filter_map { |entry| by_name[entry.fetch("method").to_s.split("::").last] }
    member[:access] = accessors.map { |accessor| accessor[:access] }
                               .max_by { |access| ACCESS_RANK.fetch(access, 0) } || "private"
  end
  list
end

def surface?(member)
  return true if %w[public family].include?(member[:access].to_s)
  # An explicit interface implementation is IL-private and still observable through the interface.
  # For a read-only collection that is precisely where the refusal to mutate lives.
  member[:kind] == "method" && member[:name].to_s.include?(".")
end

def split_top_level(text)
  parts = []
  buffer = +""
  depth = 0
  text.to_s.each_char do |char|
    case char
    when "<", "[", "(" then depth += 1
    when ">", "]", ")" then depth -= 1
    end
    if char == "," && depth.zero?
      parts << buffer
      buffer = +""
    else
      buffer << char
    end
  end
  parts << buffer
  parts
end

def declaration_of(frame)
  header = frame[:header]
  # `implements` is a comma-separated list, but a constructed generic carries commas of its own:
  # `IDictionary`2<!TKey,!TValue>` is one entry, not two. Splitting only at depth zero is what keeps
  # `!TValue` from being recorded as an interface.
  declared = split_top_level(header[/implements\s+(.*?)\n\{/m, 1].to_s)
                .map { |item| item.strip.gsub(/\s+/, " ") }.reject(&:empty?)
  {"kind" => header.include?(" interface ") ? "interface" : header.include?("extends System.Enum") ? "enum" : "class",
   "baseType" => header[/extends\s+([^\n]+)/, 1]&.strip&.sub(/\s*implements.*/, ""),
   # As declared, so the element projection `<!T>` stays visible, and reduced to the CLR generic
   # definition spelling this binding addresses types by.
   "interfaceDeclarations" => declared,
   "interfaces" => declared.map { |item| strip_generic_arguments(item).sub(/\Aclass\s+/, "").strip },
   "genericParameters" => header[/`(\d+)</, 1]&.to_i || 0,
   "sealed" => header.include?(" sealed "),
   "abstract" => header.include?(" abstract ")}
end

selected = {}
# A public nested type of an admitted family is part of that family's observable surface: the
# enumerator a caller receives from GetEnumerator is reachable from the family's public members.
# The search runs in the family's own authority, because a nested type belongs to its declaring one.
nested = FAMILIES.flat_map do |family, entry|
  bodies = bodies_by_authority.fetch(entry.fetch("authority"))
  bodies.keys.select do |identity|
    identity.start_with?("#{family}+") &&
      (bodies.fetch(identity)[:header].include?(" nested public ") || bodies.fetch(identity)[:header].include?(" public "))
  end.map { |identity| [identity, entry.fetch("authority")] }
end
# Each queue entry carries the authority that asked for it, so resolution prefers that one and only
# falls back across the registry when the identity is not there -- a System.dll family's throws land
# in mscorlib, and its own ThrowHelper does not.
queue = FAMILIES.map { |family, entry| [family, entry.fetch("authority")] } + nested.sort
# The exception closure stops at System.Exception, which is where this binding's projection register
# already roots: System.Exception maps to StandardError, so walking into System.Object would record
# a base the projection never consults.
EXCEPTION_ROOT = "System.Exception"

until queue.empty?
  identity, asked_by = queue.shift
  next if selected.key?(identity)

  authority, frame = resolve(bodies_by_authority, identity, asked_by)
  if frame.nil?
    abort "#{identity} not found in any admitted BCL authority" if FAMILIES.key?(identity)
    next
  end

  throw_helper = throw_helper_by_authority.fetch(authority)
  support_literals = support_by_authority.fetch(authority)
  declaration = declaration_of(frame)
  record = {"authority" => authority}.merge(declaration).merge("members" => [])
  annotate_properties(members(frame[:body])).each do |member|
    next unless surface?(member)

    facts = behaviour(member, throw_helper, support_literals)
    entry = {"kind" => member[:kind], "name" => member[:name], "access" => member[:access],
             "static" => member[:static], "explicitInterface" => member[:access] == "private"}
    entry["literal"] = member[:literal] if member.key?(:literal)
    entry["returnType"] = member[:returnType] if member.key?(:returnType)
    entry["parameters"] = member[:parameters] if member.key?(:parameters)
    entry["declaration"] = member[:declaration] if member.key?(:declaration)
    entry["accessors"] = member[:accessors] if member.key?(:accessors)
    entry["behaviour"] = facts if facts
    record["members"] << entry
    next if facts.nil?

    facts.fetch("throws", []).each do |thrown|
      exception = thrown.fetch("exception")
      queue << [exception, authority] unless exception.start_with?("unresolved:")
    end
  end
  # An exception's own base chain is part of its identity, so walk it up to the projection root.
  base = declaration["baseType"]
  if base && identity != EXCEPTION_ROOT && (identity.end_with?("Exception") || identity == "System.SystemException")
    queue << [base, authority] unless resolve(bodies_by_authority, base, authority).last.nil?
  end
  selected[identity] = record
end

# The third demand channel, and the only one that is neither a signature nor another BCL member's:
# an identity the measured XNA **behaviour** reaches, whose result a Ruby consumer observes.
# `System.ComponentModel.TypeDescriptor` is the case that needs it -- no XNA signature names it and
# no admitted BCL member's does either, yet `MathTypeConverter.ConvertToValues` and
# `ConvertFromValues` both call `GetConverter`, so the string form of every value the thirteen
# converters produce or accept is that class's answer. Admitting it on a remembered claim would be
# exactly the deferral this project refuses, so the evidence is the generated design inventory,
# derived from the same IL by tools/api_compat/build_design_inventory.rb. A family claimed here
# that the generated reach does not carry is refused like any other.
design_inventory_path = File.join(root, "docs", "generated", "design-converter-inventory.json")
design_inventory = File.file?(design_inventory_path) ? JSON.parse(File.read(design_inventory_path)) : {}
behavioural_reach = design_inventory.fetch("reachedBclIdentities", {}).keys
                                    .to_h { |entry| [entry.split(":", 2).last, entry.split(":", 2).first] }

# The intrinsic converter table, extracted rather than remembered.
#
# `TypeDescriptor.GetConverter(Type)` resolves a type with no `TypeConverterAttribute` through
# `ReflectTypeDescriptionProvider`'s static `_intrinsicTypeConverters` hashtable, which is built in
# that class's initialiser as a run of `ldtoken <type>; ldtoken <converter>; ... set_Item`. Reading
# the pairs out of it is what makes "Single converts through SingleConverter" a measurement.
#
# It is also the second demand channel for the three element converter families: the design
# inventory says which element types the generic helpers name, and this says which converter each
# of those resolves to.
intrinsic_frame = bodies_by_authority.fetch("System")["System.ComponentModel.ReflectTypeDescriptionProvider"]
intrinsic_converters = {}
if intrinsic_frame
  pending = []
  members(intrinsic_frame[:body]).each do |member|
    # The table is built lazily in the property getter, not in a static constructor: the field is
    # null-checked and filled on first read. Looking for a `.cctor` finds nothing at all.
    next unless member[:name] == "get_IntrinsicTypeConverters"

    member[:ops].each do |op, operand|
      case op
      when "ldtoken" then pending << operand.to_s.strip.sub(/\A\[[^\]]+\]/, "")
      when "callvirt", "call"
        intrinsic_converters[pending[-2]] = pending[-1] if operand.include?("::set_Item") && pending.length >= 2
        pending.clear if operand.include?("::set_Item")
      end
    end
  end
end
# Every element type the Design family names must resolve here. A converter family admitted for an
# element type the table does not carry would be a guess.
design_inventory.fetch("scalarElementTypes", {}).each_key do |element|
  next if intrinsic_converters.key?(element)

  abort "the Design family converts through #{element} and the intrinsic converter table does not carry it"
end

# The transitive half of the demand rule, measured against what was actually extracted.
bcl_consumers = FAMILIES.keys.to_h do |family|
  users = selected.flat_map do |identity, record|
    next [] if identity == family || identity.start_with?("#{family}+")

    record.fetch("members").filter_map do |member|
      signatures = [member["returnType"], member["declaration"],
                    *member.fetch("parameters", []).map { |parameter| parameter["type"] }].compact
      "#{identity}::#{member.fetch("name")}" if signatures.any? { |signature| signature.include?(family) }
    end
  end.uniq.sort
  [family, users]
end
# A family reached through the intrinsic converter table is demanded the same way one named in the
# Design IL is: the chain is `ConvertToValues<T>` -> `TypeDescriptor.GetConverter(typeof(T))` ->
# this table, and every link of it is generated.
intrinsic_demand = design_inventory.fetch("scalarElementTypes", {}).keys
                                   .filter_map { |element| intrinsic_converters[element] }.uniq

transitively_demanded.each do |family|
  next unless bcl_consumers.fetch(family).empty?
  next if behavioural_reach.key?(family)
  next if intrinsic_demand.include?(family)
  # The CLR base of a demanded element converter is required to represent it.
  next if intrinsic_demand.any? { |converter| selected.dig(converter, "baseType") == family }

  abort "family #{family} has no XNA consumer, no admitted-BCL consumer and no measured behavioural reach; the inventory is demand-driven"
end

families = FAMILIES.map do |family, entry|
  demand = if !consumers.fetch(family).empty?
             "direct"
           elsif !bcl_consumers.fetch(family).empty?
             "transitive"
           else
             "behavioural"
           end
  record = {"family" => family, "authority" => entry.fetch("authority"), "reason" => entry.fetch("reason"),
            "xnaConsumers" => consumers.fetch(family),
            "xnaConsumerCount" => consumers.fetch(family).length,
            "bclConsumers" => bcl_consumers.fetch(family),
            "demand" => demand,
            "types" => selected.keys.select { |identity| identity == family || identity.start_with?("#{family}+") }.sort}
  # Where the reach was measured, for every family the design inventory records -- not only the one
  # that needs it to be admitted at all.
  record["designReachAuthority"] = behavioural_reach.fetch(family) if behavioural_reach.key?(family)
  # Where an element converter's demand comes from: the element type whose intrinsic-table entry
  # names it, so the chain from `ConvertToValues<T>` to this family is visible in one place.
  element = intrinsic_converters.find { |_, converter| converter == family }&.first
  record["intrinsicConverterFor"] = element if element && design_inventory.fetch("scalarElementTypes", {}).key?(element)
  record
end

# Every authority in the registry has to earn its place. An assembly nobody demands is not a
# stronger inventory, it is a larger one, so admitting one whose families are all empty aborts.
AUTHORITIES.each_key do |name|
  next if families.any? { |family| family.fetch("authority") == name }

  abort "authority #{name} is admitted but no family is declared by it; the registry is demand-driven"
end

inventory = {
  "schemaVersion" => 2,
  "authority" => "the Microsoft .NET Framework 4.0 assemblies the pinned XNA 4.0 Windows assemblies bind to, each admitted independently by exact SHA-256",
  "separateFromXna" => "neither mscorlib nor System is an XNA assembly. Nothing here enters REFERENCE_TYPES, REFERENCE_MEMBERS or docs/generated/xna-il-inventory.json, and no BCL identity is an XNA identity.",
  "provenance" => "derived with ikdasm from Microsoft .NET Framework 4.0 assemblies admitted by exact SHA-256. No Microsoft-owned bytes, IL text or machine-local path is reproduced here.",
  "scope" => "demand-driven: a family is admitted only when the XNA reference contract names it or an already-admitted family's measured surface does, and only the surface those consumers can reach is recorded, plus the exception closure that surface throws",
  # One record per independently admitted assembly. Deliberately a map rather than a merged
  # `assembly` object: a consumer that assumed every BCL type lived in mscorlib would now be wrong,
  # and the schema makes it say which authority it means.
  "authorities" => admitted.transform_values { |entry| entry.fetch("record") },
  "throwHelperResolution" => throw_helper_by_authority.transform_values { |table| table.sort.to_h },
  # `ReflectTypeDescriptionProvider`'s intrinsic table, read out of its static initialiser. This is
  # what `TypeDescriptor.GetConverter` answers for a type carrying no TypeConverterAttribute, and
  # it is what resolves the three scalar element types the Design family converts through.
  "intrinsicTypeConverters" => intrinsic_converters.sort.to_h,
  "BCL_AUTHORITIES" => admitted.length,
  "BCL_FAMILIES" => families.length,
  "BCL_TYPES" => selected.length,
  "BCL_MEMBERS" => selected.values.sum { |record| record.fetch("members").length },
  "BCL_EXCEPTION_TYPES" => selected.keys.count { |identity| identity.end_with?("Exception") },
  # Per authority, so no consumer has to assume every BCL type lives in mscorlib.
  "BCL_TYPES_BY_AUTHORITY" => admitted.keys.to_h do |name|
    [name, selected.count { |_, record| record.fetch("authority") == name }]
  end,
  "BCL_MEMBERS_BY_AUTHORITY" => admitted.keys.to_h do |name|
    [name, selected.sum { |_, record| record.fetch("authority") == name ? record.fetch("members").length : 0 }]
  end,
  "BCL_FAMILIES_BY_AUTHORITY" => admitted.keys.to_h do |name|
    [name, families.count { |family| family.fetch("authority") == name }]
  end,
  "families" => families,
  "types" => selected.sort.to_h
}

File.write(File.join(root, "docs", "generated", "bcl-inventory.json"), JSON.pretty_generate(inventory) + "\n")

admitted.each do |name, entry|
  record = entry.fetch("record")
  puts "BCL_AUTHORITY=#{name} #{record.fetch("observedAssemblyVersion")} #{record.fetch("derivedPublicKeyToken")} #{record.fetch("sha256")}"
  puts "BCL_AUTHORITY_PAIRING=#{name} #{record.fetch("pairing").fetch("assemblies").length}/#{XNA_PINNED.length}"
end
puts "BCL_AUTHORITIES=#{inventory.fetch("BCL_AUTHORITIES")}"
puts "BCL_FAMILIES=#{inventory.fetch("BCL_FAMILIES")}"
puts "BCL_TYPES=#{inventory.fetch("BCL_TYPES")}"
puts "BCL_MEMBERS=#{inventory.fetch("BCL_MEMBERS")}"
puts "BCL_EXCEPTION_TYPES=#{inventory.fetch("BCL_EXCEPTION_TYPES")}"
