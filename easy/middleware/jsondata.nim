import json, strutils, streams, asyncdispatch, httpcore
export json

import .. / .. / easy

type JsonMiddleware* = ref object of Middleware
type JsonData* = ref object of MiddlewareData
    jdata*: JsonNode
template data*(d: JsonData): JsonNode =
    (if d.isNil: nil else: d.jdata)

proc add*(response: HttpResponse, jdata: JsonNode): HttpResponse {.discardable.} =
    var data = response.getMiddlewareData(JsonData)
    if not data.isNil:
        for key, value in jdata:
            data.jdata[key] = value
    result = response

proc send*(response: HttpResponse, jdata: JsonNode): HttpResponse {.discardable.} =
    var data = response.getMiddlewareData(JsonData)
    if not data.isNil:
        data.jdata = jdata
    result = response

method onRequest*(middleware: JsonMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    let accept = request.headers.getOrDefault("Accept")
    if request.url.path.endsWith(".json") or 
            request.headers.getOrDefault("Content-Type").find("application/json") > -1:
        case request.httpMethod:
            of HttpPost, HttpPatch, HttpPut:
                var data: JsonNode
                if request.contentLength > 0:
                    try:
                        data = parseJson(request.body)
                    except:
                        response.code(Http400).send("Json parse error").interrupt()
                else:
                    data = newJObject()
                echo data
                request.setMiddlewareData(JsonData(jdata: data))
            else:
                echo "DISCARD?"
                discard
        if accept.find("*/*") > -1 or accept.find("application/*") > -1 or accept.find("application/json") > -1:
            response.setMiddlewareData(JsonData(jdata: newJObject()))
    elif accept == "application/json":
        response.setMiddlewareData(JsonData(jdata: newJObject()))

method onRespond*(middleware: JsonMiddleware, response: HttpResponse) {.async, gcsafe.} =
    var data = response.getMiddlewareData(JsonData).data()
    if not data.isNil:
        if data.len == 0:
            let content = if response.body.len > 0: response.body else: $response.code
            data = %*{"error": {"result": content, "code": response.code.int}}
        response.body = $data