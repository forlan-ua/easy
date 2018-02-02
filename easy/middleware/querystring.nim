import strutils, asyncdispatch, tables

import .. / .. / easy
import .. / utils

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
                    result.add(k & "=" & i.urlencode() & "&")
    
    for k, v in update:
        for i in v:
            result.add(k & "=" & i.urlencode() & "&")

    result.setLen(result.len - 1)

template toString*(d: QueryStringData, update: openarray[(string, seq[string])]): string =
    d.toString(update.toTable())

proc toString*(d: QueryStringData, update: Table[string, string]): string =
    result = "?"

    if not d.isNil:
        for k, v in d.tbl:
            if k notin update:
                for i in v:
                    result.add(k & "=" & i.urlencode() & "&")
    
    for k, i in update:
        result.add(k & "=" & i.urlencode() & "&")

    result.setLen(result.len - 1)

template toString*(d: QueryStringData, update: openarray[(string, string)]): string =
    d.toString(update.toTable())

proc `$`*(d: QueryStringData): string =
    result = "?"
    if not d.isNil:
        for k, v in d.tbl:
            for i in v:
                result.add(k & "=" & i.urlencode() & "&")

    result.setLen(result.len - 1)


method onRequest*(middleware: QueryStringMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    var params = newHttpDataValues(QueryStringData)
    var pairs = request.url.query.split('&')
    for pair in pairs:
        let pairs = pair.split('=')
        let value = if pairs.len > 1: pairs[1].urldecode() else: ""
        params.add(pairs[0].urldecode(), value)
    request.setMiddlewareData(params)