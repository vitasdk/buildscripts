#
# Copyright(c) 2016 codestation
# Distributed under the MIT License (http://opensource.org/licenses/MIT)
#

# Executable format identification, used to prove that an SDK ships binaries
# for the host it claims. A staged build assembles one SDK out of two
# machines, so a file that belongs to the producer can reach the consumer's
# tree without anything else noticing: names differ (ld vs ld.exe), so
# nothing overwrites it, and a dependency audit skips what it cannot parse.

include_guard(GLOBAL)

# Decode the leading bytes of an executable, given as an uppercase hex string.
# Sets format to ELF, PE, MachO or the empty string, and machine to the ELF
# e_machine value (decimal) when the header carries one.
function(vitasdk_decode_binary_format hex out_format out_machine)
    set(format "")
    set(machine "")
    string(TOUPPER "${hex}" hex)

    if(hex MATCHES "^7F454C46")
        set(format ELF)
        # e_ident: EI_CLASS is byte 4, EI_DATA (the byte order) is byte 5.
        string(SUBSTRING "${hex}" 10 2 data_encoding)
        string(LENGTH "${hex}" hex_length)
        if(hex_length GREATER_EQUAL 40)
            string(SUBSTRING "${hex}" 36 2 machine_low)
            string(SUBSTRING "${hex}" 38 2 machine_high)
            if(data_encoding STREQUAL "02")
                set(machine_hex "${machine_low}${machine_high}")
            else()
                set(machine_hex "${machine_high}${machine_low}")
            endif()
            math(EXPR machine "0x${machine_hex}")
        endif()
    elseif(hex MATCHES "^4D5A")
        set(format PE)
    elseif(hex MATCHES "^(FEEDFACE|FEEDFACF|CEFAEDFE|CFFAEDFE|CAFEBABE)")
        set(format MachO)
    endif()

    set(${out_format} "${format}" PARENT_SCOPE)
    set(${out_machine} "${machine}" PARENT_SCOPE)
endfunction()

function(vitasdk_binary_format path out_format out_machine)
    file(READ "${path}" header OFFSET 0 LIMIT 20 HEX)
    vitasdk_decode_binary_format("${header}" format machine)
    set(${out_format} "${format}" PARENT_SCOPE)
    set(${out_machine} "${machine}" PARENT_SCOPE)
endfunction()

# The format an SDK for this host and triple must be made of.
function(vitasdk_expected_binary_format system_name host_triple out_format out_machine)
    set(machine "")
    if(system_name STREQUAL "Windows")
        set(format PE)
    elseif(system_name STREQUAL "Darwin")
        set(format MachO)
    else()
        set(format ELF)
        if(host_triple MATCHES "^(x86_64|amd64)")
            set(machine 62)
        elseif(host_triple MATCHES "^i[3-6]86")
            set(machine 3)
        elseif(host_triple MATCHES "^(aarch64|arm64)")
            set(machine 183)
        elseif(host_triple MATCHES "^arm")
            set(machine 40)
        endif()
    endif()
    set(${out_format} "${format}" PARENT_SCOPE)
    set(${out_machine} "${machine}" PARENT_SCOPE)
endfunction()

# Fail if any executable directly inside directory belongs to another host.
# Files in no executable format at all (scripts, data, target archives) are
# not this check's business and are left alone.
function(vitasdk_check_binary_directory directory system_name host_triple)
    if(NOT IS_DIRECTORY "${directory}")
        return()
    endif()
    vitasdk_expected_binary_format("${system_name}" "${host_triple}"
        expected_format expected_machine)

    file(GLOB entries "${directory}/*")
    foreach(entry IN LISTS entries)
        if(IS_DIRECTORY "${entry}")
            continue()
        endif()
        vitasdk_binary_format("${entry}" format machine)
        if(format STREQUAL "")
            continue()
        endif()
        if(NOT format STREQUAL expected_format)
            message(FATAL_ERROR
                "${entry} is a ${format} binary in a ${expected_format} SDK "
                "for ${host_triple}")
        endif()
        if(NOT expected_machine STREQUAL "" AND NOT machine STREQUAL ""
                AND NOT machine EQUAL expected_machine)
            message(FATAL_ERROR
                "${entry} is built for ELF machine ${machine}, but this SDK "
                "targets ${host_triple} (machine ${expected_machine})")
        endif()
    endforeach()
endfunction()
