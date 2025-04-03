const glfw = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});
const vk = @cImport({
    @cInclude("vulkan/vulkan.h");
});
const std = @import("std");
const builtin = @import("builtin");

pub const App = struct {
    instance: vk.VkInstance,

    pub const CreateError = error{
        OutOfMemory,
        InstanceCreationFailure,
    };

    pub fn create(allocator: std.mem.Allocator) CreateError!App {
        const applicationInfo: vk.VkApplicationInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pNext = null,
            .pApplicationName = "app",
            .applicationVersion = vk.VK_MAKE_VERSION(0, 1, 0),
            .pEngineName = "No Engine",
            .engineVersion = vk.VK_MAKE_VERSION(0, 1, 0),
            .apiVersion = vk.VK_API_VERSION_1_0,
        };
        var requiredExtensionsCount: u32 = undefined;
        const requiredExtensionNames = glfw.glfwGetRequiredInstanceExtensions(&requiredExtensionsCount);
        const is_macos = comptime builtin.target.os.tag == .macos;
        const enabledExtensionsCount = requiredExtensionsCount + comptime (if (is_macos) 2 else 0);
        var enabledExtensionNames = try allocator.alloc([*c]const u8, enabledExtensionsCount);
        defer allocator.free(enabledExtensionNames);
        for (0..requiredExtensionsCount) |i| {
            enabledExtensionNames[i] = requiredExtensionNames[i];
        }
        if (is_macos) {
            enabledExtensionNames[requiredExtensionsCount] = vk.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME;
            enabledExtensionNames[requiredExtensionsCount + 1] = vk.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;
        }
        const instanceCreateInfo: vk.VkInstanceCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = if (is_macos) vk.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR else 0,
            .pApplicationInfo = &applicationInfo,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = enabledExtensionsCount,
            .ppEnabledExtensionNames = enabledExtensionNames.ptr,
        };
        var instance: vk.VkInstance = undefined;
        if (vk.vkCreateInstance(&instanceCreateInfo, null, &instance) != vk.VK_SUCCESS) {
            return CreateError.InstanceCreationFailure;
        }
        return .{ .instance = instance };
    }

    pub fn destroy(self: App) void {
        vk.vkDestroyInstance(self.instance, null);
    }
};
