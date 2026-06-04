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

pub fn trimWhitespacesStart(input: []const u8) []const u8 {
    return mem.trimStart(u8, input, " \n\r\t");
}

pub fn consumeChars(trimmedInput: []const u8, start: usize, charset: []const u8) ParsedResult([]const u8) {
    const rest = mem.trimStart(u8, trimmedInput[start..], charset);
    return .{ .value = trimmedInput[0 .. trimmedInput.len - rest.len], .rest = rest };
}
