import .. / .. / easy
import .. / .. / middleware / [jsondata]


let listArticles*: UrlListener = proc(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]): Future[bool] {.async, gcsafe.} =
    response.JsonHttpResponse.send(%*{"result": "listArticles"})
    
    
let createArticle*: UrlListener = proc(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]): Future[bool] {.async, gcsafe.} =
    response.JsonHttpResponse.send(%*{"result": "createArticle"})
    
    
let retrieveArticle*: UrlListener = proc(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]): Future[bool] {.async, gcsafe.} =
    response.JsonHttpResponse.send(%*{"result": "retrieveArticle"})
    
    
let updateArticle*: UrlListener = proc(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]): Future[bool] {.async, gcsafe.} =
    response.JsonHttpResponse.send(%*{"result": "updateArticle"})
    
    
let deleteArticle*: UrlListener = proc(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]): Future[bool] {.async, gcsafe.} =
    response.JsonHttpResponse.send(%*{"result": "deleteArticle"})