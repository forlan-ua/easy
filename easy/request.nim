import asyncstreams, uri, streams, mimetypes, asyncdispatch, asyncnet, times, os, strutils, random
import types, myasynchttpserver, middleware, response
export HttpRequest

proc patch*(request: HttpRequest, server: HttpServer, bodyChunkSize: uint32 = 1_000) = 
    request.server =  server
    request.middlewareData = @[]
    request.bodyChunkSize = bodyChunkSize

proc clone*(request: HttpRequest): HttpRequest = 
    request.type(
        client: request.client,
        httpMethod: request.httpMethod,
        headers: request.headers,
        protocol: request.protocol,
        url: request.url,
        hostname: request.hostname,
        server: request.server,
        body: request.body,
        middlewareData: request.middlewareData,
        contentLength: request.contentLength,
        bodyChunkSize: request.bodyChunkSize,
        bodyStream: request.bodyStream,
        bodyStreamFile: request.bodyStreamFile
    )

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

method bodyReader*(request: HttpRequest, response: HttpResponse) {.base, async, gcsafe.} =
    let client = request.client
    let chunkSize = request.bodyChunkSize.int

    if request.contentLength < chunkSize:
        let body = await client.recv(request.contentLength)
        if body.len != request.contentLength:
            response.send(Http400, "Bad Request. Content-Length does not match actual.").interrupt()
        else:
            request.body = body
        request.bodyStreamFile = ""
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
            let d = await client.recv(min(chunkSize, recvSize))
            length += d.len
            stream.write(d)

            if length == request.contentLength:
                break
            elif d.len < recvSize:
                response.send(Http400, "Bad Request. Content-Length does not match actual.").interrupt()
                break
        stream.close()
        request.bodyStream = newFileStream(filepath)
        request.bodyStreamFile = filepath

    
proc closeRequest*(request: HttpRequest, httpCode: HttpCode, content: string, headers: HttpHeaders) {.gcsafe, async.} =
    if request.bodyStreamFile != "":
        request.bodyStream.close()
        var i = 0
        while i < 10:
            if tryRemoveFile(request.bodyStreamFile):
                break
            else:
                i.inc

    await request.respond(httpCode, content, headers)