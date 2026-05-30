const std = @import("std");
const mem = std.mem;

const utils = @import("./utils.zig");

// Trim
fn trimWhitespacesStart(input: []const u8) []const u8 {
    return mem.trimStart(u8, input, " \n\r\t");
}

// Parsers
pub fn ParsedResult(comptime T: type) type {
    return struct { value: T, rest: []const u8 };
}

pub fn Const(comptime result: anytype, comptime prefix: []const u8) type {
    return struct {
        pub const Result = @TypeOf(result);

        pub inline fn parse(trimmedInput: []const u8) ?ParsedResult(Result) {
            return if (mem.startsWith(u8, trimmedInput, prefix)) .{ .value = result, .rest = trimmedInput[prefix.len..] } else null;
        }
    };
}

// Numbers
pub const UInt = struct {
    pub const Result = []const u8;

    pub fn parse(trimmedInput: []const u8) ?ParsedResult(Result) {
        if (trimmedInput.len > 0) {
            @branchHint(.likely);

            switch (trimmedInput[0]) {
                '0' => return .{ .value = "0", .rest = trimmedInput[1..] },
                '1'...'9' => {
                    const rest = mem.trimStart(u8, trimmedInput[1..], utils.DIGITS);
                    return .{ .value = trimmedInput[0 .. trimmedInput.len - rest.len], .rest = rest };
                },
                else => {},
            }
        }

        return null;
    }
};

pub const Int = struct {
    pub const Result = []const u8;

    pub fn parse(trimmedInput: []const u8) ?ParsedResult(Result) {
        if (trimmedInput.len > 0) {
            @branchHint(.likely);

            switch (trimmedInput[0]) {
                '0' => return .{ .value = "0", .rest = trimmedInput[1..] },
                '1'...'9' => {
                    const rest = mem.trimStart(u8, trimmedInput[1..], utils.DIGITS);
                    return .{ .value = trimmedInput[0 .. trimmedInput.len - rest.len], .rest = rest };
                },
                '-' => {
                    if (trimmedInput.len > 1) {
                        @branchHint(.likely);

                        switch (trimmedInput[1]) {
                            '0' => return .{ .value = "0", .rest = trimmedInput[2..] },
                            '1'...'9' => {
                                const rest = mem.trimStart(u8, trimmedInput[2..], utils.DIGITS);
                                return .{ .value = trimmedInput[0 .. trimmedInput.len - rest.len], .rest = rest };
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }

        return null;
    }
};

pub fn Tuple(comptime Parsers: anytype) type {
    comptime var Types: [Parsers.len]type = undefined;
    for (Parsers, 0..) |Parser, i| Types[i] = Parser.Result;
    const ParserResult = @Tuple(&Types);

    return struct {
        pub const Result = ParserResult;

        pub inline fn parse(trimmedInput: []const u8) ?ParsedResult(Result) {
            var result: Result = undefined;

            var remaining = trimmedInput;
            inline for (Parsers, 0..) |Parser, i| {
                if (if (i == 0)
                    Parser.parse(remaining)
                else
                    Parser.parse(trimWhitespacesStart(remaining))) |parsedResult|
                {
                    result[i] = parsedResult.value;
                    remaining = parsedResult.rest;
                } else return null;
            }

            return .{ .value = result, .rest = remaining };
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

        pub inline fn parse(trimmedInput: []const u8) ?ParsedResult(Result) {
            inline for (fields) |field|
                if (@field(Parsers, field.name).parse(trimmedInput)) |parsedResult|
                    return .{ .value = @unionInit(Result, field.name, parsedResult.value), .rest = parsedResult.rest };

            return null;
        }
    };
}

pub fn parse(comptime T: anytype, input: []const u8) ?T.Result {
    return if (T.parse(trimWhitespacesStart(input))) |parsedResult| parsedResult.value else null;
}

const testing = std.testing;
const Value = enum(u8) { x, y, z };

test "Const" {
    const Parser = Const(Value.x, "x");
    try testing.expect(parse(Parser, "x").? == .x);
}

test "Integers" {
    try testing.expect(mem.eql(u8, parse(UInt, " 32 ").?, "32"));
    try testing.expect(mem.eql(u8, parse(Int, " -32 ").?, "-32"));
}

test "Tuple" {
    const Parser = Tuple(.{ Const(Value.x, "x"), Const(Value.y, "y"), Const(Value.z, "z") });

    const value = parse(Parser, " x y z t").?;
    try testing.expect(value[0] == .x);
    try testing.expect(value[1] == .y);
    try testing.expect(value[2] == .z);
}

test "Union" {
    const Parser = Union(.{ .x = Const(true, "x"), .y = Const(true, "y"), .z = Const(true, "z") });

    const parsed = parse(Parser, "y t").?;
    switch (parsed) {
        .y => {},
        else => try testing.expect(false),
    }
}
