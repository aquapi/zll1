const std = @import("std");
const builder = @import("zll1").builder;

const b = builder.init(.{});

// naive bf parser
const program = b.recurse(struct {
    pub fn init(self: type) type {
        // list of cmd or loop
        return b.list(b.any(.{
            // move to next byte
            .inc_ptr = b.literal(">"),
            // move to previous byte
            .dec_ptr = b.literal("<"),
            // increment current byte
            .inc_byte = b.literal("+"),
            // decrement current byte
            .dec_byte = b.literal("-"),
            // output current byte
            .out_byte = b.literal("."),
            // recieve input and write to current byte
            .in_byte = b.literal(","),
            // loop until current byte is 0
            .loop = b.tuple(.{
                .start = b.literal("["),
                // list of instructions
                .body = b.ref(self),
                .end = b.literal("]"),
            }),
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
                defer program.deparseValue(value, ctx);
                std.debug.print("[hello-world] parsed: {any}", .{value.*});
            },
            .err => |*err| {
                defer program.deparseErr(err, ctx);
                std.debug.print("[hello-world] error: {any}", .{err.*});
            },
        }
    }
}
