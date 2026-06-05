const p = @import("zll1").parser;

pub const Value = p.Recursive(struct {
    pub fn init() type {
        return p.Union(.{ .number = Number, .string = String, .nil = p.Const("null"), .true = p.Const("true"), .false = p.Const("false"), .object = Object, .array = Array });
    }
});

pub const Number = p.Float;
pub const String = p.String('"');

pub const Object = p.Wrap("{", p.Array(p.Tuple(.{ String, p.Prefix(":", p.Ref(Value)) }), ","), "}");
pub const Array = p.Wrap("[", p.Array(p.Ref(Value), ","), "]");
