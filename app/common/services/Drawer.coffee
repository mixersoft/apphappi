return if !angular? 

drawerService = angular.module('drawerModule', [
  # dependecies
]
).factory('drawerService', [
  'appConfig'
  '$location'
  '$http'
  '$timeout'
, (appConfig, $location, $http, $timeout)->
    drawer = {
      url: '/common/data/drawer.json'
      isDrawerOpen: false
      isCardExpanded: false
      json: {}    # drawer config object 
      # initial defaultDrawerItemState, override on drawer.init() in controller 
      defaultDrawerItemState: {  
        name: 'findhappi'
        state:
          # isOpen: true
          active: 'current'
          filter: null    # filter:{key:value}
          query: ''       # filter:[string]
          orderProp: ''   # orderBy propertyName
      },
      drawerItemState: {},  # active state

      animateClose: (delay=750)->
        $timeout ()->
            drawer.isDrawerOpen = false
          , delay  

      # set properties for drawerItem click
      itemClick: ($scope, options, cb)->
        # drawer = $scope.$root.drawer
        # same drawer-group, stay on page
        drawer.drawerItemState.state.orderProp = options.orderBy if options.orderBy?
        # options.filter is an object {key:query}
        drawer.drawerItemState.state.filter = options.filter if options.filter?
        drawer.drawerItemState.state.active = options.name if options.name?
        if $scope.$route.current.originalPath==options.route
          # set .item.active
          drawerGroup = _.findWhere(drawer.json.data, {name:drawer.drawerItemState.name})
          # drawerGroup.state.active = options.name   # use drawer.drawerItemState.state.active
          drawer.animateClose()
          return cb() if _.isFunction(cb);
          # shuffle?
          # $scope.cards = drawer._shuffleArray $scope.cards if options.name=='shuffle'
        else 
          # navigate to options.route, set initial state
          console.log "navigate to href=#"+options.route
          console.warn "save drawer state to localStorage"
          $location.path(options.route)
          drawer.animateClose(500)

      getDrawerItem: (drawerGroup, itemName) ->
        try 
          drawerGroup = _.findWhere(drawer.json.data, {name: drawerGroup})
          return drawerItemOptions = _.findWhere(drawerGroup.items, {name: itemName})
        catch
          return false
         
      forceGroupOpen: (group)->
        # force open accordion-group on ng-click toggle()
        # NOTE: this is different from initial state open/close
        drawer.drawerItemState.name = group.name
        return group.isOpen = false   # toggle will set isOpen=true

      init: (challenges, moments, drawerItemState)->
        drawer.drawerItemState = _.merge(drawer.defaultDrawerItemState, drawerItemState)
        # drawer = $scope.$root.drawer;
        drawer._setForeignKeys challenges, moments
        # set counts for drawerGroups
        _.each ['gethappi', 'findhappi'], (groupName)->
          found = _.findWhere drawer.json.data, {name: groupName}
          found.count = challenges.length if groupName=='findhappi'
          if groupName=='gethappi'
            found.count = (_.filter moments, (o)-> o.status!='pass').length


        # set drawer query,filter propery
        drawerGroup = _.findWhere(drawer.json.data, {name: drawer.drawerItemState.name})
        drawerGroup.isOpen = true;
        drawerItem = _.findWhere(drawerGroup.items, {name: drawer.drawerItemState.state.active})
        drawer.drawerItemState.state.filter = drawerItem && drawerItem.filter
        return

      # TODO: move to syncService parse  
      _setForeignKeys: (challenges, moments)->
        challengeStatusPriority = ['new','pass', 'complete','edit','active']
        challengeStatusCount = {
          new: 0
          pass: 0 
          complete: 0
          edit: 0
          active: 0
        }
        for challenge in challenges
          challenge.moments = _.where(moments, {challengeId: challenge.id})
          if challenge.moments.length
            _.each challenge.moments, (moment,k,l)->
                moment.challenge = challenge    # moment belongsto challenge assoc
                challenge.status = moment.status if challengeStatusPriority.indexOf(moment.status) > challengeStatusPriority.indexOf(challenge.status)
          else 
            challenge.status = 'new'
          challengeStatusCount[challenge.status]++
        return challengeStatusCount;

      ready: (drawer)->   # should be a promise
        return "Usage: drawer.load(url); drawer.ready.then();"

      load: (url)->
        url = drawer.url if !url?
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