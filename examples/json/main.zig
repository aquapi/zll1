const std = @import("std");
const parser = @import("zll1").parser;

const grammar = @import("./grammar.zig");

pub fn main(init: std.process.Init) void {
    const arena = init.arena.allocator();

    {
        const example_json = parser.parse(grammar.JSON, arena,
            \\{
            \\  "hello": "world",
            \\  "id": 0
            \\}
        ).?;
        defer parser.deparse(grammar.JSON, arena, example_json);

        const props = example_json.object[1].?;
        _ = props[0][2].cast().string;
        _ = props[1].items[0][1][2].cast().number;
    }
}
