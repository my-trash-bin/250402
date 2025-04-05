const cstring = @cImport(@cInclude("string.h"));
pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", {});
    @cInclude("GLFW/glfw3.h");
});
const std = @import("std");
const builtin = @import("builtin");

pub const App = struct {
    instance: c.VkInstance,
    validation: AppValidation,
    surface: c.VkSurfaceKHR,
    physicalDevice: c.VkPhysicalDevice,
    device: c.VkDevice,
    graphicsQueue: c.VkQueue,
    presentQueue: c.VkQueue,

    pub const CreationError = error{
        OutOfMemory,
        UnsupportedLayer,
        DebugMessengerSetupFailure,
        NoAvailableDevice,
        NoSuitableDevice,
        Call_vkCreateInstance,
        Call_vkEnumerateInstanceLayerProperties,
        Call_vkEnumeratePhysicalDevices,
        Call_vkCreateDevice,
        Call_glfwCreateWindowSurface,
        Call_vkGetPhysicalDeviceSurfaceSupportKHR,
    };

    const is_macos = builtin.target.os.tag == .macos;
    const validation_enabled = builtin.mode == .Debug;
    const validation_layer_name = "VK_LAYER_KHRONOS_validation";

    const AppValidation = if (validation_enabled) struct {
        messenger: c.VkDebugUtilsMessengerEXT,

        pub fn create(allocator: std.mem.Allocator, instance: c.VkInstance) CreationError!AppValidation {
            if (!try supported(allocator)) {
                return CreationError.UnsupportedLayer;
            }
            const createInfo: c.VkDebugUtilsMessengerCreateInfoEXT = .{
                .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
                .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
                .pfnUserCallback = debug_callback,
            };
            const func: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
            if (func == null) {
                return CreationError.DebugMessengerSetupFailure;
            }
            var messenger: c.VkDebugUtilsMessengerEXT = undefined;
            if (func.?(instance, &createInfo, null, &messenger) != c.VK_SUCCESS) {
                return CreationError.DebugMessengerSetupFailure;
            }
            return .{ .messenger = messenger };
        }

        fn supported(allocator: std.mem.Allocator) CreationError!bool {
            var propertyCount: u32 = undefined;
            if (c.vkEnumerateInstanceLayerProperties(&propertyCount, null) != c.VK_SUCCESS) {
                return CreationError.Call_vkEnumerateInstanceLayerProperties;
            }
            const properties = try allocator.alloc(c.VkLayerProperties, propertyCount);
            defer allocator.free(properties);
            if (c.vkEnumerateInstanceLayerProperties(&propertyCount, properties.ptr) != c.VK_SUCCESS) {
                return CreationError.Call_vkEnumerateInstanceLayerProperties;
            }
            for (properties) |property| {
                if (cstring.strcmp(@ptrCast(&property.layerName), validation_layer_name) == 0) {
                    return true;
                }
            }
            return false;
        }

        fn debug_callback(messageSeverity: c.VkDebugUtilsMessageSeverityFlagBitsEXT, messageType: c.VkDebugUtilsMessageTypeFlagsEXT, pCallbackData: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT, pUserData: ?*anyopaque) callconv(.C) c.VkBool32 {
            const Severity = enum { ERROR, WARNING, INFO, VERBOSE, OTHER };
            const severity = if (messageSeverity == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) Severity.ERROR else if (messageSeverity == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) Severity.WARNING else if (messageSeverity == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) Severity.INFO else if (messageSeverity == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT) Severity.VERBOSE else Severity.OTHER;
            const Type = enum { GENERAL, VALIDATION, PERFORMANCE, OTHER };
            const rType = if (messageType == c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT) Type.GENERAL else if (messageType == c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT) Type.VALIDATION else if (messageType == c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT) Type.PERFORMANCE else Type.OTHER;
            std.debug.print("[{s}][{s}] {s}\n", .{ @tagName(severity), @tagName(rType), pCallbackData.*.pMessage });
            _ = pUserData;
            return c.VK_FALSE;
        }

        pub fn destroy(self: AppValidation, instance: c.VkInstance) void {
            const func: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
            if (func != null) {
                func.?(instance, self.messenger, null);
            }
        }
    } else struct {
        pub fn create(allocator: std.mem.Allocator, instance: c.VkInstance) CreationError!AppValidation {
            _ = allocator;
            _ = instance;
            return .{};
        }

        pub fn destroy(self: AppValidation, instance: c.VkInstance) void {
            _ = self;
            _ = instance;
        }
    };

    pub fn create(allocator: std.mem.Allocator, window: ?*c.GLFWwindow) CreationError!App {
        const instance = try createInstance(allocator);
        errdefer c.vkDestroyInstance(instance, null);
        const validation = try AppValidation.create(allocator, instance);
        errdefer validation.destroy(instance);
        const surface = try createSurface(window, instance);
        errdefer c.vkDestroySurfaceKHR(instance, surface, null);
        const physicalDevice = try pickPhysicalDevice(allocator, instance, surface);
        const device = try createLogicalDevice(allocator, physicalDevice);
        var graphicsQueue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, physicalDevice.indices.graphics, 0, &graphicsQueue);
        var presentQueue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, physicalDevice.indices.present, 0, &presentQueue);
        return .{
            .instance = instance,
            .validation = validation,
            .surface = surface,
            .physicalDevice = physicalDevice.device,
            .device = device,
            .graphicsQueue = graphicsQueue,
            .presentQueue = presentQueue,
        };
    }

    fn createInstance(allocator: std.mem.Allocator) CreationError!c.VkInstance {
        const applicationInfo: c.VkApplicationInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "app",
            .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
            .pEngineName = "No Engine",
            .engineVersion = c.VK_MAKE_VERSION(0, 1, 0),
            .apiVersion = c.VK_API_VERSION_1_0,
        };
        var requiredExtensionsCount: u32 = undefined;
        const requiredExtensionNames = c.glfwGetRequiredInstanceExtensions(&requiredExtensionsCount);
        var enabledLayerNames = std.ArrayList([*c]const u8).init(allocator);
        defer enabledLayerNames.deinit();
        var enabledExtensionNames = std.ArrayList([*c]const u8).init(allocator);
        defer enabledExtensionNames.deinit();
        for (0..requiredExtensionsCount) |i| {
            try enabledExtensionNames.append(requiredExtensionNames[i]);
        }
        if (is_macos) {
            try enabledExtensionNames.append(c.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);
            try enabledExtensionNames.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        }
        if (validation_enabled) {
            try enabledLayerNames.append(validation_layer_name);
            try enabledExtensionNames.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        }
        const instanceCreateInfo: c.VkInstanceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .flags = if (is_macos) c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR else 0,
            .pApplicationInfo = &applicationInfo,
            .enabledLayerCount = @intCast(enabledLayerNames.items.len),
            .ppEnabledLayerNames = enabledLayerNames.items.ptr,
            .enabledExtensionCount = @intCast(enabledExtensionNames.items.len),
            .ppEnabledExtensionNames = enabledExtensionNames.items.ptr,
        };
        var instance: c.VkInstance = undefined;
        if (c.vkCreateInstance(&instanceCreateInfo, null, &instance) != c.VK_SUCCESS) {
            return CreationError.Call_vkCreateInstance;
        }
        return instance;
    }

    fn createSurface(window: ?*c.GLFWwindow, instance: c.VkInstance) CreationError!c.VkSurfaceKHR {
        var result: c.VkSurfaceKHR = undefined;
        if (c.glfwCreateWindowSurface(instance, window, null, &result) != c.VK_SUCCESS) {
            return CreationError.Call_glfwCreateWindowSurface;
        }
        return result;
    }

    const QueueFamilyIndices = struct { graphics: u32, present: u32 };
    const PickPhysicalDeviceResult = struct { device: c.VkPhysicalDevice, indices: QueueFamilyIndices };

    fn pickPhysicalDevice(allocator: std.mem.Allocator, instance: c.VkInstance, surface: c.VkSurfaceKHR) CreationError!PickPhysicalDeviceResult {
        var deviceCount: u32 = undefined;
        if (c.vkEnumeratePhysicalDevices(instance, &deviceCount, null) != c.VK_SUCCESS) {
            return CreationError.Call_vkEnumeratePhysicalDevices;
        }
        if (deviceCount == 0) {
            return CreationError.NoAvailableDevice;
        }
        const devices = try allocator.alloc(c.VkPhysicalDevice, deviceCount);
        defer allocator.free(devices);
        if (c.vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr) != c.VK_SUCCESS) {
            return CreationError.Call_vkEnumeratePhysicalDevices;
        }
        for (devices) |device| {
            return .{
                .device = device,
                .indices = (try isSuitable(allocator, device, surface)) orelse continue,
            };
        }
        return CreationError.NoSuitableDevice;
    }

    fn isSuitable(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) CreationError!?QueueFamilyIndices {
        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(device, &properties);
        if (properties.deviceType != c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU and properties.deviceType != c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
            return null;
        }

        // var features: c.VkPhysicalDeviceFeatures = undefined;
        // c.vkGetPhysicalDeviceFeatures(device, &features);
        // if (features.geometryShader != c.VK_TRUE) {
        //     return null;
        // }

        var queueFamilyCount: u32 = undefined;
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
        defer allocator.free(queueFamilies);
        c.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);

        const graphics: u32 = blk: {
            for (queueFamilies, 0..) |queueFamily, i| {
                if (queueFamily.queueFlags & c.VK_QUEUE_GRAPHICS_BIT == c.VK_QUEUE_GRAPHICS_BIT) {
                    break :blk @as(u32, @intCast(i));
                }
            }
            return null;
        };

        const present: u32 = blk: {
            for (queueFamilies, 0..) |_, i| {
                var supported: c.VkBool32 = undefined;
                if (c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface, &supported) != c.VK_SUCCESS) {
                    return CreationError.Call_vkGetPhysicalDeviceSurfaceSupportKHR;
                }
                if (supported == c.VK_TRUE) {
                    break :blk @as(u32, @intCast(i));
                }
            }
            return null;
        };

        return .{ .graphics = graphics, .present = present };
    }

    fn createLogicalDevice(allocator: std.mem.Allocator, physicalDevice: PickPhysicalDeviceResult) CreationError!c.VkDevice {
        var queueCreateInfos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(allocator);
        defer queueCreateInfos.deinit();
        for ([_]u32{ physicalDevice.indices.graphics, physicalDevice.indices.present }) |index| {
            blk: {
                for (queueCreateInfos.items) |queueCreateInfo| {
                    if (queueCreateInfo.queueFamilyIndex == index) {
                        break :blk;
                    }
                }
                try queueCreateInfos.append(.{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                    .queueFamilyIndex = index,
                    .queueCount = 1,
                    .pQueuePriorities = &@as(f32, 1.0),
                });
            }
        }
        const deviceCreateInfo: c.VkDeviceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = @intCast(queueCreateInfos.items.len),
            .pQueueCreateInfos = queueCreateInfos.items.ptr,
            .enabledLayerCount = if (validation_enabled) 1 else 0,
            .ppEnabledLayerNames = if (validation_enabled) &[_][*c]const u8{validation_layer_name} else null,
            .enabledExtensionCount = if (is_macos) 1 else 0,
            .ppEnabledExtensionNames = if (is_macos) &[_][*c]const u8{"VK_KHR_portability_subset"} else null,
            .pEnabledFeatures = &.{},
        };
        var result: c.VkDevice = undefined;
        if (c.vkCreateDevice(physicalDevice.device, &deviceCreateInfo, null, &result) != c.VK_SUCCESS) {
            return CreationError.Call_vkCreateDevice;
        }
        return result;
    }

    pub fn destroy(self: App) void {
        c.vkDestroyDevice(self.device, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        self.validation.destroy(self.instance);
        c.vkDestroyInstance(self.instance, null);
    }
};
