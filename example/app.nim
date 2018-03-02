import ospaths
import easy
import easy / middleware / [trailingslash, jsondata, querystring, formdata, cookiesdata, multipartformdata]
import unicode, strutils, asyncdispatch, httpcore
import index_views

import services / categories / category_urls
import services / developers / developer_urls


var server = HttpServer.new()


routes:
    "":
        HttpGet: indexUrlListener
    "/category" as "categories":
        urlsCategory
    "/developer" as "developers":
        urlsDeveloper


let middlewares = [
    TrailingSlashMiddleware.new(false),
    JsonMiddleware.new(),
    QueryStringMiddleware.new(),
    FormDataMiddleware.new(),
    CookiesMiddleware.new(),
    MultipartFormDataMiddleware.new()
]


server.registerRoutes(urls)
server.registerMiddlewares(middlewares)

server.listen(9000)