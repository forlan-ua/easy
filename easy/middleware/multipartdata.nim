import strutils, os

import .. / easy
import data
export data

type MultipartFormDataMiddleware* = ref object of Middleware
type MultipartFormData* = ref object of HttpDataValues


proc parseError*(request: HttpRequest, response: HttpResponse): (HttpRequest, HttpResponse) =
    response.send(Http400, "Request parse error").interrupt()
    result = (request, response)


method onRequest(middleware: MultipartFormDataMiddleware, request: HttpRequest, response: HttpResponse) {.async, gcsafe.} = 
    let contentType = request.headers.getOrDefault("Content-Type")

    if contentType.find("multipart/form-data") > -1:
        writeFile("test.data", request.body)
        # var boundary = ""
        # for part in contentType.split(";"):
        #     let p = part.strip()
        #     if part.startsWith("boundary"):
        #         let splits = part.split('=', 2)
        #         boundary = "--" & (if splits.len == 2: splits[1] else: "")
        # if boundary == "":
        #     return parseError(request, response)
        # else:
        #     var data = newHttpDataValues[MultipartFormData]()
            # let body = request.body
            # let boundaryLen = boundary.len

            # var i = 0
            # var l = request.body.len

            # var curValStart = 0
            # var curValEnd = 0
            
            # while i < l:
            #     let ch = request.body[i]
            #     case ch:
            #         of '-':
                        
            #             if i - 1 + boundaryLen >= l:
            #                 return parseError(request, response)
            #             if body[i - 1 ..< i - 1 + boundaryLen] == boundary:
            #                 i += boundaryLen + 2
            #                 case body[i-2..i-1]:
            #                     of "\r\n":
            #                         curValEnd.dec
            #                         curValEnd.dec
            #                         #save value

            #                         # parse headers
            #                         curValStart = i
            #                         curValEnd = i
            #                     of "--":
            #                         curValEnd.dec
            #                         curValEnd.dec
            #                         #save value

            #                         break
            #                     else:
            #                         return parseError(request, response)
            #             else:
            #                 curValEnd.inc
            #         else:
            #             curValEnd.inc
            #     i.inc
            # response.setMiddlewareData(data)