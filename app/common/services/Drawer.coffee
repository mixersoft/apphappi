return if !angular? 

angular.module( 
  'appHappi'
).factory('drawerService', [
  'appConfig'
  '$location'
  '$http'
  '$timeout'
  '$rootScope'
  'localStorageService'
, (appConfig, $location, $http, $timeout, $rootScope, localStorageService)->
    drawer = {
      url: '/common/data/drawer.json'
      isDrawerOpen: false
      json: {}    # drawer config object 
      # initial defaultDrawerItemState, override on drawer.init() in controller 
      defaultDrawerItemState: {  
        group: 'findhappi'
        item: 'current'
        filter: null    # filter:{key:value}
        query: ''       # filter:[string]
        orderProp: ''   # orderBy propertyName
      },
      state: {}           # init with $scope.initalDrawerState if !drawer.state?
      statusCount: null

      animateClose: (delay=750)->
        $timeout ()->
            drawer.isDrawerOpen = false
          , delay  

      # set properties for drawerItem click
      itemClick: (options, cb)->
        # same drawer-group, stay on page

        # special case for reset
        if options.group=='settings'
          if options.item=='reset'
            localStorageService.clearAll()
            drawer.animateClose(500)
            $timeout (()->window.location.reload()), 1000
            return

        sameGroup = drawer.state.group == options.group
        # get drawerItemGroup options
        drawerItemOptions = drawer.getDrawerItem(options.group, options.item)
        drawerItemOptions.item = drawerItemOptions.name
        _.extend( drawer.state, {
          'group': options.group
          'filter':null
          'query':''
          'orderBy':''
          'countKey':''
          }, drawerItemOptions)


        # save state to localStorage
        localStorageService.set('drawerState', drawer.state)

        if sameGroup
          drawer.animateClose()
        else 
          $location.path(drawerItemOptions.route)
          drawer.animateClose(500)
        return cb() if _.isFunction(cb)
        return  

      getDrawerItem: (drawerGroup, itemName) ->
        try 
          drawerGroup = _.findWhere(drawer.json.data, {name: drawerGroup})
          return drawerItemOptions = _.findWhere(drawerGroup.items, {name: itemName})
        catch
          return false
         
      forceGroupOpen: (group)->
        # force open accordion-group on ng-click toggle()
        # NOTE: this is different from initial state open/close
        # drawer.state.group = group.name
        return group.isOpen = false   # toggle will set isOpen=true

      init: (challenges, moments, drawerItemState)->
        # drawer = $rootScope.drawer
        _.extend(drawer.state, drawerItemState) if drawerItemState?

        drawer.updateCounts(challenges, moments)

        # set drawer query, filter property
        drawerGroup = _.findWhere(drawer.json.data, {name: drawer.state.group})
        drawerGroup.isOpen = true;
        return drawer

      _getCounts: (challenges, moments)->
        return _.reduce challenges, (
          (result, challenge)->
            result[challenge.status]++
            return result
        ), {
          new: 0
          pass: 0 
          complete: 0
          working: 0
          active: 0
        }

      updateCounts: (challenges, moments)->
        drawer.state.counts = _.extend (drawer.state.counts || {}), (drawer._getCounts challenges)
        # set counts for drawerGroups
        updateList = []
        updateList.push('findhappi') if challenges?
        updateList.push('gethappi') if moments?
        _.each updateList, (groupName)->
          drawerGroup = _.findWhere drawer.json.data, {name: groupName}
          switch groupName
            when 'findhappi' 
              drawerGroup.count = _.values( challenges ).length
            when 'gethappi' 
              drawerGroup.count = _.values( _.filter moments, (o)-> o.status!='pass').length
          drawer.state.counts[groupName] = drawerGroup.count
        localStorageService.set('drawerState', drawer.state)  
        return drawer

      ready: (drawer)->   # should be a promise
        return "Usage: drawer.load(url); drawer.ready.then();"

      load: (url)->
        url = drawer.url if _.isEmpty(url)
        console.log "*** drawer.load()"  
        drawer.ready = $http.get(url).success (data, status, headers, config)->
          drawer.json = data
          # console.log "*** drawer ready"
          return 
        console.log drawer.ready  
        return drawer.ready  
    }
    return drawer
])