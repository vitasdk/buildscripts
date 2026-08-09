# Apply a sequence of patches without fuzz or silent success.
# PATCH_SERIES entries use the form absolute-path|strip-level and may be
# separated with either CMake list separators or carets when transported as
# one ExternalProject command-line argument.

if(NOT DEFINED SOURCE_DIR)
    message(FATAL_ERROR "SOURCE_DIR is required")
endif()

if(NOT DEFINED PATCH_SERIES OR PATCH_SERIES STREQUAL "")
    message(FATAL_ERROR "PATCH_SERIES is required")
endif()

find_program(PATCH_EXECUTABLE patch)
if(NOT PATCH_EXECUTABLE)
    message(FATAL_ERROR "The patch executable is required")
endif()

string(REPLACE "^" ";" PATCH_SERIES "${PATCH_SERIES}")

foreach(entry IN LISTS PATCH_SERIES)
    string(REPLACE "|" ";" fields "${entry}")
    list(LENGTH fields field_count)
    if(NOT field_count EQUAL 2)
        message(FATAL_ERROR "Invalid patch entry: ${entry}")
    endif()

    list(GET fields 0 patch_file)
    list(GET fields 1 strip_level)

    if(NOT EXISTS "${patch_file}")
        message(FATAL_ERROR "Patch does not exist: ${patch_file}")
    endif()

    message(STATUS "Applying ${patch_file} (-p${strip_level}, fuzz=0)")
    execute_process(
        COMMAND "${PATCH_EXECUTABLE}"
            --directory "${SOURCE_DIR}"
            "--strip=${strip_level}"
            --fuzz=0
            --forward
            --no-backup-if-mismatch
            --input "${patch_file}"
        RESULT_VARIABLE result
        OUTPUT_VARIABLE stdout
        ERROR_VARIABLE stderr
    )

    if(NOT result EQUAL 0)
        message(FATAL_ERROR
            "Failed to apply ${patch_file}\n"
            "stdout:\n${stdout}\n"
            "stderr:\n${stderr}")
    endif()
endforeach()
