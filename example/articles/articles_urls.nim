import .. / .. / easy

import articles_views

let urls_articles* = [
    url("^/$", {HttpGet: listArticles, HttpPost: createArticle}, name="index"),
    url("^/(?<id>[0-9]+)/?$", {HttpGet: retrieveArticle, HttpPut: updateArticle, HttpDelete: deleteArticle}, name="item")
]