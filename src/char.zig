pub fn range(comptime start: u8, comptime end: u8) [end - start + 1]u8 {
    comptime {
        if (end < start)
            @compileError("end must be >= start");
    }
    var result: [end - start + 1]u8 = undefined;
    inline for (0..result.len) |i|
        result[i] = start + i;
    return result;
}
