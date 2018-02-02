import os, nake, ospaths

createDir("build")
copyFile("data.sqlite", "build/data.sqlite")

let args = @[
    "--out:build/app",
    "app.nim"
]

task "compile", "Compile and example app":
    var curArgs = @[nimExe, "c"]
    curArgs.add(args)
    direShell curArgs

task "default", "Compile and run example server on 5050 port":
    var curArgs = @[nimExe, "c", "--run", "-d:dbfile=build/data.sqlite"]
    curArgs.add(args)
    direShell curArgs