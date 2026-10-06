import Base

# D-Bus wire format (marshalling and unmarshalling), in pure Bend.
#
# Spec: https://dbus.freedesktop.org/doc/dbus-specification.html
# Outgoing messages are little-endian; incoming ones may be either.
# Every alignment is relative to the start of the message; a body starts on
# an 8-byte boundary, so a body marshalled from offset 0 aligns the same way.

# A D-Bus value. Struct fields and array items are DSeq chains ending in
# DEnd, so one recursive def can walk any value.
type Value is Data:
  DByte{v: U32}
  DBool{v: Bool}
  DI16{v: U32}
  DI32{v: U32}
  DU32{v: U32}
  DF64{hi: U32, lo: U32}
  DStr{s: String}
  DPath{s: String}
  DSig{s: String}
  DVar{v: Value}
  DArr{sig: String, items: Value}
  DStruct{items: Value}
  DEntry{k: Value, v: Value}
  DSeq{h: Value, t: Value}
  DEnd{}

# kind: 1 method call, 2 method return, 3 error, 4 signal. An empty string
# or a zero reply serial means the header field is absent.
type Message is Data:
  Message{kind: U32, flags: U32, serial: U32, reply: U32, path: String,
    iface: String, member: String, error: String, dest: String,
    sender: String, body: Value}

# Writer
# ------

# The bytes written so far, newest first, and the offset of the next one.
type Out is Data:
  Out{pos: U32, rev: List<&2, U32>}

def pad_len(+align: U32, pos: U32) -> U32:
  ((align - (pos % align)) % align : U32)

def zeros(n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      zeros(p, Con{0, acc})

def align(+a: U32, o: Out) -> Out:
  Out{+pos, rev} = o
  +n = pad_len(a, pos)
  Out{(pos + n : U32), zeros(U32.to_nat(n), rev)}

def byte_at(+x: U32, n: Nat) -> U32:
  U32.and(U32.shrn(x, n), 255)

# Pushes x little-endian onto a newest-first list.
def push_u32(+x: U32, rev: List<&2, U32>) -> List<&2, U32>:
  Con{byte_at(x, 24n), Con{byte_at(x, 16n), Con{byte_at(x, 8n), Con{U32.and(x, 255), rev}}}}

def w_u8(+x: U32, o: Out) -> Out:
  Out{pos, rev} = o
  Out{(pos + 1 : U32), Con{U32.and(x, 255), rev}}

def w_u16.at(+x: U32, o: Out) -> Out:
  Out{pos, rev} = o
  Out{(pos + 2 : U32), Con{byte_at(x, 8n), Con{U32.and(x, 255), rev}}}

def w_u16(x: U32, o: Out) -> Out:
  w_u16.at(x, align(2, o))

def w_u32.at(x: U32, o: Out) -> Out:
  Out{pos, rev} = o
  Out{(pos + 4 : U32), push_u32(x, rev)}

def w_u32(x: U32, o: Out) -> Out:
  w_u32.at(x, align(4, o))

def w_bytes(bs: List<&2, U32>, o: Out) -> Out:
  match bs:
    case Nil{}:
      o
    case Con{b, rest}:
      w_bytes(rest, w_u8(b, o))

# UTF-8
# -----

def utf8.push(+c: U32, +rest: List<&2, U32>) -> List<&2, U32>:
  one = {Con{c, rest} : List<&2, U32>}
  two = {Con{U32.or(192, U32.shrn(c, 6n)), Con{U32.or(128, U32.and(c, 63)), rest}} : List<&2, U32>}
  three = {Con{U32.or(224, U32.shrn(c, 12n)), Con{U32.or(128, U32.and(U32.shrn(c, 6n), 63)), Con{U32.or(128, U32.and(c, 63)), rest}}} : List<&2, U32>}
  four = {Con{U32.or(240, U32.shrn(c, 18n)), Con{U32.or(128, U32.and(U32.shrn(c, 12n), 63)), Con{U32.or(128, U32.and(U32.shrn(c, 6n), 63)), Con{U32.or(128, U32.and(c, 63)), rest}}}} : List<&2, U32>}
  Bool.pick(List<&2, U32>, (c < 128 : U32), one,
    Bool.pick(List<&2, U32>, (c < 2048 : U32), two,
      Bool.pick(List<&2, U32>, (c < 65536 : U32), three, four)))

def utf8(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{c, rest}:
      utf8.push(Char.to_u32(c), utf8(rest))

# The length of the UTF-8 sequence a lead byte opens.
type Lead is Data:
  Lead1{}
  Lead2{}
  Lead3{}
  Lead4{}

def lead(+b: U32) -> Lead:
  Bool.pick(Lead, (b < 128 : U32), Lead1{},
    Bool.pick(Lead, (b >= 240 : U32), Lead4{},
      Bool.pick(Lead, (b >= 224 : U32), Lead3{},
        Bool.pick(Lead, (b >= 192 : U32), Lead2{}, Lead1{}))))

def lead_of(bs: List<&2, U32>) -> Lead:
  match bs:
    case Nil{}:
      Lead1{}
    case Con{b, rest}:
      lead(b)

def cont(b: U32, n: Nat) -> U32:
  U32.shln(U32.and(b, 63), n)

# D-Bus guarantees valid UTF-8 on the wire; a stray or truncated sequence
# decodes as U+FFFD instead of failing.
def utf8.decode(bs: List<&2, U32>, l: Lead) -> String:
  match bs l:
    case Nil{} _:
      SNil{}
    case Con{b0, Con{b1, +rest}} Lead2{}:
      SCon{Chr{U32.or(U32.shln(U32.and(b0, 31), 6n), cont(b1, 0n))}, utf8.decode(rest, lead_of(rest))}
    case Con{b0, Con{b1, Con{b2, +rest}}} Lead3{}:
      SCon{Chr{U32.or(U32.shln(U32.and(b0, 15), 12n), U32.or(cont(b1, 6n), cont(b2, 0n)))}, utf8.decode(rest, lead_of(rest))}
    case Con{b0, Con{b1, Con{b2, Con{b3, +rest}}}} Lead4{}:
      SCon{Chr{U32.or(U32.shln(U32.and(b0, 7), 18n), U32.or(cont(b1, 12n), U32.or(cont(b2, 6n), cont(b3, 0n))))}, utf8.decode(rest, lead_of(rest))}
    case Con{+b, +rest} Lead1{}:
      SCon{Chr{Bool.pick(U32, (b < 128 : U32), b, 65533)}, utf8.decode(rest, lead_of(rest))}
    case Con{b, +rest} _:
      SCon{Chr{65533}, utf8.decode(rest, lead_of(rest))}

def from_utf8(+bs: List<&2, U32>) -> String:
  utf8.decode(bs, lead_of(bs))

def size(+bs: List<&2, U32>) -> U32:
  U32.from_nat(List.length(&2, U32, bs))

def w_str(s: String, o: Out) -> Out:
  +bs = utf8(s)
  w_u8(0, w_bytes(bs, w_u32(size(bs), o)))

def w_sig(s: String, o: Out) -> Out:
  +bs = utf8(s)
  w_u8(0, w_bytes(bs, w_u8(size(bs), o)))

# Signatures
# ----------

def sig(v: Value) -> String:
  match v:
    case DByte{x}:
      "y"
    case DBool{x}:
      "b"
    case DI16{x}:
      "n"
    case DI32{x}:
      "i"
    case DU32{x}:
      "u"
    case DF64{a, b}:
      "d"
    case DStr{s}:
      "s"
    case DPath{s}:
      "o"
    case DSig{s}:
      "g"
    case DVar{x}:
      "v"
    case DArr{s, items}:
      "a" ++ s
    case DStruct{items}:
      "(" ++ sig(items) ++ ")"
    case DEntry{k, x}:
      "{" ++ sig(k) ++ sig(x) ++ "}"
    case DSeq{h, t}:
      sig(h) ++ sig(t)
    case DEnd{}:
      ""

# y g v: 1; n q: 2; x t d ( {: 8; everything else: 4.
def code_align(+c: U32) -> U32:
  Bool.pick(U32, U32.is_eq(c, 121) || U32.is_eq(c, 103) || U32.is_eq(c, 118), 1,
    Bool.pick(U32, U32.is_eq(c, 110) || U32.is_eq(c, 113), 2,
      Bool.pick(U32, U32.is_eq(c, 120) || U32.is_eq(c, 116) || U32.is_eq(c, 100) || U32.is_eq(c, 40) || U32.is_eq(c, 123), 8, 4)))

def sig_align(s: String) -> U32:
  match s:
    case SNil{}:
      1
    case SCon{c, rest}:
      code_align(Char.to_u32(c))

# Marshalling
# -----------

def out_pos(o: Out) -> U32:
  Out{pos, rev} = o
  pos

def out_rev(o: Out) -> List<&2, U32>:
  Out{pos, rev} = o
  rev

# Closes an array: inner holds the items, written from start; the prefix
# (rev, ending at offset p) gets the length and the padding up to start.
# The length counts the items only, not the padding, which is present even
# when the array is empty.
def array_close(inner: Out, +p: U32, +start: U32, rev: List<&2, U32>) -> Out:
  Out{+end, items} = inner
  Out{end, List.append(&2, U32, items, zeros(U32.to_nat((start - p - 4 : U32)), push_u32((end - start : U32), rev)))}

def array_start(+p: U32, s: String) -> U32:
  (p + 4 + pad_len(sig_align(s), (p + 4 : U32)) : U32)

def marshal(v: Value, o: Out) -> Out:
  match v:
    case DByte{x}:
      w_u8(x, o)
    case DBool{b}:
      w_u32(Bool.to_u32(b), o)
    case DI16{x}:
      w_u16(x, o)
    case DI32{x}:
      w_u32(x, o)
    case DU32{x}:
      w_u32(x, o)
    case DF64{hi, lo}:
      w_u32(hi, w_u32(lo, align(8, o)))
    case DStr{s}:
      w_str(s, o)
    case DPath{s}:
      w_str(s, o)
    case DSig{s}:
      w_sig(s, o)
    case DVar{+x}:
      marshal(x, w_sig(sig(x), o))
    case DArr{s, items}:
      +o4 = align(4, o)
      +p = out_pos(o4)
      +start = array_start(p, s)
      array_close(marshal(items, Out{start, Nil{}}), p, start, out_rev(o4))
    case DStruct{items}:
      marshal(items, align(8, o))
    case DEntry{k, x}:
      marshal(x, marshal(k, align(8, o)))
    case DSeq{h, t}:
      marshal(t, marshal(h, o))
    case DEnd{}:
      o

# Builds a DSeq chain from a list.
def seq(xs: List<&2, Value>) -> Value:
  match xs:
    case Nil{}:
      DEnd{}
    case Con{h, t}:
      DSeq{h, seq(t)}

def array(s: String, xs: List<&2, Value>) -> Value:
  DArr{s, seq(xs)}

def tuple(xs: List<&2, Value>) -> Value:
  DStruct{seq(xs)}

def header_field(code: U32, v: Value, rest: Value) -> Value:
  DSeq{DStruct{DSeq{DByte{code}, DSeq{DVar{v}, DEnd{}}}}, rest}

def opt_str(code: U32, +s: String, +rest: Value) -> Value:
  Bool.pick(Value, String.is_empty(s), rest, header_field(code, DStr{s}, rest))

def opt_path(+s: String, +rest: Value) -> Value:
  Bool.pick(Value, String.is_empty(s), rest, header_field(1, DPath{s}, rest))

def opt_sig(+s: String, +rest: Value) -> Value:
  Bool.pick(Value, String.is_empty(s), rest, header_field(8, DSig{s}, rest))

def opt_reply(+r: U32, +rest: Value) -> Value:
  Bool.pick(Value, U32.is_eq(r, 0), rest, header_field(5, DU32{r}, rest))

def encode.join(head: Out, body: Out) -> List<&2, U32>:
  Out{hp, hrev} = head
  Out{bp, brev} = body
  List.reverse.go(&2, U32, hrev, List.reverse(&2, U32, brev))

# The complete little-endian message, as bytes.
def encode(m: Message) -> List<&2, U32>:
  Message{kind, flags, serial, reply, path, iface, member, error, dest, sender, +body} = m
  +bout = marshal(body, Out{0, Nil{}})
  fields = opt_path(path, opt_str(2, iface, opt_str(3, member, opt_str(4, error, opt_reply(reply, opt_str(6, dest, opt_str(7, sender, opt_sig(sig(body), DEnd{}))))))))
  head = seq([DByte{108}, DByte{kind}, DByte{flags}, DByte{1}, DU32{out_pos(bout)}, DU32{serial}, DArr{"(yv)", fields}])
  encode.join(align(8, marshal(head, Out{0, Nil{}})), bout)

# Signature parsing
# -----------------

type Tok is Data:
  KByte{}
  KBool{}
  KI16{}
  KU16{}
  KI32{}
  KU32{}
  KI64{}
  KU64{}
  KF64{}
  KStr{}
  KPath{}
  KSig{}
  KVar{}
  KFd{}
  KArr{}
  KOpen{}
  KClose{}
  KOpenE{}
  KCloseE{}
  KBad{}

def tok(+c: U32) -> Tok:
  Bool.pick(Tok, U32.is_eq(c, 121), KByte{},
  Bool.pick(Tok, U32.is_eq(c, 98), KBool{},
  Bool.pick(Tok, U32.is_eq(c, 110), KI16{},
  Bool.pick(Tok, U32.is_eq(c, 113), KU16{},
  Bool.pick(Tok, U32.is_eq(c, 105), KI32{},
  Bool.pick(Tok, U32.is_eq(c, 117), KU32{},
  Bool.pick(Tok, U32.is_eq(c, 120), KI64{},
  Bool.pick(Tok, U32.is_eq(c, 116), KU64{},
  Bool.pick(Tok, U32.is_eq(c, 100), KF64{},
  Bool.pick(Tok, U32.is_eq(c, 115), KStr{},
  Bool.pick(Tok, U32.is_eq(c, 111), KPath{},
  Bool.pick(Tok, U32.is_eq(c, 103), KSig{},
  Bool.pick(Tok, U32.is_eq(c, 118), KVar{},
  Bool.pick(Tok, U32.is_eq(c, 104), KFd{},
  Bool.pick(Tok, U32.is_eq(c, 97), KArr{},
  Bool.pick(Tok, U32.is_eq(c, 40), KOpen{},
  Bool.pick(Tok, U32.is_eq(c, 41), KClose{},
  Bool.pick(Tok, U32.is_eq(c, 123), KOpenE{},
  Bool.pick(Tok, U32.is_eq(c, 125), KCloseE{}, KBad{})))))))))))))))))))

def lex(s: String) -> List<&2, Tok>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{c, rest}:
      Con{tok(Char.to_u32(c)), lex(rest)}

# A parsed type. TRep is internal to the decoder: the items of an array,
# read until the byte offset end.
type Ty is Data:
  TBasic{tok: Tok}
  TVar{}
  TArr{elem: Ty}
  TStruct{fields: Ty}
  TEntry{k: Ty, v: Ty}
  TSeq{h: Ty, t: Ty}
  TEnd{}
  TRep{elem: Ty, end: U32}
  TBad{}

def entry(fs: Ty) -> Ty:
  match fs:
    case TSeq{k, TSeq{v, TEnd{}}}:
      TEntry{k, v}
    case _:
      TBad{}

# A parse result: the type and the tokens after it.
type Parsed is Data:
  Parsed{ty: Ty, rest: List<&2, Tok>}

def wrap_arr(p: Parsed) -> Parsed:
  Parsed{t, r} = p
  Parsed{TArr{t}, r}

def wrap_struct(p: Parsed) -> Parsed:
  Parsed{t, r} = p
  Parsed{TStruct{t}, r}

def wrap_entry(p: Parsed) -> Parsed:
  Parsed{t, r} = p
  Parsed{entry(t), r}

def parsed_rest(p: Parsed) -> List<&2, Tok>:
  Parsed{t, r} = p
  r

def parsed_ty(p: Parsed) -> Ty:
  Parsed{t, r} = p
  t

def cons_ty(h: Ty, p: Parsed) -> Parsed:
  Parsed{t, r} = p
  Parsed{TSeq{h, t}, r}

# many=False parses exactly one complete type; many=True parses types up
# to a closer (consumed) or the end of the tokens.
def parse(+fuel: Nat, many: Bool, ts: List<&2, Tok>) -> Parsed:
  match fuel many ts:
    case 0n _ ts:
      Parsed{TBad{}, ts}
    case 1n+p False{} Nil{}:
      Parsed{TBad{}, Nil{}}
    case 1n+p False{} Con{KArr{}, rest}:
      wrap_arr(parse(p, False{}, rest))
    case 1n+p False{} Con{KOpen{}, rest}:
      wrap_struct(parse(p, True{}, rest))
    case 1n+p False{} Con{KOpenE{}, rest}:
      wrap_entry(parse(p, True{}, rest))
    case 1n+p False{} Con{KVar{}, rest}:
      Parsed{TVar{}, rest}
    case 1n+p False{} Con{KClose{}, rest}:
      Parsed{TBad{}, rest}
    case 1n+p False{} Con{KCloseE{}, rest}:
      Parsed{TBad{}, rest}
    case 1n+p False{} Con{KBad{}, rest}:
      Parsed{TBad{}, rest}
    case 1n+p False{} Con{t, rest}:
      Parsed{TBasic{t}, rest}
    case 1n+p True{} Nil{}:
      Parsed{TEnd{}, Nil{}}
    case 1n+p True{} Con{KClose{}, rest}:
      Parsed{TEnd{}, rest}
    case 1n+p True{} Con{KCloseE{}, rest}:
      Parsed{TEnd{}, rest}
    case 1n+p True{} other:
      +first = parse(p, False{}, other)
      cons_ty(parsed_ty(first), parse(p, True{}, parsed_rest(first)))

# Parses a whole signature (a sequence of complete types).
def parse_sig(+s: String) -> Ty:
  parsed_ty(parse(Nat.add(String.length(s), 2n), True{}, lex(s)))

# Parses the single complete type a variant carries.
def parse_one(+s: String) -> Ty:
  parsed_ty(parse(Nat.add(String.length(s), 2n), False{}, lex(s)))

def tok_sig(t: Tok) -> String:
  match t:
    case KByte{}:
      "y"
    case KBool{}:
      "b"
    case KI16{}:
      "n"
    case KU16{}:
      "q"
    case KI32{}:
      "i"
    case KU32{}:
      "u"
    case KI64{}:
      "x"
    case KU64{}:
      "t"
    case KF64{}:
      "d"
    case KStr{}:
      "s"
    case KPath{}:
      "o"
    case KSig{}:
      "g"
    case KVar{}:
      "v"
    case KFd{}:
      "h"
    case _:
      ""

# The signature of a parsed type.
def ty_sig(t: Ty) -> String:
  match t:
    case TBasic{k}:
      tok_sig(k)
    case TVar{}:
      "v"
    case TArr{e}:
      "a" ++ ty_sig(e)
    case TStruct{f}:
      "(" ++ ty_sig(f) ++ ")"
    case TEntry{k, v}:
      "{" ++ ty_sig(k) ++ ty_sig(v) ++ "}"
    case TSeq{h, t}:
      ty_sig(h) ++ ty_sig(t)
    case _:
      ""

def tok_align(t: Tok) -> U32:
  match t:
    case KByte{}:
      1
    case KSig{}:
      1
    case KI16{}:
      2
    case KU16{}:
      2
    case KI64{}:
      8
    case KU64{}:
      8
    case KF64{}:
      8
    case _:
      4

def ty_align(t: Ty) -> U32:
  match t:
    case TBasic{k}:
      tok_align(k)
    case TVar{}:
      1
    case TStruct{f}:
      8
    case TEntry{k, v}:
      8
    case _:
      4

# Reader
# ------

# ok turns False once a read runs past the end or meets a bad type.
type In is Data:
  In{pos: U32, bytes: List<&2, U32>, big: Bool, ok: Bool}

# A reader is a state monad over In, so decoding reads in do blocks.
def Rd(-A: Type) -> Type:
  In -> A & In

def Rd.pure(-A: Type, x: A) -> Rd(A):
  i => (x, i)

def Rd.then(-A: Type, -B: Type, r: A & In, f: A -> Rd(B)) -> B & In:
  (a, i) = r
  f(a, i)

def Rd.bind(-A: Type, -B: Type, m: Rd(A), f: A -> Rd(B)) -> Rd(B):
  i => Rd.then(A, B, m(i), f)

def Rd.value(-A: Type, r: A & In) -> A:
  (a, i) = r
  a

def r_u8.go(bytes: List<&2, U32>, pos: U32, big: Bool, ok: Bool) -> U32 & In:
  match bytes:
    case Nil{}:
      (0, In{pos, Nil{}, big, False{}})
    case Con{b, rest}:
      (b, In{(pos + 1 : U32), rest, big, ok})

def r_u8(inp: In) -> U32 & In:
  In{pos, bytes, big, ok} = inp
  r_u8.go(bytes, pos, big, ok)

def u8() -> Rd(U32):
  i => r_u8(i)

def after(r: U32 & In) -> In:
  (b, i) = r
  i

def r_skip(n: Nat, inp: In) -> In:
  match n:
    case 0n:
      inp
    case 1n+p:
      r_skip(p, after(r_u8(inp)))

def skip(n: Nat) -> Rd(Unit):
  i => (Unit{}, r_skip(n, i))

def r_align(+a: U32, inp: In) -> In:
  In{+pos, bytes, big, ok} = inp
  r_skip(U32.to_nat(pad_len(a, pos)), In{pos, bytes, big, ok})

def align_to(a: U32) -> Rd(Unit):
  i => (Unit{}, r_align(a, i))

def big.go(inp: In) -> Bool & In:
  In{pos, bytes, +big, ok} = inp
  (big, In{pos, bytes, big, ok})

def big() -> Rd(Bool):
  i => big.go(i)

def position.go(inp: In) -> U32 & In:
  In{+pos, bytes, big, ok} = inp
  (pos, In{pos, bytes, big, ok})

def position() -> Rd(U32):
  i => position.go(i)

def okay.go(inp: In) -> Bool & In:
  In{pos, bytes, big, +ok} = inp
  (ok, In{pos, bytes, big, ok})

def okay() -> Rd(Bool):
  i => okay.go(i)

def fail.go(inp: In) -> In:
  In{pos, bytes, big, ok} = inp
  In{pos, bytes, big, False{}}

def fail() -> Rd(Value):
  i => (DEnd{}, fail.go(i))

def join2(big: Bool, a: U32, b: U32) -> U32:
  match big:
    case False{}:
      U32.or(a, U32.shln(b, 8n))
    case True{}:
      U32.or(b, U32.shln(a, 8n))

def join4(big: Bool, a: U32, b: U32, c: U32, d: U32) -> U32:
  match big:
    case False{}:
      U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))
    case True{}:
      U32.or(U32.or(d, U32.shln(c, 8n)), U32.or(U32.shln(b, 16n), U32.shln(a, 24n)))

def u16() -> Rd(U32):
  do Rd<U32>:
    align_to(2)
    g : Bool <- big()
    a : U32 <- u8()
    b : U32 <- u8()
    return join2(g, a, b)

def u32() -> Rd(U32):
  do Rd<U32>:
    align_to(4)
    g : Bool <- big()
    a : U32 <- u8()
    b : U32 <- u8()
    c : U32 <- u8()
    d : U32 <- u8()
    return join4(g, a, b, c, d)

def order64(big: Bool, a: U32, b: U32) -> Value:
  match big:
    case False{}:
      DF64{b, a}
    case True{}:
      DF64{a, b}

# Eight bytes as DF64{hi, lo}; x and t also land here (Auvia only skips them).
def u64() -> Rd(Value):
  do Rd<Value>:
    align_to(8)
    g : Bool <- big()
    a : U32 <- u32()
    b : U32 <- u32()
    return order64(g, a, b)

def r_bytes(n: Nat, inp: In, acc: List<&2, U32>) -> List<&2, U32> & In:
  match n:
    case 0n:
      (List.reverse(&2, U32, acc), inp)
    case 1n+p:
      Rd.then(U32, List<&2, U32>, r_u8(inp), b => i => r_bytes(p, i, Con{b, acc}))

def bytes(n: Nat) -> Rd(List<&2, U32>):
  i => r_bytes(n, i, Nil{})

def str() -> Rd(String):
  do Rd<String>:
    n : U32 <- u32()
    bs : List<&2, U32> <- bytes(U32.to_nat(n))
    skip(1n)
    return from_utf8(bs)

def sig_str() -> Rd(String):
  do Rd<String>:
    n : U32 <- u8()
    bs : List<&2, U32> <- bytes(U32.to_nat(n))
    skip(1n)
    return from_utf8(bs)

def wrap(-A: Type, f: A -> Value, m: Rd(A)) -> Rd(Value):
  Rd.bind(A, Value, m, x => Rd.pure(Value, f(x)))

def basic(t: Tok) -> Rd(Value):
  match t:
    case KByte{}:
      wrap(U32, x => DByte{x}, u8())
    case KBool{}:
      wrap(U32, x => DBool{U32.is_ne(x, 0)}, u32())
    case KI16{}:
      wrap(U32, x => DI16{x}, u16())
    case KU16{}:
      wrap(U32, x => DI16{x}, u16())
    case KI32{}:
      wrap(U32, x => DI32{x}, u32())
    case KU32{}:
      wrap(U32, x => DU32{x}, u32())
    case KFd{}:
      wrap(U32, x => DU32{x}, u32())
    case KI64{}:
      u64()
    case KU64{}:
      u64()
    case KF64{}:
      u64()
    case KStr{}:
      wrap(String, s => DStr{s}, str())
    case KPath{}:
      wrap(String, s => DPath{s}, str())
    case KSig{}:
      wrap(String, s => DSig{s}, sig_str())
    case _:
      fail()

def rep_or_end.go(elem: Ty, +end: U32, inp: In) -> Ty & In:
  In{+pos, bytes, big, ok} = inp
  (Bool.pick(Ty, (pos < end : U32), TRep{elem, end}, TEnd{}), In{pos, bytes, big, ok})

# The items of an array continue while the reader is before end.
def rep_or_end(elem: Ty, end: U32) -> Rd(Ty):
  i => rep_or_end.go(elem, end, i)

def array_end(+elem: Ty) -> Rd(U32):
  do Rd<U32>:
    n : U32 <- u32()
    align_to(ty_align(elem))
    p : U32 <- position()
    return (p + n : U32)

# Decodes a value of type t. fuel bounds the recursion depth; running out
# marks the reader failed. Eight-byte integers come back as DF64 bits.
def dec(+fuel: Nat, t: Ty) -> Rd(Value):
  match fuel t:
    case 0n _:
      fail()
    case 1n+p TBasic{k}:
      basic(k)
    case 1n+p TVar{}:
      do Rd<Value>:
        s : String <- sig_str()
        v : Value <- dec(p, parse_one(s))
        return DVar{v}
    case 1n+p TArr{+elem}:
      do Rd<Value>:
        end : U32 <- array_end(elem)
        next : Ty <- rep_or_end(elem, end)
        items : Value <- dec(p, next)
        return DArr{ty_sig(elem), items}
    case 1n+p TRep{+elem, +end}:
      do Rd<Value>:
        h : Value <- dec(p, elem)
        next : Ty <- rep_or_end(elem, end)
        t : Value <- dec(p, next)
        return DSeq{h, t}
    case 1n+p TStruct{fields}:
      do Rd<Value>:
        align_to(8)
        v : Value <- dec(p, fields)
        return DStruct{v}
    case 1n+p TEntry{k, v}:
      do Rd<Value>:
        align_to(8)
        a : Value <- dec(p, k)
        b : Value <- dec(p, v)
        return DEntry{a, b}
    case 1n+p TSeq{h, t}:
      do Rd<Value>:
        a : Value <- dec(p, h)
        b : Value <- dec(p, t)
        return DSeq{a, b}
    case 1n+p TEnd{}:
      Rd.pure(Value, DEnd{})
    case 1n+p TBad{}:
      fail()

# Header access
# -------------

def lookup(v: Value, +code: U32) -> Value:
  match v:
    case DArr{s, items}:
      lookup(items, code)
    case DSeq{DStruct{DSeq{DByte{c}, DSeq{DVar{x}, DEnd{}}}}, t}:
      Bool.pick(Value, U32.is_eq(c, code), x, lookup(t, code))
    case _:
      DEnd{}

def text(v: Value) -> String:
  match v:
    case DStr{s}:
      s
    case DPath{s}:
      s
    case DSig{s}:
      s
    case _:
      ""

def word(v: Value) -> U32:
  match v:
    case DByte{x}:
      x
    case DI16{x}:
      x
    case DI32{x}:
      x
    case DU32{x}:
      x
    case DBool{b}:
      Bool.to_u32(b)
    case _:
      0

# The arguments of a body, as a list.
def args(v: Value) -> List<&2, Value>:
  match v:
    case DSeq{h, t}:
      Con{h, args(t)}
    case _:
      Nil{}

def arg.pick(m: Maybe<&2, Value>) -> Value:
  match m:
    case None{}:
      DEnd{}
    case Some{x}:
      x

def arg(v: Value, n: Nat) -> Value:
  arg.pick(List.get(&2, Value, args(v), n))

# Framing and decoding
# --------------------

def is_big(bs: List<&2, U32>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case Con{b, rest}:
      U32.is_eq(b, 66)

def total_size(ok: Bool, +flen: U32, blen: U32) -> U32:
  +head = (16 + flen : U32)
  Bool.pick(U32, ok, (head + pad_len(8, head) + blen : U32), 0)

def frame_size.rd() -> Rd(U32):
  do Rd<U32>:
    skip(4n)
    blen : U32 <- u32()
    serial : U32 <- u32()
    flen : U32 <- u32()
    ok : Bool <- okay()
    return total_size(ok, flen, blen)

# The size of the message at the head of buf, known once its 16-byte fixed
# header has arrived; 0 before that.
def frame_size(+buf: List<&2, U32>) -> U32:
  Rd.value(U32, frame_size.rd()(In{0, buf, is_big(buf), True{}}))

# A complete message cut from the head of a byte stream, if one is there.
type Cut is Data:
  Cut{frame: Maybe<&2, List<&2, U32>>, rest: List<&2, U32>}

def cut.at(+need: U32, +buf: List<&2, U32>) -> Cut:
  +ready = U32.is_ne(need, 0) && (size(buf) >= need : U32)
  Bool.pick(Cut, ready, Cut{Some{List.take(&2, U32, buf, U32.to_nat(need))}, List.drop(&2, U32, buf, U32.to_nat(need))}, Cut{None{}, buf})

def cut(+buf: List<&2, U32>) -> Cut:
  cut.at(frame_size(buf), buf)

def decoded(ok: Bool, m: Message) -> Maybe<&2, Message>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{m}

def header_ty() -> Ty:
  TArr{TStruct{TSeq{TBasic{KByte{}}, TSeq{TVar{}, TEnd{}}}}}

def message(kind: U32, flags: U32, serial: U32, +fs: Value, body: Value) -> Message:
  Message{kind, flags, serial, word(lookup(fs, 5)), text(lookup(fs, 1)), text(lookup(fs, 2)),
    text(lookup(fs, 3)), text(lookup(fs, 4)), text(lookup(fs, 6)), text(lookup(fs, 7)), body}

def body_ty(+fs: Value) -> Ty:
  parse_sig(text(lookup(fs, 8)))

def decode.rd(+fuel: Nat, +total: U32) -> Rd(Maybe<&2, Message>):
  do Rd<Maybe<&2, Message>>:
    skip(1n)
    kind : U32 <- u8()
    flags : U32 <- u8()
    ver : U32 <- u8()
    blen : U32 <- u32()
    serial : U32 <- u32()
    +fields : Value <- dec(fuel, header_ty())
    align_to(8)
    body : Value <- dec(fuel, body_ty(fields))
    pos : U32 <- position()
    ok : Bool <- okay()
    return decoded(ok && U32.is_eq(ver, 1) && U32.is_eq(pos, total), message(kind, flags, serial, fields, body))

# Decodes one complete message; None{} if it is malformed or unsupported.
def decode(+bytes: List<&2, U32>) -> Maybe<&2, Message>:
  +total = size(bytes)
  Rd.value(Maybe<&2, Message>, decode.rd(U32.to_nat((total * 2 + 64 : U32)), total)(In{0, bytes, is_big(bytes), True{}}))

# The messages complete in a byte stream, the bytes left over, and how many
# frames failed to decode (they are dropped).
type Inbox is Data:
  Inbox{messages: List<&2, Message>, rest: List<&2, U32>, bad: U32}

def keep(m: Maybe<&2, Message>, acc: List<&2, Message>) -> List<&2, Message>:
  match m:
    case None{}:
      acc
    case Some{x}:
      Con{x, acc}

def is_none(m: Maybe<&2, Message>) -> U32:
  match m:
    case None{}:
      1
    case Some{x}:
      0

def drain.go(fuel: Nat, c: Cut, acc: List<&2, Message>, bad: U32) -> Inbox:
  match fuel c:
    case 0n Cut{f, rest}:
      Inbox{List.reverse(&2, Message, acc), rest, bad}
    case 1n+p Cut{None{}, rest}:
      Inbox{List.reverse(&2, Message, acc), rest, bad}
    case 1n+p Cut{Some{frame}, rest}:
      +m = decode(frame)
      drain.go(p, cut(rest), keep(m, acc), (bad + is_none(m) : U32))

def drain(+buf: List<&2, U32>) -> Inbox:
  drain.go(U32.to_nat((size(buf) / 16 + 1 : U32)), cut(buf), Nil{}, 0)

# Message constructors
# --------------------

def call(dest: String, path: String, iface: String, member: String, body: Value) -> Message:
  Message{1, 0, 0, 0, path, iface, member, "", dest, "", body}

def signal(path: String, iface: String, member: String, body: Value) -> Message:
  Message{4, 0, 0, 0, path, iface, member, "", "", "", body}

def method_return(to: Message, body: Value) -> Message:
  Message{k, f, serial, r, p, i, m, e, d, sender, b} = to
  Message{2, 0, 0, serial, "", "", "", "", sender, "", body}

def error_reply(to: Message, name: String, message: String) -> Message:
  Message{k, f, serial, r, p, i, m, e, d, sender, b} = to
  Message{3, 0, 0, serial, "", "", "", name, sender, "", seq([DStr{message}])}

def with_serial(m: Message, serial: U32) -> Message:
  Message{k, f, old, r, p, i, mem, e, d, s, b} = m
  Message{k, f, serial, r, p, i, mem, e, d, s, b}

# Doubles
# -------

def f32_bits(x: F32) -> U32:
  F32{w} = x
  U32{w}

def f64_parts(s: U32, +e: U32, +m: U32) -> Value:
  +sign = U32.shln(s, 31n)
  zero = {DF64{sign, 0} : Value}
  special = {DF64{U32.or(sign, U32.or(2146435072, U32.shrn(m, 3n))), U32.shln(m, 29n)} : Value}
  normal = {DF64{U32.or(sign, U32.or(U32.shln((e + 896 : U32), 20n), U32.shrn(m, 3n))), U32.shln(U32.and(m, 7), 29n)} : Value}
  Bool.pick(Value, U32.is_eq(e, 0), zero, Bool.pick(Value, U32.is_eq(e, 255), special, normal))

# An F32 as a D-Bus double, exactly (every F32 is a double). Subnormals,
# which a UI value never needs, flush to signed zero.
def f64(x: F32) -> Value:
  +b = f32_bits(x)
  f64_parts(U32.shrn(b, 31n), U32.and(U32.shrn(b, 23n), 255), U32.and(b, 8388607))
