const glfw = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});
const std = @import("std");

fn error_callback(err: c_int, description: [*c]const u8) callconv(.C) void {
    std.debug.print("[{}] {s}", .{ err, description });
}

fn key_callback(window: ?*glfw.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    if (key == glfw.GLFW_KEY_ESCAPE and action == glfw.GLFW_PRESS) {
        glfw.glfwSetWindowShouldClose(window, glfw.GLFW_TRUE);
    }
    _ = scancode;
    _ = mods;
}

pub export fn app_entry() callconv(.C) void {
    _ = glfw.glfwSetErrorCallback(error_callback);

    if (glfw.glfwInit() == 0) {
        std.process.exit(1);
    }
    defer glfw.glfwTerminate();

    const window = glfw.glfwCreateWindow(640, 480, "test", null, null);
    if (window == null) {
        std.process.exit(1);
    }
    defer glfw.glfwDestroyWindow(window);

    _ = glfw.glfwSetKeyCallback(window, key_callback);

    glfw.glfwMakeContextCurrent(window);
    glfw.glfwSwapInterval(1);

    while (glfw.glfwWindowShouldClose(window) == 0) {
        var width: c_int = undefined;
        var height: c_int = undefined;
        glfw.glfwGetFramebufferSize(window, &width, &height);

        glfw.glfwSwapBuffers(window);
        glfw.glfwPollEvents();
    }
}
