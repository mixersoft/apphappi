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

			persistRating : (ev, i)->
				$target = angular.element(ev.currentTarget)
				now = new Date().toJSON()
				switch $target.attr('rating-type')
					when "photo"
						switch this.card.type
							when "moment"
								this.card.stale = this.card.modified = now
								syncService.set('moment', this.card)
							when "challenge"
								this.moment.stale = this.card.modified = now
								syncService.set('moment', this.moment)

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

			drawerItemClick : (groupName, options)->
				scope = this
				options.group = groupName
				options.item = options.name
				scope.deck.index(0)
				return drawerService.itemClick options, ()->
					# drawerService.state is updated with new filter/query/search, setupDeck
					if !scope.deck.validateDeck(scope.cards)
						scope.deck.cards(scope.cards)
					scope.deck.shuffle() if options.name=='shuffle'
					$location.path(options.route) if options.route != $location.path()	

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
						scope.card = scope.deck.nextCard(drawerService.state)
						ev.gesture.preventDefault()
					when 'filmstrip-right'
						scope.card = scope.deck.nextCard(drawerService.state, -1)
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
				# Modernizr: cssanimations csstransforms csstranisitions
				if !scope.deck?
					length = index = 0
				else 		
					length = scope.deck.size()
					index = scope.deck.index()
				if true || window.Modernizr.touch
					style = {
						width: length * w + 'px'
						left: -1 * index * w + 'px'
					}
				else 
					translateCss = 'translate(' + -1 * index * w + 'px, 0)'
					style = {
						width: length * w + 'px'
						'transform': translateCss
						'-webkit-transform': translateCss
						'-ms-transform': translateCss
					}
				return style

			shuffleDeck : ()->
				scope = this
				if !scope.deck.validateDeck(scope.cards)
						scope.deck.cards(scope.cards)
				return scope.deck.shuffle().nextCard() 
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

		# attributes
		$scope.$route = $route
		$scope.$location = $location
		$scope.cameraService = cameraService
		$scope.notify = notify
		$scope.CFG = CFG
		_.extend $scope, actionService 		# add methods to scope

		# for common scope inside ng-repeat
		# $scope.root = {
		# 	deck : null			# Class Deck
		# 	cards : []			# all challenge cards
		# 	moment : null		# current moment, status=active only
		# 	drawer : drawer
		# }
		$scope.drawer = drawer;

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
			if _.isEmpty(state) || state.group !='findhappi'
				drawerItemOptions = drawer.getDrawerItem('findhappi', 'current')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

# ???: why do I need this?
			# o.moment = $filter('filter')(o.moment, {status:"!pass"})
			# $scope.moments = o.moment 		

			if $route.current.params.id?
				# filter challenges by id
				if _.isNaN parseInt $route.current.params.id 
					f = {"name": $route.current.params.id}
				else f = {"id": $route.current.params.id}
				$scope.challenges = $filter('filter')(o.challenge, f)
			else 
				$scope.challenges = o.challenge 

			$scope.cards = _.values $scope.challenges
			$scope.deck = deckService.setupDeck($scope.cards, drawer.state).shuffle()

			# redirect to all if no active challenge
			if (drawer.state.group=='findhappi' &&
							drawer.state.item=='current' &&
							drawer.state.counts['active'] == 0)
				$scope.drawerShowAll()

			# hide loading
			CFG.$curtain.addClass 'hidden'
			return


		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			return $scope.drawerItemClick 'findhappi', options


		$scope.challenge_getPhoto = (e)->
			saveToMoment = (uri)->
				# $scope.cameraRollSrc = uri
				m = $scope.moment || 
					_.findWhere $scope.deck.topCard().moments, {status:'active'} 
				now = new Date()
				if m? && _.isArray m.photos
					photo = {
						id: now.getTime()
						src: uri
					}
					# update moment
					m.photos.push photo
					m.stats.count = m.photos.length
					m.stats.viewed += 1
					m.stale = m.modified = now.toJSON()

					# notify.alert "Saved to moment.photos: count= " + m.photos.length + ", last=" + m.photos[m.photos.length-1].src , 'success', 5000 
					$scope.deck.topCard().challengePhotos = $filter('reverse')(m.photos)  	# for display of challenge only 'active'
					syncService.set('moment', m)
				return


			if !navigator.camera
				promise = cameraService.getPicture()
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )
				return true	# continue to input[type=file] handler
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )

		$scope.challenge_pass = ()->
			if drawer.state.filter.status=='active' && (c = $scope.deck.topCard())
				# set status=pass if current card, then show all challenges
				stale = [c]
				_.each c.moments, (m)-> 
					if m.status=='active'
						c.status=m.status='working'
						c.stale = m.stale = c.modified = m.modified = new Date().toJSON()
						stale.push m

				c.status='pass' if c.status=='active'		

				syncService.set('challenge', stale)
				syncService.set('moment', stale)
				drawer.updateCounts( $scope.challenges )	
				c.challengePhotos = null;
				$scope.moment = null
				return $scope.drawerShowAll()
			return $scope.deck.nextCard()


		$scope.challenge_done = ()->
			c = $scope.deck.topCard()
			now = new Date().toJSON()
			m = $scope.moment || 
					_.findWhere c.moments, {status:'active'} 
			throw "warning: challenge.status != active in $scope.challenge_done()" if c.status != 'active'
			throw "warning: moment.status != active in $scope.challenge_done()" if m.status != 'active'

			stale = [c]
			c.status = m.status='complete'
			c.stale = m.stale = c.modified = m.modified = now
			stale.push(m)
			m.stats.completedIn += 123						# fix this
			m.stats.viewed += 1
			c.stats.completions.push m.stats.completedIn
			c.challengePhotos = null;
			syncService.set('challenge', stale)
			syncService.set('moment', stale)
			drawer.updateCounts( $scope.challenges )

			# clear 'active' challenge photos
			$scope.moment = null

			# goto moment

			return $scope.drawerItemClick 'gethappi', {name:'mostRecent'}

		$scope.challenge_open = ()->
			# TODO: check for existing 'active' moment by challenge.moments and set to 'pass'/'working'
			c = $scope.deck.topCard()
			stale = [c]
			now = new Date().toJSON()

			_.each c.moments, (m)-> 
				if m.status=='working'
					c.status = m.status='active'
					c.stale = m.stale = c.modified = m.modified = now
					stale.push m
					moment = m

			if c.status !='active' && c.moments.length
					# working moment not found, just activate the first moment
					m = c.moments[0]
					c.status = m.status ='active'
					c.stale = m.stale = c.modified = m.modified = now
					stale.push m
					moment = m

			$scope.moment = moment
			c.challengePhotos = $filter('reverse')(moment.photos)  	# for display of challenge only 'active'
			syncService.set('challenge', stale)
			syncService.set('moment', stale)		
			drawer.updateCounts( $scope.challenges)
			return $scope.drawerItemClick 'findhappi', {name:'current'}

		# TODO: change to accept
		$scope.challenge_new = ()->
			# TODO: check for existing 'active' and set to 'pass'/'working'
			c = $scope.deck.topCard()
			c.stats.accept += 1
			now = new Date()
			stale = [c]
			m = {
				# id: _.reduce $scope.moments, (last, m)->return if last.id > m.id then last.id else m.id
				id: now.getTime()
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
			# $scope.moments[m.id] = m
			$scope.moment = m

			syncService.set('challenge', stale)
			syncService.set('moment', stale)
			drawer.updateCounts( $scope.challenges, syncService.localData['moment'] )
			c.challengePhotos = $filter('reverse')(m.photos)  	# for display of challenge only 'active'
			return $scope.drawerItemClick 'findhappi', {name:'current'}

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

		# attributes
		$scope.$route = $route
		$scope.$location = $location
		$scope.cameraService = cameraService
		$scope.notify = notify
		$scope.CFG = CFG
		_.extend $scope, actionService 		# add methods to scope

		# for common scope inside ng-repeat
		# $scope.root = {
		# 	deck : null			# Class Deck
		# 	cards : []			# all challenge cards
		# 	moment : null		# current moment, status=active only
		# 	drawer : drawer
		# }
		$scope.drawer = drawer;

		$scope.initialDrawerState = {
			group: 'gethappi'
			item: 'mostRecent'
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

			# wrap challenges in a Deck
			$scope.challenges = deckService.setupDeck(o.challenge)

			if $route.current.params.id?
				# filter moments by id
				if _.isNaN parseInt $route.current.params.id 
					f = {"name": $route.current.params.id}
				else f = {"id": $route.current.params.id}
				$scope.moments = $filter('filter')(_.values( o.moment ), f)
			else 
				o.moment = $filter('filter')(o.moment, {status:"!pass"})
				$scope.moments = o.moment



			# get nextCard
			$scope.cards = _.values $scope.moments 
			$scope.deck = deckService.setupDeck($scope.cards, drawer.state)

			m = $scope.deck.topCard()
			if $route.current.params.id? && m?.status=='active'
				$scope.set_editMode(m) 


			# hide loading
			CFG.$curtain.addClass 'hidden'
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
			# m = _.findWhere $scope.cards, {id: id}
			m = $scope.deck.topCard()
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
			m.isCardExpanded = true

		$scope.moment_getPhoto = (id, $event)->
			moment = _.findWhere $scope.cards, {id: id}

			saveToMoment = (uri)->
				# $scope.cameraRollSrc = uri
				now = new Date()
				if moment? && _.isArray moment.photos
					photo = {
						id: now.getTime()
						src: uri
					}
					# update moment
					moment.photos.push photo
					moment.stats.count = moment.photos.length
					moment.stale = moment.modified = now.toJSON()

					notify.alert "Saved to moment.photos: count= " + moment.photos.length + ", last=" + moment.photos[moment.photos.length-1].src , 'success', 5000 
					syncService.set('moment', moment)
				return

			if !navigator.camera
				promise = cameraService.getPicture()
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )
				return true	# continue to input[type=file] handler
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )			


		return;
	]
)


