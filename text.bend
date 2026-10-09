import Base
import ./model.bend as M

# Queries over a node's text (AT-SPI Text): slices, clusters, words,
# extents, hit tests, selections and the edit between two texts. Offsets
# are Unicode scalars, as AT-SPI's character offsets. Pure; depends only on
# the model. Texts are short (a field holds at most 4096 scalars), so each
# query walks the string or the stops once.

def is_space(+c: U32) -> Bool:
  U32.is_eq(c, 32) || U32.is_eq(c, 160)

def is_mark(+c: U32) -> Bool:
  U32.is_ge(c, 768) && U32.is_le(c, 879)

def is_negative(+v: U32) -> Bool:
  U32.is_ge(v, 2147483648)

# A requested end offset (an AT-SPI i32 carried as U32): negative, or past
# the text, means the end, as in GTK.
def clamp_end(+v: U32, +n: U32) -> U32:
  Bool.pick(U32, is_negative(v) || U32.is_gt(v, n), n, v)

# A requested start offset: negative means 0; past the text, the end.
def clamp_start(+v: U32, +n: U32) -> U32:
  Bool.pick(U32, is_negative(v), 0, U32.min(v, n))

# The scalars [lo, hi) of s (nothing when hi <= lo).
def slice(s: String, +lo: U32, +hi: U32) -> String:
  String.take(String.drop(s, U32.to_nat(lo)), U32.to_nat((U32.max(lo, hi) - lo : U32)))

def text_count(t: M.Text) -> U32:
  M.Text{c, n, ca, an, ox, oy, lh, st} = t
  n

def text_caret(t: M.Text) -> U32:
  M.Text{c, n, ca, an, ox, oy, lh, st} = t
  ca

def content(t: M.Text) -> String:
  M.Text{c, n, ca, an, ox, oy, lh, st} = t
  c

# The text record of a content with its caret, anchor and geometry; the
# count is the content's length in scalars.
def text(content: String, +caret: U32, +anchor: U32, origin_x: F32, origin_y: F32, line_height: F32, stops: List<&2, M.Stop>) -> M.Text:
  +c = content
  M.Text{c, U32.from_nat(String.length(c)), caret, anchor, origin_x, origin_y, line_height, stops}

# The selection as [start, end), in order.
def selection(t: M.Text) -> U32 & U32:
  M.Text{c, n, +ca, +an, ox, oy, lh, st} = t
  (U32.min(ca, an), U32.max(ca, an))

def has_selection(t: M.Text) -> Bool:
  M.Text{c, n, +ca, +an, ox, oy, lh, st} = t
  U32.is_ne(ca, an)

# Clusters
# --------

# A caret cluster: scalars [start, end) drawn from x0 to x1 (x from the
# text's origin). Past the end it is empty, at the end of the text.
type Span is Data:
  Span{start: U32, end: U32, x0: F32, x1: F32}

# Walks the stops keeping the last one at or before i (lo, lx); `found`
# says the stop just read (hi, hx) is past i, which ends the cluster.
def span.go(stops: List<&2, M.Stop>, found: Bool, +i: U32, +lo: U32, +lx: F32, +hi: U32, +hx: F32) -> Span:
  match stops found:
    case _ True{}:
      Span{lo, hi, lx, hx}
    case Nil{} False{}:
      Span{lo, lo, lx, lx}
    case Con{M.Stop{+j, +x}, rest} False{}:
      +past = U32.is_gt(j, i)
      span.go(rest, past, i, Bool.pick(U32, past, lo, j), Bool.pick(F32, past, lx, x), j, x)

# The cluster holding offset i.
def span(stops: List<&2, M.Stop>, +i: U32) -> Span:
  span.go(stops, False{}, i, 0, 0.0, 0, 0.0)

# The x (from the origin) of the caret stop at or before i.
def span_x0(sp: Span) -> F32:
  Span{s, e, x0, x1} = sp
  x0

def x_at(stops: List<&2, M.Stop>, +i: U32) -> F32:
  span_x0(span(stops, i))

# Words
# -----
#
# A word starts at a scalar that is not a space (32 or NBSP), at index 0 or
# after a space, and is not a combining mark past index 0 (Kairo's rule).
# AT-SPI's word granularity runs from the start of the word at the offset to
# the start of the next one, trailing spaces included (GTK's behavior).

def starts_word(+after_space: Bool, +c: U32, +j: U32) -> Bool:
  after_space && Bool.not(is_space(c)) && (U32.is_eq(j, 0) || Bool.not(is_mark(c)))

# The largest word start below `limit` (0 when none); `more` is j < limit.
def word_below(s: String, more: Bool, +j: U32, +limit: U32, +after_space: Bool, +best: U32) -> U32:
  match s more:
    case _ False{}:
      best
    case SNil{} True{}:
      best
    case SCon{Chr{+c}, t} True{}:
      +next = (j + 1 : U32)
      word_below(t, U32.is_lt(next, limit), next, limit, is_space(c), Bool.pick(U32, starts_word(after_space, c, j), j, best))

# The smallest word start above i (the end of the text when none); `found`
# says the index just read, `at`, was it.
def word_above(s: String, found: Bool, +j: U32, +i: U32, +after_space: Bool, +at: U32) -> U32:
  match s found:
    case _ True{}:
      at
    case SNil{} False{}:
      j
    case SCon{Chr{+c}, t} False{}:
      word_above(t, starts_word(after_space, c, j) && U32.is_gt(j, i), (j + 1 : U32), i, is_space(c), j)

# Strings at an offset
# --------------------

# A piece of the text and its offsets [start, end).
type Piece is Data:
  Piece{text: String, start: U32, end: U32}

def piece(+s: String, +lo: U32, +hi: U32) -> Piece:
  Piece{slice(s, lo, hi), lo, hi}

def char_piece(+s: String, sp: Span) -> Piece:
  Span{+lo, +hi, x0, x1} = sp
  piece(s, lo, hi)

def word_piece(+s: String, +i: U32) -> Piece:
  piece(s, word_below(s, True{}, 0, (i + 1 : U32), True{}, 0), word_above(s, False{}, 0, i, True{}, 0))

def inside_piece(inside: Bool, +s: String, +n: U32, +i: U32, +granularity: U32, stops: List<&2, M.Stop>) -> Piece:
  match inside:
    case False{}:
      Piece{"", n, n}
    case True{}:
      Bool.pick(Piece, U32.is_eq(granularity, 0), char_piece(s, span(stops, i)), word_piece(s, i))

def whole(t: M.Text) -> Piece:
  M.Text{c, +n, ca, an, ox, oy, lh, st} = t
  Piece{c, 0, n}

def small_piece(t: M.Text, +i: U32, +granularity: U32) -> Piece:
  M.Text{+c, +n, ca, an, ox, oy, lh, st} = t
  inside_piece(U32.is_lt(i, n), c, n, i, granularity, st)

def piece_at(small: Bool, t: M.Text, +i: U32, +granularity: U32) -> Piece:
  match small:
    case False{}:
      whole(t)
    case True{}:
      small_piece(t, i, granularity)

# GetStringAtOffset: granularity 0 is the character (the caret cluster, a
# base and its combining mark), 1 the word; sentence (2), line (3) and
# paragraph (4) are the whole text, which is one line. Past the end the
# character and the word are empty, at the end.
def string_at(+t: M.Text, +i: U32, +granularity: U32) -> Piece:
  piece_at(U32.is_lt(granularity, 2), t, i, granularity)

# GetTextAtOffset's boundary types: 0 character, 1-2 word start/end, 3-4
# sentence, 5-6 line.
def boundary_granularity(+b: U32) -> U32:
  Bool.pick(U32, U32.is_eq(b, 0), 0, Bool.pick(U32, U32.is_lt(b, 3), 1, 3))

def scalar.of(m: Maybe<&2, Char>) -> U32:
  match m:
    case None{}:
      0
    case Some{Chr{c}}:
      c

# The scalar at offset i, or 0 outside the text.
def scalar_at(+t: M.Text, +i: U32) -> U32:
  M.Text{+c, +n, ca, an, ox, oy, lh, st} = t
  Bool.pick(U32, U32.is_lt(i, n), scalar.of(String.get(c, U32.to_nat(i))), 0)

# Geometry
# --------

# The box of the character at offset i, in window coordinates: its cluster
# (a mark shares its base's box), one line tall. Past the end, an empty box
# at the end of the text, where the caret would stand.
def span_box(sp: Span, +ox: F32, +oy: F32, +lh: F32) -> M.Box:
  Span{s, e, +x0, +x1} = sp
  M.Box{(ox + x0 : F32), oy, (x1 - x0 : F32), lh}

def char_box(+t: M.Text, +i: U32) -> M.Box:
  M.Text{c, n, ca, an, +ox, +oy, +lh, st} = t
  span_box(span(st, i), ox, oy, lh)

# The box of the characters [lo, hi), in either order.
def range_box(+t: M.Text, +a: U32, +b: U32) -> M.Box:
  M.Text{c, n, ca, an, +ox, +oy, +lh, +st} = t
  +x0 = x_at(st, U32.min(a, b))
  +x1 = x_at(st, U32.max(a, b))
  M.Box{(ox + x0 : F32), oy, (x1 - x0 : F32), lh}

def nearest(stops: List<&2, M.Stop>, +px: F32, +best: U32, +gap: F32) -> U32:
  match stops:
    case Nil{}:
      best
    case Con{M.Stop{+j, +x}, rest}:
      +d = F32.abs((px - x : F32))
      +closer = F32.is_lt(d, gap)
      nearest(rest, px, Bool.pick(U32, closer, j, best), Bool.pick(F32, closer, d, gap))

# The offset of the caret stop nearest the window point (ties go left), or
# -1 when the point is outside the text's line or beyond its ends.
def offset_at(+t: M.Text, +px: F32, +py: F32) -> U32:
  M.Text{c, n, ca, an, +ox, +oy, +lh, +st} = t
  +x = (px - ox : F32)
  +inside = (py >= oy : F32) && (py < oy + lh : F32) && (x >= 0.0 : F32) && (x <= x_at(st, n) : F32)
  Bool.pick(U32, inside, nearest(st, x, 0, 1000000000.0), 4294967295)

# Edits
# -----

# How many leading scalars a and b share. `differs` says the pair just read
# differed, so n counted one too many.
def common.go(a: String, b: String, differs: Bool, +n: U32) -> U32:
  match a b differs:
    case _ _ True{}:
      (n - 1 : U32)
    case SCon{Chr{+x}, at} SCon{Chr{+y}, bt} False{}:
      common.go(at, bt, U32.is_ne(x, y), (n + 1 : U32))
    case _ _ False{}:
      n

def common(a: String, b: String) -> U32:
  common.go(a, b, False{}, 0)

# The change from one text to another as one replacement: at `offset`,
# `removed` (removed_count scalars) gave way to `inserted`.
type Change is Data:
  Change{offset: U32, removed: String, removed_count: U32, inserted: String, inserted_count: U32}

def change.of(+old: String, +now: String, +n0: U32, +n1: U32, +p: U32) -> Change:
  +q = common(String.reverse(String.drop(old, U32.to_nat(p))), String.reverse(String.drop(now, U32.to_nat(p))))
  Change{p, slice(old, p, (n0 - q : U32)), (n0 - q - p : U32), slice(now, p, (n1 - q : U32)), (n1 - q - p : U32)}

# The shortest replacement turning old into now: the common prefix and
# suffix are kept (the suffix never overlaps the prefix).
def change(+old: String, +now: String, +n0: U32, +n1: U32) -> Change:
  change.of(old, now, n0, n1, common(old, now))
