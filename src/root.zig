const App = @import("app.zig");
const std = @import("std");

fn error_callback(err: c_int, description: [*c]const u8) callconv(.C) void {
    std.debug.print("[{}] {s}\n", .{ err, description });
}

fn key_callback(window: ?*App.c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    if (key == App.c.GLFW_KEY_ESCAPE and action == App.c.GLFW_PRESS) {
        App.c.glfwSetWindowShouldClose(window, App.c.GLFW_TRUE);
    }
    _ = scancode;
    _ = mods;
}

pub export fn app_entry() callconv(.C) void {
    actual_entry() catch |err| std.debug.print("ERROR: {}\n", .{err});
}

fn actual_entry() anyerror!void {
    _ = App.c.glfwSetErrorCallback(error_callback);

    if (App.c.glfwInit() == 0) {
        std.process.exit(1);
    }
    defer App.c.glfwTerminate();

    if (App.c.glfwVulkanSupported() != App.c.GLFW_TRUE) {
        return anyerror.VulkanNotSupported;
    }

    App.c.glfwWindowHint(App.c.GLFW_CLIENT_API, App.c.GLFW_NO_API);

    const window = App.c.glfwCreateWindow(640, 480, "test", null, null);
    if (window == null) {
        std.process.exit(1);
    }
    defer App.c.glfwDestroyWindow(window);

    _ = App.c.glfwSetKeyCallback(window, key_callback);

    const allocator = std.heap.page_allocator;
    var app = try App.create(allocator, window);
    defer app.destroy();

    while (App.c.glfwWindowShouldClose(window) == 0) {
        var width: c_int = undefined;
        var height: c_int = undefined;
        App.c.glfwGetFramebufferSize(window, &width, &height);

        // App.c.glfwSwapBuffers(window);
        App.c.glfwPollEvents();
        try app.render();
    }
}
