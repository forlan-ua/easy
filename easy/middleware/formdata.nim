import strutils

import .. / easy
import data
export data

type QueryParamsMiddleware* = ref object of Middleware
type FormData* = ref object of HttpDataValues


method onRequest(middleware: QueryParamsMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    if request.headers.getOrDefault("Content-Type").find("application/x-www-form-urlencoded") > -1:
        var params = newHttpDataValues[FormData]()
        var pairs = request.body.replace("+", "%20").split('&')
        for pair in pairs:
            let pairs = pair.split('=')
            let value = if pairs.len > 1: pairs[1].urldecode() else: ""
            params.add(pairs[0], value)
        request.setMiddlewareData(params)