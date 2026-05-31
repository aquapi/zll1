const std = @import("std");
const mem = std.mem;

const utils = @import("./utils.zig");

// Trim
fn trimWhitespacesStart(input: []const u8) []const u8 {
    return mem.trimStart(u8, input, " \n\r\t");
}

// Parsed value and type resolution
pub fn Parsed(comptime T: type) type {
    return struct { value: T, rest: []const u8 };
}

// Constant
pub fn Const(comptime prefix: []const u8) type {
    return struct {
        pub const Value = bool;

        pub inline fn parse(_: mem.Allocator, trimmedInput: []const u8) ?Parsed(Value) {
            return if (mem.startsWith(u8, trimmedInput, prefix)) .{ .value = true, .rest = trimmedInput[prefix.len..] } else null;
        }
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
};

// Combinators
pub fn Tuple(comptime Parsers: anytype) type {
  comptime var parser_value_types: [Parsers.len]type = undefined;

  for (Parsers, 0..) |Parser, i|
      parser_value_types[i] = Parser.Value;

  const _Value = @Tuple(&parser_value_types);

  return struct {
      pub const Value = _Value;

      pub inline fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?Parsed(@This().Value) {
          var value: @This().Value = undefined;
          var currentInput = trimmedInput;

          inline for (Parsers, 0..) |Parser, i|
              if (Parser.parse(allocator, currentInput)) |token| {
                  value[i] = token.value;
                  if (comptime i < Parsers.len - 1) {
                      currentInput = trimWhitespacesStart(token.rest);
                  } else return .{ .value = value, .rest = token.rest };
              } else return null;
      }
  };
}

pub fn Union(comptime Parsers: anytype) type {
  const fields = std.meta.fields(@TypeOf(Parsers));

  comptime var names: [fields.len][]const u8 = undefined;
  comptime var parsers: [fields.len]type = undefined;
  comptime var parser_value_types: [fields.len]type = undefined;
  comptime var attrs: [fields.len]std.builtin.Type.UnionField.Attributes = undefined;
  comptime var values: [fields.len]u8 = undefined;

  inline for (fields, 0..) |field, i| {
      names[i] = field.name;
      parsers[i] = @field(Parsers, field.name);
      parser_value_types[i] = parsers[i].Value;
      attrs[i] = .{};
      values[i] = i;
  }

  const _Value = @Union(
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
  const _ScopedParsers = parsers;

  return struct {
      pub const Value = _Value;

      const ScopedParsers = _ScopedParsers;
      pub inline fn parse(allocator: mem.Allocator, trimmedInput: []const u8) ?Parsed(@This().Value) {
          inline for (fields, 0..) |field, i|
              if (ScopedParsers[i].parse(allocator, trimmedInput)) |parsedResult|
                  return .{ .value = @unionInit(@This().Value, field.name, parsedResult.value), .rest = parsedResult.rest };

          return null;
      }
  };
}

pub fn parse(comptime T: anytype, allocator: mem.Allocator, input: []const u8) ?T.Value {
    return if (T.parse(allocator, trimWhitespacesStart(input))) |parsedResult| parsedResult.value else null;
}

const testing = std.testing;

test "Const" {
    const Parser = Const("x");
    try testing.expect(parse(Parser, testing.allocator, "x").?);
}

test "Integers" {
    try testing.expect(mem.eql(u8, parse(UInt, testing.allocator, " 32 ").?, "32"));
    try testing.expect(mem.eql(u8, parse(Int, testing.allocator, " -32 ").?, "-32"));
}

test "Tuple" {
    const Parser = Tuple(.{ Const("x"), Const("y"), Const("z") });

    const value = parse(Parser, testing.allocator, " x y z t").?;
    try testing.expect(value[0]);
    try testing.expect(value[1]);
    try testing.expect(value[2]);
}

test "Union" {
    const Parser = Union(.{ .x = Const("x"), .y = Const("y"), .z = Const("z") });

    const parsed = parse(Parser, testing.allocator, "y t").?;
    try testing.expect(switch (parsed) {
        .y => true,
        else => false,
    });
}

// const Grammar = struct {
//         pub const Root = Union(.{
//             .end = Const(.end, "end"),
//             .next = Tuple(.{
//                 Union(.{ .x = Const(.x, "x"), .y = Const(.y, "y") }),
//                 Ref("Root", @This()), // Reference back to the top
//             }),
//         });
//     };
