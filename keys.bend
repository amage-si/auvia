import Base

# Copied from Voltra's keys.bend (2026-10-09) so that Auvia's model stays
# free of GPU-layer imports; keep the two in step.
#
# A persistent map from U32 keys to values: a big-endian Patricia trie
# (Okasaki and Gill, "Fast Mergeable Integer Maps", 1998). A fork splits
# its keys on their highest distinguishing bit, so a lookup follows one
# branch per such bit: at most 32 steps, about log2(n) for n spread keys,
# with no comparison against the keys it passes. `put` and `del` rebuild
# only the path to their key and share the rest.
#
# Values are Data, so a map is Data as well: models can hold it, copy it
# and keep older versions, all valid. Lookups borrow the map. Keys are
# visited in ascending (unsigned) order by `keys` and `values`.

type Keys<-V: Data> is Data:
  Tip{}
  Leaf{key: U32, value: V}
  Fork{prefix: U32, bit: U32, lo: Keys<V>, hi: Keys<V>}

def new(-V: Data) -> Keys<V>:
  Tip{}

# Bit arithmetic
# --------------

# Whether k goes to the low side of a fork on `bit`.
def low(+k: U32, +bit: U32) -> Bool:
  U32.is_eq((k .&. bit : U32), 0)

# The bits of k above `bit` (`bit` is a power of two; above bit 31 there
# are none).
def above(+k: U32, +bit: U32) -> U32:
  (k .&. U32.not((bit + bit - 1 : U32)) : U32)

# Whether k shares a fork's prefix, the bits above its branching bit.
def inside(+k: U32, +prefix: U32, +bit: U32) -> Bool:
  U32.is_eq(above(k, bit), prefix)

# The highest set bit of x (x > 0).
def highest(+x: U32) -> U32:
  +a = (x .|. (x >> 1n) : U32)
  +b = (a .|. (a >> 2n) : U32)
  +c = (b .|. (b >> 4n) : U32)
  +d = (c .|. (c >> 8n) : U32)
  +e = (d .|. (d >> 16n) : U32)
  (e .^. (e >> 1n) : U32)

def join.order(-V: Data, first_low: Bool, +prefix: U32, +bit: U32, a: Keys<V>, b: Keys<V>) -> Keys<V>:
  match first_low:
    case True{}:
      Fork{prefix, bit, a, b}
    case False{}:
      Fork{prefix, bit, b, a}

# Two trees with disjoint key prefixes (ka for a's keys, kb for b's) under
# a fork on their highest differing bit.
def join(-V: Data, +ka: U32, a: Keys<V>, +kb: U32, b: Keys<V>) -> Keys<V>:
  +bit = highest((ka .^. kb : U32))
  join.order(V, low(ka, bit), above(ka, bit), bit, a, b)

# Lookup
# ------

def get.hit(-V: Data, same: Bool, value: V) -> Maybe<&2, V>:
  match same:
    case True{}:
      Some{value}
    case False{}:
      None{}

# One step down: `side` says which of the fork's two sides holds k.
def get.go(-V: Data, n: Nat, side: Bool, lo: Keys<V>, hi: Keys<V>, +k: U32) -> Maybe<&2, V>:
  match n side lo hi:
    case 0n _ _ _:
      None{}
    case 1n+f True{} Fork{p, b, l, h} _:
      get.go(V, f, low(k, b), l, h, k)
    case 1n+f True{} Leaf{j, v} _:
      get.hit(V, U32.is_eq(j, k), v)
    case 1n+f True{} Tip{} _:
      None{}
    case 1n+f False{} _ Fork{p, b, l, h}:
      get.go(V, f, low(k, b), l, h, k)
    case 1n+f False{} _ Leaf{j, v}:
      get.hit(V, U32.is_eq(j, k), v)
    case 1n+f False{} _ Tip{}:
      None{}

# The value of k, if any.
def get(-V: Data, m: Keys<V>, +k: U32) -> Maybe<&2, V>:
  match m:
    case Tip{}:
      None{}
    case Leaf{j, v}:
      get.hit(V, U32.is_eq(j, k), v)
    case Fork{p, b, lo, hi}:
      get.go(V, 32n, low(k, b), lo, hi, k)

def has(-V: Data, m: Keys<V>, +k: U32) -> Bool:
  Maybe.is_some(&2, V, get(V, m, k))

# Insertion
# ---------

def put.leaf(-V: Data, same: Bool, +j: U32, w: V, +k: U32, v: V) -> Keys<V>:
  match same:
    case True{}:
      Leaf{k, v}
    case False{}:
      join(V, k, Leaf{k, v}, j, Leaf{j, w})

# Puts k into the fork m, given whether k shares its prefix (`within`) and
# which side holds k (`side`); each case sees the child it descends into.
def put.go(-V: Data, n: Nat, within: Bool, side: Bool, m: Keys<V>, +k: U32, v: V) -> Keys<V>:
  match n within side m:
    case 0n _ _ m0:
      m0
    case 1n+f False{} _ Fork{+p, b, lo, hi}:
      join(V, k, Leaf{k, v}, p, Fork{p, b, lo, hi})
    case 1n+f True{} True{} Fork{p, b, Tip{}, hi}:
      Fork{p, b, Leaf{k, v}, hi}
    case 1n+f True{} True{} Fork{p, b, Leaf{+j, w}, hi}:
      Fork{p, b, put.leaf(V, U32.is_eq(j, k), j, w, k, v), hi}
    case 1n+f True{} True{} Fork{p, b, Fork{+p2, +b2, l2, h2}, hi}:
      Fork{p, b, put.go(V, f, inside(k, p2, b2), low(k, b2), Fork{p2, b2, l2, h2}, k, v), hi}
    case 1n+f True{} False{} Fork{p, b, lo, Tip{}}:
      Fork{p, b, lo, Leaf{k, v}}
    case 1n+f True{} False{} Fork{p, b, lo, Leaf{+j, w}}:
      Fork{p, b, lo, put.leaf(V, U32.is_eq(j, k), j, w, k, v)}
    case 1n+f True{} False{} Fork{p, b, lo, Fork{+p2, +b2, l2, h2}}:
      Fork{p, b, lo, put.go(V, f, inside(k, p2, b2), low(k, b2), Fork{p2, b2, l2, h2}, k, v)}
    case 1n+f _ _ m1:
      m1

# The map with k bound to v (replacing any earlier value of k).
def put(-V: Data, m: Keys<V>, +k: U32, v: V) -> Keys<V>:
  match m:
    case Tip{}:
      Leaf{k, v}
    case Leaf{+j, w}:
      put.leaf(V, U32.is_eq(j, k), j, w, k, v)
    case Fork{+p, +b, lo, hi}:
      put.go(V, 33n, inside(k, p, b), low(k, b), Fork{p, b, lo, hi}, k, v)

# Removal
# -------

# A fork that lost one side becomes the other side.
def fork.made(-V: Data, +p: U32, +b: U32, lo: Keys<V>, hi: Keys<V>) -> Keys<V>:
  match lo hi:
    case Tip{} h:
      h
    case l Tip{}:
      l
    case l h:
      Fork{p, b, l, h}

def del.leaf(-V: Data, same: Bool, +j: U32, w: V) -> Keys<V>:
  match same:
    case True{}:
      Tip{}
    case False{}:
      Leaf{j, w}

def del.go(-V: Data, n: Nat, within: Bool, side: Bool, m: Keys<V>, +k: U32) -> Keys<V>:
  match n within side m:
    case 0n _ _ m0:
      m0
    case 1n+f False{} _ m1:
      m1
    case 1n+f True{} True{} Fork{+p, +b, Leaf{+j, w}, hi}:
      fork.made(V, p, b, del.leaf(V, U32.is_eq(j, k), j, w), hi)
    case 1n+f True{} True{} Fork{+p, +b, Fork{+p2, +b2, l2, h2}, hi}:
      fork.made(V, p, b, del.go(V, f, inside(k, p2, b2), low(k, b2), Fork{p2, b2, l2, h2}, k), hi)
    case 1n+f True{} False{} Fork{+p, +b, lo, Leaf{+j, w}}:
      fork.made(V, p, b, lo, del.leaf(V, U32.is_eq(j, k), j, w))
    case 1n+f True{} False{} Fork{+p, +b, lo, Fork{+p2, +b2, l2, h2}}:
      fork.made(V, p, b, lo, del.go(V, f, inside(k, p2, b2), low(k, b2), Fork{p2, b2, l2, h2}, k))
    case 1n+f _ _ m2:
      m2

# The map without k.
def del(-V: Data, m: Keys<V>, +k: U32) -> Keys<V>:
  match m:
    case Tip{}:
      Tip{}
    case Leaf{+j, w}:
      del.leaf(V, U32.is_eq(j, k), j, w)
    case Fork{+p, +b, lo, hi}:
      del.go(V, 33n, inside(k, p, b), low(k, b), Fork{p, b, lo, hi}, k)

# Contents
# --------

def size(-V: Data, m: Keys<V>) -> U32:
  match m:
    case Tip{}:
      0
    case Leaf{k, v}:
      1
    case Fork{p, b, lo, hi}:
      (size(V, lo) + size(V, hi) : U32)

def keys.go(-V: Data, m: Keys<V>, acc: List<&2, U32>) -> List<&2, U32>:
  match m:
    case Tip{}:
      acc
    case Leaf{k, v}:
      k <> acc
    case Fork{p, b, lo, hi}:
      keys.go(V, lo, keys.go(V, hi, acc))

# The keys in ascending order.
def keys(-V: Data, m: Keys<V>) -> List<&2, U32>:
  keys.go(V, m, Nil{})

def values.go(-V: Data, m: Keys<V>, acc: List<&2, V>) -> List<&2, V>:
  match m:
    case Tip{}:
      acc
    case Leaf{k, v}:
      v <> acc
    case Fork{p, b, lo, hi}:
      values.go(V, lo, values.go(V, hi, acc))

# The values in the order of their keys.
def values(-V: Data, m: Keys<V>) -> List<&2, V>:
  values.go(V, m, Nil{})
