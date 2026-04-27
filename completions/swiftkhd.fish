# A function which filters options which starts with "-" from $argv.
function _swift_swiftkhd_preprocessor
    set -l results
    for i in (seq (count $argv))
        switch (echo $argv[$i] | string sub -l 1)
            case '-'
            case '*'
                echo $argv[$i]
        end
    end
end

function _swift_swiftkhd_using_command
    set -l currentCommands (_swift_swiftkhd_preprocessor (commandline -opc))
    set -l expectedCommands (string split " " $argv[1])
    set -l subcommands (string split " " $argv[2])
    if [ (count $currentCommands) -ge (count $expectedCommands) ]
        for i in (seq (count $expectedCommands))
            if [ $currentCommands[$i] != $expectedCommands[$i] ]
                return 1
            end
        end
        if [ (count $currentCommands) -eq (count $expectedCommands) ]
            return 0
        end
        if [ (count $subcommands) -gt 1 ]
            for i in (seq (count $subcommands))
                if [ $currentCommands[(math (count $expectedCommands) + 1)] = $subcommands[$i] ]
                    return 1
                end
            end
        end
        return 0
    end
    return 1
end

complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -s c -l config -d 'Specify config file path'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -s V -l verbose -d 'Enable verbose logging'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -l no-hotload -s h -d 'Disable config hot reload'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -s o -l observe -d 'Observe mode: print raw keyboard events'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -s P -l profile -d 'Enable profiling/tracing'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -s k -l key -d 'Synthesize a keypress (e.g. \'cmd - a\')'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -s t -l text -d 'Synthesize text input'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -l install-service -d 'Install launchd service'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -l uninstall-service -d 'Uninstall launchd service'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -l start-service -d 'Start launchd service'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -l stop-service -d 'Stop launchd service'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -l restart-service -d 'Restart launchd service'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -l status -d 'Show service status'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -s r -l reload -d 'Reload config in running instance'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -l version -d 'Show the version.'
complete -c swiftkhd -n '_swift_swiftkhd_using_command "swiftkhd"' -s h -l help -d 'Show help information.'
