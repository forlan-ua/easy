import ospaths
import easy
import easy / middleware / [trailingslash, jsondata, querystring, formdata, cookiesdata, multipartformdata]
import unicode, strutils, asyncdispatch, httpcore
import index_views

import services / categories / category_urls


var server = HttpServer.new()


routes:
    "":
        HttpGet: indexUrlListener
    "/category" as "categories":
        urlsCategory


let middlewares = [
    TrailingSlashMiddleware.new(false),
    JsonMiddleware.new(),
    QueryStringMiddleware.new()
]


server.registerRoutes(urls)
server.registerMiddlewares(middlewares)

echo server.router.routes
echo server.router.namedRoutes
echo server.router.reverseUrl("categories:item", {"id": "123"})
echo server.router.reverseUrl("categories:index")

server.listen(6060)