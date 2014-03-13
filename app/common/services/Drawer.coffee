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
).directive('responsiveDrawerWrap', [ 
  'appConfig'
  'drawerService' 
  '$window'
  (CFG, drawerService, $window)->
    return {
      restrict: 'A'
      link: (scope, element, attrs)->
        setResponsive = _.debounce (()->
                  # either $window.innerWidth or $window.outerWidth
                  isStacked = $window.innerWidth < CFG.drawerOpenBreakpoint
                  if (isStacked) 
                    element.removeClass('force-open')
                  else 
                    element.addClass('force-open')
                  # drawerService.setDrawerOpen() 
                  drawerService.setDrawerOpen()
          ), 200

        angular.element($window).bind 'resize', ->
          setResponsive()

        scope.drawer = drawerService
        setResponsive()
    }    
]).factory('drawerService', [
  'appConfig'
  '$location'
  '$http'
  '$timeout'
  '$window'
  'localStorageService'
, (CFG, $location, $http, $timeout, $window, localStorageService)->

    # private
    _drawer = {
      url: '/common/data/drawer.json'
      json: {}    
      drawerWrap : null     #  #drawer element
      syncService : null    # ref to syncService for counts

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

      setDrawerOpen: ()->
        # directive responsiveDrawerWrap will add/remove .force-open class to drawerWrap
        if !(_drawer.drawerWrap?.length)
          _drawer.drawerWrap = angular.element(document.getElementById('drawer'))  
        self.isDrawerOpen =  _drawer.drawerWrap.hasClass('force-open') 
        _drawer.drawerWrap?.scope()?.$apply()
        # console.log "setDrawerOpen, isDrawerOpen="+self.isDrawerOpen
        return

      # ng-click handler to discard .fa-bars open click as necessary 
      handleDrawerOpen: (e)->
        if !_drawer.drawerWrap
          _drawer.drawerWrap = angular.element(document.getElementById('drawer'))
        if _drawer.drawerWrap.hasClass('force-open')
          # prevent close on ng-click
          self.isDrawerOpen = true
          e.preventDefault()
          e.stopImmediatePropagation()
          return false
        return true # let accordion.ng-click do its work

      state: {}           # init with $scope.initalDrawerState if !drawer.state?
      setSyncService: (syncService)->
        _drawer.syncService = syncService

      isDrawerItemActive: (id)->
        return id == self.state?['activeItemId']

      animateClose: (delay=750)->
        return if !_drawer.drawerWrap?
        return if _drawer.drawerWrap?.hasClass('force-open')
        $timeout ()->
            self.isDrawerOpen = false
          , delay  

      drawerItemClick : (e, callback)->
        # set active
        if _.isString(e)
          target = {id: e} 
        else 
          target = e.currentTarget 

        [type, group, item] = target.id?.split('-') || []
        if type == 'drawer'
          drawerOptions = {
            group: group
            item: item
          }
        else 
          throw "ERROR: expecting something in the form of 'drawer-[group]-[item]'"

        # usually called from drawer.menuItem onclick handler
        after_handleItemClick = (route)->
          if route? && route != $location.path()
            return $location.path(route)

          # controllerScope should validate deck and load route
          controllerScope = angular.element(document.getElementById("notify")).scope()
          # verify deck
          return if !controllerScope?.deck?

          deck = controllerScope?.deck   
          isValid = deck.validateDeck()
          deck.cards('refresh') if !isValid

          # check topCard
          if /challenge/.test(route)
            c = deck.topCard()
            if c?.type=="challenge" && c?.status=="active"
              controllerScope.getChallengePhotos(c) 
          return

        return self.itemClick drawerOptions, callback || after_handleItemClick


      # set properties for drawerItem click
      itemClick: (options, cb)->
        # Settings click will cause reload
        if options.group=='settings'
          switch options.item
            when 'reset'
              _resetCb = (clearAll=false)->
                localStorageService.clearAll() if clearAll
                self.animateClose()
                $timeout (()->window.location.reload()), 1000
                return $location.path('/')

              if navigator.notification
                _onConfirm = (index)->
                  clearAll = index==2 
                  return _resetCb(clearAll)
                navigator.notification.confirm(
                        "You are about to delete everything and reset the App.", # message
                        _onConfirm,
                        "Are you sure?", # title 
                        ['Cancel', 'OK']
                      )
              else
                resp = window.confirm('Are you sure you want to delete everything?')
                return _resetCb(resp)
            when 'debug'
              CFG.debug = !CFG.debug
              return
            when 'reload'
              return window.location.reload();
            # when 'reminder' # do nothing


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

        notify.alert "drawer.activeItemId=="+self?.state?.activeItemId, "danger", 3000
        # save state to localStorage
        localStorageService.set('drawerState', self.state)
        # notify.alert "itemClick, filter="+JSON.stringify(self.state.filter)
        self.animateClose()

        return cb(drawerItemOptions.route) if _.isFunction(cb)
        if !drawerItemOptions.route
          console.error "itemClick: not sure where to go?"
        return $location.path(drawerItemOptions.route) 

      getDrawerItem: (drawerGroup, itemName) ->
        try 
          drawerCfg = _drawer.syncService?.localData['drawer']?.data || _drawer.json.data
          drawerGroup = _.findWhere(drawerCfg, {name: drawerGroup})
          drawerItemOptions = _.findWhere(drawerGroup.items, {name: itemName})
          drawerItemOptions['group'] = drawerGroup.name
          return drawerItemOptions
        catch
          return false
         
      init: (challenges, moments, drawerItemState)->
        # drawer = $rootScope.drawer
        _.extend(self.state, drawerItemState) if drawerItemState?

        # update syncService
        self.updateCounts(challenges, moments)

        self.state.activeItemId = ["drawer",self.state.group, self.state.item || self.state.name ].join('-')

        # set drawer query, filter property
        # drawerGroup = _.findWhere(_drawer.json.data, {name: self.state.group})
        # drawerGroup.isOpen = true;
        return self

      

      updateCounts: (challenges, moments)->
        # set counts for drawerGroups from syncService
        self.state.counts = self.state.counts || {}
        updateList = [
          {groupName:'findhappi', model:'challenge'}
          {groupName:'gethappi', model:'moment'}
          {groupName:'timeline', model:'photo'}
        ]
        throw "Error: syncService not set in Drawer" if !_drawer.syncService? 
        _.each updateList, (o)->
          models = _drawer.syncService.get(o.model)
          self.state.counts[o.groupName] = _.values( models ).length
          # additional parsing
          switch o.model
            when "challenge"
              self.state.counts = _.extend self.state.counts, _drawer.getCounts models

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
