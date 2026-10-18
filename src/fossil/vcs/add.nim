## Add / Remove / Rename - tracking file changes

import ../types
import ../config
import std/[os, strutils, tables, sequtils]

type
  AddOptions* = object
    force*: bool
    dotFiles*: bool
    ignoreGlobs*: seq[string]

  RmOptions* = object
    force*: bool

proc isIgnored*(path: string, globs: seq[string]): bool =
  for g in globs:
    # Simple glob: support * and exact contains
    if g.contains("*"):
      # Convert glob to contains check for scaffold: *.o -> .o suffix
      let stripped = g.replace("*", "")
      if stripped.len>0 and path.contains(stripped):
        return true
    else:
      if path.contains(g):
        return true
  false

proc addFiles*(checkoutPath: string, files: seq[string], opts: AddOptions): FossilResult[seq[string]] =
  var added: seq[string] = @[]
  for f in files:
    let full = if isAbsolute(f): f else: checkoutPath / f
    if not fileExists(full) and not dirExists(full):
      if not opts.force:
        return err[seq[string]](feNotFound, "file not found", f)
      else:
        continue
    if isIgnored(f, opts.ignoreGlobs) and not opts.force:
      continue
    # In real fossil, would insert into vfile table
    added.add f
  ok(added)

proc addAll*(checkoutPath: string, opts: AddOptions): FossilResult[seq[string]] =
  var files: seq[string] = @[]
  for path in walkDirRec(checkoutPath):
    if not fileExists(path): continue
    let rel = relativePath(path, checkoutPath)
    if rel.startsWith("_FOSSIL_") or rel.startsWith(".fslckout"): continue
    if not opts.dotFiles and extractFilename(rel).startsWith("."): continue
    if isIgnored(rel, opts.ignoreGlobs): continue
    files.add rel
  addFiles(checkoutPath, files, opts)

proc rmFiles*(checkoutPath: string, files: seq[string], opts: RmOptions): FossilResult[seq[string]] =
  var removed: seq[string] = @[]
  for f in files:
    let full = checkoutPath / f
    if not fileExists(full):
      if not opts.force:
        return err[seq[string]](feNotFound, "file not found", f)
      else:
        continue
    # Would mark as deleted in vfile
    removed.add f
  ok(removed)

proc renameFile*(checkoutPath: string, oldPath: string, newPath: string): FossilResult[void] =
  let oldFull = checkoutPath / oldPath
  let newFull = checkoutPath / newPath
  if not fileExists(oldFull):
    return errVoid(feNotFound, "old file not found", oldPath)
  try:
    moveFile(oldFull, newFull)
    okVoid()
  except:
    errVoid(feIoError, "rename failed", getCurrentExceptionMsg())
