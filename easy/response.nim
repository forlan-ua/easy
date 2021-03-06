import httpcore, strutils, mimetypes, os, asyncdispatch, streams, asyncnet, asyncfile, logging
import types, middleware

proc new*(T: typedesc[HttpResponse], socket: AsyncSocket, server: HttpServer): T = 
    T(
        server: server,
        socket: socket,
        statusCode: Http200,
        headers: newHttpHeaders(),
        middlewareData: @[], 
        body: "",
        interrupted: false
    )

proc add*(res: HttpResponse, content: string): HttpResponse {.gcsafe, discardable.} = 
    res.body.add(content)
    result = res

proc send*(res: HttpResponse, content: string): HttpResponse {.gcsafe, discardable.} = 
    res.body = content
    result = res

proc code*(res: HttpResponse, httpCode: HttpCode): HttpResponse {.gcsafe, discardable.} =
    res.statusCode = httpCode
    result = res
template code*(res: HttpResponse, httpCode: int): HttpResponse = res.code(httpCode.HttpCode)
template code*(res: HttpResponse): HttpCode = res.statusCode 

proc interrupt*(res: HttpResponse) =
    res.interrupted = true

proc header*(res: HttpResponse, header: string, value: string): HttpResponse {.discardable.} =
    res.headers[header] = value
    result = res

proc header*(res: HttpResponse, header: string): string =
    res.headers.getOrDefault(header)

proc headers*(res: HttpResponse, headers: openarray[tuple[name: string, value: string]]): HttpResponse {.discardable.} =
    for header in headers:
        res.headers[header.name] = header.value
    result = res

proc removeHeaders*(res: HttpResponse, headers: varargs[string]): HttpResponse {.discardable.} =
    for header in headers:
        res.headers.del(header)
    result = res

proc redirect*(res: HttpResponse, url: string, permanent: bool = true) =
    let code = if permanent: Http301 else: Http302
    res.code(code).header("Location", url).interrupt()

template mimeTypes*(res: HttpResponse): MimeDB = res.server.mimeTypes

proc respondHeaders(res: HttpResponse) {.async.} =
    let code = res.code().HttpStatusCode

    var msg = "HTTP/1.1 "
    msg.add($code.int & " " & $code)
    msg.add("\c\L")
    
    if res.headers != nil:
        for k, v in res.headers:
            msg.add(k & ": " & v & "\c\L")
    msg.add("\c\L")

    result = res.socket.send(msg)

proc respond*(res: HttpResponse) {.async.} =
    if res.sent:
        warn "Response has been already responded. Skip."
        return
    res.sent = true

    let code = res.code().HttpStatusCode

    var i = res.server.middlewares.high
    while i > -1:
        await res.server.middlewares[i].onRespond(res)
        i.dec

    if res.body == "" and code.int != 200:
        res.body = $code

    res.header("Content-Length", $res.body.len)

    await res.respondHeaders()
    result = res.socket.send(res.body)

proc close*(res: HttpResponse) {.async.} =
    await res.respond()
    res.socket.close()

proc sendFile*(res: HttpResponse, file: string, cacheControl: string = "public, max-age=31536000") {.async.} =
    if res.sent:
        warn "Response has been already responded. Skip."
        return
    res.sent = true

    if not file.fileExists():
        res.code(404)
        await res.respond()
        return
    
    let mimetype = res.server.mimeTypes.getMimetype(file.splitFile().ext[1 .. ^1], default = "application/octet-stream")

    res.header("Content-Type", mimetype)
    res.header("Cache-Control", cacheControl)
    res.header("Content-Length", $file.getFileSize())

    await res.respondHeaders()

    var fileStream = newFutureStream[string]("sendFile")
    var file = openAsync(file, fmRead)
    
    asyncCheck file.readToStream(fileStream)
    
    while true:
        let (hasValue, value) = await fileStream.read()
        if hasValue:
            await res.socket.send(value)
        else:
            break
    file.close()