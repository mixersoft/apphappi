return if !angular? 

drawerService = angular.module('drawerModule', [
  # dependecies
]
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
      isCardExpanded: false
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
        # drawer = $scope.$root.drawer
        # same drawer-group, stay on page

        # special case for reset
        if options.group=='settings'
          if options.item=='reset'
            localStorageService.clearAll()
            $location.path(options.route)
            drawer.animateClose(500)
            return

        sameGroup = drawer.state.group == options.group
        itemState = _.pick(options, ['group', 'item', 'filter', 'query', 'orderBy'])
        _.extend( drawer.state, {
          'filter':null
          'query':''
          'orderBy':''
          }, itemState)

        if sameGroup
          drawer.animateClose()
          return cb() if _.isFunction(cb)
        else 
          localStorageService.set('drawerState', drawer.state)
          $location.path(options.route)
          drawer.animateClose(500)
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
        # drawer = $scope.$root.drawer;
        if !drawer.state.counts?
          drawer.state.counts = drawer.getCounts challenges

        # set counts for drawerGroups
        _.each ['gethappi', 'findhappi'], (groupName)->
          drawerGroup = _.findWhere drawer.json.data, {name: groupName}
          switch groupName
            when 'findhappi' 
              drawerGroup.count = challenges.length
              drawer.state.counts[groupName] = challenges.length
            when 'gethappi' 
              drawerGroup.count = (_.filter moments, (o)-> o.status!='pass').length
              drawer.state.counts[groupName] = (_.filter moments, (o)-> o.status!='pass').length

        # set drawer query, filter property
        drawerGroup = _.findWhere(drawer.json.data, {name: drawer.state.group})
        drawerGroup.isOpen = true;
        return

      getCounts: (challenges, moments)->
        challengeStatusCount = {
          new: 0
          pass: 0 
          complete: 0
          edit: 0
          active: 0
        }
        for challenge in challenges
          challengeStatusCount[challenge.status]++
        return challengeStatusCount;

      ready: (drawer)->   # should be a promise
        return "Usage: drawer.load(url); drawer.ready.then();"

      load: (url)->
        url = drawer.url if _.isEmpty(url)
        console.log "*** drawer.load()"  
        drawer.ready = $http.get(url).success (data, status, headers, config)->
          # drawer = $scope.$root.drawer
          drawer.json = data
          # console.log "*** drawer ready"
          return 
        console.log drawer.ready  
        return drawer.ready  
    }
    return drawer
])