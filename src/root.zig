pub const parser = @import("./parser.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
