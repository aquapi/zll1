// https://www.json.org/json-en.html
const mem = @import("std").mem;
const zll1 = @import("zll1");

const p = zll1.parser;
const utils = zll1.utils;

// Mark as recursive to avoid type errors while using Ref(Value)
pub const Value = p.Recursive(struct {
    pub fn init() type {
        return p.Union(.{ .nil = p.Const("null"), .true = p.Const("true"), .false = p.Const("false"), .number = Number, .string = String, .object = Object, .array = Array });
    }
});

// JSON compliant number parser
pub const Number = struct {
    pub const Value = []const u8;

    inline fn consumeDigits(trimmedInput: []const u8, start: usize) usize {
        return utils.consumeChars(trimmedInput, start, utils.DIGITS);
    }

    pub fn parse(_: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult([]const u8) {
        if (trimmedInput.len == 0) return null;

        var endInt: usize = undefined;
        switch (trimmedInput[0]) {
            '+', '-' => {
                if (trimmedInput.len == 1)
                    return null;

                // Consume uint
                switch (trimmedInput[1]) {
                    '0' => endInt = 2,
                    '1'...'9' => endInt = consumeDigits(trimmedInput, 1),
                    else => return null,
                }
            },

            // Consume uint
            '0' => endInt = 1,
            '1'...'9' => endInt = consumeDigits(trimmedInput, 1),
            else => return null,
        }

        // Number ends with int
        if (trimmedInput.len == endInt)
            return utils.split(trimmedInput, endInt);

        switch (trimmedInput[endInt]) {
            '.' => {
                // Consume fraction
                const endFrac = consumeDigits(trimmedInput, endInt + 1);
                if (endInt + 1 == endFrac)
                    return null;

                // Number ends with fraction
                if (trimmedInput.len == endFrac)
                    return utils.split(trimmedInput, endFrac);

                switch (trimmedInput[endFrac]) {
                    // Consume exponent
                    'E', 'e' => {
                        const endExp = consumeDigits(trimmedInput, endFrac + 1);
                        return if (endFrac + 1 == endExp)
                            null
                        else
                            utils.split(trimmedInput, endExp);
                    },
                    else => return null,
                }
            },

            // Consume exponent
            'E', 'e' => {
                const endExp = consumeDigits(trimmedInput, endInt + 1);
                return if (endInt + 1 == endExp)
                    null
                else
                    utils.split(trimmedInput, endExp);
            },
            else => return null,
        }
    }

    pub inline fn deparse(_: mem.Allocator, _: []const u8) void {}
};

// JSON compliant string parser
pub const String = struct {
    pub const Value = []const u8;

    pub fn parse(_: mem.Allocator, trimmedInput: []const u8) ?utils.ParsedResult([]const u8) {
        if (trimmedInput.len < 2 or trimmedInput[0] != '"')
            return null;

        var begin: usize = 1;
        while (begin < trimmedInput.len) {
            switch (trimmedInput[begin]) {
                // String end
                '"' => return .{ .value = trimmedInput[1..begin], .rest = trimmedInput[begin + 1 ..] },

                // Escape
                '\\' => {
                    if (begin + 1 == trimmedInput.len) return null;

                    switch (trimmedInput[begin + 1]) {
                        // Known escape character
                        '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => begin += 2,

                        // Hex
                        'u' => {
                            // 2,3,4,5 are hex
                            if (trimmedInput.len < begin + 6) return null;
                            blk: for (2..5) |i| {
                                inline for (utils.HEX) |c|
                                    if (trimmedInput[begin + i] == c)
                                        continue :blk;

                                return null;
                            }
                            begin += 6;
                        },

                        // Invalid escape
                        else => return null
                    }
                },

                // Not allowed characters
                0...31 => return null,

                else => begin += 1,
            }
        }

        return null;
    }

    pub inline fn deparse(_: mem.Allocator, _: []const u8) void {}
};

pub const Object = p.Wrap("{", p.Array(p.Tuple(.{ String, p.Prefix(":", p.Ref(Value)) }), ","), "}");
pub const Array = p.Wrap("[", p.Array(p.Ref(Value), ","), "]");
