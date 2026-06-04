const p = @import("zll1").parser;

const Self = @This();

pub const JSON = p.Cache(p.Union(.{ .number = Number, .bool = Bool, .string = String, .nil = Nil, .object = Object, .array = Array }));

pub const Number = p.Float;
pub const String = p.String('"');
pub const Bool = p.Cache(p.Union(.{ .y = p.Prefix("true"), .n = p.Prefix("false") }));
pub const Nil = p.Prefix("null");

pub const Object = p.Recursive(struct {
    pub fn init(comptime _: anytype) type {
        const Property = p.Cache(p.Tuple(.{ String, p.Prefix(":"), p.Ref(JSON) }));

        return p.Tuple(.{ p.Prefix("{"), p.Optional(p.Tuple(.{ Property, p.Array(p.Tuple(.{ p.Prefix(","), Property })) })), p.Prefix("}") });
    }
});

pub const Array = p.Recursive(struct {
    pub fn init(comptime _: anytype) type {
        return p.Tuple(.{ p.Prefix("["), p.Optional(p.Tuple(.{ p.Ref(JSON), p.Array(p.Tuple(.{ p.Prefix(","), p.Ref(JSON) })) })), p.Prefix("]") });
    }
});
