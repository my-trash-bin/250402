const glad = @cImport({
    @cDefine("GLAD_GL_IMPLEMENTATION", {});
    @cInclude("glad/gl.h");
});
const glfw = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});
const std = @import("std");

fn error_callback(err: c_int, description: [*c]const u8) callconv(.C) void {
    std.debug.print("[{}] {s}", .{ err, description });
}

pub export fn app_entry() callconv(.C) void {
    _ = glfw.glfwSetErrorCallback(error_callback);
}
