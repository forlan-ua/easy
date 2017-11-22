import httpcore, strutils, mimetypes, os, asyncdispatch, streams
import types

proc new*(T: typedesc[HttpResponse], server: HttpServer): T = 
    T(
        server: server, 
        statusCode: Http200,
        headers: newHttpHeaders(),
        middlewareData: @[], 
        body: "",
        interrupted: false
    )

proc new*(T: typedesc[HttpResponse], response: HttpResponse): T =
    T(
        server: response.server,
        statusCode: response.statusCode,
        headers: response.headers,
        middlewareData: response.middlewareData,
        body: response.body,
        interrupted: response.interrupted
    )

proc body*(res: HttpResponse): string = res.body

proc add*(res: HttpResponse, content: string): HttpResponse {.discardable.} = 
    res.body &= content
    result = res

method send*(res: HttpResponse, content: string): HttpResponse {.base, gcsafe, discardable.} = 
    res.body = content
    result = res

proc code*(res: HttpResponse, httpCode: HttpCode): HttpResponse {.discardable.} =
    res.statusCode = httpCode
    result = res

proc code*(res: HttpResponse): HttpCode = res.statusCode

proc send*(res: HttpResponse, httpCode: HttpCode, content: string): HttpResponse {.discardable.} = 
    res.code(httpCode).send(content)

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