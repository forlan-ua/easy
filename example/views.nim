import tables, asyncdispatch, json
import easy
import easy / middleware / [jsondata, querystring, formdata, cookiesdata, multipartformdata]


let indexUrlListener*: UrlListener = proc(request: HttpRequest, response: HttpResponse, args: seq[string], kwargs: Table[string, string]): Future[void] {.async, gcsafe.} =
    var jsonData = response.getMiddlewareData(JsonData).data()
    let queryStringData = request.getMiddlewareData(QueryStringData)
    let formData = request.getMiddlewareData(FormData)
    let filesFormData = request.getMiddlewareData(FilesFormData)
    let cookiesData = request.getMiddlewareData(CookiesData)

    if jsonData.isNil:
        if not queryStringData.isNil:
            response.add($queryStringData.tbl)
            response.add("\L")
        if not formData.isNil:
            response.add($formData.tbl)
            response.add("\L")
        response.add($cookiesData.requestCookies)
        response.add("\L")
        response.add($cookiesData.responseCookies)
        response.add("\L")
    else:
        response.send(
            %*{
                "queryStringData": if queryStringData.isNil: "" else: $queryStringData.tbl,
                "formData": if formData.isNil: "" else: $formData.tbl,
                "filesFormData": if filesFormData.isNil: "" else: $filesFormData.tbl,
                "requestCookies": $cookiesData.requestCookies,
                "responseCookies": $cookiesData.responseCookies
            }
        )