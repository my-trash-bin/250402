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
    swapChain: c.VkSwapchainKHR,
    swapChainImages: []c.VkImage,
    swapChainImageFormat: c.VkFormat,
    swapChainExtent: c.VkExtent2D,
    swapChainImageViews: []c.VkImageView,
    graphicsQueue: c.VkQueue,
    presentQueue: c.VkQueue,
    allocator: std.mem.Allocator,

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
        Call_vkEnumerateDeviceExtensionProperties,
        Call_vkGetPhysicalDeviceSurfaceCapabilitiesKHR,
        Call_vkGetPhysicalDeviceSurfaceFormatsKHR,
        Call_vkGetPhysicalDeviceSurfacePresentModesKHR,
        Call_vkCreateSwapchainKHR,
        Call_vkGetSwapchainImagesKHR,
        Call_vkCreateImageView,
    };

    const is_macos = builtin.target.os.tag == .macos;
    const validation_enabled = builtin.mode == .Debug;
    const validation_layer_name = "VK_LAYER_KHRONOS_validation";
    const required_extensions = [_][*c]const u8{
        c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    };

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
        errdefer c.vkDestroyDevice(device, null);
        const swapChainSupportDetails = try SwapChainSupportDetails.create(allocator, physicalDevice.device, surface);
        defer swapChainSupportDetails.destroy();
        const swapChain = try createSwapChain(allocator, window, device, surface, &swapChainSupportDetails, physicalDevice.indices);
        errdefer c.vkDestroySwapchainKHR(device, swapChain.swapChain, null);
        errdefer allocator.free(swapChain.swapChainImages);
        const swapChainImageViews = try createSwapChainImageViews(allocator, device, &swapChain);
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
            .swapChain = swapChain.swapChain,
            .swapChainImages = swapChain.swapChainImages,
            .swapChainImageFormat = swapChain.swapChainImageFormat,
            .swapChainExtent = swapChain.swapChainExtent,
            .swapChainImageViews = swapChainImageViews,
            .graphicsQueue = graphicsQueue,
            .presentQueue = presentQueue,
            .allocator = allocator,
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
    const CreateSwapChainResult = struct { swapChain: c.VkSwapchainKHR, swapChainImages: []c.VkImage, swapChainImageFormat: c.VkFormat, swapChainExtent: c.VkExtent2D };
    const SwapChainSupportDetails = struct {
        allocator: std.mem.Allocator,
        capabilities: c.VkSurfaceCapabilitiesKHR,
        formats: []c.VkSurfaceFormatKHR,
        presentModes: []c.VkPresentModeKHR,

        fn create(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) CreationError!SwapChainSupportDetails {
            var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
            if (c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &capabilities) != c.VK_SUCCESS) {
                return CreationError.Call_vkGetPhysicalDeviceSurfaceCapabilitiesKHR;
            }

            var formatCount: u32 = undefined;
            if (c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, null) != c.VK_SUCCESS) {
                return CreationError.Call_vkGetPhysicalDeviceSurfaceFormatsKHR;
            }
            const formats = try allocator.alloc(c.VkSurfaceFormatKHR, formatCount);
            errdefer allocator.free(formats);
            if (c.vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formatCount, formats.ptr) != c.VK_SUCCESS) {
                return CreationError.Call_vkGetPhysicalDeviceSurfaceFormatsKHR;
            }

            var presentModeCount: u32 = undefined;
            if (c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, null) != c.VK_SUCCESS) {
                return CreationError.Call_vkGetPhysicalDeviceSurfacePresentModesKHR;
            }
            const presentModes = try allocator.alloc(c.VkPresentModeKHR, presentModeCount);
            errdefer allocator.free(presentModes);
            if (c.vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, &presentModeCount, presentModes.ptr) != c.VK_SUCCESS) {
                return CreationError.Call_vkGetPhysicalDeviceSurfacePresentModesKHR;
            }

            return .{ .allocator = allocator, .capabilities = capabilities, .formats = formats, .presentModes = presentModes };
        }

        fn destroy(self: SwapChainSupportDetails) void {
            self.allocator.free(self.formats);
            self.allocator.free(self.presentModes);
        }
    };

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
                .indices = (try isPhysicalDeviceSuitable(allocator, device, surface)) orelse continue,
            };
        }
        return CreationError.NoSuitableDevice;
    }

    fn isPhysicalDeviceSuitable(allocator: std.mem.Allocator, device: c.VkPhysicalDevice, surface: c.VkSurfaceKHR) CreationError!?QueueFamilyIndices {
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

        if (!try checkPhysicalDeviceExtensionSupport(allocator, device)) {
            return null;
        }

        const swapChainSupportDetails = try SwapChainSupportDetails.create(allocator, device, surface);
        defer swapChainSupportDetails.destroy();

        if (swapChainSupportDetails.formats.len == 0 or swapChainSupportDetails.presentModes.len == 0) {
            return null;
        }

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

    fn checkPhysicalDeviceExtensionSupport(allocator: std.mem.Allocator, device: c.VkPhysicalDevice) CreationError!bool {
        var propertyCount: u32 = undefined;
        if (c.vkEnumerateDeviceExtensionProperties(device, null, &propertyCount, null) != c.VK_SUCCESS) {
            return CreationError.Call_vkEnumerateDeviceExtensionProperties;
        }
        const properties = try allocator.alloc(c.VkExtensionProperties, propertyCount);
        defer allocator.free(properties);
        if (c.vkEnumerateDeviceExtensionProperties(device, null, &propertyCount, properties.ptr) != c.VK_SUCCESS) {
            return CreationError.Call_vkEnumerateDeviceExtensionProperties;
        }

        for (required_extensions) |required_extension| {
            blk: {
                for (properties) |property| {
                    if (cstring.strcmp(@ptrCast(&property.extensionName), required_extension) == 0) {
                        break :blk;
                    }
                }
                return false;
            }
        }
        return true;
    }

    fn chooseSwapSurfaceFormat(availableFormats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
        for (availableFormats) |availableFormat| {
            if (availableFormat.format == c.VK_FORMAT_B8G8R8A8_SRGB and availableFormat.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return availableFormat;
            }
        }

        return availableFormats[0];
    }

    fn chooseSwapPresentMode(availablePresentModes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
        for (availablePresentModes) |availablePresentMode| {
            if (availablePresentMode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
                return availablePresentMode;
            }
        }

        return c.VK_PRESENT_MODE_FIFO_KHR;
    }

    fn chooseSwapExtent(window: ?*c.GLFWwindow, capabilities: *const c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
        if (capabilities.currentExtent.width != 4294967295) {
            return capabilities.currentExtent;
        } else {
            var width: c_int = undefined;
            var height: c_int = undefined;
            c.glfwGetFramebufferSize(window, &width, &height);
            return .{
                .width = @min(capabilities.maxImageExtent.width, @max(capabilities.minImageExtent.width, @as(u32, @intCast(width)))),
                .height = @min(capabilities.maxImageExtent.height, @max(capabilities.minImageExtent.height, @as(u32, @intCast(height)))),
            };
        }
    }

    fn createSwapChain(allocator: std.mem.Allocator, window: ?*c.GLFWwindow, device: c.VkDevice, surface: c.VkSurfaceKHR, swapChainSupportDetails: *const SwapChainSupportDetails, indices: QueueFamilyIndices) CreationError!CreateSwapChainResult {
        const surfaceFormat = chooseSwapSurfaceFormat(swapChainSupportDetails.formats);
        const presentMode = chooseSwapPresentMode(swapChainSupportDetails.presentModes);
        const extent = chooseSwapExtent(window, &swapChainSupportDetails.capabilities);
        const imageCount = if (swapChainSupportDetails.capabilities.maxImageCount > 0 and swapChainSupportDetails.capabilities.minImageCount + 1 > swapChainSupportDetails.capabilities.maxImageCount) swapChainSupportDetails.capabilities.maxImageCount else swapChainSupportDetails.capabilities.minImageCount;

        const createInfo: c.VkSwapchainCreateInfoKHR = .{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = imageCount,
            .imageFormat = surfaceFormat.format,
            .imageColorSpace = surfaceFormat.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = if (indices.graphics != indices.present) c.VK_SHARING_MODE_CONCURRENT else c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = if (indices.graphics != indices.present) 2 else 0,
            .pQueueFamilyIndices = if (indices.graphics != indices.present) &[_]u32{ indices.graphics, indices.present } else null,
            .preTransform = swapChainSupportDetails.capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = presentMode,
            .clipped = c.VK_TRUE,
            .oldSwapchain = @ptrCast(c.VK_NULL_HANDLE),
        };
        var swapChain: c.VkSwapchainKHR = undefined;
        if (c.vkCreateSwapchainKHR(device, &createInfo, null, &swapChain) != c.VK_SUCCESS) {
            return CreationError.Call_vkCreateSwapchainKHR;
        }
        errdefer c.vkDestroySwapchainKHR(device, swapChain, null);

        var swapChainImageCount: u32 = undefined;
        if (c.vkGetSwapchainImagesKHR(device, swapChain, &swapChainImageCount, null) != c.VK_SUCCESS) {
            return CreationError.Call_vkGetSwapchainImagesKHR;
        }
        const swapChainImages = try allocator.alloc(c.VkImage, swapChainImageCount);
        errdefer allocator.free(swapChainImages);
        if (c.vkGetSwapchainImagesKHR(device, swapChain, &swapChainImageCount, swapChainImages.ptr) != c.VK_SUCCESS) {
            return CreationError.Call_vkGetSwapchainImagesKHR;
        }

        return .{
            .swapChain = swapChain,
            .swapChainImages = swapChainImages,
            .swapChainImageFormat = surfaceFormat.format,
            .swapChainExtent = extent,
        };
    }

    fn createSwapChainImageViews(allocator: std.mem.Allocator, device: c.VkDevice, swapChain: *const CreateSwapChainResult) CreationError![]c.VkImageView {
        var initializedCount: usize = 0;
        const result = try allocator.alloc(c.VkImageView, swapChain.swapChainImages.len);
        errdefer {
            for (0..initializedCount) |i| {
                c.vkDestroyImageView(device, result[i], null);
            }
            allocator.free(result);
        }
        for (swapChain.swapChainImages) |image| {
            const createInfo: c.VkImageViewCreateInfo = .{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = swapChain.swapChainImageFormat,
                .components = .{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = .{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            if (c.vkCreateImageView(device, &createInfo, null, &result[initializedCount]) != c.VK_SUCCESS) {
                return CreationError.Call_vkCreateImageView;
            }
            initializedCount += 1;
        }
        return result;
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
        var enabledExtensionNames = std.ArrayList([*]const u8).init(allocator);
        defer enabledExtensionNames.deinit();
        for (required_extensions) |required_extension| {
            try enabledExtensionNames.append(required_extension);
        }
        if (is_macos) {
            try enabledExtensionNames.append("VK_KHR_portability_subset");
        }
        const deviceCreateInfo: c.VkDeviceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = @intCast(queueCreateInfos.items.len),
            .pQueueCreateInfos = queueCreateInfos.items.ptr,
            .enabledLayerCount = if (validation_enabled) 1 else 0,
            .ppEnabledLayerNames = if (validation_enabled) &[_][*c]const u8{validation_layer_name} else null,
            .enabledExtensionCount = @intCast(enabledExtensionNames.items.len),
            .ppEnabledExtensionNames = enabledExtensionNames.items.ptr,
            .pEnabledFeatures = &.{},
        };
        var result: c.VkDevice = undefined;
        if (c.vkCreateDevice(physicalDevice.device, &deviceCreateInfo, null, &result) != c.VK_SUCCESS) {
            return CreationError.Call_vkCreateDevice;
        }
        return result;
    }

    pub fn destroy(self: App) void {
        for (self.swapChainImageViews) |view| {
            c.vkDestroyImageView(self.device, view, null);
        }
        self.allocator.free(self.swapChainImageViews);
        self.allocator.free(self.swapChainImages);
        c.vkDestroySwapchainKHR(self.device, self.swapChain, null);
        c.vkDestroyDevice(self.device, null);
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        self.validation.destroy(self.instance);
        c.vkDestroyInstance(self.instance, null);
    }
};
