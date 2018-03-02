import strutils, asyncdispatch, tables, cgi, parseutils

import .. / .. / easy

import data
export data

type QueryStringMiddleware* = ref object of Middleware
type QueryStringData* = ref object of HttpDataValues[string]


proc toString*(d: QueryStringData, update: Table[string, seq[string]]): string =
    result = "?"

    if not d.isNil:
        for k, v in d.tbl:
            if k notin update:
                for i in v:
                    result.add(k.encodeUrl() & "=" & i.encodeUrl() & "&")
    
    for k, v in update:
        for i in v:
            result.add(k.encodeUrl() & "=" & i.encodeUrl() & "&")

    result.setLen(result.len - 1)

template toString*(d: QueryStringData, update: openarray[(string, seq[string])]): string =
    d.toString(update.toTable())

proc toString*(d: QueryStringData, update: Table[string, string]): string =
    result = "?"

    if not d.isNil:
        for k, v in d.tbl:
            if k notin update:
                for i in v:
                    result.add(k.encodeUrl() & "=" & i.encodeUrl() & "&")
    
    for k, i in update:
        result.add(k.encodeUrl() & "=" & i.encodeUrl() & "&")

    result.setLen(result.len - 1)

template toString*(d: QueryStringData, update: openarray[(string, string)]): string =
    d.toString(update.toTable())

proc `$`*(d: QueryStringData): string =
    result = "?"
    if not d.isNil:
        for k, v in d.tbl:
            for i in v:
                result.add(k.encodeUrl() & "=" & i.encodeUrl() & "&")

    result.setLen(result.len - 1)


method onRequest*(middleware: QueryStringMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    var params = newHttpDataValues(QueryStringData)
    var key, value: string
    var ind = 0
    let query = request.url.query
    while ind < query.len:
        ind += query.parseUntil(key, '=', ind)
        ind += query.parseUntil(value, '&', ind + 1) + 1
        params.add(key.decodeUrl(), value.decodeUrl())
    request.setMiddlewareData(params)