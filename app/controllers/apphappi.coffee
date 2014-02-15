return if !angular? 

angular.module( 
	'appHappi'
).service( 'notifyService', [
	'$timeout'
	'appConfig'
	($timeout, appConfig)->
		this.alerts = {}
		this.timeouts = []
		this.alert = (msg=null, type='info', timeout=3000)->
			return if !appConfig.debug || appConfig.debug=='off'
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
	'syncService'
	'notifyService'
	'$location'
	(drawerService, deckService, syncService, notify, $location)->
		self = {

			exports: [
				# 'setCardStatus'
				'persistRating'
				'drawerItemClick'
				'removePhoto'
				'shuffleDeck'
				# 'swipe'
			]

			_getMoments : (c)->
				return [] if c.type != 'challenge'
				return _.map c.momentIds, (id)->
					return syncService.get('moment', id)

			_getPhotos : (m)->
				return [] if m.type != 'moment'
				return _.map m.photoIds, (id)->
					return syncService.get('photo', id)

			# do housekeeping when changing status of challenge, moment
			setCardStatus : (card, status, now)->
				now = new Date() if !now?
				card = [card] if _.isPlainObject(card) 
				_.each card, (o)->
					oldStatus = o.status
					o.status = status
					o.stale = o.modified = now.toJSON() 
					# update drawer counts
					isDrawerStale = false
					if oldStatus != status && o.type == 'challenge'
						drawerService.state.counts[oldStatus] -= 1 if drawerService.state.counts[oldStatus]?
						drawerService.state.counts[status] += 1 if drawerService.state.counts[status]?
						isDrawerStale = true
					if o.type=='moment' && oldStatus==null
						drawerService.state.counts['gethappi'] += 1
						isDrawerStale = true
					return
				syncService.set('drawerState') if isDrawerStale?


			persistRating : (ev, i)->
				$target = angular.element(ev.currentTarget)
				now = new Date().toJSON()
				switch $target.attr('rating-type')
					when "photo"
						switch this.card.type
							when "moment"
								p = this.card.photos[i]
								this.card.stale = this.card.modified = now
								syncService.set('moment', this.card)
							when "challenge"
								p = this.moment.photos[i]
								this.moment.stale = this.card.modified = now
								syncService.set('moment', this.moment)
						p.stale = now
						syncService.set('photo', p)

					when "moment"
						this.card.stale = this.card.modified = now
						syncService.set('moment', this.card)
					when "challenge"
						this.card.stale = this.card.modified = now

						syncService.set('moment', this.card)
						# also update challenge
						c = this.card.challenge
						c.stats.ratings.push(this.card.stats.rating.challenge)
						c.stale = true	
						syncService.set('challenge', this.card.challenge)

			drawerItemClick : (e, groupName, options)->
				# set active
				scope = this
				target = e.currentTarget || {id: e}

				[type, group, item] = target.id?.split('-') || []
				if type == 'drawer'
					options = {
						group: group
						item: item
					}
				else 
					# for drawerShowAll
					options = {item: options} if _.isString(options)
					options.item = options.name if options?.name?
					options.group = groupName
				
				scope.deck.index(0)
				return drawerService.itemClick options, (route)->
					# drawerService.state is updated with new filter/query/search, setupDeck
					scope.deck.cards('refresh') if !scope.deck.validateDeck()
					scope.deck.shuffle() if options.name=='shuffle' || options.shuffle
					$location.path(route) if route? 

			XXXswipe : ( target, ev, index)->
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
							m = card
							momentIndex = i
						when "challenge"	
							throw "removePhoto() id mismatch" if id != card.challengePhotos[i].id
							m = _.findWhere self._getMoments(card), {status:'active'}
							momentIndex = m.photoIds.length - (i+1)	# reversed array
							check2 = card.challengePhotos.splice(i, 1)[0]
						else throw "invalid card type"

					check1 = m.photoIds.splice(momentIndex, 1)
					if m.photos?
						check1b = m.photos && m.photos.splice(momentIndex, 1)
						throw "removePhoto() id mismatch" if id != check1 != check1b.id
					throw "removePhoto() challengePhotos id mismatch" if check2 && id != check2.id
				catch error
					notify.alert error, 'warning', 10000
					return false

			shuffleDeck : ()->
				scope = this
				scope.deck.cards('refresh') if !scope.deck.validateDeck()
				scope.deck.shuffle()
				drawerService.animateClose(500)
				return 
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
	($scope, $filter, $q, $route, $location, drawer, syncService, deckService, cameraService, notify, actionService, CFG)->

		#
		# Controller: ChallengeCtrl
		#
		CFG.$curtain.find('h3').html('Loading Challenges...')

		_challenges = _moments = _cards = null

		# attributes
		# $scope.$route = $route
		# $scope.$location = $location
		# $scope.cameraService = cameraService
		$scope.notify = window.notify = notify
		$scope.CFG = CFG
		$scope.carousel = {index:0}

		_.each actionService.exports, (key)->
			$scope[key] = actionService[key] 

		$scope.drawer = drawer;
		$scope.initialDrawerState = {  
			group: 'findhappi'  
			item: 'current'
		}


		# reset for testing
		syncService.clearAll() if $route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer', 'photo']) 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='findhappi'
				drawerItemOptions = drawer.getDrawerItem('findhappi', 'current')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

			if $route.current.params.id?
				# filter challenges by id
				if _.isNaN parseInt $route.current.params.id 
					f = {"name": $route.current.params.id}
				else f = {"id": $route.current.params.id}
				_challenges = $filter('filter')(o.challenge, f)
			else 
				_challenges = o.challenge 

			_cards = _.values _challenges
			$scope.deck = deckService.setupDeck(_cards, _.extend( {control: $scope.carousel}, drawer.state ) )

			# redirect to all if no active challenge
			if (drawer.state.group=='findhappi' &&
							drawer.state.item=='current' &&
							drawer.state.counts['active'] == 0)
				$scope.drawerShowAll()

			# hide loading
			CFG.$curtain.addClass 'hidden'
			return

		# deactivate any active challenges before activating a new one
		_deactivateChallenges = (active)->
			if active?
				active = [active] if _.isPlainObject(active)
				active = _.where active, {type: 'challenge'}
			else 	
				active = _.where $scope.deck.allCards, {status:'active'}
			stale = []
			_.each active, (c)->
				stale.push c
				_.each actionService._getMoments( c ), (m)-> 
					if m.status=='active'
						stale.push m
			actionService.setCardStatus(stale, 'working')
			return stale				
		

		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			options.shuffle = true
			return $scope.drawerItemClick 'drawer-findhappi-all', 'findhappi', options


		$scope.challenge_getPhoto = ($event)->
			c = $scope.deck.topCard()
			m = $scope.moment || _.findWhere actionService._getMoments( c ), {status:'active'} 

			# @params p object, p.id, p.src
			saveToMoment = (p)->
				now = new Date()
				if m?
					photo = _.defaults p, {
						type: 'photo'
						stale: now.toJSON()
					}
					# update moment
					syncService.set('photo', photo)
					m.photoIds.push photo.id
					m.stats.count = m.photoIds.length
					m.stats.viewed += 1
					m.photos = actionService._getPhotos m
					actionService.setCardStatus(m, 'active', now)

					# notify.alert "Saved to moment.photos: count= " + m.photos.length + ", last=" + m.photos[m.photos.length-1].src , 'success', 5000 
					$scope.deck.topCard().challengePhotos = $filter('reverse')(m.photos)  	# for display of challenge only 'active'
					syncService.set('moment', m)
				return


			if !navigator.camera
				promise = cameraService.getPicture($event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )
				return true	# continue to input[type=file] handler
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary, $event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )

		$scope.challenge_pass = ($index)->
			if drawer.state.filter?.status? =='active' && (c = $scope.deck.topCard())
				# set status=pass if current card, then show all challenges
				stale =_deactivateChallenges(c)
				actionService.setCardStatus(c, 'pass')	if c.momentIds.length==0 
				syncService.set('challenge', stale)
				syncService.set('moment', stale)
				# drawer.updateCounts( _challenges )	
				c.challengePhotos = null;
				$scope.moment = null
				return $scope.drawerShowAll()
			return $scope.deck.nextCard()  # $scope.carousel.index++


		$scope.challenge_done = ()->
			c = $scope.deck.topCard()
			now = new Date()
			m = $scope.moment || _.findWhere  actionService._getMoments( c ), {status:'active'} 
			throw "warning: challenge.status != active in $scope.challenge_done()" if c.status != 'active'
			throw "warning: moment.status != active in $scope.challenge_done()" if m.status != 'active'

			stale = [c, m]
			m.stats.completedIn += 123						# fix this
			m.stats.viewed += 1
			c.stats.completions.push m.stats.completedIn
			c.challengePhotos = null;

			actionService.setCardStatus(stale, 'complete', now)
			syncService.set('challenge', stale)
			syncService.set('moment', stale)
			# drawer.updateCounts( _challenges )

			# clear 'active' challenge photos
			$scope.moment = null

			# goto moment

			return $scope.drawerItemClick 'gethappi', {item:'mostRecent'}

		$scope.challenge_open = ()->
			deactivated = _deactivateChallenges()

			c = $scope.deck.topCard()
			stale = [c]
			now = new Date()

			m = $scope.moment || _.findWhere  actionService._getMoments( c ), {status:'working'} 

			if !m? && c.momentIds.length
					# working moment not found, just activate the first moment
					m = actionService._getMoments( c )[0]
			if !m?		
				throw "WARNING: open challenge without moment"
			stale.push m
			m.photos = actionService._getPhotos m
			moment = m
			$scope.moment = moment
			c.challengePhotos = $filter('reverse')(moment.photos)  	# for display of challenge only 'active'
			actionService.setCardStatus(stale, 'active', now)
			stale = stale.concat(deactivated)
			syncService.set('challenge', stale)
			syncService.set('moment', stale)		
			# drawer.updateCounts( _challenges)
			return $scope.drawerItemClick 'findhappi', {item:'current'}


		# TODO: change to accept
		$scope.challenge_new_moment = ()->
			deactivated = _deactivateChallenges()

			c = $scope.deck.topCard()
			c.stats.accept += 1
			now = new Date()
			stale = [c]
			m = {
				id: now.getTime()+'-moment'
				type: 'moment'
				userId: CFG.userId
				challengeId: c.id
				stats: 
					count: 0
					completedIn: 0
					viewed: 0
					rating:
						moment: 0
						challenge: 0
				status: null
				created: now
				modified: now
				stale: now
				photoIds: []
				photos: []
			}

			stale.push m
			c.momentIds.push(m.id)
			$scope.moment = m
			c.challengePhotos = []  	# for display of challenge only 'active'

			actionService.setCardStatus(stale, 'active', now)
			stale = stale.concat(deactivated)
			syncService.set('challenge', stale)
			syncService.set('moment', stale)
			# drawer.updateCounts( _challenges, syncService.localData['moment'] )
			
			return $scope.drawerItemClick 'findhappi', {item:'current'}

		$scope.challenge_later = ()->
			# set current challenge, then put app to sleep
			# on wake, should open to current challenge
			notify.alert "Later clicked at "+new Date().toJSON(), "success", 5000
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
	($scope, $filter, $q, $route, $location, drawer, syncService, deckService, cameraService, notify, actionService, CFG)->
		#
		# Controller: MomentCtrl
		#
		CFG.$curtain.find('h3').html('Loading Moments...')

		_challenges = _moments = _cards = null

		# attributes
		# $scope.$route = $route
		# $scope.$location = $location
		# $scope.cameraService = cameraService
		$scope.notify = window.notify = notify
		$scope.CFG = CFG
		$scope.carousel = {index:0}
		_.each actionService.exports, (key)->
			$scope[key] = actionService[key] 

		$scope.drawer = drawer;
		$scope.initialDrawerState = {
			group: 'gethappi'
			item: 'mostRecent'
		}
		
		# reset for testing
		syncService.clearAll() if $route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer', 'photo']) 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='gethappi'
				drawerItemOptions = drawer.getDrawerItem('gethappi', 'mostRecent')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

			# wrap challenges in a Deck
			_challenges = deckService.setupDeck(o.challenge)

			if $route.current.params.id?
				# filter moments by id
				if _.isNaN parseInt $route.current.params.id 
					f = {"name": $route.current.params.id}
				else f = {"id": $route.current.params.id}
				_moments = $filter('filter')(_.values( o.moment ), f)
			else 
				o.moment = $filter('filter')(o.moment, {status:"!pass"})
				_moments = o.moment



			# get nextCard
			_cards = _.values _moments 
			$scope.deck = deckService.setupDeck(_cards, _.extend( {control: $scope.carousel}, drawer.state ) )

			m = $scope.deck.topCard()
			if $route.current.params.id? && m?.status=='active'
				$scope.set_editMode(m) 


			# hide loading
			CFG.$curtain.addClass 'hidden'
			return      

		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			return $scope.drawerItemClick 'drawer-findhappi-all', 'findhappi', options

		$scope.moment_cancel = (id)->
			m = $scope.deck.topCard()
			throw "ERROR: moment.id mismatch" if m.id != id 
			notify.alert "Warning: no undo[photos] NOT found", "warning" if !m.undo['photos']?

			m.photos = m.undo['photos']
			delete m.undo['photos']

			actionService.setCardStatus(m, 'complete')	
			syncService.set('moment', m)
			# drawer.updateCounts( null, _moments )

			$location.path drawer.state.route 

		$scope.moment_done = (id)->
			m = $scope.deck.topCard()
			throw "ERROR: moment.id mismatch" if m.id != id 
			throw "warning: moment.status != active in $scope.moment_done()" if m.status != 'active'

			m.stats.count = m.photos.length
			m.stats.completedIn += 123						# fix this
			m.stats.viewed += 1
			delete m.undo['photos']

			actionService.setCardStatus(m, 'complete')	
			syncService.set('moment', m)
			# drawer.updateCounts( null, _moments )

			$location.path drawer.state.route 

		$scope.moment_edit = (id)->
			m = $scope.deck.topCard()
			throw "ERROR: moment.id mismatch" if m.id != id 

			actionService.setCardStatus(m, 'active')	
			syncService.set('moment', m)
			# drawer.updateCounts( null, _moments )
			# nav to new route, then open in editMode
			$location.path editRroute = drawer.state.route + '/' + id

		$scope.set_editMode = (m)->
			# ???: should I set challenge to 'active'
			m.undo = {} if !m.undo?
			m.undo['photos'] = _.cloneDeep m.photos  # save undo info
			m.isCardExpanded = true

		$scope.moment_getPhoto = (id, $event)->
			m = $scope.deck.topCard() || _.findWhere _cards, {id: id}
			throw "moment id mismatch" if m.id != id

			saveToMoment = (p)->
				now = new Date()
				if m?
					photo = _.defaults p, {
						type: 'photo'
						stale: now.toJSON()
					}
					# update moment
					syncService.set('photo', photo)
					m.photoIds.push photo.id
					m.stats.count = m.photoIds.length
					m.stats.viewed += 1
					m.photos = actionService._getPhotos m
					actionService.setCardStatus(m, 'active', now)

					# notify.alert "Saved to moment.photos: count= " + m.photos.length + ", last=" + m.photos[m.photos.length-1].src , 'success', 5000 
					syncService.set('moment', m)
				return

			if !navigator.camera
				promise = cameraService.getPicture($event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )
				return true	# continue to input[type=file] handler
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary, $event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )			


		return;
	]
)


