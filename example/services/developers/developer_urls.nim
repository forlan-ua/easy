import easy, httpcore
import developer_views


routes urlsDeveloper:
    "" as "index":
        HttpGet: listDevelopers
        HttpPost: createDeveloper
    "/:id" as "item":
        HttpGet: retrieveDeveloper
        HttpPut: updateDeveloper
        HttpDelete: deleteDeveloper

export urlsDeveloper