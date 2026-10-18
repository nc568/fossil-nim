## Commit command wrapper

import ../../types
import ../../vcs/commit as vcsCommit
import ../../vcs/checkout as vcsCheckout
import ../../storage/sqlite_backend
import ../../config
import std/[os, options, times, strutils]

proc cmdCommit*(args: seq[string], cfg: FossilConfig, checkoutRoot: string = ""): FossilResult[CommitResult] =
  var root = checkoutRoot
  if root.len == 0:
    let rootRes = vcsCheckout.findCheckoutRoot()
    if rootRes.isErr:
      return err[CommitResult](feNotRepo, "not in a checkout")
    root = rootRes.value

  # Parse args for message, branch, etc.
  var message = ""
  var branch = "trunk"
  var i = 0
  while i < args.len:
    if args[i] == "-m" and i+1 < args.len:
      message = args[i+1]; i+=2
    elif args[i].startsWith("-m="):
      message = args[i].split("=",1)[1]; i+=1
    elif args[i] == "--branch" and i+1 < args.len:
      branch = args[i+1]; i+=2
    elif args[i].startsWith("--branch="):
      branch = args[i].split("=",1)[1]; i+=1
    else:
      inc i

  if message.len == 0:
    return err[CommitResult](feInvalidArg, "commit message required")

  # Resolve repo path
  var repoPath = cfg.repoPath
  if repoPath.len == 0:
    let fossilPath = root / "_FOSSIL_"
    if fileExists(fossilPath):
      var db = SqliteBackend()
      if db.open(fossilPath).isOk:
        let r = db.getMeta("repository")
        if r.isOk: repoPath = r.value
        else:
          let r2 = db.getMeta("repo")
          if r2.isOk: repoPath = r2.value
        db.close()

  if repoPath.len == 0 or not fileExists(repoPath):
    return err[CommitResult](feNotFound, "cannot find repository")

  var repoDb = SqliteBackend()
  if repoDb.open(repoPath).isErr:
    return err[CommitResult](feDbError, "cannot open repo")

  defer: repoDb.close()

  var opts = CommitOptions(message: message, branch: branch, user: getEnv("USER", "unknown"), date: now().utc)
  vcsCommit.commit(repoDb, opts, root)
