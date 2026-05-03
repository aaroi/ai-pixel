import Foundation

// One binary, two modes:
//   - GUI (when launched from Finder / `open`): no user args, hand off to SwiftUI
//   - CLI (when invoked from a shell with file args): run the headless processor
//
// macOS LaunchServices passes `-psn_*` and `-NS*` flags; those don't count as
// user args, so we filter them out before deciding which mode to run.

let rawArgs = Array(CommandLine.arguments.dropFirst())
let userArgs = rawArgs.filter { !$0.hasPrefix("-psn_") && !$0.hasPrefix("-NS") }

if !userArgs.isEmpty {
    let exitCode = CLI.run(args: userArgs)
    exit(Int32(exitCode))
}

AiPixelApp.main()
