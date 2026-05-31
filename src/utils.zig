const std = @import("std");

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
