return if !angular? 

angular.module( 
  'appHappi'
).directive('onOffSwitch', ()->
  link = (scope, element, attrs)->
    ngModel = scope.$parent?.options?.switch
    if ngModel?
      element.attr('my-ng-model', ngModel)
      # _.each(element.children().children(), ((o)->o.setAttribute 'ng-model', ngModel) )
    return

  return {
    template: '<div class="btn-group">
    <button type="button" class="btn btn-primary btn-xs" ng-model="myNgModel" btn-radio="false">Off</button>
    <button type="button" class="btn btn-primary btn-xs" ng-model="myNgModel" btn-radio="true">On</button>
</div>'
    restrict: 'AE'
    scope: 
      myNgModel: '='     # this is NOT working, scope.mirror is not set
    # link: link 
  }
).factory('drawerService', [
  'appConfig'
  '$location'
  '$http'
  '$timeout'
  'localStorageService'
, (appConfig, $location, $http, $timeout, localStorageService)->
    # private
    _drawer = {
      url: '/common/data/drawer.json'
      json: {}    
      # initial defaultDrawerItemState, override on drawer.init() in controller 
      defaultDrawerItemState: {  
        group: 'findhappi'
        item: 'current'
        filter: null    # filter:{key:value}
        query: ''       # filter:[string]
        orderProp: ''   # orderBy propertyName
      }
      getCounts: (challenges, moments)->
        challengeCounts = _.reduce challenges, (
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
        return {'challenge': challengeCounts}
      
    }

    self = {
      isDrawerOpen: false
      state: {}           # init with $scope.initalDrawerState if !drawer.state?

      isDrawerItemActive: (id)->
        return id == self.state?['activeItemId']

      animateClose: (delay=750)->
        $timeout ()->
            self.isDrawerOpen = false
          , delay  

      # set properties for drawerItem click
      itemClick: (options, cb)->
        # same drawer-group, stay on page

        # special case for reset
        if options.group=='settings'
          switch options.item
            when 'reset'
              localStorageService.clearAll()
              self.animateClose(500)
              $timeout (()->window.location.reload()), 1000
              return
            when 'debug'
              appConfig.debug = !appConfig.debug
            when 'reload'
              return window.location.reload();


        sameGroup = self.state.group == options.group
        # get drawerItemGroup options
        drawerItemOptions = self.getDrawerItem(options.group, options.item)
        drawerItemOptions.item = drawerItemOptions.name 
        deckOptions = _.pick(options, ['filter', 'query', 'orderBy'])
        _.extend( self.state, {
          'group': options.group
          'filter': null
          'query':''
          'orderBy':''
          'countKey':''
          'activeItemId': ['drawer', options.group, options.item].join('-')
          }, drawerItemOptions, deckOptions)


        # save state to localStorage
        localStorageService.set('drawerState', self.state)
        # notify.alert "itemClick, filter="+JSON.stringify(self.state.filter)

        if sameGroup
          self.animateClose()
        else 
          self.animateClose(500)

        return cb(drawerItemOptions.route) if _.isFunction(cb)
        if !drawerItemOptions.route
          console.error "itemClick: not sure where to go?"
        return $location.path(drawerItemOptions.route) 

      getDrawerItem: (drawerGroup, itemName) ->
        try 
          drawerGroup = _.findWhere(_drawer.json.data, {name: drawerGroup})
          return drawerItemOptions = _.findWhere(drawerGroup.items, {name: itemName})
        catch
          return false
         
      forceGroupOpen: (group)->
        # force open accordion-group on ng-click toggle()
        # NOTE: this is different from initial state open/close
        # self.state.group = group.name
        return group.isOpen = false   # toggle will set isOpen=true

      init: (challenges, moments, drawerItemState)->
        # drawer = $rootScope.drawer
        _.extend(self.state, drawerItemState) if drawerItemState?

        self.updateCounts(challenges, moments)

        # set drawer query, filter property
        drawerGroup = _.findWhere(_drawer.json.data, {name: self.state.group})
        drawerGroup.isOpen = true;
        return self

      

      updateCounts: (challenges, moments)->
        self.state.counts = _.extend (self.state.counts || {}), (_drawer.getCounts challenges)
        # set counts for drawerGroups
        updateList = []
        updateList.push('findhappi') if challenges?
        updateList.push('gethappi') if moments?
        _.each updateList, (groupName)->
          drawerGroup = _.findWhere _drawer.json.data, {name: groupName}
          switch groupName
            when 'findhappi' 
              drawerGroup.count = _.values( challenges ).length
            when 'gethappi' # moments
              drawerGroup.count = _.values( _.filter moments, (o)-> o.status!='pass').length
          self.state.counts[groupName] = drawerGroup.count
        localStorageService.set('drawerState', self.state)  
        return self

      load: (url)->
        url = _drawer.url if _.isEmpty(url)
        console.log "*** drawer.load()"  
        _drawer.ready = $http.get(url).success (data, status, headers, config)->
          _drawer.json = data
          localStorageService.set('drawer', _drawer.json )
          # console.log "*** drawer ready"
          return 'ready'
        console.log _drawer.ready  
        return _drawer.ready  

      json: (data)->
        _drawer.json = data if data?
        return _drawer.json 

      ready: (drawer)->   # should be a promise
        return "Usage: self.load(url); self.ready.then();"
    }
    return self
])