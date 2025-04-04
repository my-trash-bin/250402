const cstring = @cImport(@cInclude("string.h"));
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
    validation: AppValidation,
    physicalDevice: vk.VkPhysicalDevice,
    queueFamilyIndexGraphics: u32,
    device: vk.VkDevice,
    graphicsQueue: vk.VkQueue,

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
        Etc,
    };

    const is_macos = builtin.target.os.tag == .macos;
    const validation_enabled = builtin.mode == .Debug;
    const validation_layer_name = "VK_LAYER_KHRONOS_validation";

    const AppValidation = if (validation_enabled) struct {
        messenger: vk.VkDebugUtilsMessengerEXT,

        pub fn create(allocator: std.mem.Allocator, instance: vk.VkInstance) CreationError!AppValidation {
            if (!try supported(allocator)) {
                return CreationError.UnsupportedLayer;
            }
            const createInfo: vk.VkDebugUtilsMessengerCreateInfoEXT = .{
                .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                .pNext = null,
                .flags = 0,
                .messageSeverity = vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
                .messageType = vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
                .pfnUserCallback = debug_callback,
                .pUserData = null,
            };
            const func: vk.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(vk.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
            if (func == null) {
                return CreationError.DebugMessengerSetupFailure;
            }
            var messenger: vk.VkDebugUtilsMessengerEXT = undefined;
            if (func.?(instance, &createInfo, null, &messenger) != vk.VK_SUCCESS) {
                return CreationError.DebugMessengerSetupFailure;
            }
            return .{ .messenger = messenger };
        }

        fn supported(allocator: std.mem.Allocator) CreationError!bool {
            var propertyCount: u32 = undefined;
            if (vk.vkEnumerateInstanceLayerProperties(&propertyCount, null) != vk.VK_SUCCESS) {
                return CreationError.Call_vkEnumerateInstanceLayerProperties;
            }
            const properties = try allocator.alloc(vk.VkLayerProperties, propertyCount);
            defer allocator.free(properties);
            if (vk.vkEnumerateInstanceLayerProperties(&propertyCount, properties.ptr) != vk.VK_SUCCESS) {
                return CreationError.Call_vkEnumerateInstanceLayerProperties;
            }
            for (properties) |property| {
                if (cstring.strcmp(@ptrCast(&property.layerName), validation_layer_name) == 0) {
                    return true;
                }
            }
            return false;
        }

        fn debug_callback(messageSeverity: vk.VkDebugUtilsMessageSeverityFlagBitsEXT, messageType: vk.VkDebugUtilsMessageTypeFlagsEXT, pCallbackData: [*c]const vk.VkDebugUtilsMessengerCallbackDataEXT, pUserData: ?*anyopaque) callconv(.C) vk.VkBool32 {
            const Severity = enum { ERROR, WARNING, INFO, VERBOSE, OTHER };
            const severity = if (messageSeverity == vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) Severity.ERROR else if (messageSeverity == vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) Severity.WARNING else if (messageSeverity == vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) Severity.INFO else if (messageSeverity == vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT) Severity.VERBOSE else Severity.OTHER;
            const Type = enum { GENERAL, VALIDATION, PERFORMANCE, OTHER };
            const rType = if (messageType == vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT) Type.GENERAL else if (messageType == vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT) Type.VALIDATION else if (messageType == vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT) Type.PERFORMANCE else Type.OTHER;
            std.debug.print("[{s}][{s}] {s}\n", .{ @tagName(severity), @tagName(rType), pCallbackData.*.pMessage });
            _ = pUserData;
            return vk.VK_FALSE;
        }

        pub fn destroy(self: AppValidation, instance: vk.VkInstance) void {
            const func: vk.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(vk.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
            if (func != null) {
                func.?(instance, self.messenger, null);
            }
        }
    } else struct {
        pub fn create(allocator: std.mem.Allocator, instance: vk.VkInstance) CreationError!AppValidation {
            _ = allocator;
            _ = instance;
            return .{};
        }

        pub fn destroy(self: AppValidation, instance: vk.VkInstance) void {
            _ = self;
            _ = instance;
        }
    };

    pub fn create(allocator: std.mem.Allocator) CreationError!App {
        const instance = try createInstance(allocator);
        errdefer vk.vkDestroyInstance(instance, null);
        const validation = try AppValidation.create(allocator, instance);
        errdefer validation.destroy(instance);
        const physicalDevice = try pickPhysicalDevice(allocator, instance);
        const queueFamilyIndexGraphics = (try findQueueFamilies(allocator, physicalDevice)) orelse return CreationError.Etc;
        const device = try createLogicalDevice(physicalDevice, queueFamilyIndexGraphics);
        var graphicsQueue: vk.VkQueue = undefined;
        vk.vkGetDeviceQueue(device, queueFamilyIndexGraphics, 0, &graphicsQueue);
        return .{
            .instance = instance,
            .validation = validation,
            .physicalDevice = physicalDevice,
            .queueFamilyIndexGraphics = queueFamilyIndexGraphics,
            .device = device,
            .graphicsQueue = graphicsQueue,
        };
    }

    fn createInstance(allocator: std.mem.Allocator) CreationError!vk.VkInstance {
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
        var enabledLayerNames = std.ArrayList([*c]const u8).init(allocator);
        defer enabledLayerNames.deinit();
        var enabledExtensionNames = std.ArrayList([*c]const u8).init(allocator);
        defer enabledExtensionNames.deinit();
        for (0..requiredExtensionsCount) |i| {
            try enabledExtensionNames.append(requiredExtensionNames[i]);
        }
        if (is_macos) {
            try enabledExtensionNames.append(vk.VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME);
            try enabledExtensionNames.append(vk.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        }
        if (validation_enabled) {
            try enabledLayerNames.append(validation_layer_name);
            try enabledExtensionNames.append(vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        }
        const instanceCreateInfo: vk.VkInstanceCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = if (is_macos) vk.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR else 0,
            .pApplicationInfo = &applicationInfo,
            .enabledLayerCount = @intCast(enabledLayerNames.items.len),
            .ppEnabledLayerNames = enabledLayerNames.items.ptr,
            .enabledExtensionCount = @intCast(enabledExtensionNames.items.len),
            .ppEnabledExtensionNames = enabledExtensionNames.items.ptr,
        };
        var instance: vk.VkInstance = undefined;
        if (vk.vkCreateInstance(&instanceCreateInfo, null, &instance) != vk.VK_SUCCESS) {
            return CreationError.Call_vkCreateInstance;
        }
        return instance;
    }

    fn pickPhysicalDevice(allocator: std.mem.Allocator, instance: vk.VkInstance) CreationError!vk.VkPhysicalDevice {
        var deviceCount: u32 = undefined;
        if (vk.vkEnumeratePhysicalDevices(instance, &deviceCount, null) != vk.VK_SUCCESS) {
            return CreationError.Call_vkEnumeratePhysicalDevices;
        }
        if (deviceCount == 0) {
            return CreationError.NoAvailableDevice;
        }
        const devices = try allocator.alloc(vk.VkPhysicalDevice, deviceCount);
        defer allocator.free(devices);
        if (vk.vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr) != vk.VK_SUCCESS) {
            return CreationError.Call_vkEnumeratePhysicalDevices;
        }
        for (devices) |device| {
            if (try isSuitable(allocator, device)) {
                return device;
            }
        }
        return CreationError.NoSuitableDevice;
    }

    fn isSuitable(allocator: std.mem.Allocator, device: vk.VkPhysicalDevice) CreationError!bool {
        var properties: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(device, &properties);
        if (properties.deviceType != vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU and properties.deviceType != vk.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
            return false;
        }

        // var features: vk.VkPhysicalDeviceFeatures = undefined;
        // vk.vkGetPhysicalDeviceFeatures(device, &features);
        // if (features.geometryShader != vk.VK_TRUE) {
        //     return false;
        // }

        if (try findQueueFamilies(allocator, device) == null) {
            return false;
        }

        return true;
    }

    fn findQueueFamilies(allocator: std.mem.Allocator, device: vk.VkPhysicalDevice) CreationError!?u32 {
        var queueFamilyCount: u32 = undefined;
        vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, null);
        const queueFamilies = try allocator.alloc(vk.VkQueueFamilyProperties, queueFamilyCount);
        defer allocator.free(queueFamilies);
        vk.vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, queueFamilies.ptr);
        for (queueFamilies, 0..) |queueFamily, i| {
            if (queueFamily.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT == vk.VK_QUEUE_GRAPHICS_BIT) {
                return @intCast(i);
            }
        }
        return null;
    }

    fn createLogicalDevice(physicalDevice: vk.VkPhysicalDevice, queueFamilyIndexGraphics: u32) CreationError!vk.VkDevice {
        const queueCreateInfo: vk.VkDeviceQueueCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = queueFamilyIndexGraphics,
            .queueCount = 1,
            .pQueuePriorities = &@as(f32, 1.0),
        };
        const deviceFeatures: vk.VkPhysicalDeviceFeatures = .{};
        const deviceCreateInfo: vk.VkDeviceCreateInfo = .{
            .sType = vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queueCreateInfo,
            .enabledLayerCount = if (validation_enabled) 1 else 0,
            .ppEnabledLayerNames = if (validation_enabled) &[_][*c]const u8{validation_layer_name} else null,
            .enabledExtensionCount = if (is_macos) 1 else 0,
            .ppEnabledExtensionNames = if (is_macos) &[_][*c]const u8{"VK_KHR_portability_subset"} else null,
            .pEnabledFeatures = &deviceFeatures,
        };
        var result: vk.VkDevice = undefined;
        if (vk.vkCreateDevice(physicalDevice, &deviceCreateInfo, null, &result) != vk.VK_SUCCESS) {
            return CreationError.Call_vkCreateDevice;
        }
        return result;
    }

    pub fn destroy(self: App) void {
        vk.vkDestroyDevice(self.device, null);
        self.validation.destroy(self.instance);
        vk.vkDestroyInstance(self.instance, null);
    }
};
