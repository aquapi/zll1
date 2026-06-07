const std = @import("std");
const parser = @import("zll1").parser;

const json = @import("./grammar.zig");

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    {
        const example_json = parser.parse(json.Value, allocator,
            \\{
            \\  "hello": "world",
            \\  "id": 0
            \\}
        ).?;
        defer parser.deparse(json.Value, allocator, example_json);

        const props = example_json.object.cast();
        _ = props.items[0].value.string;
        _ = props.items[1].value.number;
    }
}
