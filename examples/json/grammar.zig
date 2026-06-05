const p = @import("zll1").parser;

const Self = @This();

pub const JSON = p.Union(.{ .number = Number, .bool = Bool, .string = String, .nil = Nil, .object = Object, .array = Array });

pub const Number = p.Float;
pub const String = p.String('"');
pub const Bool = p.Union(.{ .y = p.Prefix("true"), .n = p.Prefix("false") });
pub const Nil = p.Prefix("null");

pub const Object = p.Recursive(struct {
    fn init() type {
        const Property = p.Tuple(.{ String, p.Prefix(":"), p.Ref(JSON) });

        return p.Tuple(.{ p.Prefix("{"), p.Optional(p.Tuple(.{ Property, p.Array(p.Tuple(.{ p.Prefix(","), Property })) })), p.Prefix("}") });
    }
});

pub const Array = p.Recursive(struct {
    fn init() type {
        return p.Tuple(.{ p.Prefix("["), p.Optional(p.Tuple(.{ p.Ref(JSON), p.Array(p.Tuple(.{ p.Prefix(","), p.Ref(JSON) })) })), p.Prefix("]") });
    }
});
