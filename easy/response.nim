import httpcore, strutils, mimetypes, os, asyncdispatch, streams, asyncnet
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

proc new*(T: typedesc[HttpResponse], response: HttpResponse): T =
    T(
        server: response.server,
        socket: response.socket,
        statusCode: response.statusCode,
        headers: response.headers,
        middlewareData: response.middlewareData,
        body: response.body,
        interrupted: response.interrupted
    )

proc body*(res: HttpResponse): string = res.body

method add*(res: HttpResponse, content: string): HttpResponse {.base, gcsafe, discardable.} = 
    res.body.add(content)
    result = res

method send*(res: HttpResponse, content: string): HttpResponse {.base, gcsafe, discardable.} = 
    res.body = content
    result = res

method code*(res: HttpResponse, httpCode: HttpCode): HttpResponse {.base, gcsafe, discardable.} =
    res.statusCode = httpCode
    result = res
template code*(res: HttpResponse, httpCode: int): HttpResponse = res.code(httpCode.HttpCode)

proc code*(res: HttpResponse): HttpCode = res.statusCode

proc interrupt*(res: HttpResponse) =
    res.interrupted = true

proc header*(res: HttpResponse, header: string, value: string): HttpResponse {.discardable.} =
    res.headers[header] = value
    result = res

proc header*(res: HttpResponse, header: string): string =
    res.headers.getOrDefault(header)

proc headers*(res: HttpResponse, headers: openarray[(string, string)]): HttpResponse {.discardable.} =
    for header in headers:
        res.headers[header[0]] = header[1]
    result = res

proc removeHeaders*(res: HttpResponse, headers: openarray[string]): HttpResponse {.discardable.} =
    for header in headers:
        res.headers.del(header)
    result = res

proc redirect*(res: HttpResponse, url: string, permanent: bool = true) =
    let code = if permanent: Http301 else: Http302
    res.code(code).header("Location", url).interrupt()

proc mimeTypes*(res: HttpResponse): MimeDB = res.server.mimeTypes

proc respond*(res: HttpResponse) {.async.} =
    if res.body == "":
        res.body = $res.code()

    var i = res.server.middlewares.high
    while i > -1:
        await res.server.middlewares[i].onRespond(res)
        i.dec

    let code = res.code().HttpStatusCode

    var msg = "HTTP/1.1 "
    msg.add($code)
    msg.add("\c\L")
    
    if res.headers != nil:
        for k, v in res.headers:
            msg.add(k & ": " & v & "\c\L")

    msg.add("Content-Length: ")
    # this particular way saves allocations:
    msg.add(res.body.len)
    msg.add("\c\L\c\L")
    msg.add(res.body)

    result = res.socket.send(msg)

proc close*(res: HttpResponse) {.async.} =
    await res.respond()
    res.socket.close()