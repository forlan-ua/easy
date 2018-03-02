import asynchttpserver, asyncdispatch, logging


var server = newAsyncHttpServer()
proc cb(req: Request) {.async.} =
  await req.respond(Http200, "Hello World")


while true:
    try:
        info "App listening on port ", 9000, "!"
        waitFor server.serve(Port(9000), cb)
    except:
        error "Server has been shutted down"