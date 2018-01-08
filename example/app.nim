import ospaths
import easy
import easy / middleware / [trailingslash, jsondata, querystring, formdata, cookiesdata, multipartformdata]
import unicode, strutils, asyncdispatch, httpcore
import views
# import articles.articles_urls

var server = HttpServer.new()
let urls = [
    url("^/path1/path2/path3/path4/path5/test$", indexUrlListener, name="index"),
    # url("^/article/?", url_import(urlsArticles, namespace="articles"))
]
let middlewares = [
    TrailingSlashMiddleware.new(false),
    JsonMiddleware.new(),
    QueryStringMiddleware.new(),
    FormDataMiddleware.new(),
    CookiesMiddleware.new(),
    MultipartFormDataMiddleware.new(getTempDir())
]
server.registerRoutes(urls)
server.registerMiddlewares(middlewares)
server.listen(5050)