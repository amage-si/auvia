import Base
import ./model.bend as M
import ./text.bend as T
import ./kairo.bend as AK
import ../Mokko/field.bend as MF
import ../Kairo/types.bend as KT
import ../Kairo/edit.bend as KE
import ../Syllo/caret.bend as SC
import ../Runika/font.bend as F
import ../Tessra/geometry.bend as G

# Mokko's text field, made accessible: its EditState becomes the node's
# text (AT-SPI Text), and text requests from assistive technologies
# (EditableText, caret and selection) are performed through Mokko's `feed`
# and Kairo's editing rules, exactly as the user's own typing is. So the
# same refusals apply: a scalar the layout or font cannot show (for
# example U+20AC), a control character or line break, a text over the
# length limit. A refused request changes nothing but the field's error
# message, and its caller is told it failed.

def stops(ss: List<&2, SC.Stop>) -> List<&2, M.Stop>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{SC.Stop{i, x}, rest}:
      Con{M.Stop{i, x}, stops(rest)}

# The field's Content for AK.build.with, from the EditState Mokko's `view`
# returns (FieldView.edit).
def content(e: MF.EditState) -> AK.Content:
  MF.EditState{+id, text, caret, anchor, placeholder, ox, oy, lh, st} = e
  AK.Content{id, T.text(text, caret, anchor, ox, oy, lh, stops(st)), placeholder}

# The field after a request, and whether the request was performed. Redraw
# when `fed.dirty`; perform `fed.request` (a copy or a paste) as for a key
# binding; give `accepted` to the service's `settle`.
type Edited is Data:
  Edited{fed: MF.Fed, accepted: Bool}

def with_edit(f: MF.Field, e: KE.Edit) -> MF.Field:
  MF.Field{old, st, line, scroll, refused} = f
  MF.Field{e, st, line, scroll, refused}

def count(e: KE.Edit) -> U32:
  KE.Edit{t, n, c, a} = e
  n

# f with [a, b) selected (anchor a, caret b; a == b places the caret),
# snapped to caret stops as Kairo places a caret.
def selecting(+f: MF.Field, +a: U32, +b: U32) -> MF.Field:
  with_edit(f, KE.place(KE.place(MF.edit_of(f), a, False{}), b, True{}))

def same_place(a: KE.Edit, b: KE.Edit) -> Bool:
  KE.Edit{t0, n0, +c0, +a0} = a
  KE.Edit{t1, n1, +c1, +a1} = b
  U32.is_eq(c0, c1) && U32.is_eq(a0, a1)

# A request first places the caret or selection, so the field is dirty when
# that moved them too, even if the command itself did not.
def against(+f: MF.Field, fed: MF.Fed, +ok: Bool) -> Edited:
  MF.Fed{+field, dirty, request} = fed
  Edited{MF.Fed{field, dirty || Bool.not(same_place(MF.edit_of(f), MF.edit_of(field))), request}, ok}

def outcome.of(m: Maybe<&2, String>, +f: MF.Field, fed: MF.Fed) -> Edited:
  match m:
    case None{}:
      against(f, fed, True{})
    case Some{why}:
      Edited{MF.refuse(f, why), False{}}

def message_of(fed: MF.Fed) -> Maybe<&2, String>:
  MF.Fed{field, dirty, request} = fed
  MF.message(field)

# A refused edit keeps f (text, caret and selection) and only shows why.
def outcome(+f: MF.Field, +fed: MF.Fed) -> Edited:
  outcome.of(message_of(fed), f, fed)

def fed(+font: F.Font, +size: F32, +bounds: G.Rect, +id: U32, +f: MF.Field, from: MF.Field, a: KT.Action) -> Edited:
  outcome(f, MF.feed(font, size, bounds, id, from, a))

def request_of(a: KE.Applied) -> KE.Request:
  KE.Applied{e, t, c, r} = a
  r

def performed(op: M.TextOp, +font: F.Font, +size: F32, +bounds: G.Rect, +id: U32, +f: MF.Field) -> Edited:
  match op:
    case M.SetCaret{+o}:
      Edited{MF.placed(f, bounds, KE.place(MF.edit_of(f), o, False{})), True{}}
    case M.Select{+a, +b}:
      Edited{MF.placed(f, bounds, MF.edit_of(selecting(f, a, b))), True{}}
    case M.SetContents{text}:
      fed(font, size, bounds, id, f, selecting(f, 0, count(MF.edit_of(f))), KT.TextDelivered{id, text})
    case M.Insert{+o, text}:
      fed(font, size, bounds, id, f, selecting(f, o, o), KT.TextDelivered{id, text})
    case M.Delete{+a, +b}:
      fed(font, size, bounds, id, f, selecting(f, a, b), KT.TextDelivered{id, ""})
    case M.Copy{+a, +b}:
      Edited{MF.Fed{f, False{}, request_of(KE.apply(MF.edit_of(selecting(f, a, b)), KT.Copy{}))}, True{}}
    case M.Cut{+a, +b}:
      fed(font, size, bounds, id, f, selecting(f, a, b), KT.EditRequested{id, KT.Cut{}})
    case M.Paste{+o}:
      fed(font, size, bounds, id, f, selecting(f, o, o), KT.EditRequested{id, KT.Paste{}})

def edit.ok(ok: Bool, op: M.TextOp, +font: F.Font, +size: F32, +bounds: G.Rect, +id: U32, +f: MF.Field) -> Edited:
  match ok:
    case False{}:
      Edited{MF.unchanged(f), False{}}
    case True{}:
      performed(op, font, size, bounds, id, f)

# Performs a text request on the field `id` (laid out in `bounds` with
# `font` at `size`), as Mokko's `feed` performs the user's editing:
#   SetCaret, Select   place the caret, or select (anchor, caret)
#   SetContents        replace the whole text
#   Insert             insert at the offset; the caret ends after it
#   Delete             remove the range
#   Copy               request a copy of the range; the field is unchanged
#   Cut                remove the range and request a copy of it
#   Paste              place the caret and request a paste (the text comes
#                      back later as the user's paste does)
# Kairo must let the user edit the node (AK.editable: a live runtime and an
# enabled editable node). Requests for other ids, or that Kairo or the
# layout refuse, are not accepted.
def edit(+font: F.Font, +size: F32, +bounds: G.Rect, +state: KT.State, +id: U32, f: MF.Field, r: M.Request) -> Edited:
  match r:
    case M.EditText{+rid, op, t}:
      edit.ok(U32.is_eq(rid, id) && AK.editable(state, id), op, font, size, bounds, id, f)
    case _:
      Edited{MF.unchanged(f), False{}}
