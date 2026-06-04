# zll1
LL(1) parser generator for Zig. A port of ParseBox.
```sh
git fetch https://github.com/aquapi/zll1
```

Add in `build.zig.zon`:
```zig
.dependencies = .{
    .zll1 = .{
        .path = "zll1", // or the path you saved zuws to
    },
},
```

And import it in `build.zig`:
```zig
const zuws = b.dependency("zll1", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zll1", zuws.module("zll1"));
```

See [./examples](./examples) for usages.
