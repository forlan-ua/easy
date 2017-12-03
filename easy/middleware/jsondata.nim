import json, strutils, streams, asyncdispatch, httpcore
export json

import .. / .. / easy

type JsonMiddleware* = ref object of Middleware
type JsonData* = ref object of MiddlewareData
    pairs*: JsonNode
template data*(d: JsonData): JsonNode =
    (if d.isNil: nil else: d.pairs)

proc add*(response: HttpResponse, pairs: JsonNode): HttpResponse {.discardable.} =
    var data = response.getMiddlewareData(JsonData)
    if not data.isNil:
        for key, value in pairs:
            data.pairs[key] = value
    result = response

proc send*(response: HttpResponse, pairs: JsonNode): HttpResponse {.discardable.} =
    var data = response.getMiddlewareData(JsonData)
    if not data.isNil:
        data.pairs = pairs
    result = response

method onInit(middleware: JsonMiddleware, request: HttpRequest, response: HttpResponse): Future[(HttpRequest, HttpResponse)] {.async, gcsafe.} =
    let accept = request.headers.getOrDefault("Accept")
    if request.url.path.endsWith(".json") or 
            request.headers.getOrDefault("Content-Type").find("application/json") > -1:
        case request.httpMethod:
            of HttpPost, HttpPatch, HttpPut:
                var data: JsonNode
                if request.contentLength > 0:
                    try:
                        if not request.bodyFile.isNil:
                            data = parseFile(request.bodyFile)
                        else:
                            data = parseJson(request.body)
                    except:
                        response.code(Http400).send("Json parse error").interrupt()
                else:
                    data = newJObject()
                request.setMiddlewareData(JsonData(pairs: data))
            else:
                discard
        if accept.find("*/*") > -1 or accept.find("application/*") > -1 or accept.find("application/json") > -1:
            response.setMiddlewareData(JsonData(pairs: newJObject()))
    elif accept == "application/json":
        response.setMiddlewareData(JsonData(pairs: newJObject()))
    result = (request, response)

method onRespond(middleware: JsonMiddleware, response: HttpResponse) {.async, gcsafe.} =
    var data = response.getMiddlewareData(JsonData).data()
    if not data.isNil:
        if data.len == 0:
            let content = if response.body.len > 0: response.body else: $response.code
            data = %*{"error": {"result": content, "code": response.code.int}}
        response.body = $data