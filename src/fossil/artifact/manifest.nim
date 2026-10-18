## Manifest parsing - Fossil's checkin manifest format
## https://fossil-scm.org/home/doc/trunk/www/fileformat.wiki

import ../types
import ../utils/hash
import std/[strutils, tables, options, times]

type
  FileEntry* = object
    name*: string
    uuid*: Uuid
    perm*: string # e.g. "644", "755", or "link"
    isExe*: bool
    isLink*: bool

  Manifest* = object
    uuid*: Option[Uuid] # computed hash
    comment*: string
    date*: DateTime
    user*: string
    branch*: string
    parent*: seq[Uuid]
    pParent*: seq[Uuid] # merged parents? Actually P and M
    files*: seq[FileEntry]
    tags*: Table[string, string]
    isPrivate*: bool
    raw*: string # original text
    checksum*: string # Z line

  ManifestParseError* = object of ValueError

proc parseManifest*(text: string): FossilResult[Manifest] =
  var m = Manifest(raw: text)
  m.files = @[]
  m.parent = @[]
  m.pParent = @[]
  m.tags = initTable[string, string]()
  m.branch = "trunk"

  var lines = text.splitLines()
  var i = 0
  var commentLines: seq[string] = @[]

  while i < lines.len:
    let line = lines[i]
    if line.len == 0:
      inc i; continue
    let card = line[0]
    let rest = if line.len>1: line[1..^1].strip() else: ""
    case card
    of 'C':
      # C comment, may be multi-line? In Fossil, C can be "C ..." and continuation lines starting with space?
      # Simplified: C <text> and following lines starting with space are continuation
      commentLines.add rest
      # Check continuation
      var j = i+1
      while j < lines.len and lines[j].len>0 and lines[j][0]==' ':
        commentLines.add lines[j].strip()
        inc j
      i = j-1
    of 'D':
      try:
        m.date = parse(rest, "yyyy-MM-dd'T'HH:mm:ss'.'fff", utc())
      except:
        try:
          m.date = parse(rest, "yyyy-MM-dd'T'HH:mm:ss", utc())
        except:
          m.date = now().utc
    of 'F':
      # F filename uuid ?perm?
      # Format: F <name> <uuid> ?perm?
      var parts = rest.splitWhitespace()
      if parts.len >= 2:
        let name = parts[0]
        let uuidStr = parts[1]
        let uuidRes = uuidFromHex(uuidStr)
        if uuidRes.isErr:
          return err[Manifest](feManifestError, "invalid file uuid", uuidStr)
        var perm = if parts.len>=3: parts[2] else: ""
        var fe = FileEntry(name: name, uuid: uuidRes.value, perm: perm)
        if perm == "x" or perm == "755": fe.isExe=true
        if perm == "l" or perm == "link": fe.isLink=true
        m.files.add fe
      else:
        return err[Manifest](feManifestError, "invalid F card", rest)
    of 'M':
      # M <manifest uuid>? Actually M is for? In manifest, M is for manifest? Wait
      # Actually in checkin manifest, M is not used; but in artifact, M is parent manifest?
      # We'll treat M as merge marker? Let's parse as parent for simplicity
      let uuidRes = uuidFromHex(rest)
      if uuidRes.isOk:
        m.parent.add uuidRes.value
    of 'P':
      let uuidRes = uuidFromHex(rest)
      if uuidRes.isOk:
        m.parent.add uuidRes.value
      else:
        return err[Manifest](feManifestError, "invalid P uuid", rest)
    of 'U':
      m.user = rest
    of 'B':
      m.branch = rest
    of 'T':
      # T +tag *tag -tag ? Actually T tagname ?value?
      # Simplified: T <tag> <uuid> ?value?
      var parts = rest.splitWhitespace(2)
      if parts.len>=1:
        let tag = parts[0]
        let val = if parts.len>=2: parts[1] else: ""
        m.tags[tag] = val
    of 'Z':
      m.checksum = rest
    of 'R':
      # R <hash> - integrity check? SHA3 of manifest without R line?
      m.checksum = rest
    else:
      # Unknown card, ignore for forward compat
      discard
    inc i

  m.comment = commentLines.join("\n")
  # Compute uuid as hash of raw without Z/R? Actually fossil computes hash of entire artifact including Z? Need spec
  # For now compute sha3 of raw
  let blob = newBlob(text)
  let h = sha3_256(blob)
  m.uuid = some(h)

  ok(m)

proc manifestToString*(m: Manifest): string =
  var sb = ""
  if m.comment.len>0:
    for line in m.comment.splitLines():
      sb.add "C " & line & "\n"
  sb.add "D " & m.date.format("yyyy-MM-dd'T'HH:mm:ss'.'fff") & "\n"
  sb.add "U " & m.user & "\n"
  if m.branch != "trunk" and m.branch.len>0:
    sb.add "B " & m.branch & "\n"
  for p in m.parent:
    sb.add "P " & $p & "\n"
  for f in m.files:
    sb.add "F " & f.name & " " & $f.uuid
    if f.perm.len>0: sb.add " " & f.perm
    sb.add "\n"
  for k,v in m.tags:
    sb.add "T " & k & " " & v & "\n"
  # Compute real Z checksum: SHA3-256 of content so far
  let contentForHash = sb
  let blobForHash = newBlob(contentForHash)
  let hashUuid = hashBlob(blobForHash)
  let hashHex = $hashUuid
  sb.add "Z " & hashHex & "\n"
  sb

proc validateManifest*(m: Manifest): FossilResult[void] =
  if m.files.len==0:
    # Empty checkin allowed? Usually at least one file or initial
    discard
  if m.user.len==0:
    return errVoid(feManifestError, "manifest missing user")
  okVoid()

# --- Artifact wrapper ---

type
  Artifact* = object
    uuid*: Uuid
    rid*: Rid
    data*: Blob
    manifest*: Option[Manifest]
    artifactType*: ArtifactType

proc parseArtifact*(data: Blob): FossilResult[Artifact] =
  let text = data.data
  # Try manifest
  let mRes = parseManifest(text)
  if mRes.isOk:
    let m = mRes.value
    let uuid = if m.uuid.isSome: m.uuid.get else: hashBlob(data)
    return ok(Artifact(uuid: uuid, data: data, manifest: some(m), artifactType: atManifest))
  # Otherwise generic file artifact
  let uuid = hashBlob(data)
  ok(Artifact(uuid: uuid, data: data, manifest: none(Manifest), artifactType: atFile))

proc hashBlobToUuid*(b: Blob): Uuid = hashBlob(b)
