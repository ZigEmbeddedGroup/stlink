const std = @import("std");
const Build = std.Build;
const LazyPath = Build.LazyPath;

const c_flags = &.{};

pub fn init(b: *Build, dependency_name: []const u8) *STLink {
    const st = b.allocator.create(STLink) catch @panic("OOM");
    st.* = STLink{
        .b = b,
        .self = b.dependency(dependency_name, .{ .optimize = .ReleaseSafe }),
    };
    return st;
}

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libusb_dep = b.dependency("libusb", .{
        .target = target,
        .optimize = optimize,
    });

    const libusb = libusb_dep.artifact("usb");

    const version = b.addConfigHeader(.{
        .style = .{
            .cmake = .{ .path = "inc/version.h.in" },
        },
    }, .{
        .PROJECT_VERSION = "1.7.0",
        .PROJECT_VERSION_MAJOR = 1,
        .PROJECT_VERSION_MINOR = 7,
        .PROJECT_VERSION_PATCH = 0,
    });

    const stlink = b.addStaticLibrary(.{
        .name = "stlink",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    stlink.addCSourceFiles(&.{
        "src/common.c",
        "src/stlink-lib/chipid.c",
        "src/stlink-lib/flash_loader.c",
        "src/stlink-lib/logging.c",
        "src/stlink-lib/md5.c",
        "src/stlink-lib/sg.c",
        "src/stlink-lib/usb.c",
        "src/stlink-lib/helper.c",
    }, c_flags);
    switch (target.getOsTag()) {
        .macos => {
            stlink.defineCMacro("STLINK_HAVE_SYS_TIME_H", null);
            stlink.defineCMacro("STLINK_HAVE_SYS_MMAN_H", null);
            stlink.linkFramework("CoreFoundation");
            stlink.linkFramework("IOKit");
        },
        .windows => {
            stlink.defineCMacro("STLINK_HAVE_SYS_TIME_H", null);
            stlink.addCSourceFiles(&.{
                "src/win32/win32_socket.c",
                "src/win32/mmap.c",
            }, c_flags);
            stlink.addIncludePath(.{ .path = "src/win32" });
            stlink.linkSystemLibrary("wsock32");
            stlink.linkSystemLibrary("ws2_32");
        },
        .linux => {
            stlink.defineCMacro("STLINK_HAVE_SYS_TIME_H", null);
            stlink.defineCMacro("STLINK_HAVE_SYS_MMAN_H", null);
        },
        else => {},
    }
    stlink.addIncludePath(.{ .path = "inc" });
    stlink.addIncludePath(.{ .path = "src/stlink-lib" });
    stlink.addConfigHeader(version);
    stlink.linkLibrary(libusb);
    b.installArtifact(stlink);

    const st_flash = b.addExecutable(.{
        .name = "st-flash",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    st_flash.addCSourceFiles(&.{
        "src/st-flash/flash.c",
        "src/st-flash/flash_opts.c",
    }, c_flags);
    st_flash.addIncludePath(.{ .path = "inc" });
    st_flash.addIncludePath(.{ .path = "src/stlink-lib" });
    st_flash.addConfigHeader(version);
    st_flash.linkLibrary(stlink);
    st_flash.linkLibrary(libusb);
    b.installArtifact(st_flash);

    const st_info = b.addExecutable(.{
        .name = "st-info",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    st_info.addCSourceFiles(&.{
        "src/st-info/info.c",
    }, c_flags);
    st_info.addIncludePath(.{ .path = "inc" });
    st_info.addIncludePath(.{ .path = "src/stlink-lib" });
    st_info.addConfigHeader(version);
    st_info.linkLibrary(stlink);
    st_info.linkLibrary(libusb);
    b.installArtifact(st_info);

    const st_util = b.addExecutable(.{
        .name = "st-util",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    st_util.addCSourceFiles(&.{
        "src/st-util/gdb-remote.c",
        "src/st-util/gdb-server.c",
        "src/st-util/semihosting.c",
    }, c_flags);

    if (target.getOsTag() == .windows)
        st_util.addIncludePath(.{ .path = "src/win32" });

    st_util.addIncludePath(.{ .path = "inc" });
    st_util.addIncludePath(.{ .path = "src/stlink-lib" });
    st_util.addConfigHeader(version);
    st_util.linkLibrary(stlink);
    st_util.linkLibrary(libusb);
    b.installArtifact(st_util);

    const st_trace = b.addExecutable(.{
        .name = "st-trace",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    st_trace.addCSourceFiles(&.{
        "src/st-trace/trace.c",
    }, c_flags);
    st_trace.addIncludePath(.{ .path = "inc" });
    st_trace.addIncludePath(.{ .path = "src/stlink-lib" });
    st_trace.addConfigHeader(version);
    st_trace.linkLibrary(stlink);
    st_trace.linkLibrary(libusb);
    b.installArtifact(st_trace);
}

pub const STLink = struct {
    b: *Build,
    self: *Build.Dependency,

    pub const Format = enum {
        binary,
        ihex,
    };

    pub const Area = enum {
        main,
        system,
        otp,
        optcr,
        optcr1,
        option,
        option_boot_add,
    };

    pub const FlashOptions = union(enum) {
        read: ReadWriteOptions,
        write: ReadWriteOptions,
        erase: struct {
            debug: bool = false,
            connect_under_reset: bool = false,
            hot_plug: bool = false,
            /// in KHz
            freq: ?u32 = null,
            serial: ?u32 = null,
        },
        reset: struct {
            debug: bool = false,
            /// in KHz
            freq: ?u32 = null,
            serial: ?u32 = null,
        },

        pub const ReadWriteOptions = struct {
            debug: bool = false,
            reset: bool = false,
            connect_under_reset: bool = false,
            hot_plug: bool = false,
            opt: bool = false,
            serial: ?u32 = null,
            format: Format = .binary,
            flash: ?u32 = null,
            /// in KHz
            freq: ?u32 = null,
            area: Area = .main,
            path: *Build.CompileStep,
            addr: u32,
            size: u32,
        };
    };

    fn add_read_write_opts(b: *Build, run: *Build.RunStep, opts: FlashOptions.ReadWriteOptions, cmd: []const u8) void {
        if (opts.debug) run.addArg("--debug");
        if (opts.reset) run.addArg("--reset");
        if (opts.connect_under_reset) run.addArg("--connect-under-reset");
        if (opts.hot_plug) run.addArg("--hot-plug");
        if (opts.opt) run.addArg("--opt");
        if (opts.serial) |s| run.addArg(b.fmt("--serial=0x{x}", .{s}));
        run.addArg(b.fmt("--format={s}", .{switch (opts.format) {
            .binary => "binary",
            .ihex => "ihex",
        }}));
        if (opts.flash) |f| run.addArg(b.fmt("--flash=0x{x}", .{f}));
        if (opts.freq) |f| run.addArg(b.fmt("--freq={x}", .{f}));
        run.addArg(b.fmt("--area={s}", .{switch (opts.area) {
            .main => "main",
            .system => "system",
            .otp => "otp",
            .optcr => "optcr",
            .optcr1 => "optcr1",
            .option => "option",
            .option_boot_add => "option_boot_add",
        }}));

        run.addArg(cmd);

        const raw_elf = opts.path.getEmittedBin();
        const objcopy = b.addObjCopy(raw_elf, .{
            .basename = opts.path.name,
            .format = switch (opts.format) {
                .binary => .bin,
                .ihex => .hex,
            },
        });
        run.addFileArg(objcopy.getOutput());

        run.addArg(b.fmt("0x{x}", .{opts.addr}));
        run.addArg(b.fmt("0x{x}", .{opts.size}));
    }

    pub fn flash(stlink: *STLink, opts: FlashOptions) *Build.RunStep {
        const b = stlink.b;
        const st_flash = stlink.self.artifact("st-flash");
        const run = stlink.b.addRunArtifact(st_flash);

        switch (opts) {
            .read => |o| add_read_write_opts(b, run, o, "read"),
            .write => |o| add_read_write_opts(b, run, o, "write"),
            .erase => |o| {
                if (o.debug) run.addArg("--debug");
                if (o.connect_under_reset) run.addArg("--connect-under-reset");
                if (o.hot_plug) run.addArg("--hot-plug");
                if (o.freq) |f| run.addArg(b.fmt("--freq={}", .{f}));
                if (o.serial) |s| run.addArg(b.fmt("--serial=0x{x}", .{s}));
                run.addArg("erase");
            },
            .reset => |o| {
                if (o.debug) run.addArg("--debug");
                if (o.freq) |f| run.addArg(b.fmt("--freq={}", .{f}));
                if (o.serial) |s| run.addArg(b.fmt("--serial=0x{x}", .{s}));
                run.addArg("reset");
            },
        }

        return run;
    }

    pub const InfoOptions = struct {};

    pub fn info(stlink: *STLink, opts: InfoOptions) *Build.RunStep {
        _ = stlink;
        _ = opts;
        @panic("TODO: st-info arguments");
    }

    pub const UtilOptions = struct {};

    pub fn util(stlink: *STLink, opts: UtilOptions) *Build.RunStep {
        _ = stlink;
        _ = opts;
        @panic("TODO: st-util arguments");
    }

    pub const TraceOptions = struct {};

    pub fn trace(stlink: *STLink, opts: TraceOptions) *Build.RunStep {
        _ = stlink;
        _ = opts;
        @panic("TODO: st-trace arguments");
    }
};
