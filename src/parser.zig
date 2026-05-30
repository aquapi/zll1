const std = @import("std");
const mem = std.mem;

const char = @import("./char.zig");

// Trim
fn trimWhitespacesStart(input: []const u8) []const u8 {
    return mem.trimStart(u8, input, " \n\r\t");
}

// Parsers
pub fn ParseResult(comptime T: type) type {
    return struct { result: T, rest: []const u8 };
}

pub fn Const(comptime result: anytype, comptime prefix: []const u8) type {
    return struct {
        pub const Result = @TypeOf(result);

        pub inline fn parse(trimmedInput: []const u8) ?ParseResult(Result) {
            return if (mem.startsWith(u8, trimmedInput, prefix)) .{ .result = result, .rest = trimmedInput[prefix.len..] } else null;
        }
    };
}

pub fn Tuple(comptime Parsers: anytype) type {
    comptime var Types: [Parsers.len]type = undefined;
    for (Parsers, 0..) |Parser, i| Types[i] = Parser.Result;
    const ParserResult = @Tuple(&Types);

    return struct {
        pub const Result = ParserResult;

        pub inline fn parse(trimmedInput: []const u8) ?ParseResult(Result) {
            var result: Result = undefined;

            var remaining = trimmedInput;
            inline for (Parsers, 0..) |Parser, i| {
                if (if (i == 0)
                    Parser.parse(remaining)
                else
                    Parser.parse(trimWhitespacesStart(remaining))) |parseResult|
                {
                    result[i] = parseResult.result;
                    remaining = parseResult.rest;
                } else return null;
            }

            return .{ .result = result, .rest = remaining };
        }
    };
}

pub fn Union(comptime Parsers: anytype) type {
    const fields = std.meta.fields(@TypeOf(Parsers));

    comptime var names: [fields.len][]const u8 = undefined;
    comptime var types: [fields.len]type = undefined;
    comptime var attrs: [fields.len]std.builtin.Type.UnionField.Attributes = undefined;
    comptime var values: [fields.len]u8 = undefined;

    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
        types[i] = @field(Parsers, field.name).Result;
        attrs[i] = .{};
        values[i] = i;
    }

    const ParserResult = @Union(
        .auto,
        @Enum(
            u8,
            .exhaustive,
            &names,
            &values,
        ),
        &names,
        &types,
        &attrs,
    );

    return struct {
        pub const Result = ParserResult;

        pub inline fn parse(trimmedInput: []const u8) ?ParseResult(Result) {
            inline for (fields, 0..) |field, i| {
                const Parser = @field(Parsers, field.name);

                if (if (i == 0) Parser.parse(trimmedInput) else Parser.parse(trimWhitespacesStart(trimmedInput))) |parseResult|
                    return .{ .result = @unionInit(Result, field.name, parseResult.result), .rest = parseResult.rest };
            }

            return null;
        }
    };
}

const testing = std.testing;
const Value = enum(u8) { x, y, z };

test "Const" {
    const Parser = Const(Value.x, "x");
    try testing.expect(Parser.parse("x").?.result == .x);
}

test "Tuple" {
    const Parser = Tuple(.{ Const(Value.x, "x"), Const(Value.y, "y"), Const(Value.z, "z") });

    const parsed = Parser.parse("x y z t").?;
    try testing.expect(parsed.result[0] == .x);
    try testing.expect(parsed.result[1] == .y);
    try testing.expect(parsed.result[2] == .z);
    try testing.expect(mem.eql(u8, parsed.rest, " t"));
}

test "Union" {
    const Parser = Union(.{ .x = Const(true, "x"), .y = Const(true, "y"), .z = Const(true, "z") });
    std.debug.print("\nUnion: {any}\n", .{ Parser });

    const parsed = Parser.parse("y").?.result;
    switch (parsed) {
        .y => {},
        else => try testing.expect(false),
    }
}
