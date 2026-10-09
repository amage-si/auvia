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
#
# Incoming bytes sit in one Array<U32>, a byte per slot, filled once from
# the socket's list. Decoding reads it at a position with no closure per
# byte: `run`, the only recursive def, steps a stack of jobs over a state
# record (`St`) and stops at the first read that does not fit. Reads that
# hand back the array next to a byte are passed to the next def as a
# parameter, which destructures them.

# What is left to do. JDec decodes a type and pushes its value; the others
# pop the values of their parts and push the value they make. JVarTy pops
# the signature a variant carries and schedules its type.
type Job is Data:
  JDec{ty: Ty}
  JVarTy{}
  JVar{}
  JArr{sig: String}
  JStruct{}
  JEntry{}
  JSeq{}

# The bytes, where the message starts in them, the read position (relative
# to that start, as alignment is), the message length, the byte order,
# whether every read so far fit, the jobs left and the values decoded so
# far, newest first.
type St is Type:
  St{bytes: Array<U32>, base: U32, pos: U32, len: U32, big: Bool, ok: Bool, jobs: List<&2, Job>, vals: List<&2, Value>}

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

def order64(big: Bool, a: U32, b: U32) -> Value:
  match big:
    case False{}:
      DF64{b, a}
    case True{}:
      DF64{a, b}

# Whether n bytes from pos fit in a message of len bytes (pos <= len).
def fits(+pos: U32, +n: U32, +len: U32) -> Bool:
  (n <= (len - pos : U32) : U32)

# Two, four and eight bytes at i.
def rd2.b(r: Array<U32> & U32, +big: Bool, +a: U32) -> Array<U32> & U32:
  (arr, b) = r
  (arr, join2(big, a, b))

def rd2.a(r: Array<U32> & U32, +big: Bool, +i: U32) -> Array<U32> & U32:
  (arr, a) = r
  rd2.b(arr[(i + 1 : U32)], big, a)

def rd2(arr: Array<U32>, +big: Bool, +i: U32) -> Array<U32> & U32:
  rd2.a(arr[i], big, i)

def rd4.d(r: Array<U32> & U32, +big: Bool, +a: U32, +b: U32, +c: U32) -> Array<U32> & U32:
  (arr, d) = r
  (arr, join4(big, a, b, c, d))

def rd4.c(r: Array<U32> & U32, +big: Bool, +i: U32, +a: U32, +b: U32) -> Array<U32> & U32:
  (arr, c) = r
  rd4.d(arr[(i + 3 : U32)], big, a, b, c)

def rd4.b(r: Array<U32> & U32, +big: Bool, +i: U32, +a: U32) -> Array<U32> & U32:
  (arr, b) = r
  rd4.c(arr[(i + 2 : U32)], big, i, a, b)

def rd4.a(r: Array<U32> & U32, +big: Bool, +i: U32) -> Array<U32> & U32:
  (arr, a) = r
  rd4.b(arr[(i + 1 : U32)], big, i, a)

def rd4(arr: Array<U32>, +big: Bool, +i: U32) -> Array<U32> & U32:
  rd4.a(arr[i], big, i)

def rd8.b(r: Array<U32> & U32, +big: Bool, +a: U32) -> Array<U32> & Value:
  (arr, b) = r
  (arr, order64(big, a, b))

def rd8.a(r: Array<U32> & U32, +big: Bool, +i: U32) -> Array<U32> & Value:
  (arr, a) = r
  rd8.b(rd4(arr, big, (i + 4 : U32)), big, a)

# Eight bytes as DF64{hi, lo}; x and t also land here (Auvia only skips them).
def rd8(arr: Array<U32>, +big: Bool, +i: U32) -> Array<U32> & Value:
  rd8.a(rd4(arr, big, i), big, i)

# Bytes i-k .. i as a list, given the read of byte i.
def grab(k: Nat, r: Array<U32> & U32, +i: U32, acc: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match k:
    case 0n:
      (arr, b) = r
      (arr, Con{b, acc})
    case 1n+p:
      (arr, b) = r
      grab(p, arr[(i - 1 : U32)], (i - 1 : U32), Con{b, acc})

def bytes.go(empty: Bool, arr: Array<U32>, +from: U32, +n: U32) -> Array<U32> & List<&2, U32>:
  match empty:
    case True{}:
      (arr, Nil{})
    case False{}:
      +last = (from + n - 1 : U32)
      grab(U32.to_nat((n - 1 : U32)), arr[last], last, Nil{})

# The n bytes from `from`, as a list.
def bytes(arr: Array<U32>, +from: U32, +n: U32) -> Array<U32> & List<&2, U32>:
  bytes.go(U32.is_eq(n, 0), arr, from, n)

def num_value(k: Tok, +x: U32) -> Value:
  match k:
    case KByte{}:
      DByte{x}
    case KBool{}:
      DBool{U32.is_ne(x, 0)}
    case KI16{}:
      DI16{x}
    case KU16{}:
      DI16{x}
    case KI32{}:
      DI32{x}
    case _:
      DU32{x}

def text_value(k: Tok, s: String) -> Value:
  match k:
    case KPath{}:
      DPath{s}
    case KSig{}:
      DSig{s}
    case _:
      DStr{s}

# State steps
# -----------

def failed(st: St) -> St:
  St{arr, base, pos, len, big, ok, js, vs} = st
  St{arr, base, pos, len, big, False{}, js, vs}

def push_val(st: St, v: Value) -> St:
  St{arr, base, pos, len, big, ok, js, vs} = st
  St{arr, base, pos, len, big, ok, js, Con{v, vs}}

def push2(st: St, a: Job, b: Job) -> St:
  St{arr, base, pos, len, big, ok, js, vs} = st
  St{arr, base, pos, len, big, ok, Con{a, Con{b, js}}, vs}

def push3(st: St, a: Job, b: Job, c: Job) -> St:
  St{arr, base, pos, len, big, ok, js, vs} = st
  St{arr, base, pos, len, big, ok, Con{a, Con{b, Con{c, js}}}, vs}

def aligned.at(fit: Bool, arr: Array<U32>, +base: U32, +pos: U32, +len: U32, big: Bool, js: List<&2, Job>, vs: List<&2, Value>) -> St:
  match fit:
    case True{}:
      St{arr, base, pos, len, big, True{}, js, vs}
    case False{}:
      St{arr, base, pos, len, big, False{}, js, vs}

# Skips the padding up to a multiple of a.
def aligned(+a: U32, st: St) -> St:
  St{arr, +base, +pos, +len, big, ok, js, vs} = st
  +n = pad_len(a, pos)
  aligned.at(ok && fits(pos, n, len), arr, base, (pos + n : U32), len, big, js, vs)

# Fixed-size values: a byte, 16, 32 or 64 bits, aligned to their size.
def fixed.got(r: Array<U32> & Value, +base: U32, +pos: U32, +len: U32, big: Bool, js: List<&2, Job>, vs: List<&2, Value>) -> St:
  (arr, v) = r
  St{arr, base, pos, len, big, True{}, js, Con{v, vs}}

def fixed.wrap(r: Array<U32> & U32, k: Tok) -> Array<U32> & Value:
  (arr, x) = r
  (arr, num_value(k, x))

def fixed.read(k: Tok, arr: Array<U32>, +big: Bool, +i: U32) -> Array<U32> & Value:
  match k:
    case KByte{}:
      fixed.wrap(arr[i], KByte{})
    case KI16{}:
      fixed.wrap(rd2(arr, big, i), KI16{})
    case KU16{}:
      fixed.wrap(rd2(arr, big, i), KU16{})
    case KI64{}:
      rd8(arr, big, i)
    case KU64{}:
      rd8(arr, big, i)
    case KF64{}:
      rd8(arr, big, i)
    case other:
      fixed.wrap(rd4(arr, big, i), other)

def fixed.at(fit: Bool, k: Tok, arr: Array<U32>, +base: U32, +q: U32, +size: U32, +len: U32, +big: Bool, js: List<&2, Job>, vs: List<&2, Value>) -> St:
  match fit:
    case False{}:
      St{arr, base, q, len, big, False{}, js, vs}
    case True{}:
      fixed.got(fixed.read(k, arr, big, (base + q : U32)), base, (q + size : U32), len, big, js, vs)

def fixed(+size: U32, k: Tok, st: St) -> St:
  St{arr, +base, +pos, +len, big, ok, js, vs} = st
  +n = pad_len(size, pos)
  fixed.at(fits(pos, (n + size : U32), len), k, arr, base, (pos + n : U32), size, len, big, js, vs)

# Strings, object paths and signatures: a length (u32, or a byte for
# signatures), the UTF-8 bytes and a NUL, which is skipped unread.
def text.got(r: Array<U32> & List<&2, U32>, k: Tok, +base: U32, +pos: U32, +len: U32, big: Bool, js: List<&2, Job>, vs: List<&2, Value>) -> St:
  (arr, bs) = r
  St{arr, base, pos, len, big, True{}, js, Con{text_value(k, from_utf8(bs)), vs}}

def text.fit(fit: Bool, k: Tok, arr: Array<U32>, +base: U32, +start: U32, +n: U32, +len: U32, big: Bool, js: List<&2, Job>, vs: List<&2, Value>) -> St:
  match fit:
    case False{}:
      St{arr, base, start, len, big, False{}, js, vs}
    case True{}:
      text.got(bytes(arr, (base + start : U32), n), k, base, (start + n + 1 : U32), len, big, js, vs)

# r is the read of the length; the text starts at start.
def text.at(r: Array<U32> & U32, k: Tok, +base: U32, +start: U32, +len: U32, big: Bool, js: List<&2, Job>, vs: List<&2, Value>) -> St:
  (arr, +n) = r
  text.fit((n < (len - start : U32) : U32), k, arr, base, start, n, len, big, js, vs)

def str.at(fit: Bool, k: Tok, arr: Array<U32>, +base: U32, +q: U32, +len: U32, +big: Bool, js: List<&2, Job>, vs: List<&2, Value>) -> St:
  match fit:
    case False{}:
      St{arr, base, q, len, big, False{}, js, vs}
    case True{}:
      text.at(rd4(arr, big, (base + q : U32)), k, base, (q + 4 : U32), len, big, js, vs)

def str(k: Tok, st: St) -> St:
  St{arr, +base, +pos, +len, big, ok, js, vs} = st
  +n = pad_len(4, pos)
  str.at(fits(pos, (n + 4 : U32), len), k, arr, base, (pos + n : U32), len, big, js, vs)

def sig_str.at(fit: Bool, arr: Array<U32>, +base: U32, +pos: U32, +len: U32, big: Bool, js: List<&2, Job>, vs: List<&2, Value>) -> St:
  match fit:
    case False{}:
      St{arr, base, pos, len, big, False{}, js, vs}
    case True{}:
      text.at(arr[(base + pos : U32)], KSig{}, base, (pos + 1 : U32), len, big, js, vs)

def sig_str(st: St) -> St:
  St{arr, +base, +pos, +len, big, ok, js, vs} = st
  sig_str.at((pos < len : U32), arr, base, pos, len, big, js, vs)

def basic(k: Tok, st: St) -> St:
  match k:
    case KByte{}:
      fixed(1, KByte{}, st)
    case KBool{}:
      fixed(4, KBool{}, st)
    case KI16{}:
      fixed(2, KI16{}, st)
    case KU16{}:
      fixed(2, KU16{}, st)
    case KI32{}:
      fixed(4, KI32{}, st)
    case KU32{}:
      fixed(4, KU32{}, st)
    case KFd{}:
      fixed(4, KFd{}, st)
    case KI64{}:
      fixed(8, KI64{}, st)
    case KU64{}:
      fixed(8, KU64{}, st)
    case KF64{}:
      fixed(8, KF64{}, st)
    case KStr{}:
      str(KStr{}, st)
    case KPath{}:
      str(KPath{}, st)
    case KSig{}:
      sig_str(st)
    case _:
      failed(st)

# Arrays: a u32 byte length, padding to the element's alignment (present
# even when the array is empty), then items until the offset end.
def array_head.fit(fit: Bool, arr: Array<U32>, +base: U32, +q: U32, +len: U32, big: Bool, js: List<&2, Job>, vs: List<&2, Value>, +elem: Ty, +end: U32) -> St:
  match fit:
    case False{}:
      St{arr, base, q, len, big, False{}, js, vs}
    case True{}:
      St{arr, base, q, len, big, True{}, Con{JDec{TRep{elem, end}}, Con{JArr{ty_sig(elem)}, js}}, vs}

def array_head.got(r: Array<U32> & U32, +base: U32, +p: U32, +len: U32, big: Bool, js: List<&2, Job>, vs: List<&2, Value>, +elem: Ty) -> St:
  (arr, +n) = r
  +pad = pad_len(ty_align(elem), p)
  +q = (p + pad : U32)
  array_head.fit(fits(p, pad, len), arr, base, q, len, big, js, vs, elem, (q + n : U32))

def array_head.at(fit: Bool, arr: Array<U32>, +base: U32, +q: U32, +len: U32, +big: Bool, js: List<&2, Job>, vs: List<&2, Value>, elem: Ty) -> St:
  match fit:
    case False{}:
      St{arr, base, q, len, big, False{}, js, vs}
    case True{}:
      array_head.got(rd4(arr, big, (base + q : U32)), base, (q + 4 : U32), len, big, js, vs, elem)

def array_head(elem: Ty, st: St) -> St:
  St{arr, +base, +pos, +len, big, ok, js, vs} = st
  +n = pad_len(4, pos)
  array_head.at(fits(pos, (n + 4 : U32), len), arr, base, (pos + n : U32), len, big, js, vs, elem)

def rep(more: Bool, +elem: Ty, +end: U32, st: St) -> St:
  match more:
    case True{}:
      push3(st, JDec{elem}, JDec{TRep{elem, end}}, JSeq{})
    case False{}:
      push_val(st, DEnd{})

def rep_at(elem: Ty, +end: U32, st: St) -> St:
  St{arr, base, +pos, len, big, ok, js, vs} = st
  rep((pos < end : U32), elem, end, St{arr, base, pos, len, big, ok, js, vs})

def dec(t: Ty, st: St) -> St:
  match t:
    case TBasic{k}:
      basic(k, st)
    case TVar{}:
      push3(st, JDec{TBasic{KSig{}}}, JVarTy{}, JVar{})
    case TArr{elem}:
      array_head(elem, st)
    case TRep{elem, end}:
      rep_at(elem, end, st)
    case TStruct{fields}:
      push2(aligned(8, st), JDec{fields}, JStruct{})
    case TEntry{k, v}:
      push3(aligned(8, st), JDec{k}, JDec{v}, JEntry{})
    case TSeq{h, t}:
      push3(st, JDec{h}, JDec{t}, JSeq{})
    case TEnd{}:
      push_val(st, DEnd{})
    case TBad{}:
      failed(st)

# Pops the values a job combines. A stack without them cannot happen; it
# fails the read rather than inventing a value.
def made(j: Job, st: St) -> St:
  match j st:
    case JVarTy{} St{arr, base, pos, len, big, ok, js, Con{DSig{s}, rest}}:
      St{arr, base, pos, len, big, ok, Con{JDec{parse_one(s)}, js}, rest}
    case JVar{} St{arr, base, pos, len, big, ok, js, Con{x, rest}}:
      St{arr, base, pos, len, big, ok, js, Con{DVar{x}, rest}}
    case JArr{s} St{arr, base, pos, len, big, ok, js, Con{x, rest}}:
      St{arr, base, pos, len, big, ok, js, Con{DArr{s, x}, rest}}
    case JStruct{} St{arr, base, pos, len, big, ok, js, Con{x, rest}}:
      St{arr, base, pos, len, big, ok, js, Con{DStruct{x}, rest}}
    case JEntry{} St{arr, base, pos, len, big, ok, js, Con{v, Con{k, rest}}}:
      St{arr, base, pos, len, big, ok, js, Con{DEntry{k, v}, rest}}
    case JSeq{} St{arr, base, pos, len, big, ok, js, Con{t, Con{h, rest}}}:
      St{arr, base, pos, len, big, ok, js, Con{DSeq{h, t}, rest}}
    case _ St{arr, base, pos, len, big, ok, js, vs}:
      St{arr, base, pos, len, big, False{}, js, vs}

def step(j: Job, st: St) -> St:
  match j:
    case JDec{t}:
      dec(t, st)
    case other:
      made(other, st)

# Runs the jobs until none is left, a read does not fit, or fuel (a bound
# on steps) runs out.
def run(fuel: Nat, st: St) -> St:
  match fuel st:
    case 0n St{a, b, p, l, g, o, js, vs}:
      St{a, b, p, l, g, False{}, js, vs}
    case 1n+f St{a, b, p, l, g, False{}, js, vs}:
      St{a, b, p, l, g, False{}, js, vs}
    case 1n+f St{a, b, p, l, g, True{}, Nil{}, vs}:
      St{a, b, p, l, g, True{}, Nil{}, vs}
    case 1n+f St{a, b, p, l, g, True{}, Con{j, js}, vs}:
      run(f, step(j, St{a, b, p, l, g, True{}, js, vs}))

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

def header_ty() -> Ty:
  TArr{TStruct{TSeq{TBasic{KByte{}}, TSeq{TVar{}, TEnd{}}}}}

def message(kind: U32, flags: U32, serial: U32, +fs: Value, body: Value) -> Message:
  Message{kind, flags, serial, word(lookup(fs, 5)), text(lookup(fs, 1)), text(lookup(fs, 2)),
    text(lookup(fs, 3)), text(lookup(fs, 4)), text(lookup(fs, 6)), text(lookup(fs, 7)), body}

def body_ty(+fs: Value) -> Ty:
  parse_sig(text(lookup(fs, 8)))

def top(vs: List<&2, Value>) -> Value:
  match vs:
    case Con{v, rest}:
      v
    case Nil{}:
      DEnd{}

def decoded(ok: Bool, m: Message) -> Maybe<&2, Message>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{m}

# A bound on run's steps: no well-formed message needs more than a few per
# byte, and a malformed one (an array of empty structs) stops here.
def fuel(+len: U32) -> Nat:
  U32.to_nat((len * 16 + 256 : U32))

# The fixed header is read; st has decoded the header fields, then the
# body.
def decode.body(st: St, +ver: U32, kind: U32, flags: U32, serial: U32, +fields: Value) -> Array<U32> & Maybe<&2, Message>:
  St{arr, base, +pos, +len, big, ok, js, vs} = st
  (arr, decoded(ok && U32.is_eq(ver, 1) && U32.is_eq(pos, len), message(kind, flags, serial, fields, top(vs))))

def decode.fields(st: St, +ver: U32, kind: U32, flags: U32, serial: U32) -> Array<U32> & Maybe<&2, Message>:
  St{arr, base, pos, +len, big, ok, js, vs} = st
  +fields = top(vs)
  decode.body(run(fuel(len), aligned(8, St{arr, base, pos, len, big, ok, [JDec{body_ty(fields)}], Nil{}})), ver, kind, flags, serial, fields)

def decode.serial(r: Array<U32> & U32, +base: U32, +len: U32, +big: Bool, kind: U32, flags: U32, ver: U32) -> Array<U32> & Maybe<&2, Message>:
  (arr, serial) = r
  decode.fields(run(fuel(len), St{arr, base, 12, len, big, True{}, [JDec{header_ty()}], Nil{}}), ver, kind, flags, serial)

def decode.ver(r: Array<U32> & U32, +base: U32, +len: U32, +big: Bool, kind: U32, flags: U32) -> Array<U32> & Maybe<&2, Message>:
  (arr, ver) = r
  decode.serial(rd4(arr, big, (base + 8 : U32)), base, len, big, kind, flags, ver)

def decode.flags(r: Array<U32> & U32, +base: U32, +len: U32, +big: Bool, kind: U32) -> Array<U32> & Maybe<&2, Message>:
  (arr, flags) = r
  decode.ver(arr[(base + 3 : U32)], base, len, big, kind, flags)

def decode.kind(r: Array<U32> & U32, +base: U32, +len: U32, +big: Bool) -> Array<U32> & Maybe<&2, Message>:
  (arr, kind) = r
  decode.flags(arr[(base + 2 : U32)], base, len, big, kind)

def decode.order(r: Array<U32> & U32, +base: U32, +len: U32) -> Array<U32> & Maybe<&2, Message>:
  (arr, +e) = r
  decode.kind(arr[(base + 1 : U32)], base, len, U32.is_eq(e, 66))

def decode.fit(fit: Bool, arr: Array<U32>, +base: U32, +len: U32) -> Array<U32> & Maybe<&2, Message>:
  match fit:
    case False{}:
      (arr, None{})
    case True{}:
      decode.order(arr[base], base, len)

# Decodes the len bytes of one message starting at base; None{} if it is
# malformed or unsupported. The array comes back for the next message.
def decode.at(arr: Array<U32>, +base: U32, +len: U32) -> Array<U32> & Maybe<&2, Message>:
  decode.fit((len >= 12 : U32), arr, base, len)

# Loading
# -------

def depth.go(k: Nat, done: Bool, +cap: U32, +n: U32, d: Nat) -> Nat:
  match k done:
    case _ True{}:
      d
    case 0n False{}:
      d
    case 1n+p False{}:
      depth.go(p, ((cap * 2 : U32) >= n : U32), (cap * 2 : U32), n, 1n+d)

# The depth of the smallest array with n slots.
def depth(+n: U32) -> Nat:
  depth.go(32n, (1 >= n : U32), 1, n, 0n)

def fill(xs: List<&2, U32>, arr: Array<U32>, +i: U32) -> Array<U32>:
  match xs:
    case Nil{}:
      arr
    case Con{x, rest}:
      fill(rest, Array.set(U32, arr, i, x), (i + 1 : U32))

# a then b in one array of n = |a| + |b| slots (or more), without
# appending the lists.
def load(a: List<&2, U32>, +na: U32, b: List<&2, U32>, +n: U32) -> Array<U32>:
  fill(b, fill(a, Array.new(U32, depth(n), 0), 0), na)

def snd(r: Array<U32> & Maybe<&2, Message>) -> Maybe<&2, Message>:
  (arr, m) = r
  m

# Decodes one complete message; None{} if it is malformed or unsupported.
def decode(+bytes: List<&2, U32>) -> Maybe<&2, Message>:
  +total = size(bytes)
  snd(decode.at(load(bytes, total, Nil{}, total), 0, total))

# Draining
# --------

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

def total_size(+flen: U32, blen: U32) -> U32:
  +head = (16 + flen : U32)
  (head + pad_len(8, head) + blen : U32)

def frame.flen(r: Array<U32> & U32, +blen: U32) -> Array<U32> & U32:
  (arr, flen) = r
  (arr, total_size(flen, blen))

def frame.blen(r: Array<U32> & U32, +off: U32, +big: Bool) -> Array<U32> & U32:
  (arr, blen) = r
  frame.flen(rd4(arr, big, (off + 12 : U32)), blen)

def frame.order(r: Array<U32> & U32, +off: U32) -> Array<U32> & U32:
  (arr, +e) = r
  +big = U32.is_eq(e, 66)
  frame.blen(rd4(arr, big, (off + 4 : U32)), off, big)

def frame.fit(fit: Bool, arr: Array<U32>, +off: U32) -> Array<U32> & U32:
  match fit:
    case False{}:
      (arr, 0)
    case True{}:
      frame.order(arr[off], off)

# The size of the message starting at off, known once its 16-byte fixed
# header has arrived; 0 before that.
def frame_size(arr: Array<U32>, +off: U32, +n: U32) -> Array<U32> & U32:
  frame.fit(fits(off, 16, n), arr, off)

# What the previous frame decoded to (nothing before the first one).
type Got is Data:
  Start{}
  Got{message: Maybe<&2, Message>}

def got.keep(g: Got, acc: List<&2, Message>) -> List<&2, Message>:
  match g:
    case Start{}:
      acc
    case Got{m}:
      keep(m, acc)

def got.bad(g: Got) -> U32:
  match g:
    case Start{}:
      0
    case Got{m}:
      is_none(m)

# The bytes, what the previous frame decoded to, and whether the frame at
# the current offset is complete (and its size).
type Next is Type:
  Whole{bytes: Array<U32>, prev: Got, need: U32}
  Short{bytes: Array<U32>, prev: Got}

def next.pick(ready: Bool, arr: Array<U32>, +need: U32, g: Got) -> Next:
  match ready:
    case True{}:
      Whole{arr, g, need}
    case False{}:
      Short{arr, g}

def next(r: Array<U32> & U32, +off: U32, +n: U32, g: Got) -> Next:
  (arr, +need) = r
  next.pick(U32.is_ne(need, 0) && fits(off, need, n), arr, need, g)

def next.decoded(r: Array<U32> & Maybe<&2, Message>, +off: U32, +n: U32) -> Next:
  (arr, m) = r
  next(frame_size(arr, off, n), off, n, Got{m})

def rest(r: Array<U32> & List<&2, U32>) -> List<&2, U32>:
  (arr, bs) = r
  bs

def drain.stop(arr: Array<U32>, +from: U32, +n: U32, acc: List<&2, Message>, +bad: U32) -> Inbox:
  Inbox{List.reverse(&2, Message, acc), rest(bytes(arr, from, (n - from : U32))), bad}

# Walks the frames of n bytes from off, decoding each one in place. fuel
# bounds the frames (a well-formed one is at least 16 bytes); when it runs
# out, a complete frame at off is dropped, as the List version did.
def drain.go(fuel: Nat, nx: Next, +off: U32, +n: U32, acc: List<&2, Message>, +bad: U32) -> Inbox:
  match fuel nx:
    case 0n Whole{arr, +g, +need}:
      drain.stop(arr, (off + need : U32), n, got.keep(g, acc), (bad + got.bad(g) : U32))
    case 0n Short{arr, +g}:
      drain.stop(arr, off, n, got.keep(g, acc), (bad + got.bad(g) : U32))
    case 1n+p Short{arr, +g}:
      drain.stop(arr, off, n, got.keep(g, acc), (bad + got.bad(g) : U32))
    case 1n+p Whole{arr, +g, +need}:
      +after = (off + need : U32)
      drain.go(p, next.decoded(decode.at(arr, off, need), after, n), after, n, got.keep(g, acc), (bad + got.bad(g) : U32))

# The messages complete in buf followed by more (the bytes left from the
# last read, then the new ones), read from one array filled once.
def drain.more(+buf: List<&2, U32>, +more: List<&2, U32>) -> Inbox:
  +nb = size(buf)
  +n = (nb + size(more) : U32)
  drain.go(U32.to_nat((n / 16 + 1 : U32)), next(frame_size(load(buf, nb, more, n), 0, n), 0, n, Start{}), 0, n, Nil{}, 0)

def drain(+buf: List<&2, U32>) -> Inbox:
  drain.more(buf, Nil{})

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
