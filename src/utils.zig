const std = @import("std");
const mem = std.mem;

pub fn charRange(comptime start: u8, comptime end: u8) [end - start + 1]u8 {
    comptime {
        if (end < start)
            @compileError("end must be >= start");

        var result: [end - start + 1]u8 = undefined;
        for (0..result.len) |i|
            result[i] = start + i;
        return result;
    }
}

pub const DIGITS = &charRange('0', '9');
pub const IDENT = &charRange('a', 'z') + &charRange('A', 'Z') + "_$" + DIGITS;

pub fn ParsedResult(comptime T: anytype) type {
    return struct { value: T, rest: []const u8 };
}

pub fn split(trimmedInput: []const u8, idx: usize) ParsedResult([]const u8) {
    return .{ .value = trimmedInput[0..idx], .rest = trimmedInput[idx..] };
}

pub fn splitIfExists(trimmedInput: []const u8, idx: ?usize) ?ParsedResult([]const u8) {
    return if (idx) |i| split(trimmedInput, i) else null;
}

pub fn trimWhitespacesStart(input: []const u8) []const u8 {
    return mem.trimStart(u8, input, " \n\r\t");
}

pub fn consumeChars(trimmedInput: []const u8, start: usize, charset: []const u8) usize {
    var begin = start;
    while (begin < charset.len and mem.findScalar(u8, charset, trimmedInput[begin]) != null) : (begin += 1) {}
    return begin;
}

pub fn consumeUnsignedDigits(trimmedInput: []const u8, start: usize) ?usize {
    return if (trimmedInput.len == start) null else switch (trimmedInput[start]) {
        '0' => @as(usize, 1),
        '1'...'9' => consumeChars(trimmedInput, start + 1, DIGITS),
        else => null,
    };
}

pub fn consumeSignedDigits(trimmedInput: []const u8, start: usize) ?usize {
    return if (trimmedInput.len < start + 2)
        if (trimmedInput.len == start + 1) switch (trimmedInput[start]) {
            '0'...'9' => @as(usize, start + 1),
            else => null,
        } else null
    else switch (trimmedInput[start]) {
        '0' => @as(usize, start + 1),
        '1'...'9' => consumeChars(trimmedInput, start + 1, DIGITS),
        '-' => switch (trimmedInput[start + 1]) {
            '0' => @as(usize, start + 2),
            '1'...'9' => consumeChars(trimmedInput, start + 2, DIGITS),
            else => null,
        },
        else => null,
    };
}
