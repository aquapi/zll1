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
pub const HEX = &charRange('a', 'z') ++ &charRange('A', 'Z') ++ DIGITS;
pub const IDENT = HEX ++ "_$";

/// startsWith with fast paths for small cases
pub fn startsWith(trimmedInput: []const u8, comptime prefix: []const u8) bool {
    const prefixLen = prefix.len;

    if (trimmedInput.len < prefixLen) return false;

    if (comptime prefixLen > 16)
        return @call(.always_inline, mem.eql, .{ u8, trimmedInput[0..prefixLen], prefix });

    if (comptime prefixLen >= 4) {
        var x: u32 = 0;
        inline for ([_]usize{ 0, prefixLen - 4, (prefixLen / 8) * 4, prefixLen - 4 - ((prefixLen / 8) * 4) }) |n| {
            x |= @as(u32, @bitCast(prefix[n..][0..4].*)) ^ @as(u32, @bitCast(trimmedInput[n..][0..4].*));
        }
        return x == 0;
    }

    if (comptime prefixLen == 1)
        return prefix[0] == trimmedInput[0];

    const x = (prefix[0] ^ trimmedInput[0]) | (prefix[prefixLen - 1] ^ trimmedInput[prefixLen - 1]) | (prefix[prefixLen / 2] ^ trimmedInput[prefixLen / 2]);
    return x == 0;
}

pub inline fn findPos(haystack: []const u8, start: usize, comptime needle: []const u8) ?usize {
    return @call(.always_inline, mem.findPos, .{ u8, haystack, start, needle });
}

pub inline fn trimWhitespacesStart(input: []const u8) []const u8 {
    return input[consumeChars(input, 0, " \n\r\t")..];
}

pub fn consumeChars(trimmedInput: []const u8, start: usize, comptime charset: []const u8) usize {
    var begin = start;
    blk: while (begin < trimmedInput.len) {
        inline for (charset) |c|
            if (trimmedInput[begin] == c) {
                begin += 1;
                continue :blk;
            };

        break;
    }
    return begin;
}
