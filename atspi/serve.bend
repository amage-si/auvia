import Base
import ../model.bend as M
import ../dbus/wire.bend as W
import ./objects.bend as O
import ../text.bend as T

# Answers AT-SPI method calls from the published tree. Pure: the replies
# go back to the bus, and the requests (activate, focus) go to the app,
# which routes them into its interaction state (see kairo.bend).

type Op is Data:
  Introspect{}
  Ping{}
  PropGet{}
  PropGetAll{}
  PropSet{}
  ChildAt{}
  Children{}
  IndexInParent{}
  RelationSet{}
  GetRole{}
  RoleName{}
  LocalizedRoleName{}
  GetState{}
  Attributes{}
  GetApplication{}
  Interfaces{}
  Contains{}
  AtPoint{}
  Extents{}
  Position{}
  Size{}
  Layer{}
  ZOrder{}
  GrabFocus{}
  Alpha{}
  Actions{}
  ActionName{}
  ActionLocalizedName{}
  ActionDescription{}
  KeyBinding{}
  DoAction{}
  Locale{}
  BusAddress{}
  Items{}
  GetText{}
  SetCaretOffset{}
  StringAtOffset{}
  TextAtOffset{}
  CharacterAtOffset{}
  CharacterExtents{}
  RangeExtents{}
  OffsetAtPoint{}
  NSelections{}
  GetSelection{}
  AddSelection{}
  RemoveSelection{}
  SetSelection{}
  AttributeRun{}
  TextAttributes{}
  DefaultAttributes{}
  SetTextContents{}
  InsertText{}
  DeleteText{}
  CopyText{}
  CutText{}
  PasteText{}
  NoOp{}

def base_op(+m: String) -> Op:
  Bool.pick(Op, String.eq(m, "Introspect"), Introspect{},
  Bool.pick(Op, String.eq(m, "Ping"), Ping{},
  Bool.pick(Op, String.eq(m, "Get"), PropGet{},
  Bool.pick(Op, String.eq(m, "GetAll"), PropGetAll{},
  Bool.pick(Op, String.eq(m, "Set"), PropSet{},
  Bool.pick(Op, String.eq(m, "GetChildAtIndex"), ChildAt{},
  Bool.pick(Op, String.eq(m, "GetChildren"), Children{},
  Bool.pick(Op, String.eq(m, "GetIndexInParent"), IndexInParent{},
  Bool.pick(Op, String.eq(m, "GetRelationSet"), RelationSet{},
  Bool.pick(Op, String.eq(m, "GetRole"), GetRole{},
  Bool.pick(Op, String.eq(m, "GetRoleName"), RoleName{},
  Bool.pick(Op, String.eq(m, "GetLocalizedRoleName"), LocalizedRoleName{},
  Bool.pick(Op, String.eq(m, "GetState"), GetState{},
  Bool.pick(Op, String.eq(m, "GetAttributes"), Attributes{},
  Bool.pick(Op, String.eq(m, "GetApplication"), GetApplication{},
  Bool.pick(Op, String.eq(m, "GetInterfaces"), Interfaces{},
  Bool.pick(Op, String.eq(m, "Contains"), Contains{},
  Bool.pick(Op, String.eq(m, "GetAccessibleAtPoint"), AtPoint{},
  Bool.pick(Op, String.eq(m, "GetExtents"), Extents{},
  Bool.pick(Op, String.eq(m, "GetPosition"), Position{},
  Bool.pick(Op, String.eq(m, "GetSize"), Size{},
  Bool.pick(Op, String.eq(m, "GetLayer"), Layer{},
  Bool.pick(Op, String.eq(m, "GetMDIZOrder"), ZOrder{},
  Bool.pick(Op, String.eq(m, "GrabFocus"), GrabFocus{},
  Bool.pick(Op, String.eq(m, "GetAlpha"), Alpha{},
  Bool.pick(Op, String.eq(m, "GetActions"), Actions{},
  Bool.pick(Op, String.eq(m, "GetName"), ActionName{},
  Bool.pick(Op, String.eq(m, "GetLocalizedName"), ActionLocalizedName{},
  Bool.pick(Op, String.eq(m, "GetDescription"), ActionDescription{},
  Bool.pick(Op, String.eq(m, "GetKeyBinding"), KeyBinding{},
  Bool.pick(Op, String.eq(m, "DoAction"), DoAction{},
  Bool.pick(Op, String.eq(m, "GetLocale"), Locale{},
  Bool.pick(Op, String.eq(m, "GetApplicationBusAddress"), BusAddress{},
  Bool.pick(Op, String.eq(m, "GetItems"), Items{}, NoOp{}))))))))))))))))))))))))))))))))))

# org.a11y.atspi.Text's members. GetAttributes here is the text's, at an
# offset (Accessible has its own).
def text_op(+m: String) -> Op:
  Bool.pick(Op, String.eq(m, "GetText"), GetText{},
  Bool.pick(Op, String.eq(m, "SetCaretOffset"), SetCaretOffset{},
  Bool.pick(Op, String.eq(m, "GetStringAtOffset"), StringAtOffset{},
  Bool.pick(Op, String.eq(m, "GetTextAtOffset"), TextAtOffset{},
  Bool.pick(Op, String.eq(m, "GetCharacterAtOffset"), CharacterAtOffset{},
  Bool.pick(Op, String.eq(m, "GetCharacterExtents"), CharacterExtents{},
  Bool.pick(Op, String.eq(m, "GetRangeExtents"), RangeExtents{},
  Bool.pick(Op, String.eq(m, "GetOffsetAtPoint"), OffsetAtPoint{},
  Bool.pick(Op, String.eq(m, "GetNSelections"), NSelections{},
  Bool.pick(Op, String.eq(m, "GetSelection"), GetSelection{},
  Bool.pick(Op, String.eq(m, "AddSelection"), AddSelection{},
  Bool.pick(Op, String.eq(m, "RemoveSelection"), RemoveSelection{},
  Bool.pick(Op, String.eq(m, "SetSelection"), SetSelection{},
  Bool.pick(Op, String.eq(m, "GetAttributeRun"), AttributeRun{},
  Bool.pick(Op, String.eq(m, "GetAttributes"), TextAttributes{},
  Bool.pick(Op, String.eq(m, "GetDefaultAttributes"), DefaultAttributes{},
  Bool.pick(Op, String.eq(m, "GetDefaultAttributeSet"), DefaultAttributes{}, NoOp{})))))))))))))))))

def edit_op(+m: String) -> Op:
  Bool.pick(Op, String.eq(m, "SetTextContents"), SetTextContents{},
  Bool.pick(Op, String.eq(m, "InsertText"), InsertText{},
  Bool.pick(Op, String.eq(m, "DeleteText"), DeleteText{},
  Bool.pick(Op, String.eq(m, "CopyText"), CopyText{},
  Bool.pick(Op, String.eq(m, "CutText"), CutText{},
  Bool.pick(Op, String.eq(m, "PasteText"), PasteText{}, NoOp{}))))))

def or_edit(op: Op, +m: String) -> Op:
  match op:
    case NoOp{}:
      edit_op(m)
    case other:
      other

def or_text(op: Op, +m: String) -> Op:
  match op:
    case NoOp{}:
      or_edit(text_op(m), m)
    case other:
      other

def op_in(text: Bool, edit: Bool, +m: String) -> Op:
  match text edit:
    case True{} _:
      text_op(m)
    case False{} True{}:
      edit_op(m)
    case False{} False{}:
      or_text(base_op(m), m)

# The operation a call names. The interface picks between members of the
# same name (Accessible.GetAttributes and Text.GetAttributes); a call with
# no interface gets the first interface that has the member.
def op_of(+iface: String, +m: String) -> Op:
  op_in(String.eq(iface, O.i_text()), String.eq(iface, O.i_editable()), m)

def op_iface(op: Op) -> String:
  match op:
    case Introspect{}:
      O.i_introspectable()
    case Ping{}:
      O.i_peer()
    case PropGet{}:
      O.i_properties()
    case PropGetAll{}:
      O.i_properties()
    case PropSet{}:
      O.i_properties()
    case Contains{}:
      O.i_component()
    case AtPoint{}:
      O.i_component()
    case Extents{}:
      O.i_component()
    case Position{}:
      O.i_component()
    case Size{}:
      O.i_component()
    case Layer{}:
      O.i_component()
    case ZOrder{}:
      O.i_component()
    case GrabFocus{}:
      O.i_component()
    case Alpha{}:
      O.i_component()
    case Actions{}:
      O.i_action()
    case ActionName{}:
      O.i_action()
    case ActionLocalizedName{}:
      O.i_action()
    case ActionDescription{}:
      O.i_action()
    case KeyBinding{}:
      O.i_action()
    case DoAction{}:
      O.i_action()
    case Locale{}:
      O.i_application()
    case BusAddress{}:
      O.i_application()
    case Items{}:
      O.i_cache()
    case GetText{}:
      O.i_text()
    case SetCaretOffset{}:
      O.i_text()
    case StringAtOffset{}:
      O.i_text()
    case TextAtOffset{}:
      O.i_text()
    case CharacterAtOffset{}:
      O.i_text()
    case CharacterExtents{}:
      O.i_text()
    case RangeExtents{}:
      O.i_text()
    case OffsetAtPoint{}:
      O.i_text()
    case NSelections{}:
      O.i_text()
    case GetSelection{}:
      O.i_text()
    case AddSelection{}:
      O.i_text()
    case RemoveSelection{}:
      O.i_text()
    case SetSelection{}:
      O.i_text()
    case AttributeRun{}:
      O.i_text()
    case TextAttributes{}:
      O.i_text()
    case DefaultAttributes{}:
      O.i_text()
    case SetTextContents{}:
      O.i_editable()
    case InsertText{}:
      O.i_editable()
    case DeleteText{}:
      O.i_editable()
    case CopyText{}:
      O.i_editable()
    case CutText{}:
      O.i_editable()
    case PasteText{}:
      O.i_editable()
    case NoOp{}:
      ""
    case _:
      O.i_accessible()

# Replies
# -------

type Reply is Data:
  Ok{body: W.Value}
  Err{name: String, text: String}
  Act{body: W.Value, request: M.Request}
  Defer{request: M.Request}
  SetId{id: U32}

def unknown_method() -> Reply:
  Err{"org.freedesktop.DBus.Error.UnknownMethod", "auvia: no such method on this object"}

def unknown_object() -> Reply:
  Err{"org.freedesktop.DBus.Error.UnknownObject", "auvia: no such object"}

def one(v: W.Value) -> Reply:
  Ok{W.seq([v])}

# Properties
# ----------

type Prop is Data:
  Prop{iface: String, name: String, value: W.Value}

def range_props(m: Maybe<&2, M.Range>) -> List<&2, Prop>:
  match m:
    case None{}:
      Nil{}
    case Some{M.Range{c, lo, hi, st}}:
      [Prop{O.i_value(), "MinimumValue", W.f64(lo)}, Prop{O.i_value(), "MaximumValue", W.f64(hi)},
        Prop{O.i_value(), "MinimumIncrement", W.f64(st)}, Prop{O.i_value(), "CurrentValue", W.f64(c)},
        Prop{O.i_value(), "Text", W.DStr{""}}]

def text_props(m: Maybe<&2, M.Text>) -> List<&2, Prop>:
  match m:
    case None{}:
      Nil{}
    case Some{M.Text{c, n, ca, an, ox, oy, lh, st}}:
      [Prop{O.i_text(), "CharacterCount", W.DI32{n}}, Prop{O.i_text(), "CaretOffset", W.DI32{ca}}]

def app_props(+ctx: O.Ctx, root: Bool) -> List<&2, List<&2, Prop>>:
  O.Ctx{bus, id, l, x, y} = ctx
  O.when(List<&2, Prop>, root, [Prop{O.i_application(), "ToolkitName", W.DStr{"Auvia"}},
    Prop{O.i_application(), "Version", W.DStr{"0.1.0"}},
    Prop{O.i_application(), "AtspiVersion", W.DStr{"2.1"}},
    Prop{O.i_application(), "Id", W.DI32{id}}])

def table(+ctx: O.Ctx, +ix: M.Index, +n: M.Node) -> List<&2, Prop>:
  O.Ctx{bus, app, +locale, x, y} = ctx
  M.Node{+id, p, r, nm, d, s, +a, rl, at, b, v, tx, c} = n
  List.concat(&2, Prop, [
    [Prop{O.i_accessible(), "Name", W.DStr{nm}}, Prop{O.i_accessible(), "Description", W.DStr{d}},
      Prop{O.i_accessible(), "Parent", O.parent_ref(ctx, n)}, Prop{O.i_accessible(), "ChildCount", W.DI32{M.count(c)}},
      Prop{O.i_accessible(), "Locale", W.DStr{locale}}, Prop{O.i_accessible(), "AccessibleId", W.DStr{"auvia-" ++ U32.show(id)}},
      Prop{O.i_accessible(), "HelpText", W.DStr{""}}],
    List.concat(&2, Prop, app_props(ctx, U32.is_eq(id, 0))),
    O.when(Prop, O.has_actions(a), Prop{O.i_action(), "NActions", W.DI32{U32.from_nat(List.length(&2, M.Action, a))}}),
    range_props(v), text_props(tx)])

def prop_find(ps: List<&2, Prop>, +iface: String, +name: String) -> Reply:
  match ps:
    case Nil{}:
      Err{"org.freedesktop.DBus.Error.UnknownProperty", "auvia: no property " ++ iface ++ "." ++ name}
    case Con{Prop{+i, +nm, v}, rest}:
      Bool.pick(Reply, String.eq(i, iface) && String.eq(nm, name), one(W.DVar{v}), prop_find(rest, iface, name))

def prop_entries(ps: List<&2, Prop>, +iface: String) -> List<&2, W.Value>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{Prop{+i, nm, v}, rest}:
      +tail = prop_entries(rest, iface)
      Bool.pick(List<&2, W.Value>, String.eq(i, iface), Con{W.DEntry{W.DStr{nm}, W.DVar{v}}, tail}, tail)

def prop_set(+iface: String, +name: String, value: W.Value, +root: Bool) -> Reply:
  Bool.pick(Reply, root && String.eq(iface, O.i_application()) && String.eq(name, "Id"),
    SetId{W.word(value)}, Err{"org.freedesktop.DBus.Error.PropertyReadOnly", "auvia: " ++ name ++ " is read-only"})

def var_inner(v: W.Value) -> W.Value:
  match v:
    case W.DVar{x}:
      x
    case other:
      other

# Children and points
# -------------------

def child_ref(+ctx: O.Ctx, m: Maybe<&2, U32>) -> W.Value:
  match m:
    case None{}:
      O.null_ref(ctx)
    case Some{id}:
      O.node_ref(ctx, id)

# The point (x, y) of coord_type, in window coordinates.
def to_window(o: O.Offset, +x: F32, +y: F32) -> O.Offset:
  O.Offset{dx, dy} = o
  O.Offset{(x - dx : F32), (y - dy : F32)}

def point_in(b: M.Box, pt: O.Offset) -> Bool:
  O.Offset{x, y} = pt
  O.inside(b, x, y)

def child_or_root(m: Maybe<&2, M.Node>) -> M.Node:
  match m:
    case None{}:
      M.application("", Nil{})
    case Some{n}:
      n

# The first child whose box holds the point (ATK's semantics: a direct
# child; the client descends further itself).
def child_at(+ix: M.Index, kids: List<&2, U32>, +pt: O.Offset) -> Maybe<&2, U32>:
  match kids:
    case Nil{}:
      None{}
    case Con{+k, rest}:
      Bool.pick(Maybe<&2, U32>, point_in(M.node_bounds(child_or_root(M.get(ix, k))), pt), Some{k}, child_at(ix, rest, pt))

def window_point(+ctx: O.Ctx, +ix: M.Index, +n: M.Node, +body: W.Value) -> O.Offset:
  to_window(O.offset(ctx, W.word(W.arg(body, 2n)), O.parent_box(ix, n)),
    O.from_i32(W.word(W.arg(body, 0n))), O.from_i32(W.word(W.arg(body, 1n))))

# Actions
# -------

def action_at(xs: List<&2, M.Action>, +i: U32) -> Maybe<&2, M.Action>:
  List.get(&2, M.Action, xs, U32.to_nat(i))

def action_field(m: Maybe<&2, M.Action>, +which: U32) -> String:
  match m:
    case None{}:
      ""
    case Some{M.Action{name, desc, key}}:
      Bool.pick(String, U32.is_eq(which, 0), name, Bool.pick(String, U32.is_eq(which, 1), desc, key))

def is_some(m: Maybe<&2, M.Action>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{a}:
      True{}

# DoAction(i) succeeds only for an existing action on an enabled node; the
# app performs it once, when it routes the request.
def do_action(+n: M.Node, +i: U32) -> Reply:
  +ok = is_some(action_at(M.node_actions(n), i)) && M.is_enabled(n)
  Bool.pick(Reply, ok, Act{W.seq([W.DBool{True{}}]), M.Activate{M.node_id(n), i}}, one(W.DBool{False{}}))

def grab_focus(+n: M.Node) -> Reply:
  +ss = M.node_states(n)
  +ok = M.has_state(ss, M.Focusable{}) && M.has_state(ss, M.Enabled{})
  Bool.pick(Reply, ok, Act{W.seq([W.DBool{True{}}]), M.Focus{M.node_id(n)}}, one(W.DBool{False{}}))

def layer(r: M.Role) -> U32:
  Bool.pick(U32, M.same_role(r, M.Frame{}), 7, 3)

# Text
# ----

def the_text(m: Maybe<&2, M.Text>) -> M.Text:
  match m:
    case None{}:
      M.Text{"", 0, 0, 0, 0.0, 0.0, 0.0, Nil{}}
    case Some{t}:
      t

def text_of(n: M.Node) -> M.Text:
  the_text(M.node_text(n))

def count_of(n: M.Node) -> U32:
  T.text_count(text_of(n))

def int_arg(+body: W.Value, k: Nat) -> U32:
  W.word(W.arg(body, k))

def get_text(t: M.Text, +a: U32, +b: U32) -> Reply:
  M.Text{c, +n, ca, an, ox, oy, lh, st} = t
  one(W.DStr{T.slice(c, T.clamp_start(a, n), T.clamp_end(b, n))})

def piece_reply(p: T.Piece) -> Reply:
  T.Piece{s, a, b} = p
  Ok{W.seq([W.DStr{s}, W.DI32{a}, W.DI32{b}])}

def four(b: M.Box) -> Reply:
  M.Box{x, y, w, h} = b
  Ok{W.seq([W.DI32{O.to_i32(x)}, W.DI32{O.to_i32(y)}, W.DI32{O.to_i32(w)}, W.DI32{O.to_i32(h)}])}

# A box of the text in coord_type's coordinates, as Component answers.
def text_extents(+ctx: O.Ctx, +ix: M.Index, +n: M.Node, coord: U32, b: M.Box) -> Reply:
  four(O.moved(b, O.offset(ctx, coord, O.parent_box(ix, n))))

def point_offset(t: M.Text, pt: O.Offset) -> Reply:
  O.Offset{+x, +y} = pt
  one(W.DI32{T.offset_at(t, x, y)})

def pair_reply(p: U32 & U32, +ok: Bool) -> Reply:
  (a, b) = p
  Ok{W.seq([W.DI32{Bool.pick(U32, ok, a, 0)}, W.DI32{Bool.pick(U32, ok, b, 0)}])}

# The single selection, or (0, 0) when there is none or the number is not 0.
def selection_reply(+t: M.Text, +k: U32) -> Reply:
  pair_reply(T.selection(t), U32.is_eq(k, 0) && T.has_selection(t))

def attribute_run(+n: U32) -> Reply:
  Ok{W.seq([W.array("{ss}", Nil{}), W.DI32{0}, W.DI32{n}])}

def refused(op: M.TextOp) -> Reply:
  match op:
    case M.Copy{a, b}:
      Ok{W.DEnd{}}
    case _:
      one(W.DBool{False{}})

# A text request: held for the app (which performs it through its editing
# rules and settles it), or refused at once.
def text_request(ok: Bool, +n: M.Node, op: M.TextOp) -> Reply:
  match ok:
    case False{}:
      refused(op)
    case True{}:
      Defer{M.EditText{M.node_id(n), op, 0}}

def can_edit(+n: M.Node) -> Bool:
  M.is_enabled(n) && M.has_state(M.node_states(n), M.Editable{})

def ordered(+a: U32, +b: U32, +n: U32) -> U32 & U32:
  +x = T.clamp_start(a, n)
  +y = T.clamp_end(b, n)
  (U32.min(x, y), U32.max(x, y))

def delete_op(p: U32 & U32) -> M.TextOp:
  (a, b) = p
  M.Delete{a, b}

def copy_op(p: U32 & U32) -> M.TextOp:
  (a, b) = p
  M.Copy{a, b}

def cut_op(p: U32 & U32) -> M.TextOp:
  (a, b) = p
  M.Cut{a, b}

def range_extents(+ctx: O.Ctx, +ix: M.Index, +n: M.Node, +body: W.Value) -> Reply:
  +c = count_of(n)
  text_extents(ctx, ix, n, int_arg(body, 2n), T.range_box(text_of(n), T.clamp_start(int_arg(body, 0n), c), T.clamp_end(int_arg(body, 1n), c)))

def select_op(+n: M.Node, +a: U32, +b: U32) -> M.TextOp:
  +c = count_of(n)
  M.Select{T.clamp_start(a, c), T.clamp_end(b, c)}

def collapse_op(t: M.Text) -> M.TextOp:
  +c = T.text_caret(t)
  M.Select{c, c}

# Answers a Text or EditableText call on a node that has a text (the
# interface check guarantees it).
def on_text(op: Op, +ctx: O.Ctx, +ix: M.Index, +n: M.Node, +body: W.Value) -> Reply:
  match op:
    case GetText{}:
      get_text(text_of(n), int_arg(body, 0n), int_arg(body, 1n))
    case SetCaretOffset{}:
      text_request(M.is_enabled(n), n, M.SetCaret{T.clamp_end(int_arg(body, 0n), count_of(n))})
    case StringAtOffset{}:
      piece_reply(T.string_at(text_of(n), T.clamp_end(int_arg(body, 0n), count_of(n)), int_arg(body, 1n)))
    case TextAtOffset{}:
      piece_reply(T.string_at(text_of(n), T.clamp_end(int_arg(body, 0n), count_of(n)), T.boundary_granularity(int_arg(body, 1n))))
    case CharacterAtOffset{}:
      one(W.DI32{T.scalar_at(text_of(n), int_arg(body, 0n))})
    case CharacterExtents{}:
      text_extents(ctx, ix, n, int_arg(body, 1n), T.char_box(text_of(n), T.clamp_end(int_arg(body, 0n), count_of(n))))
    case RangeExtents{}:
      range_extents(ctx, ix, n, body)
    case OffsetAtPoint{}:
      point_offset(text_of(n), window_point(ctx, ix, n, body))
    case NSelections{}:
      one(W.DI32{Bool.to_u32(T.has_selection(text_of(n)))})
    case GetSelection{}:
      selection_reply(text_of(n), int_arg(body, 0n))
    case AddSelection{}:
      text_request(M.is_enabled(n) && Bool.not(T.has_selection(text_of(n))), n, select_op(n, int_arg(body, 0n), int_arg(body, 1n)))
    case RemoveSelection{}:
      text_request(M.is_enabled(n) && U32.is_eq(int_arg(body, 0n), 0) && T.has_selection(text_of(n)), n, collapse_op(text_of(n)))
    case SetSelection{}:
      text_request(M.is_enabled(n) && U32.is_eq(int_arg(body, 0n), 0), n, select_op(n, int_arg(body, 1n), int_arg(body, 2n)))
    case AttributeRun{}:
      attribute_run(count_of(n))
    case TextAttributes{}:
      attribute_run(count_of(n))
    case DefaultAttributes{}:
      one(W.array("{ss}", Nil{}))
    case SetTextContents{}:
      text_request(can_edit(n), n, M.SetContents{W.text(W.arg(body, 0n))})
    case InsertText{}:
      text_request(can_edit(n), n, M.Insert{T.clamp_end(int_arg(body, 0n), count_of(n)), W.text(W.arg(body, 1n))})
    case DeleteText{}:
      text_request(can_edit(n), n, delete_op(ordered(int_arg(body, 0n), int_arg(body, 1n), count_of(n))))
    case CopyText{}:
      text_request(M.is_enabled(n), n, copy_op(ordered(int_arg(body, 0n), int_arg(body, 1n), count_of(n))))
    case CutText{}:
      text_request(can_edit(n), n, cut_op(ordered(int_arg(body, 0n), int_arg(body, 1n), count_of(n))))
    case PasteText{}:
      text_request(can_edit(n), n, M.Paste{T.clamp_end(int_arg(body, 0n), count_of(n))})
    case _:
      unknown_method()

# Introspection
# -------------

def x_accessible() -> String:
  "<interface name='org.a11y.atspi.Accessible'><property name='Name' type='s' access='read'/><property name='Description' type='s' access='read'/><property name='Parent' type='(so)' access='read'/><property name='ChildCount' type='i' access='read'/><property name='Locale' type='s' access='read'/><property name='AccessibleId' type='s' access='read'/><property name='HelpText' type='s' access='read'/><method name='GetChildAtIndex'><arg direction='in' name='index' type='i'/><arg direction='out' type='(so)'/></method><method name='GetChildren'><arg direction='out' type='a(so)'/></method><method name='GetIndexInParent'><arg direction='out' type='i'/></method><method name='GetRelationSet'><arg direction='out' type='a(ua(so))'/></method><method name='GetRole'><arg direction='out' type='u'/></method><method name='GetRoleName'><arg direction='out' type='s'/></method><method name='GetLocalizedRoleName'><arg direction='out' type='s'/></method><method name='GetState'><arg direction='out' type='au'/></method><method name='GetAttributes'><arg direction='out' type='a{ss}'/></method><method name='GetApplication'><arg direction='out' type='(so)'/></method><method name='GetInterfaces'><arg direction='out' type='as'/></method></interface>"

def x_application() -> String:
  "<interface name='org.a11y.atspi.Application'><property name='ToolkitName' type='s' access='read'/><property name='Version' type='s' access='read'/><property name='AtspiVersion' type='s' access='read'/><property name='Id' type='i' access='readwrite'/><method name='GetLocale'><arg direction='in' name='lctype' type='u'/><arg direction='out' type='s'/></method><method name='GetApplicationBusAddress'><arg direction='out' type='s'/></method></interface>"

def x_component() -> String:
  "<interface name='org.a11y.atspi.Component'><method name='Contains'><arg direction='in' name='x' type='i'/><arg direction='in' name='y' type='i'/><arg direction='in' name='coord_type' type='u'/><arg direction='out' type='b'/></method><method name='GetAccessibleAtPoint'><arg direction='in' name='x' type='i'/><arg direction='in' name='y' type='i'/><arg direction='in' name='coord_type' type='u'/><arg direction='out' type='(so)'/></method><method name='GetExtents'><arg direction='in' name='coord_type' type='u'/><arg direction='out' type='(iiii)'/></method><method name='GetPosition'><arg direction='in' name='coord_type' type='u'/><arg direction='out' name='x' type='i'/><arg direction='out' name='y' type='i'/></method><method name='GetSize'><arg direction='out' name='width' type='i'/><arg direction='out' name='height' type='i'/></method><method name='GetLayer'><arg direction='out' type='u'/></method><method name='GetMDIZOrder'><arg direction='out' type='n'/></method><method name='GrabFocus'><arg direction='out' type='b'/></method><method name='GetAlpha'><arg direction='out' type='d'/></method></interface>"

def x_action() -> String:
  "<interface name='org.a11y.atspi.Action'><property name='NActions' type='i' access='read'/><method name='GetDescription'><arg direction='in' name='index' type='i'/><arg direction='out' type='s'/></method><method name='GetName'><arg direction='in' name='index' type='i'/><arg direction='out' type='s'/></method><method name='GetLocalizedName'><arg direction='in' name='index' type='i'/><arg direction='out' type='s'/></method><method name='GetKeyBinding'><arg direction='in' name='index' type='i'/><arg direction='out' type='s'/></method><method name='GetActions'><arg direction='out' type='a(sss)'/></method><method name='DoAction'><arg direction='in' name='index' type='i'/><arg direction='out' type='b'/></method></interface>"

def x_value() -> String:
  "<interface name='org.a11y.atspi.Value'><property name='MinimumValue' type='d' access='read'/><property name='MaximumValue' type='d' access='read'/><property name='MinimumIncrement' type='d' access='read'/><property name='CurrentValue' type='d' access='read'/><property name='Text' type='s' access='read'/></interface>"

def x_text() -> String:
  "<interface name='org.a11y.atspi.Text'><property name='CharacterCount' type='i' access='read'/><property name='CaretOffset' type='i' access='read'/><method name='GetStringAtOffset'><arg direction='in' name='offset' type='i'/><arg direction='in' name='granularity' type='u'/><arg direction='out' type='s'/><arg direction='out' type='i'/><arg direction='out' type='i'/></method><method name='GetText'><arg direction='in' name='startOffset' type='i'/><arg direction='in' name='endOffset' type='i'/><arg direction='out' type='s'/></method><method name='SetCaretOffset'><arg direction='in' name='offset' type='i'/><arg direction='out' type='b'/></method><method name='GetTextAtOffset'><arg direction='in' name='offset' type='i'/><arg direction='in' name='type' type='u'/><arg direction='out' type='s'/><arg direction='out' type='i'/><arg direction='out' type='i'/></method><method name='GetCharacterAtOffset'><arg direction='in' name='offset' type='i'/><arg direction='out' type='i'/></method><method name='GetAttributes'><arg direction='in' name='offset' type='i'/><arg direction='out' type='a{ss}'/><arg direction='out' type='i'/><arg direction='out' type='i'/></method><method name='GetDefaultAttributes'><arg direction='out' type='a{ss}'/></method><method name='GetCharacterExtents'><arg direction='in' name='offset' type='i'/><arg direction='in' name='coordType' type='u'/><arg direction='out' type='i'/><arg direction='out' type='i'/><arg direction='out' type='i'/><arg direction='out' type='i'/></method><method name='GetOffsetAtPoint'><arg direction='in' name='x' type='i'/><arg direction='in' name='y' type='i'/><arg direction='in' name='coordType' type='u'/><arg direction='out' type='i'/></method><method name='GetNSelections'><arg direction='out' type='i'/></method><method name='GetSelection'><arg direction='in' name='selectionNum' type='i'/><arg direction='out' type='i'/><arg direction='out' type='i'/></method><method name='AddSelection'><arg direction='in' name='startOffset' type='i'/><arg direction='in' name='endOffset' type='i'/><arg direction='out' type='b'/></method><method name='RemoveSelection'><arg direction='in' name='selectionNum' type='i'/><arg direction='out' type='b'/></method><method name='SetSelection'><arg direction='in' name='selectionNum' type='i'/><arg direction='in' name='startOffset' type='i'/><arg direction='in' name='endOffset' type='i'/><arg direction='out' type='b'/></method><method name='GetRangeExtents'><arg direction='in' name='startOffset' type='i'/><arg direction='in' name='endOffset' type='i'/><arg direction='in' name='coordType' type='u'/><arg direction='out' type='i'/><arg direction='out' type='i'/><arg direction='out' type='i'/><arg direction='out' type='i'/></method><method name='GetAttributeRun'><arg direction='in' name='offset' type='i'/><arg direction='in' name='includeDefaults' type='b'/><arg direction='out' type='a{ss}'/><arg direction='out' type='i'/><arg direction='out' type='i'/></method><method name='GetDefaultAttributeSet'><arg direction='out' type='a{ss}'/></method></interface>"

def x_editable() -> String:
  "<interface name='org.a11y.atspi.EditableText'><method name='SetTextContents'><arg direction='in' name='newContents' type='s'/><arg direction='out' type='b'/></method><method name='InsertText'><arg direction='in' name='position' type='i'/><arg direction='in' name='text' type='s'/><arg direction='in' name='length' type='i'/><arg direction='out' type='b'/></method><method name='CopyText'><arg direction='in' name='startPos' type='i'/><arg direction='in' name='endPos' type='i'/></method><method name='CutText'><arg direction='in' name='startPos' type='i'/><arg direction='in' name='endPos' type='i'/><arg direction='out' type='b'/></method><method name='DeleteText'><arg direction='in' name='startPos' type='i'/><arg direction='in' name='endPos' type='i'/><arg direction='out' type='b'/></method><method name='PasteText'><arg direction='in' name='position' type='i'/><arg direction='out' type='b'/></method></interface>"

def x_cache() -> String:
  "<interface name='org.a11y.atspi.Cache'><method name='GetItems'><arg direction='out' type='a((so)(so)(so)iiassusau)'/></method><signal name='AddAccessible'><arg type='((so)(so)(so)iiassusau)'/></signal><signal name='RemoveAccessible'><arg type='(so)'/></signal></interface>"

def x_dbus() -> String:
  "<interface name='org.freedesktop.DBus.Properties'><method name='Get'><arg direction='in' type='s'/><arg direction='in' type='s'/><arg direction='out' type='v'/></method><method name='GetAll'><arg direction='in' type='s'/><arg direction='out' type='a{sv}'/></method><method name='Set'><arg direction='in' type='s'/><arg direction='in' type='s'/><arg direction='in' type='v'/></method></interface><interface name='org.freedesktop.DBus.Introspectable'><method name='Introspect'><arg direction='out' type='s'/></method></interface><interface name='org.freedesktop.DBus.Peer'><method name='Ping'/></interface>"

def x_iface(+i: String) -> String:
  Bool.pick(String, String.eq(i, O.i_accessible()), x_accessible(),
  Bool.pick(String, String.eq(i, O.i_application()), x_application(),
  Bool.pick(String, String.eq(i, O.i_component()), x_component(),
  Bool.pick(String, String.eq(i, O.i_action()), x_action(),
  Bool.pick(String, String.eq(i, O.i_value()), x_value(),
  Bool.pick(String, String.eq(i, O.i_text()), x_text(),
  Bool.pick(String, String.eq(i, O.i_editable()), x_editable(), "")))))))

def x_ifaces(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{x, rest}:
      x_iface(x) ++ x_ifaces(rest)

def xml(body: String) -> Reply:
  one(W.DStr{"<!DOCTYPE node PUBLIC '-//freedesktop//DTD D-BUS Object Introspection 1.0//EN' 'http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd'><node>" ++ body ++ x_dbus() ++ "</node>"})

# Dispatch
# --------

def pos_pair(b: M.Box) -> Reply:
  M.Box{x, y, w, h} = b
  Ok{W.seq([W.DI32{O.to_i32(x)}, W.DI32{O.to_i32(y)}])}

def ref_pair(+ctx: O.Ctx, +ix: M.Index, +n: M.Node, coord: U32) -> Reply:
  pos_pair(O.box_in(ctx, ix, n, coord))

def size_pair(b: M.Box) -> Reply:
  M.Box{x, y, w, h} = b
  Ok{W.seq([W.DI32{O.to_i32(w)}, W.DI32{O.to_i32(h)}])}

def on_node(op: Op, +ctx: O.Ctx, +ix: M.Index, +n: M.Node, +body: W.Value) -> Reply:
  match op:
    case Introspect{}:
      xml(x_ifaces(O.interfaces(n)))
    case Ping{}:
      Ok{W.DEnd{}}
    case PropGet{}:
      prop_find(table(ctx, ix, n), W.text(W.arg(body, 0n)), W.text(W.arg(body, 1n)))
    case PropGetAll{}:
      one(W.array("{sv}", prop_entries(table(ctx, ix, n), W.text(W.arg(body, 0n)))))
    case PropSet{}:
      prop_set(W.text(W.arg(body, 0n)), W.text(W.arg(body, 1n)), var_inner(W.arg(body, 2n)), U32.is_eq(M.node_id(n), 0))
    case ChildAt{}:
      one(child_ref(ctx, List.get(&2, U32, M.node_children(n), U32.to_nat(W.word(W.arg(body, 0n))))))
    case Children{}:
      one(O.children_value(ctx, M.node_children(n)))
    case IndexInParent{}:
      one(W.DI32{M.position(ix, n)})
    case RelationSet{}:
      M.Node{id, p, r, nm, d, s, a, rl, at, b, v, tx, c} = n
      one(O.relations_value(ctx, rl))
    case GetRole{}:
      one(W.DU32{M.role_code(M.node_role(n))})
    case RoleName{}:
      one(W.DStr{M.role_name(M.node_role(n))})
    case LocalizedRoleName{}:
      one(W.DStr{M.role_name(M.node_role(n))})
    case GetState{}:
      one(O.node_states_value(n))
    case Attributes{}:
      M.Node{id, p, r, nm, d, s, a, rl, at, b, v, tx, c} = n
      one(O.attrs_value(at))
    case GetApplication{}:
      one(O.node_ref(ctx, 0))
    case Interfaces{}:
      one(O.strings(O.interfaces(n)))
    case Contains{}:
      one(W.DBool{point_in(M.node_bounds(n), window_point(ctx, ix, n, body))})
    case AtPoint{}:
      one(child_ref(ctx, child_at(ix, M.node_children(n), window_point(ctx, ix, n, body))))
    case Extents{}:
      one(O.extents(ctx, ix, n, W.word(W.arg(body, 0n))))
    case Position{}:
      ref_pair(ctx, ix, n, W.word(W.arg(body, 0n)))
    case Size{}:
      size_pair(M.node_bounds(n))
    case Layer{}:
      one(W.DU32{layer(M.node_role(n))})
    case ZOrder{}:
      one(W.DI16{0})
    case GrabFocus{}:
      grab_focus(n)
    case Alpha{}:
      one(O.one())
    case Actions{}:
      one(O.actions_value(M.node_actions(n)))
    case ActionName{}:
      one(W.DStr{action_field(action_at(M.node_actions(n), W.word(W.arg(body, 0n))), 0)})
    case ActionLocalizedName{}:
      one(W.DStr{action_field(action_at(M.node_actions(n), W.word(W.arg(body, 0n))), 0)})
    case ActionDescription{}:
      one(W.DStr{action_field(action_at(M.node_actions(n), W.word(W.arg(body, 0n))), 1)})
    case KeyBinding{}:
      one(W.DStr{action_field(action_at(M.node_actions(n), W.word(W.arg(body, 0n))), 2)})
    case DoAction{}:
      do_action(n, W.word(W.arg(body, 0n)))
    case Locale{}:
      O.Ctx{bus, app, locale, x, y} = ctx
      one(W.DStr{locale})
    case BusAddress{}:
      one(W.DStr{""})
    case Items{}:
      unknown_method()
    case NoOp{}:
      unknown_method()
    case other:
      on_text(other, ctx, ix, n, body)

def on_cache(op: Op, +ctx: O.Ctx, +ix: M.Index) -> Reply:
  match op:
    case Items{}:
      one(W.array(O.item_sig(), O.cache_items(ctx, ix, M.listed(ix))))
    case Introspect{}:
      xml(x_cache())
    case Ping{}:
      Ok{W.DEnd{}}
    case _:
      unknown_method()

type Target is Data:
  ToNode{node: M.Node}
  ToCache{}
  ToNothing{}

def target_node(m: Maybe<&2, M.Node>) -> Target:
  match m:
    case None{}:
      ToNothing{}
    case Some{n}:
      ToNode{n}

def target_id(m: Maybe<&2, U32>, +ix: M.Index) -> Target:
  match m:
    case None{}:
      ToNothing{}
    case Some{id}:
      target_node(M.get(ix, id))

def target(+p: String, +ix: M.Index) -> Target:
  Bool.pick(Target, String.eq(p, O.cache_path()), ToCache{}, target_id(O.path_id(p), ix))

# A call is accepted when its interface (if given) is the one that owns
# the member, and the object implements that interface.
def allowed(+op: Op, +iface: String, +ifaces: List<&2, String>) -> Bool:
  +owner = op_iface(op)
  +always = String.eq(owner, O.i_properties()) || String.eq(owner, O.i_introspectable()) || String.eq(owner, O.i_peer())
  (String.is_empty(iface) || String.eq(iface, owner)) && (always || O.implements(ifaces, owner))

# Peer.Ping answers on every path (the registry pings "/" to see that an
# app is alive); Introspect on a path that is not an object answers an
# empty node, as other services do.
def elsewhere(op: Op) -> Reply:
  match op:
    case Ping{}:
      Ok{W.DEnd{}}
    case Introspect{}:
      xml("")
    case _:
      unknown_object()

def dispatch(+op: Op, +iface: String, t: Target, +ctx: O.Ctx, +ix: M.Index, +body: W.Value) -> Reply:
  match t:
    case ToNothing{}:
      Bool.pick(Reply, String.is_empty(iface) || String.eq(iface, op_iface(op)), elsewhere(op), unknown_object())
    case ToCache{}:
      Bool.pick(Reply, allowed(op, iface, [O.i_cache()]), on_cache(op, ctx, ix), unknown_method())
    case ToNode{+n}:
      Bool.pick(Reply, allowed(op, iface, O.interfaces(n)), on_node(op, ctx, ix, n, body), unknown_method())

# Serving
# -------

# A text call the app must perform before it is answered: the ticket its
# request carries, the call to answer, and whether the answer has no body
# (CopyText returns nothing).
type Held is Data:
  Held{ticket: U32, call: W.Message, silent: Bool}

# next: the ticket the next held call gets.
type Served is Data:
  Served{ctx: O.Ctx, out: List<&2, W.Message>, requests: List<&2, M.Request>, held: List<&2, Held>, next: U32}

def set_app(ctx: O.Ctx, id: U32) -> O.Ctx:
  O.Ctx{bus, old, l, x, y} = ctx
  O.Ctx{bus, id, l, x, y}

def wants_reply(+flags: U32) -> Bool:
  U32.is_eq(U32.and(flags, 1), 0)

def out_if(ok: Bool, m: W.Message) -> List<&2, W.Message>:
  match ok:
    case False{}:
      Nil{}
    case True{}:
      [m]

def flags_of(m: W.Message) -> U32:
  W.Message{k, flags, s, r, p, i, mem, e, d, sn, b} = m
  flags

def ticketed(r: M.Request, +ticket: U32) -> M.Request:
  match r:
    case M.EditText{id, op, t}:
      M.EditText{id, op, ticket}
    case other:
      other

def silent(r: M.Request) -> Bool:
  match r:
    case M.EditText{id, M.Copy{a, b}, t}:
      True{}
    case _:
      False{}

# The answer to a held call once the app has performed it (ok) or refused
# it: a boolean, or an empty return for CopyText; nothing when the caller
# asked for no reply.
def verdict(h: Held, ok: Bool) -> List<&2, W.Message>:
  Held{t, +call, quiet} = h
  out_if(wants_reply(flags_of(call)), W.method_return(call, Bool.pick(W.Value, quiet, W.DEnd{}, W.seq([W.DBool{ok}]))))

def finish.go(reply: Reply, +send: Bool, +call: W.Message, ctx: O.Ctx, +next: U32) -> Served:
  match reply:
    case Ok{body}:
      Served{ctx, out_if(send, W.method_return(call, body)), Nil{}, Nil{}, next}
    case Err{name, text}:
      Served{ctx, out_if(send, W.error_reply(call, name, text)), Nil{}, Nil{}, next}
    case Act{body, req}:
      Served{ctx, out_if(send, W.method_return(call, body)), [req], Nil{}, next}
    case Defer{+req}:
      Served{ctx, Nil{}, [ticketed(req, next)], [Held{next, call, silent(req)}], (next + 1 : U32)}
    case SetId{id}:
      Served{set_app(ctx, id), out_if(send, W.method_return(call, W.DEnd{})), Nil{}, Nil{}, next}

def finish(+call: W.Message, reply: Reply, ctx: O.Ctx, +next: U32) -> Served:
  finish.go(reply, wants_reply(flags_of(call)), call, ctx, next)

def answer.call(is_call: Bool, +ctx: O.Ctx, +ix: M.Index, +next: U32, +m: W.Message) -> Served:
  match is_call:
    case False{}:
      Served{ctx, Nil{}, Nil{}, Nil{}, next}
    case True{}:
      W.Message{k, f, s, r, +p, +i, +mem, e, d, sn, +b} = m
      finish(m, dispatch(op_of(i, mem), i, target(p, ix), ctx, ix, b), ctx, next)

# Answers one message: method calls get a reply (unless they asked for
# none) or are held for the app (text requests); returns, errors and
# signals (the registry's Embed reply, the bus's NameAcquired) need nothing.
def answer.in(+ctx: O.Ctx, +ix: M.Index, +next: U32, +m: W.Message) -> Served:
  W.Message{k, f, s, r, p, i, mem, e, d, sn, b} = m
  answer.call(U32.is_eq(k, 1), ctx, ix, next, m)

def ctx_of(s: Served) -> O.Ctx:
  Served{ctx, out, reqs, held, next} = s
  ctx

def next_of(s: Served) -> U32:
  Served{ctx, out, reqs, held, next} = s
  next

def prepend(a: Served, b: Served) -> Served:
  Served{c1, o1, r1, h1, n1} = a
  Served{c2, o2, r2, h2, n2} = b
  Served{c2, List.append(&2, W.Message, o1, o2), List.append(&2, M.Request, r1, r2), List.append(&2, Held, h1, h2), n2}

def answer(+ctx: O.Ctx, +ns: List<&2, M.Node>, +m: W.Message) -> Served:
  answer.in(ctx, M.index(ns), 1, m)

def serve.go(msgs: List<&2, W.Message>, +ctx: O.Ctx, +ix: M.Index, +next: U32) -> Served:
  match msgs:
    case Nil{}:
      Served{ctx, Nil{}, Nil{}, Nil{}, next}
    case Con{m, rest}:
      +a = answer.in(ctx, ix, next, m)
      prepend(a, serve.go(rest, ctx_of(a), ix, next_of(a)))

# Answers every message in order against one tree, indexed (see M.index);
# held calls get tickets from `next` on.
def serve.in(msgs: List<&2, W.Message>, +ctx: O.Ctx, +ix: M.Index, +next: U32) -> Served:
  serve.go(msgs, ctx, ix, next)

# Answers every message in order against one tree. The tree is indexed
# only when there is something to answer. Tickets start at 1.
def serve(msgs: List<&2, W.Message>, +ctx: O.Ctx, +tree: M.Tree) -> Served:
  match msgs:
    case Nil{}:
      Served{ctx, Nil{}, Nil{}, Nil{}, 1}
    case Con{m, rest}:
      serve.go(Con{m, rest}, ctx, M.indexed(tree), 1)
