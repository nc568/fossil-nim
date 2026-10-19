## A pager that writes through a write-ahead log.
##
## The pager knows nothing about the log and the log knows nothing about SQL;
## this module is the single place where the two meet, which is why neither has
## to import the other.
##
## The durability story in one paragraph: `writePage` marks a page dirty and
## keeps it in cache. `stage()` copies dirty pages into the log as frames and
## records where each page's newest image lives. `commit()` appends the commit
## marker and syncs **once**, whatever the transaction covered. Until that sync
## returns, nothing is promised; after it returns, everything is. A crash before
## the marker means the transaction never happened — not "happened halfway".
##
## The index is not an optimisation. Without it, a page staged into the log but
## since evicted would be re-read from the main file, which is one commit behind,
## and the reader would get yesterday's row with no error whatsoever.

import std/tables
import fossil/db/[errors, pager, vfs, wal]

type
  Store* = ref object
    p*: Pager
    w*: Wal
    commits*: int
    checkpoints*: int

proc attach(s: Store) =
  let w = s.w
  let p = s.p
  p.walRead = proc(off: int; payload: var string): bool =
    w.readFrameAt(off, payload)

  p.walStage = proc(pg: Pager) =
    for pid in pg.dirtyPages:
      let off = w.appendFrame(pid, pg.readPage(pid))
      pg.walIndex[pid] = off
    # The header rides along. A transaction that grew the page count is only
    # durable if the count is durable too.
    pg.walIndex[0] = w.appendFrame(0, pg.headerPage)

  p.walCommit = proc(pg: Pager) =
    if w.pending > 0:
      w.commit(pg.nPages)
      inc s.commits

proc openStore*(dbVfs, walVfs: Vfs; cachePages = DefaultCachePages): Store =
  ## Opens the database and replays whatever the log holds. Recovery happens
  ## here, at open, and nowhere else: a program that opens a database and then
  ## has to remember to call `recover` is a program that will forget.
  # A file shorter than one page is either brand new or had its header torn by
  # a power cut. It is tolerated here and only here: a database that refuses to
  # open after a crash is worse than one that opens empty, and a file under 4 KiB
  # cannot hold a single data page to lose. The pager on its own stays strict,
  # so `t_storage` still rejects truncated input; leniency is a property of the
  # path that owns a log, not of the format.
  result = Store(p: openPager(dbVfs, cachePages, allowTornHeader = true),
                 w: openWal(walVfs))
  result.attach()
  discard recover(result.p, result.w)
  for pid, off in result.w.index: result.p.walIndex[pid] = off

proc commit*(s: Store) =
  ## Stages whatever is dirty, writes the commit marker, syncs once.
  s.p.flush()               # routes to the log while it is attached
  s.p.walCommit(s.p)

proc checkpoint*(s: Store) =
  ## Folds the log into the main file and starts a new generation.
  ##
  ## Two syncs, deliberately: the first makes the main file complete, the second
  ## retires the old frames by bumping the salt. Swapping the order would retire
  ## frames that the main file does not have yet — a crash between them would
  ## lose a committed transaction, which is the one thing a log must never do.
  s.p.flush()
  s.p.walCommit(s.p)

  # Pages that went to the log and were then evicted from the cache are clean,
  # so `flushToVfs` would skip them — yet their newest image exists only in the
  # log. Retiring the log at that point would leave the main file pointing at
  # pages that were never written. Pull every indexed page back into the cache
  # as dirty first; the fold is what makes the log disposable.
  for pid, off in s.p.walIndex:
    if pid == 0: continue                    # the header is written by the fold
    if s.p.walRead == nil: continue
    var payload = ""
    if s.p.walRead(off, payload):
      s.p.writePage(pid, payload)

  s.p.flushToVfs()
  s.p.walIndex.clear()
  checkpoint(s.p, s.w)
  inc s.checkpoints

proc close*(s: Store) =
  s.p.close()      # commits staged frames, then closes the store
  s.w.close()

proc stats*(s: Store): tuple[pages, commits, checkpoints, syncs, staged: int] =
  (s.p.nPages, s.commits, s.checkpoints, s.p.vfs.syncs + s.w.vfs.syncs, s.w.pending)
