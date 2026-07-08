const std = @import("std");
const builder = @import("zll1").builder;

const b = builder.init(.{});

// naive bf parser
const program = b.recurse(struct {
    pub fn init(self: type) type {
        const cmd = b.any(.{ .inc_ptr = b.literal(">"), .dec_ptr = b.literal("<"), .inc_byte = b.literal("+"), .dec_byte = b.literal("-"), .out_byte = b.literal("."), .in_byte = b.literal(",") });

        // list of cmd or loop
        return b.list(b.any(.{
            .cmd = cmd,
            // [...]
            .loop = b.tuple(.{ .start = b.literal("["), .body = b.ref(self), .end = b.literal("]") }),
        }));
    }
});

pub fn main(init: std.process.Init) !void {
    const ctx: b.Context = .{ .allocator = init.arena.allocator() };

    {
        var result = program.parse(
            \\>++++++++[<+++++++++>-]<.>++++[<+++++++>-]<+.+++++++..+++.>>++++++[<+++++++>-]<+
            \\+.------------.>++++++[<+++++++++>-]<+.<.+++.------.--------.>>>++++[<++++++++>-
            \\]<+.
        , ctx).data;

        switch (result) {
            .value => |*value| {
                std.debug.print("[hello-world] parsed: {any}", .{value.*});
                defer program.deparseValue(value, ctx);
            },
            .err => |*err| {
                std.debug.print("[hello-world] error: {any}", .{err.*});
                defer program.deparseErr(err, ctx);
            },
        }
    }
}
