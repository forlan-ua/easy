import asyncdispatch
import types

proc new*(T: typedesc[Middleware]): Middleware = T().Middleware
proc new*(T: typedesc[MiddlewareData]): MiddlewareData = T()

method onInit*(middleware: Middleware, request: HttpRequest, response: HttpResponse): Future[(HttpRequest, HttpResponse)] {.base, async, gcsafe.} = result = (request, response)
method onRequest*(middleware: Middleware, request: HttpRequest, response: HttpResponse) {.base, async, gcsafe.} = discard
method onResponse*(middleware: Middleware, request: HttpRequest, response: HttpResponse) {.base, async, gcsafe.} = discard
method onRespond*(middleware: Middleware, response: HttpResponse) {.base, async, gcsafe.} = discard


proc getMiddlewareData*[T](t: T, D: typedesc[MiddlewareData]): D =
    for d in t.middlewareData:
        if d of D:
            result = cast[D](d)
            break

proc setMiddlewareData*[T, D](t: T, data: D) =
    var index = -1
    for i, d in t.middlewareData:
        if d of D:
            index = i
            break
    if index > -1:
        t.middlewareData[index] = data
    else:
        t.middlewareData.add(data)