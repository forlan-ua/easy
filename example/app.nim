import easy
import easy / middleware / [trailingslash]
import unicode, strutils, asyncdispatch, httpcore
import views
# import articles.articles_urls

var server = HttpServer.new()
let urls = [
    url("^/path1/path2/path3/path4/path5/test$", {HttpGet: indexUrlListener}, name="index"),
    # url("^/article/?", url_import(urlsArticles, namespace="articles"))
]
let middlewares = [
    TrailingSlashMiddleware.new(false),
    # JsonMiddleware.new(),
    # QueryParamsMiddleware.new(),
    # CookiesMiddleware.new(),
    # MultipartFormDataMiddleware.new()
]
server.registerRoutes(urls)
server.registerMiddlewares(middlewares)
waitFor server.listen(5050)