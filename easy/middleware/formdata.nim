import strutils, httpcore, asyncdispatch, cgi, parseutils

import .. / .. / easy
import data
export data

type FormDataMiddleware* = ref object of Middleware
type FormData* = ref object of HttpDataValues[string]


method onRequest*(middleware: FormDataMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    if request.headers.getOrDefault("Content-Type").find("application/x-www-form-urlencoded") > -1:
        var params = newHttpDataValues(FormData)
        var key, value: string
        var ind = 0
        while ind < request.body.len:
            ind += request.body.parseUntil(key, '=', ind)
            ind += request.body.parseUntil(value, '&', ind + 1) + 1
            params.add(key.decodeUrl(), value.decodeUrl())
        request.setMiddlewareData(params)