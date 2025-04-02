cmake_minimum_required(VERSION 3.16)
project(DummyApp C)

add_executable(dummy dummy.c)

target_link_directories(dummy PRIVATE ../zig-out/lib)
target_link_libraries(dummy PRIVATE app)

target_link_directories(dummy PRIVATE ../deps/glfw-release/lib)
target_link_libraries(dummy PRIVATE glfw3)

if (WIN32)
    target_link_libraries(dummy PRIVATE user32 gdi32 shell32 ntdll)
endif()
