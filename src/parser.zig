const std = @import("std");
const meta = std.meta;
const mem = std.mem;

const utils = @import("./utils.zig");

pub fn ParserData(comptime parser: anytype) type {
    return union(enum) { value: parser.Value, err: parser.Err };
}

pub fn ParsedResult(comptime Value: type, comptime Err: type) type {
    return struct {
        /// parsed data
        data: union(enum) {
            value: Value,
            err: Err,
        },

        /// remaining slice
        rest: []const u8,
    };
}

pub const ModuleOptions = struct { context: type = struct { allocator: mem.Allocator }, whitespaces: []const u8 = " \n\r\t" };

pub fn module(comptime options: ModuleOptions) type {
    return struct {
        pub const Context = options.context;

        pub fn trimStart(input: []const u8) []const u8 {
            return input[utils.consumeChars(input, 0, options.whitespaces)..];
        }

        pub fn literal(comptime str: []const u8) type {
            return struct {
                pub const Value = struct {};
                pub const Err = struct {};

                pub fn parse(input: []const u8, _: Context) ParsedResult(Value, Err) {
                    return if (utils.startsWith(input, str)) .{ .data = .{ .value = .{} }, .rest = input[str.len..] } else .{ .data = .{ .err = .{} }, .rest = input };
                }

                pub inline fn deparseValue(_: *Value, _: Context) void {}
                pub inline fn deparseErr(_: *Err, _: Context) void {}
            };
        }

        pub fn either(comptime parser: type) type {
            return struct {
                pub const Value = ParserData(parser);
                pub const Err = noreturn;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    const parsed = parser.parse(input, c);

                    return switch (parsed.data) {
                        .value => |v| .{ .data = .{ .value = .{ .value = v } }, .rest = parsed.rest },
                        .err => |e| .{ .data = .{ .value = .{ .err = e } }, .rest = parsed.rest },
                    };
                }

                pub fn deparseValue(value: *Value, c: Context) void {
                    switch (value.*) {
                        .value => |*v| parser.deparseValue(v, c),
                        .err => |*e| parser.deparseErr(e, c),
                    }
                }
                pub inline fn deparseErr(_: *Err, _: Context) void {}
            };
        }

        pub fn optional(comptime parser: type) type {
            return struct {
                pub const Value = ?parser.Value;
                pub const Err = noreturn;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    var parsed = parser.parse(input, c);

                    switch (parsed.data) {
                        .value => |v| return .{ .data = .{ .value = v }, .rest = parsed.rest },
                        .err => |*e| {
                            parser.deparseErr(e, c);
                            return .{ .data = .{ .value = null }, .rest = parsed.rest };
                        },
                    }
                }

                pub fn deparseValue(value: *Value, c: Context) void {
                    if (value.*) |*v| parser.deparseValue(v, c);
                }
                pub inline fn deparseErr(_: *Err, _: Context) void {}
            };
        }

        /// Match parsers in sequence
        pub fn tuple(comptime parsers: anytype) type {
            const fields = meta.fields(@TypeOf(parsers));

            var names: [fields.len][]const u8 = undefined;
            var parser_value_types: [fields.len]type = undefined;
            var parser_error_types: [fields.len]type = undefined;
            var struct_attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;
            var union_attrs: [fields.len]std.builtin.Type.UnionField.Attributes = undefined;
            var values: [fields.len]u8 = undefined;

            for (fields, 0..) |field, i| {
                const parser = @field(parsers, field.name);

                names[i] = field.name;
                parser_value_types[i] = parser.Value;
                parser_error_types[i] = parser.Err;
                struct_attrs[i] = .{};
                union_attrs[i] = .{};
                values[i] = i;
            }

            const _Value = @Struct(.auto, null, &names, &parser_value_types, &struct_attrs);
            const _Err = @Union(.auto, @Enum(
                u8,
                .exhaustive,
                &names,
                &values,
            ), &names, &parser_error_types, &union_attrs);

            return struct {
                pub const Value = _Value;
                pub const Err = _Err;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    var currentInput = input;
                    var value: Value = undefined;

                    inline for (fields, 0..) |field, i| {
                        const parsed = @field(parsers, field.name).parse(currentInput, c);

                        switch (parsed.data) {
                            .value => |v| {
                                @field(value, field.name) = v;

                                // Don't trim the last one
                                currentInput = if (comptime i < fields.len - 1) trimStart(parsed.rest) else parsed.rest;
                            },
                            .err => |e| {
                                @branchHint(.cold);

                                // Deparse previous values
                                _deparseValue(&value, c, i);
                                return .{ .data = .{ .err = @unionInit(Err, field.name, e) }, .rest = parsed.rest };
                            },
                        }
                    }

                    return .{ .data = .{ .value = value }, .rest = currentInput };
                }

                fn _deparseValue(value: *Value, c: Context, len: usize) void {
                    inline for (0.., fields) |i, field| {
                        if (i < len)
                            @field(parsers, field.name).deparseValue(&@field(value, field.name), c);
                    }
                }

                pub fn deparseValue(value: *Value, c: Context) void {
                    inline for (fields) |field| {
                        @field(parsers, field.name).deparseValue(&@field(value, field.name), c);
                    }
                }
                pub fn deparseErr(err: *Err, c: Context) void {
                    inline for (fields) |field| {
                        if (err.* == @field(Err, field.name))
                            @field(parsers, field.name).deparseErr(&@field(err, field.name), c);
                    }
                }
            };
        }

        pub fn list(comptime parser: type) type {
            return struct {
                pub const Value = std.ArrayList(parser.Value);
                pub const Err = mem.Allocator.Error;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    var arr: Value = .empty;
                    var currentInput = input;

                    while (true) {
                        var parsed = parser.parse(currentInput, c);
                        switch (parsed.data) {
                            .value => |*v| {
                                arr.append(c.allocator, v.*) catch |e| {
                                    parser.deparseValue(v, c);
                                    deparseValue(&arr, c);
                                    return .{ .data = .{ .err = e }, .rest = currentInput };
                                };
                                currentInput = trimStart(parsed.rest);
                            },
                            .err => |*e| {
                                parser.deparseErr(e, c);
                                return .{ .data = .{ .value = arr }, .rest = parsed.rest };
                            },
                        }
                    }
                }

                pub fn deparseValue(value: *Value, c: Context) void {
                    for (value.items) |*item|
                        parser.deparseValue(item, c);
                    value.deinit(c.allocator);
                }
                pub inline fn deparseErr(_: *Err, _: Context) void {}
            };
        }

        pub fn separated_list(comptime parser: type, comptime separator_parser: type) type {
            return struct {
                pub const Value = std.ArrayList(parser.Value);
                pub const Err = mem.Allocator.Error!parser.Err;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    var arr: Value = .empty;
                    var currentInput = input;

                    while (true) {
                        var parsed = parser.parse(currentInput, c);
                        switch (parsed.data) {
                            .value => |*v| {
                                arr.append(c.allocator, v.*) catch |e| {
                                    parser.deparseValue(v, c);
                                    deparseValue(&arr, c);
                                    return .{ .data = .{ .err = e }, .rest = currentInput };
                                };

                                var sep_parsed = separator_parser.parse(trimStart(parsed.rest), c);
                                switch (sep_parsed.data) {
                                    .value => |*sep_v| {
                                        separator_parser.deparseValue(sep_v, c);
                                        currentInput = trimStart(sep_parsed.rest);
                                    },
                                    .err => |*sep_e| {
                                        separator_parser.deparseErr(sep_e, c);
                                        return .{ .data = .{ .value = arr }, .rest = sep_parsed.rest };
                                    },
                                }
                            },
                            .err => |e| {
                                deparseValue(&arr, c);
                                return .{ .data = .{ .err = e }, .rest = parsed.rest };
                            },
                        }
                    }
                }

                pub fn deparseValue(value: *Value, c: Context) void {
                    for (value.items) |*item|
                        parser.deparseValue(item, c);
                    value.deinit(c.allocator);
                }
                pub fn deparseErr(err: *Err, c: Context) void {
                    var ptr = err.* catch return;
                    parser.deparseErr(&ptr, c);
                }
            };
        }

        /// Match if any of the parsers matches
        pub fn any(comptime parsers: anytype) type {
            const fields = meta.fields(@TypeOf(parsers));

            var names: [fields.len][]const u8 = undefined;
            var parser_value_types: [fields.len]type = undefined;
            var parser_error_types: [fields.len]type = undefined;
            var struct_attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;
            var union_attrs: [fields.len]std.builtin.Type.UnionField.Attributes = undefined;
            var values: [fields.len]u8 = undefined;

            for (fields, 0..) |field, i| {
                const parser = @field(parsers, field.name);

                names[i] = field.name;
                parser_value_types[i] = parser.Value;
                parser_error_types[i] = parser.Err;
                struct_attrs[i] = .{};
                union_attrs[i] = .{};
                values[i] = i;
            }

            const _Value = @Union(.auto, @Enum(
                u8,
                .exhaustive,
                &names,
                &values,
            ), &names, &parser_value_types, &union_attrs);
            const _Err = @Struct(.auto, null, &names, &parser_error_types, &struct_attrs);

            return struct {
                pub const Value = _Value;
                pub const Err = _Err;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    var err: Err = undefined;

                    inline for (fields, 0..) |field, i| {
                        const parsed = @field(parsers, field.name).parse(input, c);

                        switch (parsed.data) {
                            .value => |v| {
                                _deparseErr(&err, c, i);
                                return .{ .data = .{ .value = @unionInit(Value, field.name, v) }, .rest = parsed.rest };
                            },
                            .err => |e| {
                                @field(err, field.name) = e;
                            },
                        }
                    }

                    return .{ .data = .{ .err = err }, .rest = input };
                }

                pub fn deparseValue(value: *Value, c: Context) void {
                    inline for (fields) |field| {
                        if (value.* == @field(Value, field.name))
                            @field(parsers, field.name).deparseValue(&@field(value, field.name), c);
                    }
                }

                fn _deparseErr(err: *Err, c: Context, len: usize) void {
                    inline for (0.., fields) |i, field| {
                        if (i < len)
                            @field(parsers, field.name).deparseErr(&@field(err, field.name), c);
                    }
                }

                pub fn deparseErr(err: *Err, c: Context) void {
                    inline for (fields) |field| {
                        @field(parsers, field.name).deparseErr(&@field(err, field.name), c);
                    }
                }
            };
        }

        /// Allocate for this parser
        pub fn ref(comptime parser: anytype) type {
            return struct {
                pub const Value = struct {
                    ptr: *anyopaque,

                    pub inline fn cast(self: @This()) *parser.Value {
                        return @ptrCast(@alignCast(self.ptr));
                    }
                };

                pub const Err = mem.Allocator.Error!parser.Err;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    var parsed = parser.parse(input, c);
                    switch (parsed.data) {
                        .value => |*v| {
                            const ptr = c.allocator.create(parser.Value) catch |e| {
                                parser.deparseValue(v, c);
                                return .{ .data = .{ .err = e }, .rest = parsed.rest };
                            };
                            ptr.* = v.*;
                            return .{ .data = .{ .value = .{ .ptr = ptr } }, .rest = parsed.rest };
                        },
                        .err => |e| {
                            return .{ .data = .{ .err = e }, .rest = parsed.rest };
                        },
                    }
                }

                pub fn deparseValue(value: *Value, c: Context) void {
                    const ptr = value.cast();
                    parser.deparseValue(ptr, c);
                    c.allocator.destroy(ptr);
                }

                pub inline fn deparseErr(err: *Err, c: Context) void {
                    var ptr = err.* catch return;
                    parser.deparseErr(&ptr, c);
                }
            };
        }

        /// Use this to reference a parser recursively
        pub fn recurse(comptime parser_init: anytype) type {
            return struct {
                const parser = blk: {
                    const f = if (@hasDecl(parser_init, "init")) parser_init.init else parser_init;
                    const info = @typeInfo(@TypeOf(f)).@"fn";
                    break :blk if (info.params.len == 0) f() else f(@This());
                };

                pub const Value = parser.Value;
                pub const Err = parser.Err;

                pub inline fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    return parser.parse(input, c);
                }

                pub inline fn deparseValue(value: *Value, c: Context) void {
                    parser.deparseValue(value, c);
                }
                pub inline fn deparseErr(err: *Err, c: Context) void {
                    parser.deparseErr(err, c);
                }
            };
        }
    };
}

const testing = std.testing;
test "basic" {
    const mod = module(.{ .context = struct {} });

    const parser = mod.tuple(.{ .prefix = mod.any(.{ .a = mod.literal("a"), .b = mod.literal("b") }), .suffix = mod.either(mod.literal("c")) });
    const c: mod.Context = .{};

    {
        var parsed = parser.parse("ac", c).data;
        try testing.expect(parsed == .value);
        defer parser.deparseValue(&parsed.value, c);
    }

    {
        var parsed = parser.parse("c", c).data;
        try testing.expect(parsed == .err);
        defer parser.deparseErr(&parsed.err, c);
    }
}

test "recursive" {
    const mod = module(.{});

    const parser = mod.recurse(struct {
        pub fn init(self: type) type {
            return mod.tuple(.{ .char = mod.any(.{ .a = mod.literal("a"), .b = mod.literal("b") }), .next = mod.optional(mod.ref(self)) });
        }
    });

    const c: mod.Context = .{ .allocator = testing.allocator };
    {
        var parsed = parser.parse("aabb", c).data;
        try testing.expect(parsed == .value);
        defer parser.deparseValue(&parsed.value, c);
    }

    {
        var parsed = parser.parse("aacb", c).data;
        try testing.expect(parsed == .value);
        defer parser.deparseValue(&parsed.value, c);
    }
}

test "list" {
    const mod = module(.{});

    const parser = mod.separated_list(mod.any(.{ .a = mod.literal("a"), .b = mod.literal("b") }), mod.literal(","));

    const c: mod.Context = .{ .allocator = testing.allocator };
    {
        var parsed = parser.parse("a,b,a", c).data;
        try testing.expect(parsed == .value);
        defer parser.deparseValue(&parsed.value, c);
    }

    {
        var parsed = parser.parse("a,b,a,c", c).data;
        try testing.expect(parsed == .err);
        defer parser.deparseErr(&parsed.err, c);
    }
}
