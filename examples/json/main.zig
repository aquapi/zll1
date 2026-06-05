const std = @import("std");
const parser = @import("zll1").parser;

const JSON = @import("./grammar.zig");

pub fn main(init: std.process.Init) void {
    const arena = init.arena.allocator();

    {
        const example_json = parser.parse(JSON.Value, arena,
            \\{
            \\  "hello": "world",
            \\  "id": 0
            \\}
        ).?;
        defer parser.deparse(JSON.Value, arena, example_json);

        const props = example_json.object;
        _ = props.items[0][1].cast().string;
        _ = props.items[1][1].cast().number;
    }
}
