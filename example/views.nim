import tables, asyncdispatch
import easy
# import .. / middleware / [jsondata, queryparams, data]


let indexUrlListener*: UrlListener = proc(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]): Future[void] {.async, gcsafe.} =
    response.send("HTML")