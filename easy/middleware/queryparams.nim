import strutils

import .. / easy
import data
export data

type QueryParamsMiddleware* = ref object of Middleware
type QueryStringData* = ref object of HttpDataValues


method onRequest(middleware: QueryParamsMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    var params = newHttpDataValues[QueryStringData]()
    var pairs = request.url.query.split('&')
    for pair in pairs:
        let pairs = pair.split('=')
        let value = if pairs.len > 1: pairs[1].urldecode() else: ""
        params.add(pairs[0], value)
    request.setMiddlewareData(params)