return if !angular? 

angular.module( 
	'appHappi'
).service( 'notifyService', [
	'$timeout'
	($timeout)->
		this.alerts = {}
		this.timeouts = []
		this.alert = (msg=null, type='info', timeout=3000)->
			if msg? 
				now = new Date().getTime()
				this.alerts[now] = {msg: msg, type:type, key:now} if msg?
				this.timeouts.push({key: now, value: timeout})
			else 
				# start timeouts on ng-repeat
				this.timerStart()
			return this.alerts 
		this.close = (key)->
			delete this.alerts[key]
		this.timerStart = ()->
			_.each this.timeouts, (o)=>
				$timeout (()=>
					delete this.alerts[o.key]
					), o.value
			this.timeouts = []	
		return	
]
).factory( 'actionService', [ 
	'drawerService'
	'deckService'
	'notifyService'
	'$location'
	(drawerService, deckService, notify, $location)->
		self = {

			drawerItemClick : (groupName, options)->
				scope = this
				options.group = groupName
				options.item = options.name
				return drawerService.itemClick options, ()->
					if options.name=='shuffle'
						scope.deck = deckService.setupDeck scope.cards, scope.deck, drawerService.state
					$location.path(options.route) if options.route != $location.path()	
					scope.deckCards = deckService.deckCards deckService.shuffleDeck scope.deck 
					scope.deck.index = 0	
					# return scope.card = deckService.nextCard(scope.cards, scope.deck, drawerService.state) 

			swipe : ( target, ev, index)->
				# target = ev.currentTarget
				dir = ev.gesture.direction
				action = [target, dir].join('-')
				scope = this
				card = scope.card

				notify.alert [ev.type, target, dir].join('-'), null, 1000
				switch target
					when 'thumb-img'
						# ?? use status='edit'
						throw "Error: removePhoto(), $index was NOT passed to swipe" if !index?
						sliced = self.removePhoto.call(scope, card, ev.currentTarget.id, index)
						ev.gesture.preventDefault()
						ev.stopImmediatePropagation()
						return sliced	

				switch action
					when 'filmstrip-left'
						self.nextCard.call(scope)
						ev.gesture.preventDefault()
					when 'filmstrip-right'
						self.nextCard.call(scope, 'prev')
						ev.gesture.preventDefault()
					when 'card-down'
						card.isCardExpanded = true	
						ev.gesture.preventDefault()
					when 'card-up'
						card.isCardExpanded = false
						ev.gesture.preventDefault()

			removePhoto : (card, id, i)->
				try
					throw "removePhoto() where card.status != active" if card.status!='active'
					model = card.type 
					switch model 
						when "moment"
							momentIndex = i
							momentPhotos = card.photos
						when "challenge"	
							throw "removePhoto() id mismatch" if id != card.challengePhotos[i].id.toString()
							moment = _.findWhere card.moments, {status:'active'}
							momentPhotos = moment.photos
							momentIndex = momentPhotos.length - (i+1)	# reversed array
							check2 = card.challengePhotos.splice(i, 1)
						else throw "invalid card type"

					throw "removePhoto() id mismatch" if id != momentPhotos[momentIndex].id.toString()
					return check1 = momentPhotos.splice(momentIndex, 1)
				catch error
					notify.alert error, 'warning', 10000
					return false

			setFilmstripPos : ( w=320 )->
				scope = this
				if !deckService.validateDeck(scope.cards, scope.deck, drawerService.state)
					scope.deck = deckService.setupDeck(scope.cards, scope.deck, drawerService.state)
				# Modernizr: cssanimations csstransforms csstranisitions	
				if window.Modernizr.touch
					style = {
						width: scope.deck.cards.length * w + 'px'
						left: -1 * scope.deck.index * w + 'px'
					}
				else 
					translateCss = 'translate(' + -1 * scope.deck.index * w + 'px, 0)'
					style = {
						width: scope.deck.cards.length * w + 'px'
						'transform': translateCss
						'-webkit-transform': translateCss
						'-ms-transform': translateCss
					}
				return style

			nextCard : ( dir='next')->
				scope = this
				options = _.clone drawerService.state
				if dir == 'prev'
					options.increment = -1
				return scope.card = deckService.nextCard(scope.cards, scope.deck, options)

			shuffleDeck : ()->
				scope = this
				scope.deck = deckService.setupDeck(scope.cards, scope.deck, drawerService.state)
				deckService.shuffleDeck( scope.deck )
				return deckService.nextCard(scope.cards, scope.deck, drawerService.state)	
		}
		return self
]
).controller( 'ChallengeCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'$location'
	'drawerService'
	'syncService'
	'deckService'
	'cameraService'
	'notifyService'
	'actionService'
	'appConfig'
	($scope, $filter, $q, $route, $location, drawer, syncService, deck, cameraService, notify, actionService, CFG)->

		#
		# Controller: ChallengeCtrl
		#

		# attributes
		$scope.$route = $route
		$scope.$location = $location
		$scope.cameraService = cameraService
		$scope.notify = notify
		_.extend $scope, actionService 		# add methods to scope

		# card + deck iterator
		$scope.deck = {}
		$scope.cards = []
		$scope.card = null      # current challenge
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {  
			group: 'findhappi'  
			item: 'current'
		}

		# reset for testing
		syncService.clearAll() if $scope.$route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer']) 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) # || state.group !='findhappi'
				drawerItemOptions = drawer.getDrawerItem('findhappi', 'current')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

			o.moment = $filter('filter')(o.moment, {status:"!pass"})
			$scope.moments = o.moment
			# syncService.set('moment', $scope.moments)

			if $route.current.params.id?
				# filter challenges by id
				if _.isNaN parseInt $route.current.params.id 
					f = {"name": $route.current.params.id}
				else f = {"id": $route.current.params.id}
				$scope.challenges = $filter('filter')(o.challenge, f)
			else $scope.challenges = o.challenge 
			# syncService.set('challenge', $scope.challenges)

			# get nextCard
			$scope.cards = _.values $scope.challenges
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)


			# redirect to all if no active challenge
			if drawer.state.group=='findhappi' &&
          drawer.state.item=='current' &&
          drawer.state.counts['active'] == 0
        $scope.drawerShowAll()
      else   
      	return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)


		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			return $scope.drawerItemClick 'findhappi', options


		$scope.challenge_getPhoto = ()->
			saveToMoment = (uri)->
				# $scope.cameraRollSrc = uri
				
				moment = _.findWhere $scope.card.moments, {status:'active'}

				if moment? && _.isArray moment.photos
					photo = {
						id: `new Date().getTime()`
						src: uri
					}
					# update moment
					moment.photos.push photo
					moment.stats.count = moment.photos.length
					moment.stats.viewed += 1
					moment.stale = moment.modified = new Date().toJSON()

					notify.alert "Saved to moment.photos: count= " + moment.photos.length + ", last=" + moment.photos[moment.photos.length-1].src , 'success', 5000 
					$scope.card.challengePhotos = $filter('reverse')(moment.photos)  	# for display of challenge only 'active'
					syncService.set('moment', moment)

				return


			if !navigator.camera
				dfd = $q.defer()
				dfd.promise.then saveToMoment
				uri = CFG.testPics.shift()
				dfd.resolve(uri)
				CFG.testPics.push(uri)
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )

		$scope.challenge_pass = ()->
			if drawer.state.filter.status=='active' && $scope.card
				# set status=pass if current card, then show all challenges
				c = $scope.card
				stale = [c]
				_.each c.moments, (m)-> 
					if m.status=='active'
						c.status=m.status='working'
						c.stale = m.stale = c.modified = m.modified = new Date().toJSON()
						stale.push m

				c.status='pass' if c.status=='active'		

				syncService.set('challenge', stale)
				syncService.set('moment', stale)
				drawer.updateCounts( $scope.challenges, $scope.moments )	
				$scope.card.challengePhotos = null;
				return $scope.drawerShowAll()
			return $scope.nextCard()


		$scope.challenge_done = ()->
			throw "warning: challenge.status != active in $scope.challenge_done()" if $scope.card.status != 'active'

			c = $scope.card
			stale = [c]
			_.each c.moments, (m)-> 
				if m.status=='active'
					c.status = m.status='complete'
					c.stale = m.stale = c.modified = m.modified = new Date().toJSON()
					stale.push(m)
					m.stats.completedIn += 123						# fix this
					m.stats.viewed += 1
					c.stats.completions.push m.stats.completedIn
			notify.danger "ERROR: challenge saved without matching moment" if !c.stale?
			syncService.set('challenge', stale)
			syncService.set('moment', stale)
			drawer.updateCounts( $scope.challenges, $scope.moments )

			# clear 'active' challenge photos
			$scope.card.challengePhotos = null;

			# goto moment
			return $scope.drawerItemClick 'gethappi', {name:'mostRecent'}

		$scope.challenge_open = ()->
			# TODO: check for existing 'active' moment by challenge.moments and set to 'pass'/'working'
			c = $scope.card
			stale = [c]

			_.each c.moments, (m)-> 
				if m.status=='working'
					c.status = m.status='active'
					c.stale = m.stale = c.modified = m.modified = new Date().toJSON()
					stale.push m
					moment = m

			if c.status !='active' && c.moments.length
					# working moment not found, just activate the first moment
					m = c.moments[0]
					c.status = m.status ='active'
					c.stale = m.stale = c.modified = m.modified = new Date().toJSON()
					stale.push m
					moment = m

			$scope.card.challengePhotos = $filter('reverse')(moment.photos)  	# for display of challenge only 'active'
			syncService.set('challenge', stale)
			syncService.set('moment', stale)		
			drawer.updateCounts( $scope.challenges, $scope.moments )
			return $scope.drawerItemClick 'findhappi', {name:'current'}

		# TODO: change to accept
		$scope.challenge_new = ()->
			# TODO: check for existing 'active' and set to 'pass'/'working'
			c = $scope.card
			c.stats.accept += 1
			now = new Date()
			stale = [c]
			m = {
				# id: _.reduce $scope.moments, (last, m)->return if last.id > m.id then last.id else m.id
				id: new Date().getTime()
				type: 'moment'
				userId: CFG.userId
				challengeId: c.id
				stats: 
					count: 0
					completedIn: 0
					viewed: 0
					rating:
						moment: null
						challenge: null
				status: 'active'
				created: now
				modified: now
				stale: now
				photos: []
			}
			c.status = m.status = 'active'
			c.stale = m.stale = c.modified = m.modified = now
			stale.push m
			c.moments.push(m)
			$scope.moments[m.id] = m
			$scope.cards.push(m)

			syncService.set('challenge', stale)
			syncService.set('moment', stale)
			drawer.updateCounts( $scope.challenges, $scope.moments )
			$scope.card.challengePhotos = m.photos  	# for display of challenge only 'active'
			return $scope.drawerItemClick 'findhappi', {name:'current'}

		$scope.challenge_later = ()->
			# set current challenge, then put app to sleep
			# on wake, should open to current challenge
			notify.alert "Later clicked at "+new Date().getTime(), "success", 5000
			return $scope.challege	

		return;
	]
).controller( 'MomentCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'$location'
	'drawerService'
	'syncService'
	'deckService'
	'cameraService'
	'notifyService'
	'actionService'
	'appConfig'
	($scope, $filter, $q, $route, $location, drawer, syncService, deck, cameraService, notify, actionService, CFG)->
		#
		# Controller: MomentCtrl
		#

		# attributes
		$scope.$route = $route
		$scope.$location = $location
		$scope.cameraService = cameraService
		$scope.notify = notify
		_.extend $scope, actionService 		# add methods to scope

		# card + deck iterator
		$scope.deck = {}
		$scope.cards = []
		$scope.card = null      # current moment
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {
			group: 'gethappi'
			item: 'mostRecent'
			filter: null
			query: ''
			orderBy: 'modified' 
		}
		
		# reset for testing
		syncService.clearAll() if $scope.$route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer']) 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='gethappi'
				drawerItemOptions = drawer.getDrawerItem('gethappi', 'mostRecent')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

			if $route.current.params.id?
				# filter moments by id
				if _.isNaN parseInt $route.current.params.id 
					f = {"name": $route.current.params.id}
				else f = {"id": $route.current.params.id}
				$scope.moment = $filter('filter')(_.values( o.moment ), f)
			else 
				o.moment = $filter('filter')(o.moment, {status:"!pass"})
				$scope.moments = o.moment
			# syncService.set('moment', $scope.moments)
			$scope.challenges = o.challenge 
			# syncService.set('challenge', $scope.challenges)

			# get nextCard
			$scope.cards = if  $scope.moments? then _.values $scope.moments else $scope.moment
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			$scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)
			# for use with ng-repeat, card in deckCards
			# $scope.deckCards = deck.deckCards($scope.deck)

			$scope.set_editMode($scope.card) if $route.current.params.id? && $scope.card.status=='active'
			return      

		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			return $scope.drawerItemClick 'findhappi', options

		$scope.moment_cancel = (id)->
			m = _.findWhere $scope.cards, {id: id}
			notify.alert "Warning: no undo[photos] NOT found", "warning" if !m.undo['photos']?

			m.photos = m.undo['photos']
			m.stale = m.modified = new Date().toJSON()

			delete m.undo['photos']
			m.status = 'complete'
			syncService.set('moment', m)
			drawer.updateCounts( null, $scope.moments )

			$location.path drawer.state.route 

		$scope.moment_done = (id)->
			m = _.findWhere $scope.cards, {id: id}
			throw "warning: moment.status != active in $scope.moment_done()" if m.status != 'active'
			m.stats.count = m.photos.length
			m.stats.completedIn += 123						# fix this
			m.stats.viewed += 1
			m.stale = m.modified = new Date().toJSON()
			m.status = "complete"
			delete m.undo['photos']
			syncService.set('moment', m)
			drawer.updateCounts( null, $scope.moments )

			$location.path drawer.state.route 

		$scope.moment_edit = (id)->
			m = _.findWhere $scope.cards, {id: id}
			m.status = "active"
			m.stale = new Date().toJSON()
			syncService.set('moment', m)
			drawer.updateCounts( null, $scope.moments )
			# nav to new route, then open in editMode
			$location.path editRroute = drawer.state.route + '/' + id

		$scope.set_editMode = (m)->
			# ???: should I set challenge to 'active'
			m.undo = {} if !m.undo?
			m.undo['photos'] = _.cloneDeep m.photos  # save undo info
			$scope.card.isCardExpanded = true

		$scope.moment_getPhoto = (id)->
			moment = _.findWhere $scope.cards, {id: id}

			saveToMoment = (uri)->
				# $scope.cameraRollSrc = uri

				if moment? && _.isArray moment.photos
					photo = {
						id: `new Date().getTime()`
						src: uri
					}
					# update moment
					moment.photos.push photo
					moment.stats.count = moment.photos.length
					moment.stale = moment.modified = new Date().toJSON()

					notify.alert "Saved to moment.photos: count= " + moment.photos.length + ", last=" + moment.photos[moment.photos.length-1].src , 'success', 5000 
					syncService.set('moment', moment)
				return


			if !navigator.camera
				dfd = $q.defer()
				dfd.promise.then saveToMoment
				uri = CFG.testPics.shift()
				CFG.testPics.push(uri)
				dfd.resolve(uri)
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )			


		return;
	]
)


