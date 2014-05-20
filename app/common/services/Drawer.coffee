return if !angular? 

angular.module( 
  'appHappi'
).directive('onOffSwitch', ()->
  link = (scope, element, attrs)->
    scope.toggle = (e)->
      scope.myNgModel = !scope.myNgModel
      e.preventDefault()
      e.stopImmediatePropagation() if scope.myNgModel == true
    return

  return {
    template: """
    <label class="switch-light well" ng-click='toggle($event)'>
      <input type="checkbox" ng-checked="myNgModel" >
      <span>
        <span>Off</span>
        <span>On</span>
      </span>
      <a class="btn btn-primary"></a>
    </label>
    """
    restrict: 'AE'
    scope: 
      myNgModel: '='     # this is NOT working, scope.mirror is not set
    link: link 
  }
).directive('drawerLastScroll', [ 
  'drawerService' 
  '$window'
  (CFG, drawerService, $window)->
    return {
      restrict: 'A'
      link: (scope, element, attrs)->
        if window.Modernizr.touch 
          # drawer will add a delay to the last scroll before closing with touch devices
          angular.element($window).bind 'scroll', _.throttle ()->
              if drawerService.isDrawerOpen()
                drawerService.scrolling = now = new Date().getTime()
            , 200
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
      slider: null    
      getSlider : ()->
        return _drawer.slider if _drawer.slider && _drawer.slider.length
        for check in ['frame', 'view']
          slider = angular.element(document.getElementById(check))
          break if slider.hasClass('slide')
        return _drawer.slider = if slider.hasClass('slide') then slider else angular.element()

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

      setScrollHeight: (fullHeight)->
        drawerWrap = angular.element(document.getElementById('drawer'))
        return if !drawerWrap.hasClass('collapsable')

        if fullHeight
          drawerWrap.removeClass('collapsed')
        else drawerWrap.addClass('collapsed')


    }

    self = {
      scrolling: 0          # unixtime of last scroll event
      isDrawerOpen: ()->
        return _drawer.getSlider().hasClass('slide-over')

      toggleDrawerOpen: (e, open)->
        if e?.target
          $target = angular.element( e.target )
          $target.addClass('glow')
          setTimeout( (()->$target.removeClass 'glow')
              , 500)
          
        # add .slide class to activate
        slider = _drawer.getSlider()
        if !open?
          slider.toggleClass('slide-over')
        else if open==true
          slider.addClass('slide-over')
        else if open==false
           slider.removeClass('slide-over')
        else throw "ERROR: invalid value"

        fullHeight = slider.hasClass('slide-over')
        _drawer.setScrollHeight(fullHeight)

        window.scrollTo(0, 0)
        return

      state: {}           # init with $scope.initalDrawerState if !drawer.state?
      setSyncService: (syncService)->
        _drawer.syncService = syncService

      isDrawerItemActive: (id)->
        return id == self.state?['activeItemId']

      animateClose: (delay=750)->
        # TODO: we really just want to add to delay on touchstart
        # if window.Modernizr.touch 
        #   sinceLastScroll = new Date().getTime() - self.scrolling 
        #   delay += 2000 if sinceLastScroll < 2000
        $timeout ()->
            self.toggleDrawerOpen(null, false)
          , delay  

      drawerItemClick : (e, callback)->
        # set active
        if _.isString(e)
          target = {id: e} 
        else if (e.currentTarget?)
          # BUG: drawer closing too soon on iOS6 after touchend/scroll
          # TODO: how do we discard ng-click if we are scrolling drawer by touchmove/touchend
          # notify.alert("drawerItemClick, event.type="+e.type)
          target = e.currentTarget 
        else throw "Error: expecting string or Event"


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
          controllerScope = angular.element(document.getElementById("view-frame")).scope()
          # verify deck
          return if !controllerScope?.deck?

          deck = controllerScope.$rootScope.deck   
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
              # CFG.debug = !CFG.debug    # toggle in on-off-switch
              null
            when 'drawer'
              _drawer.syncService?.clearDrawer()  
              return $location.path('/')
            when 'reload'
              return window.location.reload();
            # when 'reminder' # do nothing


        sameGroup = self.state.group == options.group
        # get drawerItemGroup options
        drawerItemOptions = self.getDrawerItem(options.group, options.item)
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
          drawerItemOptions = _.findWhere(drawerGroup.items, {item: itemName})
          drawerItemOptions['group'] = drawerGroup.name
          return drawerItemOptions
        catch
          return false
         
      init: (challenges, moments, drawerItemState)->
        # drawer = $rootScope.drawer
        _.extend(self.state, drawerItemState) if drawerItemState?

        # update syncService
        self.updateCounts(challenges, moments)
        self.state.activeItemId = ["drawer", self.state.group, self.state.name || self.state.item ].join('-')
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

      # .visible-xs uses collapsable drawer, .visible-sm keeps drawer visible
      setCollapsable: ()->
        collapsable = !!document.getElementById("sidebar-open-btn").offsetWidth
        drawerWrap = angular.element(document.getElementById('drawer'))
        # .collapse sets overflow: hidden to minimize height of drawer when hidden
        if collapsable 
          if drawerWrap.hasClass('collapsed')
            return
          else
            drawerWrap.addClass('collapsable collapsed').removeClass('slide-over')
        else drawerWrap.removeClass('collapsable collapsed').addClass('slide-over')
        return


      load: (url)->
        url = _drawer.url if _.isEmpty(url)
        console.log "*** drawer.load()"  
        _drawer.ready = $http.get(url).success (data, status, headers, config)->
          _drawer.json = data
          # localStorageService.set('drawer', _drawer.json )
          # console.log "*** drawer ready"
          angular.element($window).bind 'resize', _.throttle self.setCollapsable
            , 200 
          self.setCollapsable() # call after drawer is ready
          return 
        # console.log _drawer.ready  
        return _drawer.ready  

      json: (data)->
        _drawer.json = data if data?
        return _drawer.json 

      ready: (drawer)->   # should be a promise
        return "Usage: self.load(url); self.ready.then();"

      # fake ng-route using ng-includes
      # @return {controller, action, view, params:[], drawerState:{}}
      # TODO: move drawer.load into syncService and add syncService as dependency
      getRoute : (path)->
        path = $location.path() if !path?  
        # path = '/getting-started/check' if !path?
        pathparts = path.split('/')
        route = {
          path: path
          controller: pathparts[1]
          action: if pathparts.length>2 then pathparts[2] else ''
          view: null
          params: pathparts[3..] 
          drawerState: localStorageService.get('drawerState')
        }

        _changeLocation = (url, force)->
          $location.path(url)
          $scope = $scope || angular.element(document).scope()
          if $scope
            $scope.apply() if (force || !$scope.$$phase)
          else   
            window.location.href = $location.absUrl()
            window.location.reload()

        console.warn "Deprecate drawer.getRoute????"
        switch route.controller
          when 'challenges', 'challenge'
            route.controller = 'ChallengeCtrl'
            route.view = '/views/challenge/_challenges.html'
            route.drawerState = self.getDrawerItem('findhappi', 'current') if _.isEmpty(route.drawerState) || route.drawerState.group !='findhappi'
          when 'moments', 'moment'
            route.controller = 'MomentCtrl'
            route.view = '/views/moment/_moments.html'
            route.drawerState = self.getDrawerItem('gethappi', 'mostrecent') if _.isEmpty(route.drawerState) || route.drawerState.group !='gethappi'
          when 'shared_moments', 'shared_moment'
            route.controller = 'SharedMomentCtrl'
            route.view = '/views/shared_moment/_moments.html'
            route.drawerState = self.getDrawerItem('gethappi', 'shared') if _.isEmpty(route.drawerState) || route.drawerState.group !='gethappi'  
          when 'timeline'
            route.controller = 'TimelineCtrl'
            route.view = '/views/challenge/_challenges.html'
            route.drawerState = self.getDrawerItem('timeline', 'toprated') if _.isEmpty(route.drawerState) || route.drawerState.group !='timeline'
          when 'settings'
            route.controller = 'SettingsCtrl'
            switch path
              when '/settings/reminders'
                route.view = '/views/settings/_reminders.html'
                route.drawerState = self.getDrawerItem('settings', 'reminder') if _.isEmpty(route.drawerState) || route.drawerState.group !='settings'
              else 
                _changeLocation('/getting-started/check', true)
          when 'getting-started', 'about'
            route.controller = 'SettingsCtrl'
            # TODO: refactor /settings path in drawer.json
            switch path
              when '/getting-started', '/getting-started/check'
                route.view = '/views/settings/_gettingstarted.html'
                route.drawerState = self.getDrawerItem('settings', 'gettingstarted')
              when '/about'  
                route.view = '/views/settings/_about.html'
                route.drawerState = self.getDrawerItem('settings', 'about')
              else 
                _changeLocation('/getting-started/check', true)
          else
            _changeLocation('/getting-started/check', true)
        return route
      # end getRoute()
    }
    return self
  ]
).controller( 'DrawerCtrl', [
  '$scope'
  '$rootScope'
  '$q'
  'appConfig'
  'drawerService'
  'helpService'
  'notifyService'
  'actionService'
  'syncService'
  ($scope, $rootScope, $q, CFG, drawer, helpService, notify, actionService, syncService )->
    #
    # Controller: DrawerCtrl
    #   - use $rootScope to share common services with 'view' controllers
    #
    # CFG.$curtain.find('h3').html('Loading Menus...')

    # attributes
    $rootScope.CFG = CFG
    $rootScope.notify = window.notify = notify
    $rootScope.drawer = drawer
    $rootScope.helpService = helpService
    $rootScope.route = {
      # controller: 'SettingsCtrl'
      # view: 'views/settings/_about.html'
    }

    $scope.CFG = $rootScope.CFG         # used by on-off-switch
    $scope.route = $rootScope.route
    $scope.drawer = $rootScope.drawer
    $scope.helpService = helpService
    $scope.deck = null                  # refresh deck.cards() on filter
    # TODO: refactor actionService for exports
    $scope.shuffleDeck = actionService.shuffleDeck

    # init
    notify.clearMessages()

    # reset for testing
    syncService.clearAll() if route?.params[0] == 'reset'
    # initLocalStorage ONCE in DrawerCtrl and make available for all other controllers
    syncService.initLocalStorage()
    $q.all( syncService.promises ).then (o)->
      # rebuild FKs
      syncService.setForeignKeys(o.challenge, o.moment)
      # set defaultState based on "controller" & use ng-include instead of ng-route
      # TODO: move drawer.load into syncService and add syncService as dependency to drawerService
      _.extend( $rootScope.route, drawer.getRoute() )
      drawer.init o.challenge, o.moment, $rootScope.route.drawerState
      return 
    # done DrawerCtrl
    return
])    
