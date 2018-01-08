import asyncdispatch, net, asyncnet, httpcore, strutils, parseutils, streams, os, times, random

import .. / .. / easy
import .. / utils
import data, formdata
export data, formdata

type MultipartFormDataMiddleware* = ref object of Middleware
    uploadDir: string


proc new*(T: typedesc[MultipartFormDataMiddleware], uploadDir: string = ""): T =
    T(uploadDir: uploadDir)


type FilesFormData* = ref object of HttpDataValues[tuple[filename: string, body: string, hash: string]]


type MultipartHttpRequest = ref object of HttpRequest
    data: FormData
    curData: tuple[name: string, filename: string]
    pos: int
    bytesRead: int
    boundary: string
    uploadDir: string


proc ensureLength(request: MultipartHttpRequest, len: int) {.async.} =
    if request.contentLength < request.pos + len:
        raise newException(ValueError, "ERROR!")

    elif request.body.len - request.pos < len:
        let bytes = min(request.contentLength - request.bytesRead, BufferSize)
        request.body = request.body[request.pos ..< request.body.len]
        request.body.add(await request.socket.recv(bytes))
        request.pos = 0
        request.bytesRead += bytes


proc getRange(request: MultipartHttpRequest, len: int): string =
    request.body[request.pos ..< request.pos + len]


proc readHeaders(request: MultipartHttpRequest) {.async.} =
    request.curData.name.setLen(0)
    request.curData.filename.setLen(0)

    while true:
        await request.ensureLength(20)
        if cmpIgnoreCase(request.getRange(20), "Content-Disposition:") == 0:
            request.pos += 20

            var header = ""
            await request.ensureLength(2)
            while request.getRange(2) != "\c\L":
                header.add(request.body[request.pos])
                request.pos.inc
                await request.ensureLength(2)
            request.pos += 2

            var i = 0
            let l = header.len
            while i < l:
                if header[i] == 'n':
                    if header[i ..< i+5] == "name=":
                        i += 6
                        var j = i
                        var needReplace = false
                        while j < l:
                            if header[j] == ';':
                                j.inc
                                break
                            if not needReplace and header[j] == '"' and header[j - 1] == '\\':
                                needReplace = true
                            j.inc

                        if needReplace:
                            request.curData.name.add(header[i .. j-2].replace("\\\"", "\""))
                        else:
                            request.curData.name.add(header[i .. j-2])
                        i = j
                elif header[i] == 'f':
                    if header[i ..< i+9] == "filename=":
                        i += 10
                        var j = i
                        var needReplace = false
                        while j < l:
                            if header[j] == ';':
                                j.inc
                                break
                            if not needReplace and header[j] == '"' and header[j - 1] == '\\':
                                needReplace = true
                            j.inc

                        if needReplace:
                            request.curData.filename.add(header[i .. j-2])
                        else:
                            request.curData.filename.add(header[i .. j-2].replace("\\\"", "\""))
                        i = j
                i.inc
        elif request.getRange(2) == "\c\L":
            request.pos += 2
            return
        else:
            await request.ensureLength(2)
            while request.getRange(2) != "\c\L":
                request.pos.inc
                await request.ensureLength(2)
            request.pos += 2


proc readStrValue(request: MultipartHttpRequest, data: FormData) {.async.} =
    let len = request.boundary.len
    await request.ensureLength(len)

    var val = ""

    while true:
        if request.getRange(len) == request.boundary:
            request.pos += len
            break
        val.add(request.body[request.pos])
        request.pos.inc
        await request.ensureLength(len)
        
    data.add(request.curData.name, val)


proc readFileValue(request: MultipartHttpRequest, data: FilesFormData) {.async.} =
    let len = request.boundary.len
    await request.ensureLength(len)

    var val = (request.curData.filename, "", "")
    var stream: FileStream
    
    if request.uploadDir.len > 0:
        var path = request.uploadDir
        let rnd = (epochTime() * 1000000).int.toHex(13) & rand(0xfffffff).toHex(7)
        path.add(rnd[0 .. 3])

        for i in 0 ..< 8:
            path.add(DirSep)
            path.add(rnd[i * 2 + 4 ..< (i + 1) * 2 + 4])
        
        createDir(path)

        path.add(DirSep)
        path.add(rnd)
        path.add("_")
        path.add(urlencode(request.curData.filename))

        stream = newFileStream(path, fmWrite, 1024)

        if not stream.isNil:
            val[1].add(path)

    while true:
        if request.getRange(len) == request.boundary:
            request.pos += len
            break

        if stream.isNil:
            val[1].add(request.body[request.pos])
        else:
            stream.write(request.body[request.pos])

        request.pos.inc
        await request.ensureLength(len)
        
    if not stream.isNil:
        stream.close()
    data.add(request.curData.name, val)


proc parseMultipart(request: MultipartHttpRequest, boundary: string) {.async.} =
    request.curData = ("", "")
    let data = newHttpDataValues(FormData)
    request.setMiddlewareData(data)
    let filesData = newHttpDataValues(FilesFormData)
    request.setMiddlewareData(filesData)
    
    await request.ensureLength(boundary.len)
    while request.getRange(boundary.len) != boundary:
        request.pos.inc
        await request.ensureLength(boundary.len)
    
    request.pos += boundary.len
    request.boundary = "\c\L" & boundary

    await request.ensureLength(2)
    while request.getRange(2) == "\c\L":
        request.pos += 2
        await request.readHeaders()
        if request.curData.filename.len > 0:
            await request.readFileValue(filesData)
        else:
            await request.readStrValue(data)

    if request.getRange(2) == "--":
        return
    else:
        raise newException(ValueError, "ERROR!")


method readBody*(request: MultipartHttpRequest, response: HttpResponse) {.async, gcsafe.} =
    let header = $request.headers.getOrDefault("Content-Type")
    var start, ends: int
    let len = header.len
    block boundary:
        template findBoundary(st: int) =
            for i in st ..< len - 9:
                if header[i ..< i+9] == "boundary=":
                    start = i + 9
                    ends = start + 1
                    while ends < len:
                        if header[ends] == ';':
                            break boundary
                        ends.inc
                    break
        
        findBoundary(21)
        if start == 0:
            findBoundary(0)
    
    await request.parseMultipart("--" & header[start ..< ends])


method onInit*(middleware: MultipartFormDataMiddleware, request: HttpRequest, response: HttpResponse): Future[(HttpRequest, HttpResponse)] {.gcsafe, async.} =
    if request.headers.getOrDefault("Content-Type").find("multipart/form-data") > -1:
        let req = MultipartHttpRequest.clone(request)
        req.uploadDir = middleware.uploadDir
        result = (req, response)
    else:
        result = (request, response)