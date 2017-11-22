import os, nake, ospaths

task "default", "Compile and run example server on 5050 port":
    createDir("build")
    direShell nimExe, "c", "--run", "--out:build/app", "app.nim"