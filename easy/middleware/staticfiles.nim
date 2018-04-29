import strutils, sequtils, asyncdispatch, os, httpcore, tables, times, mimetypes
import libsha / sha1

import .. / .. / easy


type StaticFilesMiddleware* = ref object of Middleware
    timeout: int
    staticRoutes: seq[string]
    staticDirs: seq[string]


proc new*(T: typedesc[StaticFilesMiddleware], staticRoute: string, staticDirs: openarray[string], timeout: int = 3600): Middleware =
    StaticFilesMiddleware(staticRoutes: @[staticRoute], staticDirs: staticDirs.map(proc(s: string): string = s.strip(chars={'/'}, leading=false)), timeout: timeout)


proc new*(T: typedesc[StaticFilesMiddleware], staticRoutes: openarray[string], staticDirs: openarray[string], timeout: int = 3600): Middleware =
    StaticFilesMiddleware(staticRoutes: @staticRoutes, staticDirs: staticDirs.map(proc(s: string): string = s.strip(chars={'/'}, leading=false)), timeout: timeout)


var staticRegistry {.threadvar.}: TableRef[string, (string, int)]
method sendFileImpl*(middleware: StaticFilesMiddleware, request: HttpRequest, response: HttpResponse, filename: string) {.gcsafe, async, base.} =
    let oldsha = $request.headers.getOrDefault("If-None-Match")
    let mimetype = response.server.mimeTypes.getMimetype(filename.splitFile().ext[1 .. ^1], default = "application/octet-stream")
    let cacheControl = "public, max-age=" & $middleware.timeout

    if staticRegistry.isNil:
        staticRegistry = newTable[string, (string, int)]()

    let stored = staticRegistry.getOrDefault(filename)
    let now = epochTime().int
    if oldsha == stored[0] and now - stored[1] < middleware.timeout:
        response.header("Content-Type", mimetype)
        response.header("Cache-Control", cacheControl)
        response.header("ETag", oldsha)
        response.code(304)
        return

    if getFileSize(filename) > 8_000_000:
        let info = getFileInfo(filename)
        let sha = sha1hexdigest($info.lastAccessTime & $info.lastWriteTime & $info.creationTime & $info.size)
        staticRegistry[filename] = (sha, now)
        response.header("ETag", sha)
        if sha == oldsha:
            response.header("Content-Type", mimetype)
            response.header("Cache-Control", cacheControl)
            response.code(304)
            return

        await response.sendFile(filename, cacheControl)
        return

    let content = readFile(filename)
    let sha = sha1hexdigest(content)
    staticRegistry[filename] = (sha, now)
    response.header("Content-Type", mimetype)
    response.header("Cache-Control", cacheControl)
    response.header("ETag", sha)

    if sha == oldsha:
        response.code(304)
        return
    
    response.send(content)
    await response.respond()


method clearCache*(middleware: StaticFilesMiddleware) {.base.} =
    staticRegistry.clear()


method onInit*(middleware: StaticFilesMiddleware, request: HttpRequest, response: HttpResponse): Future[(HttpRequest, HttpResponse)] {.async, gcsafe.} = 
    let path = request.url.path
    
    if request.httpMethod == HttpGet:
        block findfile:
            for route in middleware.staticRoutes:
                if path.startsWith(route):
                    response.interrupt()

                    for dir in middleware.staticDirs:
                        let fn = dir & path.substr(route.len)

                        if fileExists(fn):
                            await middleware.sendFileImpl(request, response, fn)
                            break findfile

                    response.code(404)

    result = (request, response)