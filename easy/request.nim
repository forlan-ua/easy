import asyncstreams, httpcore, uri, streams, mimetypes, asyncdispatch, asyncnet, times, os, strutils, random
import types, middleware, response
export HttpRequest

proc new*(T: typedesc[HttpRequest], httpMethod: HttpMethod, socket: AsyncSocket, server: HttpServer, bodyMaxSize: int = 0): T = 
    T(
        httpMethod: httpMethod,
        server: server,
        socket: socket,
        url: initUri(),
        headers: newHttpHeaders(),
        middlewareData: @[],
        bodyMaxSize: if bodyMaxSize > 0: bodyMaxSize else: server.bodyMaxSize
    )

proc clone*(T: typedesc[HttpRequest], cloner: HttpRequest): T = 
    result = T(
        httpMethod: cloner.httpMethod,
        server: cloner.server,
        socket: cloner.socket,
        url: cloner.url,
        headers: cloner.headers,
        middlewareData: cloner.middlewareData,
        protocol: cloner.protocol,
        body: cloner.body,
        contentLength: cloner.contentLength,
        bodyMaxSize: cloner.bodyMaxSize,
    )

template mimeTypes*(req: HttpRequest): MimeDB = req.server.mimeTypes

method readBody*(request: HttpRequest, response: HttpResponse) {.base, async, gcsafe.} =
    let body = await request.socket.recv(request.contentLength)
    if body.len != request.contentLength:
        response.code(Http400).send("Bad Request. Content-Length does not match actual.").interrupt()
    else:
        request.body = body