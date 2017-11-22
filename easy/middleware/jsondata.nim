import json, strutils, streams
export json

import .. / easy

type JsonMiddleware* = ref object of Middleware
type JsonData* = ref object of MiddlewareData
    pairs*: JsonNode

proc send*(response: HttpResponse, pairs: JsonNode): HttpResponse {.discardable.} =
    var data = response.getMiddlewareData(JsonData)
    if not data.isNil:
        data.pairs = pairs

method onRequest(middleware: JsonMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    if request.url.path.endsWith(".json") or request.headers.getOrDefault("Content-Type").find("application/json") > -1:
        var data: JsonNode
        case request.httpMethod:
            of HttpPost, HttpPatch, HttpPut:
                if request.contentLength > 0:
                    try:
                        if request.bodyStreamFile != "":
                            data = parseFile(request.bodyStreamFile)
                        else:
                            data = parseJson(request.body)
                    except:
                        response.send(Http400, "Json parse error").interrupt()
                else:
                    data = newJObject()
            else:
                data = newJObject()

        request.setMiddlewareData(JsonData(pairs: data))
        response.setMiddlewareData(JsonData(pairs: newJObject()))

method onResponse(middleware: JsonMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    var data = response.getMiddlewareData(JsonData)
    if not data.isNil:
        response.send($data.pairs)

method onInterrupt(middleware: JsonMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    var data = response.getMiddlewareData(JsonData)
    if not data.isNil and response.body.len > 0:
        if response.code.int >= Http400.int:
            data.pairs = %*{"error": {"message": response.body, "code": response.statusCode.int, "type": "HttpException"}}
            response.send($data.pairs)
        elif response.statusCode.int >= Http200.int and response.statusCode.int < Http300.int:
            data.pairs = %*{"content": response.body}
            response.send($data.pairs)