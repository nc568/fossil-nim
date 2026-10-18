## Archive generation - ZIP and TAR for Fossil
## Implements real ZIP (STORE method) and TAR (USTAR) from file list

import ../types
import ../storage/sqlite_backend
import ../web/pages/file_page as filePageMod
import std/[strutils, times, os, sequtils, tables, math]

# CRC32 implementation
const crcTable: array[256, uint32] = [
  0x00000000'u32, 0x77073096'u32, 0xEE0E612C'u32, 0x990951BA'u32, 0x076DC419'u32, 0x706AF48F'u32, 0xE963A535'u32, 0x9E6495A3'u32,
  0x0EDB8832'u32, 0x79DCB8A4'u32, 0xE0D5E91E'u32, 0x97D2D988'u32, 0x09B64C2B'u32, 0x7EB17CBD'u32, 0xE7B82D07'u32, 0x90BF1D91'u32,
  0x1DB71064'u32, 0x6AB020F2'u32, 0xF3B97148'u32, 0x84BE41DE'u32, 0x1ADAD47D'u32, 0x6DDDE4EB'u32, 0xF4D4B551'u32, 0x83D385C7'u32,
  0x136C9856'u32, 0x646BA8C0'u32, 0xFD62F97A'u32, 0x8A65C9EC'u32, 0x14015C4F'u32, 0x63066CD9'u32, 0xFA0F3D63'u32, 0x8D080DF5'u32,
  0x3B6E20C8'u32, 0x4C69105E'u32, 0xD56041E4'u32, 0xA2677172'u32, 0x3C03E4D1'u32, 0x4B04D447'u32, 0xD20D85FD'u32, 0xA50AB56B'u32,
  0x35B5A8FA'u32, 0x42B2986C'u32, 0xDBBBC9D6'u32, 0xACBCF940'u32, 0x32D86CE3'u32, 0x45DF5C75'u32, 0xDCD60DCF'u32, 0xABD13D59'u32,
  0x26D930AC'u32, 0x51DE003A'u32, 0xC8D75180'u32, 0xBFD06116'u32, 0x21B4F4B5'u32, 0x56B3C423'u32, 0xCFBA9599'u32, 0xB8BDA50F'u32,
  0x2802B89E'u32, 0x5F058808'u32, 0xC60CD9B2'u32, 0xB10BE924'u32, 0x2F6F7C87'u32, 0x58684C11'u32, 0xC1611DAB'u32, 0xB6662D3D'u32,
  0x76DC4190'u32, 0x01DB7106'u32, 0x98D220BC'u32, 0xEFD5102A'u32, 0x71B18589'u32, 0x06B6B51F'u32, 0x9FBFE4A5'u32, 0xE8B8D433'u32,
  0x7807C9A2'u32, 0x0F00F934'u32, 0x9609A88E'u32, 0xE10E9818'u32, 0x7F6A0DBB'u32, 0x086D3D2D'u32, 0x91646C97'u32, 0xE6635C01'u32,
  0x6B6B51F4'u32, 0x1C6C6162'u32, 0x856530D8'u32, 0xF262004E'u32, 0x6C0695ED'u32, 0x1B01A57B'u32, 0x8208F4C1'u32, 0xF50FC457'u32,
  0x65B0D9C6'u32, 0x12B7E950'u32, 0x8BBEB8EA'u32, 0xFCB9887C'u32, 0x62DD1DDF'u32, 0x15DA2D49'u32, 0x8CD37CF3'u32, 0xFBD44C65'u32,
  0x4DB26158'u32, 0x3AB551CE'u32, 0xA3BC0074'u32, 0xD4BB30E2'u32, 0x4ADFA541'u32, 0x3DD895D7'u32, 0xA4D1C46D'u32, 0xD3D6F4FB'u32,
  0x4369E96A'u32, 0x346ED9FC'u32, 0xAD678846'u32, 0xDA60B8D0'u32, 0x44042D73'u32, 0x33031DE5'u32, 0xAA0A4C5F'u32, 0xDD0D7CC9'u32,
  0x5005713C'u32, 0x270241AA'u32, 0xBE0B1010'u32, 0xC90C2086'u32, 0x5768B525'u32, 0x206F85B3'u32, 0xB966D409'u32, 0xCE61E49F'u32,
  0x5EDEF90E'u32, 0x29D9C998'u32, 0xB0D09822'u32, 0xC7D7A8B4'u32, 0x59B33D17'u32, 0x2EB40D81'u32, 0xB7BD5C3B'u32, 0xC0BA6CAD'u32,
  0xEDB88320'u32, 0x9ABFB3B6'u32, 0x03B6E20C'u32, 0x74B1D29A'u32, 0xEAD54739'u32, 0x9DD277AF'u32, 0x04DB2615'u32, 0x73DC1683'u32,
  0xE3630B12'u32, 0x94643B84'u32, 0x0D6D6A3E'u32, 0x7A6A5AA8'u32, 0xE40ECF0B'u32, 0x9309FF9D'u32, 0x0A00AE27'u32, 0x7D079EB1'u32,
  0xF00F9344'u32, 0x8708A3D2'u32, 0x1E01F268'u32, 0x6906C2FE'u32, 0xF762575D'u32, 0x806567CB'u32, 0x196C3671'u32, 0x6E6B06E7'u32,
  0xFED41B76'u32, 0x89D32BE0'u32, 0x10DA7A5A'u32, 0x67DD4ACC'u32, 0xF9B9DF6F'u32, 0x8EBEEFF9'u32, 0x17B7BE43'u32, 0x60B08ED5'u32,
  0xD6D6A3E8'u32, 0xA1D1937E'u32, 0x38D8C2C4'u32, 0x4FDFF252'u32, 0xD1BB67F1'u32, 0xA6BC5767'u32, 0x3FB506DD'u32, 0x48B2364B'u32,
  0xD80D2BDA'u32, 0xAF0A1B4C'u32, 0x36034AF6'u32, 0x41047A60'u32, 0xDF60EFC3'u32, 0xA867DF55'u32, 0x316E8EEF'u32, 0x4669BE79'u32,
  0xCB61B38C'u32, 0xBC66831A'u32, 0x256FD2A0'u32, 0x5268E236'u32, 0xCC0C7795'u32, 0xBB0B4703'u32, 0x220216B9'u32, 0x5505262F'u32,
  0xC5BA3BBE'u32, 0xB2BD0B28'u32, 0x2BB45A92'u32, 0x5CB36A04'u32, 0xC2D7FFA7'u32, 0xB5D0CF31'u32, 0x2CD99E8B'u32, 0x5BDEAE1D'u32,
  0x9B64C2B0'u32, 0xEC63F226'u32, 0x756AA39C'u32, 0x026D930A'u32, 0x9C0906A9'u32, 0xEB0E363F'u32, 0x72076785'u32, 0x05005713'u32,
  0x95BF4A82'u32, 0xE2B87A14'u32, 0x7BB12BAE'u32, 0x0CB61B38'u32, 0x92D28E9B'u32, 0xE5D5BE0D'u32, 0x7CDCEFB7'u32, 0x0BDBDF21'u32,
  0x86D3D2D4'u32, 0xF1D4E242'u32, 0x68DDB3F8'u32, 0x1FDA836E'u32, 0x81BE16CD'u32, 0xF6B9265B'u32, 0x6FB077E1'u32, 0x18B74777'u32,
  0x88085AE6'u32, 0xFF0F6A70'u32, 0x66063BCA'u32, 0x11010B5C'u32, 0x8F659EFF'u32, 0xF862AE69'u32, 0x616BFFD3'u32, 0x166CCF45'u32,
  0xA00AE278'u32, 0xD70DD2EE'u32, 0x4E048354'u32, 0x3903B3C2'u32, 0xA7672661'u32, 0xD06016F7'u32, 0x4969474D'u32, 0x3E6E77DB'u32,
  0xAED16A4A'u32, 0xD9D65ADC'u32, 0x40DF0B66'u32, 0x37D83BF0'u32, 0xA9BCAE53'u32, 0xDEBB9EC5'u32, 0x47B2CF7F'u32, 0x30B5FFE9'u32,
  0xBDBDF21C'u32, 0xCABAC28A'u32, 0x53B39330'u32, 0x24B4A3A6'u32, 0xBAD03605'u32, 0xCDD70693'u32, 0x54DE5729'u32, 0x23D967BF'u32,
  0xB3667A2E'u32, 0xC4614AB8'u32, 0x5D681B02'u32, 0x2A6F2B94'u32, 0xB40BBE37'u32, 0xC30C8EA1'u32, 0x5A05DF1B'u32, 0x2D02EF8D'u32
]

proc crc32*(data: string): uint32 =
  var crc = 0xFFFFFFFF'u32
  for c in data:
    let b = uint8(c)
    crc = (crc shr 8) xor crcTable[(crc xor uint32(b)) and 0xFF]
  crc xor 0xFFFFFFFF'u32

proc toLittleEndian16(v: uint16): string =
  result = newString(2)
  result[0] = char(v and 0xFF)
  result[1] = char((v shr 8) and 0xFF)

proc toLittleEndian32(v: uint32): string =
  result = newString(4)
  result[0] = char(v and 0xFF)
  result[1] = char((v shr 8) and 0xFF)
  result[2] = char((v shr 16) and 0xFF)
  result[3] = char((v shr 24) and 0xFF)

proc dosTimeDate(t: DateTime): tuple[time: uint16, date: uint16] =
  # DOS time: bits 0-4 sec/2, 5-10 min, 11-15 hour
  # DOS date: bits 0-4 day, 5-8 month, 9-15 year-1980
  let sec = t.second div 2
  let min = t.minute
  let hour = t.hour
  let day = t.monthday
  let month = t.month.ord
  let year = max(0, t.year - 1980)
  let dosTime = uint16((hour shl 11) or (min shl 5) or sec)
  let dosDate = uint16((year shl 9) or (month shl 5) or day)
  (dosTime, dosDate)

# ZIP generation
type ZipEntry = object
  name*: string
  data*: string
  crc*: uint32
  dosTime*: uint16
  dosDate*: uint16
  localHeaderOffset*: uint32

proc createZip*(files: seq[tuple[name: string, content: string]], comment: string = "Fossil-Nim archive"): string =
  ## Create ZIP file with STORE method (no compression)
  var entries: seq[ZipEntry] = @[]
  var output = ""
  var offset: uint32 = 0
  
  let now = now().utc
  
  # Local file headers + data
  for f in files:
    let crc = crc32(f.content)
    let (dosTime, dosDate) = dosTimeDate(now)
    let nameBytes = f.name
    # Local file header
    var header = ""
    header.add toLittleEndian32(0x04034b50'u32) # signature
    header.add toLittleEndian16(20'u16) # version needed
    header.add toLittleEndian16(0'u16) # flags
    header.add toLittleEndian16(0'u16) # compression STORE
    header.add toLittleEndian16(dosTime)
    header.add toLittleEndian16(dosDate)
    header.add toLittleEndian32(crc)
    header.add toLittleEndian32(uint32(f.content.len)) # compressed size
    header.add toLittleEndian32(uint32(f.content.len)) # uncompressed size
    header.add toLittleEndian16(uint16(nameBytes.len))
    header.add toLittleEndian16(0'u16) # extra len
    header.add nameBytes
    # No extra field
    header.add f.content
    
    entries.add ZipEntry(name: f.name, data: f.content, crc: crc, dosTime: dosTime, dosDate: dosDate, localHeaderOffset: offset)
    output.add header
    offset += uint32(header.len)
  
  let centralDirOffset = offset
  var centralDir = ""
  
  for e in entries:
    var cd = ""
    cd.add toLittleEndian32(0x02014b50'u32) # central dir signature
    cd.add toLittleEndian16(20'u16) # version made by
    cd.add toLittleEndian16(20'u16) # version needed
    cd.add toLittleEndian16(0'u16) # flags
    cd.add toLittleEndian16(0'u16) # compression
    cd.add toLittleEndian16(e.dosTime)
    cd.add toLittleEndian16(e.dosDate)
    cd.add toLittleEndian32(e.crc)
    cd.add toLittleEndian32(uint32(e.data.len))
    cd.add toLittleEndian32(uint32(e.data.len))
    cd.add toLittleEndian16(uint16(e.name.len))
    cd.add toLittleEndian16(0'u16) # extra len
    cd.add toLittleEndian16(0'u16) # comment len
    cd.add toLittleEndian16(0'u16) # disk number start
    cd.add toLittleEndian16(0'u16) # internal attrs
    cd.add toLittleEndian32(0x20'u32) # external attrs (archive bit)
    cd.add toLittleEndian32(e.localHeaderOffset)
    cd.add e.name
    centralDir.add cd
    offset += uint32(cd.len)
  
  let centralDirSize = offset - centralDirOffset
  
  # End of central directory
  var eocd = ""
  eocd.add toLittleEndian32(0x06054b50'u32)
  eocd.add toLittleEndian16(0'u16) # disk number
  eocd.add toLittleEndian16(0'u16) # central dir disk
  eocd.add toLittleEndian16(uint16(entries.len)) # entries this disk
  eocd.add toLittleEndian16(uint16(entries.len)) # total entries
  eocd.add toLittleEndian32(centralDirSize)
  eocd.add toLittleEndian32(centralDirOffset)
  eocd.add toLittleEndian16(uint16(comment.len))
  eocd.add comment
  
  output.add centralDir
  output.add eocd
  output

# TAR generation (USTAR)
proc toOctalString(value: int, length: int): string =
  # Octal string padded with zeros, null terminated
  result = newString(length)
  for i in 0..<length:
    result[i] = '\0'
  let octal = toOct(value, length-1)
  for i in 0..<min(octal.len, length-1):
    result[i] = octal[i]

proc createTarHeader(name: string, size: int, mtime: int64, isDir: bool): string =
  result = newString(512)
  for i in 0..<512:
    result[i] = '\0'
  
  # name 0-99
  let nameToWrite = if name.len>100: name[0..99] else: name
  for i in 0..<nameToWrite.len:
    result[i] = nameToWrite[i]
  
  # mode 100-107 (octal)
  let mode = if isDir: 0o755 else: 0o644
  let modeStr = toOct(mode, 7)
  for i in 0..<7:
    result[100+i] = modeStr[i]
  
  # uid 108-115
  let uidStr = toOct(0, 7)
  for i in 0..<7:
    result[108+i] = uidStr[i]
  
  # gid 116-123
  let gidStr = toOct(0, 7)
  for i in 0..<7:
    result[116+i] = gidStr[i]
  
  # size 124-135 (octal, 11 digits + null)
  let sizeStr = toOct(size, 11)
  for i in 0..<11:
    result[124+i] = sizeStr[i]
  
  # mtime 136-147
  let mtimeStr = toOct(int(mtime), 11)
  for i in 0..<11:
    result[136+i] = mtimeStr[i]
  
  # checksum 148-155 - initially spaces
  for i in 148..155:
    result[i] = ' '
  
  # typeflag 156
  result[156] = if isDir: '5' else: '0'
  
  # magic 257-262 "ustar "
  result[257] = 'u'
  result[258] = 's'
  result[259] = 't'
  result[260] = 'a'
  result[261] = 'r'
  result[262] = '\0'
  
  # version 263-264 "00"
  result[263] = '0'
  result[264] = '0'
  
  # uname 265-296
  let uname = "fossil"
  for i in 0..<min(uname.len, 32):
    result[265+i] = uname[i]
  
  # gname 297-328
  let gname = "fossil"
  for i in 0..<min(gname.len, 32):
    result[297+i] = gname[i]
  
  # Calculate checksum
  var sum = 0
  for i in 0..<512:
    sum += int(uint8(result[i]))
  let sumStr = toOct(sum, 6)
  for i in 0..<6:
    result[148+i] = sumStr[i]
  result[154] = '\0'
  result[155] = ' '

proc createTar*(files: seq[tuple[name: string, content: string]], mtime: int64 = 0): string =
  ## Create TAR file (USTAR)
  var output = ""
  let actualMtime = if mtime==0: getTime().toUnix() else: mtime
  
  for f in files:
    let header = createTarHeader(f.name, f.content.len, actualMtime, false)
    output.add header
    output.add f.content
    # Pad to 512 bytes
    let padding = (512 - (f.content.len mod 512)) mod 512
    if padding>0:
      output.add newString(padding)
  
  # Two zero blocks at end
  output.add newString(1024)
  output

# High-level archive creation from Fossil repo
proc createArchiveFromRepo*(backend: SqliteBackend, branch: string = "trunk", path: string = "/", format: string = "zip"): FossilResult[string] =
  ## Create archive from repo files
  ## format: "zip" or "tar" or "tar.gz"
  let listRes = filePageMod.listFilesSqlite(backend, "", 10000)
  if listRes.isErr:
    return err[string](listRes.error.code, listRes.error.msg)
  
  var files: seq[tuple[name: string, content: string]] = @[]
  let cleanPath = path.strip(chars={'/'})
  
  for fileName in listRes.value:
    # Filter by path if specified
    if cleanPath.len>0:
      if not fileName.startsWith(cleanPath):
        continue
    # Get content
    let contentRes = filePageMod.getFileContentSqlite(backend, fileName)
    if contentRes.isOk:
      # Use relative name if path filter
      var archiveName = fileName
      if cleanPath.len>0 and fileName.startsWith(cleanPath):
        archiveName = fileName[cleanPath.len..^1].strip(chars={'/'})
        if archiveName.len==0:
          continue
      files.add (name: archiveName, content: contentRes.value)
  
  if files.len==0:
    return err[string](feNotFound, "no files found for path: " & path)
  
  if format=="zip":
    let zipData = createZip(files, "Fossil-Nim " & branch & " archive")
    ok(zipData)
  elif format=="tar" or format=="tar.gz" or format=="tgz":
    let tarData = createTar(files)
    # For tar.gz, we would need gzip compression - for now return tar, caller can gzip via HTTP header or we can try zlib
    ok(tarData)
  else:
    err[string](feInvalidArg, "unknown format: " & format)

# For HTTP server - create archive bytes
proc createZipArchive*(backend: SqliteBackend, branch: string = "trunk", path: string = "/"): FossilResult[string] =
  createArchiveFromRepo(backend, branch, path, "zip")

proc createTarArchive*(backend: SqliteBackend, branch: string = "trunk", path: string = "/"): FossilResult[string] =
  createArchiveFromRepo(backend, branch, path, "tar")
