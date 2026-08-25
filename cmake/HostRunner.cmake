include_guard(GLOBAL)

# A launcher prefix arrives as one string -- "arch -x86_64" -- and has to
# reach COMMAND as separate arguments. Under VERBATIM a string with a space
# in it is one argv[0], so the run dies with "no such file or directory"
# naming nothing, after the whole SDK has been built.
function(vitasdk_host_runner_command output runner)
    separate_arguments(parts NATIVE_COMMAND "${runner}")
    set(${output} ${parts} PARENT_SCOPE)
endfunction()
