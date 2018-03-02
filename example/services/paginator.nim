import easy, json, tables
import easy / middleware / querystring


proc pages*(request: HttpRequest, page: int, limit: int, count: int): JsonNode =
    let queryString = request.getMiddlewareData(QueryStringData)
    
    result = newJObject()

    result["count"] = %count
    result["page"] = %page
    result["limit"] = %limit
    result["prev"] = if page > 1: 
        %(request.url.path & queryString.toString({"p": $(page - 1), "l": $limit})) 
        else: newJNull()
    result["next"] = if page * limit < count: 
        %(request.url.path & queryString.toString({"p": $(page + 1), "l": $limit})) 
        else: newJNull()