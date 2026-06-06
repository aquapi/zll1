const std = @import("std");
const parser = @import("zll1").parser;

const JSON = @import("./grammar.zig");

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    {
        const example_json = parser.parse(JSON.Value, allocator,
            \\{
            \\  "hello": "world",
            \\  "id": 0
            \\}
        ).?;
        defer parser.deparse(JSON.Value, allocator, example_json);

        const props = example_json.object;
        _ = props.items[0][1].cast().string;
        _ = props.items[1][1].cast().number;
    }
}
