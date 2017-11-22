import asyncdispatch
import types

proc new*(T: typedesc[Middleware]): Middleware = T().Middleware
proc new*(T: typedesc[MiddlewareData]): MiddlewareData = T()

method onInit*(middleware: Middleware, request: HttpRequest, response: HttpResponse): Future[(HttpRequest, HttpResponse)] {.base, async, gcsafe.} = result = (request, response)
method onRequest*(middleware: Middleware, request: HttpRequest, response: HttpResponse) {.base, async, gcsafe.} = discard
method onResponse*(middleware: Middleware, request: HttpRequest, response: HttpResponse) {.base, async, gcsafe.} = discard
method onInterrupt*(middleware: Middleware, request: HttpRequest, response: HttpResponse) {.base, async, gcsafe.} = discard

proc getMiddlewareData*(r: HttpRequest | HttpResponse, T: typedesc[MiddlewareData]): T =
    for d in r.middlewareData:
        if d of T:
            result = cast[T](d)
            break

proc setMiddlewareData*[T](r: HttpRequest | HttpResponse, data: T) =
    var index = -1
    for i, d in r.middlewareData:
        if d of T:
            index = i
            return
    if index > -1:
        r.middlewareData[index] = data
    else:
        r.middlewareData.add(data)
    