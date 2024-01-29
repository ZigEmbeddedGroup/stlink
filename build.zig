const std = @import("std");
const Build = std.Build;

const c_flags = &.{};

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
}
