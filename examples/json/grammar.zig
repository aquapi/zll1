const p = @import("zll1").parser;

pub const Value = p.Union(.{ .number = Number, .string = String, .nil = p.Const("null"), .true = p.Const("true"), .false = p.Const("false"), .object = Object, .array = Array });

pub const Number = p.Float;
pub const String = p.String('"');

const Pair = p.Recursive(struct {
    pub fn init() type {
        return p.Tuple(.{ String, p.Prefix(":", p.Ref(Value)) });
    }
});
pub const Object = p.Wrap("{", p.Array(Pair, ","), "}");

pub const Array = p.Recursive(struct {
    pub fn init() type {
        return p.Wrap("[", p.Array(p.Ref(Value), ","), "]");
    }
});
