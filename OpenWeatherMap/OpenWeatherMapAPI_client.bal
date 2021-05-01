import  ballerina/http;
import  ballerina/url;
import  ballerina/lang.'string;

public client class Client {
    @display {
        label: "open_weather_map",
        iconPath: "path/to/icon.png"
    }
    public http:Client clientEp;
    public isolated function init(string serviceUrl = "http://api.openweathermap.org/data/2.5/", http:ClientConfiguration  httpClientConfig =  {}) returns error? {
        http:Client httpEp = check new (serviceUrl, httpClientConfig);
        self.clientEp = httpEp;
    }
    @display {label: "Get Current Weather"}
    remote isolated function currentWeatherData(@display {label: "City Name"} string? q, @display {label: "City ID"} string? id, @display {label: "Latitude"} string? lat, @display {label: "Longitude"} string? lon, @display {label: "Zip code"} string? zip, @display {label: "Units"} string? units, @display {label: "Language"} string? lang, @display {label: "Mode"} string? mode) returns '200|error {
        string  path = string `/weather`;
        map<anydata> queryParam = {
            q: q,
            id: id,
            lat: lat,
            lon: lon,
            zip: zip,
            units: units,
            lang: lang,
            mode: mode
        };
        path = path + getPathForQueryParam(queryParam);
        '200 response = check self.clientEp->get(path, targetType = '200);
        return response;
    }
}

isolated function  getPathForQueryParam(map<anydata>   queryParam)  returns  string {
    string[] param = [];
    param[param.length()] = "?";
    foreach  var [key, value] in  queryParam.entries() {
        if  value  is  () {
            _ = queryParam.remove(key);
        } else {
            if  string:startsWith( key, "'") {
                 param[param.length()] = string:substring(key, 1, key.length());
            } else {
                param[param.length()] = key;
            }
            param[param.length()] = "=";
            if  value  is  string {
                string updateV =  checkpanic url:encode(value, "UTF-8");
                param[param.length()] = updateV;
            } else {
                param[param.length()] = value.toString();
            }
            param[param.length()] = "&";
        }
    }
    _ = param.remove(param.length()-1);
    if  param.length() ==  1 {
        _ = param.remove(0);
    }
    string restOfPath = string:'join("", ...param);
    return restOfPath;
}
