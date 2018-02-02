import easy, httpcore
import category_views


routes urlsCategory:
    "" as "index":
        HttpGet: listCategories
        HttpPost: createCategory
    "/:id" as "item":
        HttpGet: retrieveCategory
        HttpPut: updateCategory
        HttpDelete: deleteCategory