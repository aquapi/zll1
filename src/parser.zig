const std = @import("std");
const mem = std.mem;

const utils = @import("./utils.zig");

pub const Noop = struct {
    pub const Value = struct {};

    pub inline fn parse(_: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
        return .{ .value = .{}, .rest = trimmedInput };
    }

    pub inline fn deparse(_: mem.Allocator, _: Value) void {}
};

/// Identifier parser.
pub const Ident = struct {
    pub const Value = []const u8;

    pub fn parse(_: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
        return if (trimmedInput.len == 0) null else switch (trimmedInput[0]) {
            'a'...'z', 'A'...'Z', '$', '_' => utils.split(trimmedInput, utils.consumeChars(trimmedInput, 1, utils.IDENT)),
            else => null,
        };
    }

    pub inline fn deparse(_: mem.Allocator, _: Value) void {}
};

pub fn Const(comptime prefix: []const u8) type {
    return struct {
        pub const Value = struct {};

        pub inline fn parse(_: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            return if (utils.startsWith(trimmedInput, prefix)) .{ .value = .{}, .rest = trimmedInput[prefix.len..] } else null;
        }

        pub inline fn deparse(_: mem.Allocator, _: Value) void {}
    };
}

pub fn Comment(comptime prefix: []const u8, comptime suffix: []const u8) type {
    return struct {
        pub const Value = struct {};

        pub fn parse(_: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            if (utils.startsWith(trimmedInput, prefix)) {
                return if (utils.findPos(u8, trimmedInput, prefix.len, suffix)) |pos|
                    .{ .value = .{}, .rest = trimmedInput[pos + suffix.len] }
                else
                    .{ .value = .{}, .rest = trimmedInput[trimmedInput.len..] };
            }

            return .{ .value = .{}, .rest = trimmedInput };
        }

        pub inline fn deparse(_: mem.Allocator, _: Value) void {}
    };
}

pub fn Prefix(comptime prefix: []const u8, comptime Parser: anytype) type {
    return struct {
        pub const Value = Parser.Value;

        pub inline fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            return if (utils.startsWith(trimmedInput, prefix))
                Parser.parse(allocator, utils.trimWhitespacesStart(trimmedInput[prefix.len..]))
            else
                null;
        }

        pub inline fn deparse(allocator: mem.Allocator, value: Value) void {
            Parser.deparse(allocator, value);
        }
    };
}

pub fn Suffix(comptime Parser: anytype, comptime suffix: []const u8) type {
    return struct {
        pub const Value = Parser.Value;

        pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            if (Parser.parse(allocator, trimmedInput)) |token| {
                const rest = utils.trimWhitespacesStart(token.rest);
                if (utils.startsWith(rest, suffix))
                    return .{ .value = token.value, .rest = rest }
                else
                    Parser.deparse(allocator, token.value);
            }

            return null;
        }

        pub inline fn deparse(allocator: mem.Allocator, value: Value) void {
            Parser.deparse(allocator, value);
        }
    };
}

pub fn Wrap(comptime prefix: []const u8, comptime Parser: anytype, comptime suffix: []const u8) type {
    return struct {
        pub const Value = Parser.Value;

        pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            if (utils.startsWith(trimmedInput, prefix)) {
                if (Parser.parse(allocator, utils.trimWhitespacesStart(trimmedInput[prefix.len..]))) |token| {
                    const rest = utils.trimWhitespacesStart(token.rest);
                    if (utils.startsWith(rest, suffix))
                        return .{ .value = token.value, .rest = rest }
                    else
                        Parser.deparse(allocator, token.value);
                }
            }

            return null;
        }

        pub inline fn deparse(allocator: mem.Allocator, value: Value) void {
            Parser.deparse(allocator, value);
        }
    };
}

// Combinators
pub fn Tuple(comptime Parsers: anytype) type {
    const fields = std.meta.fields(@TypeOf(Parsers));

    return struct {
        pub const Value = blk: {
            var names: [fields.len][]const u8 = undefined;
            var parser_value_types: [fields.len]type = undefined;
            var attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;
            var values: [fields.len]u8 = undefined;

            for (fields, 0..) |field, i| {
                names[i] = field.name;
                parser_value_types[i] = @field(Parsers, field.name).Value;
                attrs[i] = .{};
                values[i] = i;
            }

            break :blk @Struct(.auto, null, &names, &parser_value_types, &attrs);
        };

        fn deparseUntil(allocator: mem.Allocator, freeIdx: usize, value: Value) void {
            inline for (fields, 0..) |field, i|
                if (i < freeIdx)
                    @field(Parsers, field.name).deparse(allocator, @field(value, field.name));
        }

        pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            var value: Value = undefined;
            var currentInput = trimmedInput;

            inline for (fields, 0..) |field, i| {
                if (@field(Parsers, field.name).parse(allocator, currentInput)) |token| {
                    @field(value, field.name) = token.value;
                    if (comptime i < fields.len - 1)
                        currentInput = utils.trimWhitespacesStart(token.rest)
                    else
                        return .{ .value = value, .rest = token.rest };
                } else {
                    deparseUntil(allocator, i, value);
                    return null;
                }
            }
        }

        pub inline fn deparse(allocator: mem.Allocator, value: Value) void {
            deparseUntil(allocator, fields.len, value);
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

        pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            inline for (fields) |field|
                if (@field(Parsers, field.name).parse(allocator, trimmedInput)) |parsedResult|
                    return .{ .value = @unionInit(Value, field.name, parsedResult.value), .rest = parsedResult.rest };

            return null;
        }

        pub fn deparse(allocator: mem.Allocator, value: Value) void {
            inline for (fields) |field|
                if (value == @field(Value, field.name))
                    @field(Parsers, field.name).deparse(allocator, @field(value, field.name));
        }
    };
}

pub fn Optional(comptime Parser: anytype) type {
    return struct {
        pub const Value = ?Parser.Value;

        pub inline fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            return if (Parser.parse(allocator, trimmedInput)) |token|
                .{ .value = token.value, .rest = token.rest }
            else
                .{ .value = null, .rest = trimmedInput };
        }

        pub inline fn deparse(allocator: mem.Allocator, value: Value) void {
            if (value) |val| Parser.deparse(allocator, val);
        }
    };
}

pub fn Array(comptime Parser: anytype, comptime separator: []const u8) type {
    return struct {
        pub const Value = std.ArrayList(Parser.Value);

        pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            var list: Value = .empty;
            var currentInput = trimmedInput;

            while (Parser.parse(allocator, currentInput)) |token| {
                list.append(allocator, token.value) catch {
                    @This().deparse(allocator, list);
                    return null;
                };

                currentInput = utils.trimWhitespacesStart(token.rest);
                if (comptime separator.len > 0) {
                    if (!utils.startsWith(currentInput, separator))
                        break;

                    currentInput = utils.trimWhitespacesStart(currentInput[separator.len..]);
                }
            }

            return .{ .value = list, .rest = currentInput };
        }

        pub fn deparse(allocator: mem.Allocator, value: Value) void {
            for (value.items) |item|
                Parser.deparse(allocator, item);
            defer @constCast(&value).deinit(allocator);
        }
    };
}

/// Reference parser recursively.
pub fn Ref(comptime Parser: anytype) type {
    return struct {
        pub const Value = struct {
            ptr: *anyopaque,

            pub inline fn cast(self: @This()) *Parser.Value {
                return @ptrCast(@alignCast(self.ptr));
            }
        };

        pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            if (Parser.parse(allocator, trimmedInput)) |token| {
                const ptr = allocator.create(Parser.Value) catch {
                    Parser.deparse(allocator, token.value);
                    return null;
                };
                ptr.* = token.value;
                return .{ .value = .{ .ptr = ptr }, .rest = token.rest };
            }

            return null;
        }

        pub fn deparse(allocator: mem.Allocator, value: Value) void {
            const ptr = value.cast();
            Parser.deparse(allocator, ptr.*);
            allocator.destroy(ptr);
        }
    };
}

pub fn Recursive(comptime ParserInit: type) type {
    return struct {
        const T = blk: {
            const info = @typeInfo(@TypeOf(ParserInit.init)).@"fn";
            break :blk if (info.params.len == 0) ParserInit.init() else ParserInit.init(@This());
        };

        pub const Value = T.Value;

        pub fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult(Value) {
            return T.parse(allocator, trimmedInput);
        }

        pub fn deparse(allocator: mem.Allocator, value: Value) void {
            T.deparse(allocator, value);
        }
    };
}

pub fn parse(comptime T: anytype, allocator: mem.Allocator, input: []const u8) ?T.Value {
    return if (T.parse(allocator, utils.trimWhitespacesStart(input))) |parsedResult| parsedResult.value else null;
}

pub fn deparse(comptime T: anytype, allocator: mem.Allocator, value: T.Value) void {
    T.deparse(allocator, value);
}

//
// TESTING STUFF
//
const testing = std.testing;

test "Const" {
    const Parser = Const("x");

    const parsed = parse(Parser, testing.failing_allocator, "x").?;
    _ = parsed;
}

test "Tuple" {
    const Parser = Tuple(.{ .x = Const("x"), .y = Const("y"), .z = Const("z") });

    const parsed = parse(Parser, testing.failing_allocator, " x y z t").?;
    _ = parsed.x;
    _ = parsed.y;
    _ = parsed.z;
}

test "Union" {
    const Parser = Union(.{ .x = Const("x"), .y = Const("y"), .z = Const("z") });

    const parsed = parse(Parser, testing.failing_allocator, "y t").?;
    _ = parsed.y;
}

test "Ref" {
    const Parser = Recursive(struct {
        fn init(Self: type) type {
            return Union(.{
                .end = Const("end"),
                .next = Tuple(.{
                    .prefix = Union(.{ .x = Const("x"), .y = Const("y") }),
                    .ref = Ref(Self),
                }),
            });
        }
    });

    const allocator = testing.allocator;

    if (parse(Parser, allocator, "  x  end  ")) |val| {
        defer deparse(Parser, allocator, val);

        _ = val.next.prefix;
        _ = val.next.ref.cast().end;
    } else try testing.expect(false);
}

test "Module" {
    const Parser = (struct {
        const Self = @This();

        pub const Root = Union(.{
            .end = Const("end"),
            .next = Tuple(.{
                .prefix = Union(.{ .x = Const("x"), .y = Const("y") }),
                .z = Self.Z,
            }),
        });

        pub const Z = Const("z");
    }).Root;

    const allocator = testing.allocator;

    if (parse(Parser, allocator, "  x  z  ")) |val| {
        defer deparse(Parser, allocator, val);

        _ = val.next.prefix;
        _ = val.next.z;
    } else try testing.expect(false);
}
