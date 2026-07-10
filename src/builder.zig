const std = @import("std");
const meta = std.meta;
const mem = std.mem;

const utils = @import("./utils.zig");

pub fn ParserData(comptime parser: anytype) type {
    return union(enum) { value: parser.Value, err: parser.Err };
}

pub fn ParsedResult(comptime Value: type, comptime Err: type) type {
    return union(enum) { value: struct { data: Value, rest: []const u8 }, err: Err };
}

pub const BuilderOptions = struct {
    /// Shared values used by parsers
    ctx: type = struct { allocator: mem.Allocator },

    /// Methods
    vtable: type = struct {
        pub inline fn trimStart(input: []const u8) []const u8 {
            return input[utils.consumeChars(input, 0, " \n\r\t")..];
        }
    },
};

pub fn init(comptime options: BuilderOptions) type {
    return struct {
        pub const Context = options.ctx;

        inline fn trimStart(input: []const u8) []const u8 {
            return options.vtable.trimStart(input);
        }

        /// Match a literal
        pub fn literal(comptime str: []const u8) type {
            return struct {
                pub const Value = struct {};
                pub const Err = []const u8;

                pub fn parse(input: []const u8, _: Context) ParsedResult(Value, Err) {
                    return if (utils.startsWith(input, str)) .{ .value = .{ .data = .{}, .rest = input[str.len..] } } else .{ .err = input };
                }

                pub inline fn deparseValue(_: *Value, _: Context) void {}
                pub inline fn deparseErr(_: *Err, _: Context) void {}
            };
        }

        /// Discard a parser result
        pub fn discard(comptime parser: type) type {
            return struct {
                pub const Value = struct {};
                pub const Err = parser.Err;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    switch (parser.parse(input, c)) {
                        .value => |*v| {
                            parser.deparseValue(&v.data, c);
                            return .{
                                .value = .{ .data = .{}, .rest = v.rest },
                            };
                        },
                        .err => |e| return .{ .err = e },
                    }
                }

                pub fn deparseValue(_: *Value, _: Context) void {}
                pub inline fn deparseErr(e: *Err, c: Context) void {
                    parser.deparseErr(e, c);
                }
            };
        }

        /// Collect error and continue parsing instead of returning
        pub fn either(comptime parser: type) type {
            return struct {
                pub const Value = ParserData(parser);
                pub const Err = noreturn;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    return switch (parser.parse(input, c)) {
                        .value => |v| .{ .value = .{ .data = .{ .value = v.data }, .rest = v.rest } },
                        .err => |e| .{ .value = .{ .data = .{ .err = e }, .rest = input } },
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

        /// Ignore error and continue parsing
        pub fn optional(comptime parser: type) type {
            return struct {
                pub const Value = ?parser.Value;
                pub const Err = noreturn;

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    var parsed = parser.parse(input, c);
                    switch (parsed) {
                        .value => |v| return .{ .value = .{ .data = v.data, .rest = v.rest } },
                        .err => |*e| {
                            parser.deparseErr(e, c);
                            return .{ .value = .{ .data = null, .rest = input } };
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
                        switch (@field(parsers, field.name).parse(currentInput, c)) {
                            .value => |v| {
                                @field(value, field.name) = v.data;

                                // Don't trim the last one
                                currentInput = if (comptime i < fields.len - 1) trimStart(v.rest) else v.rest;
                            },
                            .err => |e| {
                                // Deparse previous values
                                _deparseValue(&value, c, i);
                                return .{ .err = @unionInit(Err, field.name, e) };
                            },
                        }
                    }

                    return .{ .value = .{ .data = value, .rest = currentInput } };
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
                        switch (parsed) {
                            .value => |*v| {
                                arr.append(c.allocator, v.data) catch |e| {
                                    parser.deparseValue(&v.data, c);
                                    deparseValue(&arr, c);
                                    return .{ .err = e };
                                };
                                currentInput = trimStart(v.rest);
                            },
                            .err => |*e| {
                                parser.deparseErr(e, c);
                                return .{ .value = .{ .data = arr, .rest = currentInput } };
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
                        switch (parsed) {
                            .value => |*v| {
                                arr.append(c.allocator, v.data) catch |e| {
                                    parser.deparseValue(&v.data, c);
                                    deparseValue(&arr, c);
                                    return .{ .err = e };
                                };

                                currentInput = trimStart(v.rest);
                                var sep_parsed = separator_parser.parse(currentInput, c);
                                switch (sep_parsed) {
                                    .value => |*sep_v| {
                                        separator_parser.deparseValue(&sep_v.data, c);
                                        currentInput = trimStart(sep_v.rest);
                                    },
                                    .err => |*sep_e| {
                                        separator_parser.deparseErr(sep_e, c);
                                        return .{ .value = .{ .data = arr, .rest = currentInput } };
                                    },
                                }
                            },
                            .err => |e| {
                                deparseValue(&arr, c);
                                return .{ .err = e };
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
                        switch (@field(parsers, field.name).parse(input, c)) {
                            .value => |v| {
                                _deparseErr(&err, c, i);
                                return .{ .value = .{ .data = @unionInit(Value, field.name, v.data), .rest = v.rest } };
                            },
                            .err => |e| {
                                @field(err, field.name) = e;
                            },
                        }
                    }

                    return .{ .err = err };
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

                pub const Err = mem.Allocator.Error!struct {
                    ptr: *anyopaque,

                    pub inline fn cast(self: @This()) *parser.Err {
                        return @ptrCast(@alignCast(self.ptr));
                    }
                };

                pub fn parse(input: []const u8, c: Context) ParsedResult(Value, Err) {
                    var parsed = parser.parse(input, c);
                    switch (parsed) {
                        .value => |*v| {
                            const ptr = c.allocator.create(parser.Value) catch |alloc_e| {
                                parser.deparseValue(&v.data, c);
                                return .{ .err = alloc_e };
                            };
                            ptr.* = v.data;
                            return .{ .value = .{ .data = .{ .ptr = ptr }, .rest = v.rest } };
                        },
                        .err => |*e| {
                            const ptr = c.allocator.create(parser.Err) catch |alloc_e| {
                                parser.deparseErr(e, c);
                                return .{ .err = alloc_e };
                            };
                            ptr.* = e.*;
                            return .{ .err = .{ .ptr = ptr } };
                        },
                    }
                }

                pub fn deparseValue(value: *Value, c: Context) void {
                    const ptr = value.cast();
                    parser.deparseValue(ptr, c);
                    c.allocator.destroy(ptr);
                }

                pub fn deparseErr(err: *Err, c: Context) void {
                    const ptr = (err.* catch return).cast();
                    parser.deparseErr(ptr, c);
                    c.allocator.destroy(ptr);
                }
            };
        }

        /// Use this to reference a parser recursively
        pub fn recurse(comptime parser_init: anytype) type {
            return struct {
                const parser = blk: {
                    // Detect different signatures:
                    // struct { pub fn init(self: type) type }
                    // struct { pub fn init() type }
                    // pub fn init(self: type) type
                    // pub fn init() type
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

test init {
    _ = struct {
        const b = init(.{});
        const ctx: b.Context = .{ .allocator = std.testing.allocator };

        test "literal" {
            const parser = b.literal("ab");

            {
                const value = parser.parse("ab", ctx).value;
                try testing.expectEqualStrings("", value.rest);
            }

            {
                const value = parser.parse("abcd", ctx).value;
                try testing.expectEqualStrings("cd", value.rest);
            }

            {
                const err = parser.parse("ad", ctx).err;
                try testing.expectEqualStrings("ad", err);
            }
        }
    };
}

// test "basic" {
//     const b = init(.{ .ctx = struct {} });

//     const parser = b.tuple(.{ .prefix = b.any(.{ .a = b.literal("a"), .b = b.literal("b") }), .suffix = b.either(b.literal("c")) });
//     const c: b.Context = .{};

//     {
//         var parsed = parser.parse("ac", c);
//         try testing.expect(parsed == .value);
//         defer parser.deparseValue(&parsed.value.data, c);
//     }

//     {
//         var parsed = parser.parse("c", c);
//         try testing.expect(parsed == .err);
//         defer parser.deparseErr(&parsed.err, c);
//     }
// }

// test "recursive" {
//     const b = init(.{});

//     const parser = b.recurse(struct {
//         pub fn init(self: type) type {
//             return b.tuple(.{ .char = b.any(.{ .a = b.literal("a"), .b = b.literal("b") }), .next = b.optional(b.ref(self)) });
//         }
//     });

//     const c: b.Context = .{ .allocator = testing.allocator };
//     {
//         var parsed = parser.parse("aabb", c);
//         try testing.expect(parsed == .value);
//         defer parser.deparseValue(&parsed.value.data, c);
//         try testing.expectEqualStrings(parsed.value.rest, "");
//     }

//     {
//         var parsed = parser.parse("aacb", c);
//         try testing.expect(parsed == .value);
//         defer parser.deparseValue(&parsed.value.data, c);
//         try testing.expectEqualStrings(parsed.value.rest, "cb");
//     }
// }

// test "list" {
//     const b = init(.{});
//     const c: b.Context = .{ .allocator = testing.allocator };

//     // List
//     {
//         const parser = b.list(b.any(.{ .a = b.literal("a"), .b = b.literal("b") }));

//         {
//             var parsed = parser.parse("aba", c);
//             try testing.expect(parsed == .value);
//             defer parser.deparseValue(&parsed.value.data, c);
//             try testing.expectEqualStrings(parsed.value.rest, "");
//         }
//     }

//     // Separated list
//     {
//         const parser = b.separated_list(b.any(.{ .a = b.literal("a"), .b = b.literal("b") }), b.literal(","));

//         {
//             var parsed = parser.parse("a,b,a", c);
//             try testing.expect(parsed == .value);
//             defer parser.deparseValue(&parsed.value.data, c);
//             try testing.expectEqualStrings(parsed.value.rest, "");
//         }

//         {
//             var parsed = parser.parse("a,b,a,c", c);
//             try testing.expect(parsed == .err);
//             defer parser.deparseErr(&parsed.err, c);
//         }
//     }
// }
