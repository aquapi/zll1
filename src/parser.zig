
const std = @import("std");
const mem = std.mem;

const utils = @import("./utils.zig");

// Trim
fn trimWhitespacesStart(input: []const u8) []const u8 {
    return mem.trimStart(u8, input, " \n\r\t");
}

// Parsed value and type resolution
pub fn Parsed(comptime T: anytype) type {
    return struct { value: T, rest: []const u8 };
}

// Constant
pub fn Const(comptime prefix: []const u8) type {
    return struct {
        pub const Value = struct {};

        pub inline fn parse(_: mem.Allocator, trimmedInput: []const u8) ?Parsed(Value) {
            return if (mem.startsWith(u8, trimmedInput, prefix)) .{ .value = .{}, .rest = trimmedInput[prefix.len..] } else null;
        }

        pub inline fn deparse(_: mem.Allocator, _: Value) void {}
    };
}

// Numbers
pub const UInt = struct {
    pub const Value = []const u8;

    pub fn parse(_: mem.Allocator, trimmedInput: []const u8) ?Parsed(Value) {
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

    pub inline fn deparse(_: mem.Allocator, _: Value) void {}
};

pub const Int = struct {
    pub const Value = []const u8;

    pub fn parse(_: mem.Allocator, trimmedInput: []const u8) ?Parsed(Value) {
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

    pub inline fn deparse(_: mem.Allocator, _: Value) void {}
};

// Combinators
pub fn Tuple(comptime Parsers: anytype) type {
    return struct {
        pub const Value = blk: {
            var parser_value_types: [Parsers.len]type = undefined;

            for (Parsers, 0..) |Parser, i|
                parser_value_types[i] = Parser.Value;

           break :blk @Tuple(&parser_value_types);
        };

        pub fn deparseUntil(allocator: mem.Allocator, freeIdx: usize, value: Value) void {
            inline for (Parsers, 0..) |Parser, i|
                if (i < freeIdx)
                    Parser.deparse(allocator, value[i]);
        }

        pub inline fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?Parsed(Value) {
            var value: Value = undefined;
            var currentInput = trimmedInput;

            inline for (Parsers, 0..) |Parser, i| {
                if (Parser.parse(allocator, currentInput)) |token| {
                    value[i] = token.value;
                    if (comptime i < Parsers.len - 1)
                        currentInput = trimWhitespacesStart(token.rest)
                    else
                        return .{ .value = value, .rest = token.rest };
                } else {
                    deparseUntil(allocator, i, value);
                    return null;
                }
            }
        }

        pub inline fn deparse(allocator: mem.Allocator, value: Value) void {
            inline for (Parsers, 0..) |Parser, i|
                Parser.deparse(allocator, value[i]);
        }
    };
}

pub fn Union(comptime Parsers: anytype) type {
    const fields = std.meta.fields(@TypeOf(Parsers));

    return struct {
      pub const Value = blk: {
            var names: [fields.len][]const u8 = undefined;
            var parser_value_types: [fields.len]type = undefined;
            var attrs: [fields.len]std.builtin.Type.UnionField.Attributes = undefined;
            var values: [fields.len]u8 = undefined;

            for (fields, 0..) |field, i| {
                names[i] = field.name;
                parser_value_types[i] = @field(Parsers, field.name).Value;
                attrs[i] = .{};
                values[i] = i;
            }

            break :blk @Union(
                .auto,
                @Enum(
                    u8,
                    .exhaustive,
                    &names,
                    &values,
                ),
                &names,
                &parser_value_types,
                &attrs,
            );
        };

        pub inline fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?Parsed(Value) {
            inline for (fields) |field|
                if (@field(Parsers, field.name).parse(allocator, trimmedInput)) |parsedResult|
                    return .{ .value = @unionInit(Value, field.name, parsedResult.value), .rest = parsedResult.rest };

            return null;
        }

        pub inline fn deparse(allocator: mem.Allocator, value: Value) void {
            inline for (fields) |field| {
                if (value == @field(Value, field.name)) {
                    const active_val = @field(value, field.name);
                    @field(Parsers, field.name).deparse(allocator, active_val);
                }
            }
        }
    };
}

pub fn Ref(comptime Parser: anytype) type {
    return struct {
        pub const Value = *anyopaque;

        pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?Parsed(Value) {
            if (Parser.parse(allocator, trimmedInput)) |token| {
                const ptr = allocator.create(Parser.Value) catch {
                    Parser.deparse(allocator, token.value);
                    return null;
                };
                ptr.* = token.value;

                return .{ .value = ptr, .rest = token.rest };
            }

            return null;
        }

        pub fn deparse(allocator: mem.Allocator, value: Value) void {
            const ptr: *Parser.Value = @ptrCast(@alignCast(value));
            Parser.deparse(allocator, ptr.*);
            allocator.destroy(ptr);
        }
    };
}

pub fn Cache(comptime Parser: anytype) type {
    return struct {
        pub const Value = Parser.Value;

        pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?Parsed(Value) {
            return Parser.parse(allocator, trimmedInput);
        }

        pub fn deparse(allocator: mem.Allocator, value: Value) void {
            Parser.deparse(allocator, value);
        }
    };
}

pub fn parse(comptime T: anytype, allocator: mem.Allocator, input: []const u8) ?T.Value {
    return if (T.parse(allocator, trimWhitespacesStart(input))) |parsedResult| parsedResult.value else null;
}

//
// TESTING STUFF
//
const testing = std.testing;

test "Const" {
    const Parser = Const("x");
    try testing.expect(parse(Parser, testing.allocator, "x") != null);
}

test "Integers" {
    try testing.expect(mem.eql(u8, parse(UInt, testing.allocator, " 32 ").?, "32"));
    try testing.expect(mem.eql(u8, parse(Int, testing.allocator, " -32 ").?, "-32"));
}

test "Tuple" {
    const Parser = Tuple(.{ Const("x"), Const("y"), Const("z") });
    try testing.expect(parse(Parser, testing.allocator, " x y z t") != null);
}

test "Union" {
    const Parser = Union(.{ .x = Const("x"), .y = Const("y"), .z = Const("z") });

    const parsed = parse(Parser, testing.allocator, "y t").?;
    try testing.expect(switch (parsed) {
        .y => true,
        else => false,
    });
}

test "Ref" {
    const Recursive = struct {
      fn init(Self: type) type {
        return Cache(Union(.{
            .end = Const("end"),
            .next = Tuple(.{
                Union(.{ .x = Const("x"), .y = Const("y") }),
                Ref(Self), // hmm
            }),
        }));
      }
    };

    const Parser = struct {
      const T = Recursive.init(@This());

      pub const Value = T.Value;

      pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?Parsed(Value) {
          return T.parse(allocator, trimmedInput);
      }

      pub fn deparse(allocator: mem.Allocator, value: Value) void {
          T.deparse(allocator, value);
      }
    };

    const allocator = testing.allocator;

    if (parse(Parser, allocator, "  x  end  ")) |val| {
        defer Parser.deparse(allocator, val);
        try testing.expect(true);
    } else try testing.expect(false);
}
