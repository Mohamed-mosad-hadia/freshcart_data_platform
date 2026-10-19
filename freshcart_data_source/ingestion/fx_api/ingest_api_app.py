"""
    
    workflow 
        1- read the data from the API 
        2- extract the data from the API response 
        3- load into the Clickhouse as bronze.ingest_api_app
        
    required : 
        1- api url 
        2- api key 
        3- api secret
        4- clickhouse  connection details 
        5- full load as first time 
        6- incremental load as subsequent time
        7- apply the dempotent Loading
        8- retry mechanism for the API call in case of failure
        9- handle the error and log the error in the log file 
        10- schema validation for the API response and Clickhouse table 
        11- 
"""