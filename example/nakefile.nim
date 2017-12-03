import os, nake, ospaths

task "compile", "Compile and example app":
    createDir("build")
    direShell nimExe, "c", "-d:release", "--out:build/app", "app.nim"

task "default", "Compile and run example server on 5050 port":
    createDir("build")
    direShell nimExe, "c", "--run", "-d:release", "--out:build/app", "app.nim"