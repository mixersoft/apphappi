return if !angular? 

drawerService = angular.module('drawerModule', [
  # dependecies
]
).factory('drawerService', [
  '$http'
, ($http)->
    drawer = {
      url: '/common/data/drawer.json'
      isDrawerOpen: false
      isCardExpanded: false
      query: ''     # filter:[string]
      filter: null  # filter:{key:value}
      json: {}    # drawer config object 
      # initial defaultDrawerItemState, override on drawer.init() in controller 
      defaultDrawerItemState: {  
        name: 'findhappi'
        state:
          # isOpen: true
          active: 'current'
      },
      # set properties for drawerItem click
      itemClick: ($scope, options, cb)->
        # drawer = $scope.$root.drawer
        if $scope.$route.current.originalPath==options.route
          # same drawer-group, stay on page
          $scope.orderProp = options.orderBy if options.orderBy?
          # options.filter is an object {key:query}
          # don't forget to pipe into $root.drawer.query
          drawer.filter = options.filter if options.filter?


          # set .item.active
          drawerGroup = _.findWhere(drawer.json, {name:drawer.drawerItemState.name})
          drawerGroup.state.active = options.name
          return cb();
          # shuffle?
          # $scope.cards = drawer._shuffleArray $scope.cards if options.name=='shuffle'
        else 
          # navigate to options.route, set initial state
          console.log "navigate to href="+options.route
        return
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
          found = _.findWhere drawer.json, {name: groupName}
          found.count = challenges.length if groupName=='findhappi'
          if groupName=='gethappi'
            found.count = (_.filter moments, (o)-> o.status!='pass').length


        # set drawer query,filter propery
        drawerGroup = _.findWhere(drawer.json, {name: drawer.drawerItemState.name})
        drawerGroup.isOpen = true;
        drawerItem = _.findWhere(drawerGroup.items, {name: drawer.drawerItemState.state.active})
        drawer.filter = drawerItem && drawerItem.filter
        return

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
        return "Usage: drawer.load(); drawer.ready.then();"

      load: (url)->
        url = drawer.url if !url?
        drawer.ready = $http.get(url).success (data, status, headers, config)->
          # drawer = $scope.$root.drawer
          drawer.json = data
          console.log "*** drawer ready"
          return drawer
        return drawer.ready  
    }
    return drawer
])