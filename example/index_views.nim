import asyncdispatch
import easy


proc indexUrlListener*(request: HttpRequest, response: HttpResponse) {.async, gcsafe.} =
    response.send("Hello World")