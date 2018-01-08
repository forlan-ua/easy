import mimetypes, ospaths, strutils, asyncdispatch
import easy

type TrailingSlashMiddleware* = ref object of Middleware
    exists: bool

proc new*(T: typedesc[TrailingSlashMiddleware], exists: bool = false): Middleware =
    TrailingSlashMiddleware(exists: exists)

method onInit*(middleware: TrailingSlashMiddleware, request: HttpRequest, response: HttpResponse): Future[(HttpRequest, HttpResponse)] {.async, gcsafe.} = 
    let path = request.url.path
    
    if path != "/":
        if middleware.exists:
            let (_, _, ext) = path.splitFile()
            let mimeType = request.mimeTypes().getMimetype(ext[1..ext.len], "")
            if mimeType == "" and not path.endsWith("/"):
                response.redirect(path & "/")
        else:
            if path.endsWith("/"):
                response.redirect(path[0..path.len-2])

    result = (request, response)