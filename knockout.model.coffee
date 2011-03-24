# Cache implementation using the IdentityMap pattern
ko.utils.IdentityMap = ->

    #Simple object comparison by value
    @find = (id,params) ->
        $.grep(@,(d) ->
            d.id is id and ko.utils.stringifyJson(d.params) is ko.utils.stringifyJson(params)
        )[0]
    @
ko.utils.IdentityMap.prototype = new Array()

# Helper function
ko.utils.unescapeHtml = (str) ->
  if str.length > 0
    temp = document.createElement "div"
    temp.innerHTML = str
    result = temp.childNodes[0].nodeValue
    temp.removeChild temp.firstChild
    result
  else
    str

# Base model
class @KnockoutModel

    # Override these static values on your model
    @__urls: {}
    @__defaults: {}
    @__transientParameters: []
    @__cacheContainer: new ko.utils.IdentityMap()

    # Sets default values on initialization
    constructor: ->
        @__urls = @constructor.__urls
        @set(@constructor.__defaults)

    # instance urls list
    __urls: {}

    # Adds or modifies a route on instance and stactically
    addRoute: (id,href,static = true) ->
      @__urls[id] = href
      @constructor.__urls[id] = href if static is true

    # Gets an attribute value(observable or not)
    get: (attr) -> ko.utils.unwrapObservable @[attr]

    # Args must be an object containing one or more attributes and its new values
    # Additionally, detects HTML entities and unescape them
    set: (args) ->
        for own i,item of args
            if ko.isWriteableObservable(@[i])
                @[i](if typeof item is "string" and item.match(/&[^\s]*;/) then ko.utils.unescapeHtml(item) else item)
            else if @[i] isnt undefined
                @[i] = if typeof item is "string" and item.match(/&[^\s]*;/) then ko.utils.unescapeHtml(item) else item

        @

    # creates an action with HTTP POST
    doPost: (routeName,params = {},callback = null) ->
        if routeName.match(/^http:\/\//) is null
            url = @__urls[routeName]
        else
            url = routeName
        @constructor.doPost url,params,callback

    # creates an action with HTTP GET
    doGet: (routeName,params = {},callback = null) ->
        if routeName.match(/^http:\/\//) is null
            url = @__urls[routeName]
        else
            url = routeName
        @constructor.doGet url,params,callback

    # (static) creates an action with HTTP POST
    @doPost: (routeName,params = {},callback = null) ->
        if routeName.match(/^http:\/\//) is null
            url = @__parse_url(@__urls[routeName],params)
        else
            url = @__parse_url(routeName,params)
        RQ.add ($.post url, params, (data) ->
                callback(data) if typeof callback is "function"
            , "json"
        ), "rq_#{@name}_"+new Date()

    # (static) creates an action with HTTP GET
    @doGet: (routeName,params = {},callback = null) ->
        if routeName.match(/^http:\/\//) is null
            url = @__parse_url(@__urls[routeName],params)
        else
            url = @__parse_url(routeName,params)
        isCache = params["__cache"] is true
        delete params["__cache"] if isCache is true
        cc = @__cacheContainer
        cached = cc.find("#{@name}##{routeName}", params) if isCache is true
        if cached?
            callback(cached.data) if typeof callback is "function"
        else
            tempParams = $.extend {},params
            tempParams["__no_cache"] = new Date().getTime()
            RQ.add $.getJSON url, tempParams, (data) ->
                cc.push({id: "#{@name}##{routeName}", params: params,data: data}) if isCache is true
                callback(data) if typeof callback is "function"
            , "rq_#{@name}_"+new Date()

    # (static) Returns an array of objects using the data param(another array of data)
    @createCollection: (data,callback) ->
        collection = []
        for item in data
            obj = new @
            if typeof callback is "function"
                obj.set(callback(item))
            else
                obj.set(item)
            collection.push(obj)
        collection

    # Clear all attributes and set default values
    clear: ->
        values = {}
        for own i,item of @
            if i isnt "__urls"
                switch(typeof @get(i))
                    when "string" then values[i] = (if @constructor.__defaults[i] isnt undefined then @constructor.__defaults[i] else "")
                    when "number" then values[i] = (if @constructor.__defaults[i] isnt undefined then @constructor.__defaults[i] else 0)
                    when "boolean" then values[i] = (if @constructor.__defaults[i] isnt undefined then @constructor.__defaults[i] else false)
                    when "object"
                        values[i] = (if @constructor.__defaults[i] isnt undefined then @constructor.__defaults[i] else [])
        @set(values)

    # Refreshes model data calling show()
    refresh: (callback) ->
        @show (data) ->
            if data.status is "SUCCESS"
                @set(data)
            callback(data) if typeof callback is "function"

    # Convert whole model to JSON, adds a random attribute to avoid IE issues with GET requests
    toJSON: (options) -> ko.toJSON @clone(options)

    # Convert whole model to a plain JS object, adds a random attribute to avoid IE issues with GET requests
    toJS: (options) -> ko.toJS @clone(options)

    # Clones the model without 'private' attributes
    clone: (args = {}) ->
        transientAttributes = {'__urls': false}
        for param in @constructor.__transientParameters
            transientAttributes[param] = false
        args = $.extend(transientAttributes,args)
        temp = {}
        for own i of @
            if args[i] is true or args[i] is undefined
                temp[i] = @get(i)
        temp

    # A simple convention: if model.id is blank, then it's new
    isNew: ->
        value = @get("id")
        value? && value isnt ""

    # Override this with your own validation method returning true or false
    validate: -> true

    # Validate the model then check if it's new(call create) or existing(call update)
    save: ->
        if @validate() is true
            if @isNew() is true then @create.apply(@,arguments) else @update.apply(@,arguments)
        else
            [params,callback] = @constructor.__generate_request_parameters.apply(@,arguments)
            callback {status: "ERROR",message: "Invalid object"} if typeof callback is "function"

    # Helper for all standard request methods
    # First parameter is a object containing additional parameters to send via AJAX
    # Second parameter is a callback to execute after request is finished
    @__generate_request_parameters: ->
        params = {}
        callback = null
        if typeof arguments[0] is "function"
            callback = arguments[0]
        else if typeof arguments[0] is "object"
            params = arguments[0]
            if typeof arguments[1] is "function"
                callback = arguments[1]
        [params,callback]

    # parses an url(Sinatra-like style with :parameters)
    @__parse_url: (url,params) ->
        url.replace /:([a-zA-Z0-9_]+)/g, (match) ->
            params[match.substring(1)]
            value = params[attr]
            delete params[attr]
            value

    # Starts an AJAX request to create the entity using the "create" URL
    create: ->
        [params,callback] = @constructor.__generate_request_parameters.apply(@,arguments)
        params = $.extend(params,@toJS())
        @doPost "create",params,callback

    # Starts an AJAX request to update the entity using the "update" URL
    update: ->
        [params,callback] = @constructor.__generate_request_parameters.apply(@,arguments)
        params = $.extend(params,@toJS())
        @doPost "update",params,callback

    # Starts an AJAX request to remove the entity using the "destroy" URL
    destroy: ->
        [params,callback] = @constructor.__generate_request_parameters.apply(@,arguments)
        params = $.extend(params,@toJS())
        @doPost "destroy",params,callback

    # Fetch by model ID using the "show" URL
    show: ->
        [params,callback] = @constructor.__generate_request_parameters.apply(@,arguments)
        params = $.extend(params,{id: @get("id")})
        @doGet "show",params,callback

    # Fetch all using the "index" URL
    index: ->
        [params,callback] = @constructor.__generate_request_parameters.apply(@,arguments)
        @doGet "index",params,callback

    # (static) Starts an AJAX request to create the entity using the "create" URL
    @create: ->
        [params,callback] = @__generate_request_parameters.apply(@,arguments)
        @doPost "create",params,callback

    # (static) Starts an AJAX request to update the entity using the "update" URL
    @update: ->
        [params,callback] = @__generate_request_parameters.apply(@,arguments)
        @doPost "update",params,callback

    # (static) Starts an AJAX request to remove the entity using the "destroy" URL
    @destroy: ->
        [params,callback] = @__generate_request_parameters.apply(@,arguments)
        @doPost "destroy",params,callback

    # (static) Fetch by model ID using the "show" URL
    @show: ->
        [params,callback] = @__generate_request_parameters.apply(@,arguments)
        @doGet "show",params,callback

    # (static) Fetch all using the "index" URL
    @index: ->
        [params,callback] = @__generate_request_parameters.apply(@,arguments)
        @doGet "index",params,callback

    # (static) Abort all requests of this model
    @killAllRequests: -> RQ.killByRegex /^rq_#{@name}_/
