import asyncstreams, httpcore, uri, streams, mimetypes, asyncdispatch, asyncnet, times, os, strutils, random
import types, middleware, response
export HttpRequest

proc new*(T: typedesc[HttpRequest], httpMethod: HttpMethod, socket: AsyncSocket, server: HttpServer, bodyChunkSize: uint16 = 1_000): T = 
    T(
        httpMethod: httpMethod,
        server: server,
        socket: socket,
        url: initUri(),
        bodyChunkSize: bodyChunkSize,
        headers: newHttpHeaders(),
        middlewareData: @[],
        bodyMaxSize: server.bodyMaxSize
    )

proc clone*(request: HttpRequest): HttpRequest = 
    result = request.type(
        httpMethod: request.httpMethod,
        server: request.server,
        socket: request.socket,
        url: request.url,
        headers: request.headers,
        middlewareData: request.middlewareData,
        protocol: request.protocol
    )
    case request.httpMethod:
        of HttpPost, HttpPut, HttpPatch:
            result.body = request.body
            result.contentLength = request.contentLength
            result.bodyChunkSize = request.bodyChunkSize
            result.bodyMaxSize = request.bodyMaxSize
            result.bodyFile = request.bodyFile
        else:
            discard

proc url*(req: HttpRequest): Uri = req.url
proc httpMethod*(req: HttpRequest): HttpMethod = req.httpMethod
proc headers*(req: HttpRequest): HttpHeaders = req.headers
proc protocol*(req: HttpRequest): tuple[orig: string, major, minor: int] = req.protocol
proc hostname*(req: HttpRequest): string = req.hostname
    
proc body*(req: HttpRequest): string = req.body
proc bodyStream*(req: HttpRequest): Stream = req.bodyStream
proc bodyStreamFile*(req: HttpRequest): string = req.bodyStreamFile
proc contentLength*(req: HttpRequest): int = req.contentLength

proc mimeTypes*(req: HttpRequest): MimeDB = req.server.mimeTypes

method readBody*(request: HttpRequest, response: HttpResponse) {.base, async, gcsafe.} =
    let socket = request.socket
    let chunkSize = request.bodyChunkSize.int

    if request.contentLength < chunkSize:
        let body = await socket.recv(request.contentLength)
        if body.len != request.contentLength:
            response.code(Http400).send("Bad Request. Content-Length does not match actual.").interrupt()
        else:
            request.body = body
    else:
        var filepath: string = ""
        var stream: Stream
        while true:
            filepath = os.getTempDir() / "requests." & (epochTime() * 1000).int.toHex() & "." & random(1000000).toHex()
            try:
                stream = newFileStream(filepath)
                break
            except:
                continue
        var length = 0
        while true:
            let recvSize = request.contentLength - length
            let d = await socket.recv(min(chunkSize, recvSize))
            length += d.len
            stream.write(d)

            if length == request.contentLength:
                break
            elif d.len < recvSize:
                response.code(Http400).send("Bad Request. Content-Length does not match actual.").interrupt()
                break
        stream.close()
        request.bodyFile = filepath