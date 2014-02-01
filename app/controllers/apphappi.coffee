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
	'appConfig'
	($scope, $filter, $q, $route, $location, drawer, syncService, deck, cameraService, notify, CFG)->

		#
		# Controller: ChallengeCtrl
		#

		# attributes
		$scope.$route = $route
		$scope.$location = $location
		$scope.cameraService = cameraService
		$scope.notify = notify

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
			$scope.cards = $scope.challenges
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			

			# redirect to all if no active challenge
			if drawer.state.group=='findhappi' &&
          drawer.state.item=='current' &&
          drawer.state.counts['active'] == 0
        $scope.drawerShowAll()
      else   
      	return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)

		# methods
		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			return $scope.drawerItemClick 'findhappi', options

		$scope.nextCard = ()->
			return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)

		# returns deck.TopCard()
		$scope.drawerItemClick = (groupName, options)->
			options.group = groupName
			options.item = options.name || options.item
			return drawer.itemClick options, ()->
				if options.name=='shuffle'
					$scope.deck = deck.setupDeck $scope.cards, $scope.deck, drawer.state
					deck.shuffleDeck( $scope.deck )
				$location.path(options.route) if options.route != $location.path()
				return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state) 

		$scope.shuffleDeck = ()->
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			deck.shuffleDeck( $scope.deck )
			return deck.nextCard($scope.cards, $scope.deck, drawer.state)

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
					moment.modified = new Date().toJSON()

					notify.alert "Saved to moment.photos: count= " + moment.photos.length + ", last=" + moment.photos[moment.photos.length-1].src , 'success', 5000 
					$scope.challengePhotos = $filter('reverse')(moment.photos)  	# for display of challenge only 'active'
					syncService.set('moment', $scope.moments)

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
				_.each $scope.card.moments, (o)-> 
					if o.status=='active'
						$scope.card.status=o.status='working'
						$scope.card = o.modified = new Date().toJSON()
				$scope.card.status='pass' if $scope.card.status=='active'		

				syncService.set('challenge', $scope.challenges)
				syncService.set('moment', $scope.moments)
				$scope.challengePhotos = null;
				return $scope.drawerShowAll()
			return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)


		$scope.challenge_done = ()->
			throw "warning: challenge.status != active in $scope.challenge_done()" if $scope.card.status != 'active'

			c = $scope.card
			_.each c.moments, (m)-> 
				if m.status=='active'
					c.status = m.status='complete'
					c.modified = m.modified = new Date().toJSON()
					m.stats.completedIn += 123						# fix this
					m.stats.viewed += 1
					c.stats.completions.push m.stats.completedIn

			syncService.set('challenge', $scope.challenges)
			syncService.set('moment', $scope.moments)

			# clear 'active' challenge photos
			$scope.challengePhotos = null;

			# goto moment
			return $scope.drawerItemClick 'gethappi', {name:'mostRecent'}

		$scope.challenge_open = ()->
			# TODO: check for existing 'active' moment by challenge.moments and set to 'pass'/'working'
			c = $scope.card

			_.each c.moments, (m)-> 
				if m.status=='working'
					c.status = m.status='active'
					c.modified = m.modified = new Date().toJSON()
					moment = m

			if c.status !='active' && c.moments.length
					# working moment not found, just activate the first moment
					m = c.moments[0]
					c.status = m.status='active'
					c.modified = m.modified = new Date().toJSON()
					moment = m

			$scope.challengePhotos = $filter('reverse')(moment.photos)  	# for display of challenge only 'active'
			syncService.set('challenge', $scope.challenges)
			syncService.set('moment', $scope.moments)		
			return $scope.drawerItemClick 'findhappi', {name:'current'}

		$scope.challenge_new = ()->
			# TODO: check for existing 'active' and set to 'pass'/'working'
			challenge = $scope.card
			challenge.stats.accept += 1
			now = new Date()
			blankMoment = {
				# id: _.reduce $scope.moments, (last, m)->return if last.id > m.id then last.id else m.id
				id: new Date().getTime()
				userId: CFG.userId
				challengeId: challenge.id
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
				photos: []
			}
			challenge.status = blankMoment.status = 'active'
			$scope.moments.push(blankMoment)
			challenge.moments.push(blankMoment)

			syncService.set('challenge', $scope.challenges)
			syncService.set('moment', $scope.moments)
			$scope.challengePhotos = blankMoment.photos  	# for display of challenge only 'active'
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
	'appConfig'
	($scope, $filter, $q, $route, $location, drawer, syncService, deck, cameraService, notify, CFG)->
		#
		# Controller: MomentCtrl
		#

		# attributes
		$scope.$route = $route

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
				$scope.moments = $filter('filter')(o.moment, f)
			else 
				o.moment = $filter('filter')(o.moment, {status:"!pass"})
				$scope.moments = o.moment
			# syncService.set('moment', $scope.moments)
			$scope.challenges = o.challenge 
			# syncService.set('challenge', $scope.challenges)

			# get nextCard
			$scope.cards = $scope.moments
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			$scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)
			# for use with ng-repeat, card in deckCards
			$scope.deckCards = deck.deckCards($scope.deck) 
			return      

		# methods
		$scope.nextCard = ()->
			return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			return $scope.drawerItemClick 'findhappi', options

		$scope.drawerItemClick = (groupName, options)->
			options.group = groupName
			options.item = options.name
			return drawer.itemClick options, ()->
				if options.name=='shuffle'
					$scope.deck = deck.setupDeck $scope.cards, $scope.deck, drawer.state
				$location.path(options.route) if options.route != $location.path()	
				$scope.deckCards = deck.deckCards deck.shuffleDeck $scope.deck 
				# return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state) 

		$scope.shuffleDeck = ()->
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			deck.shuffleDeck( $scope.deck )
			return $scope.deckCards = deck.deckCards deck.shuffleDeck $scope.deck 
			# return deck.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.moment_cancel = (id)->
			m = _.findWhere $scope.moments, {id: id}
			notify.alert "Warning: no undo[photos] NOT found", "warning" if !m.undo['photos']?

			m.photos = m.undo['photos']
			delete m.undo['photos']
			$scope.card.status = 'complete'
			syncService.set('moment', $scope.moments)
			$location.path drawer.state.route 

		$scope.moment_done = (id)->
			m = _.findWhere $scope.moments, {id: id}
			throw "warning: moment.status != active in $scope.moment_done()" if m.status != 'active'
			m.stats.count = m.photos.length
			m.stats.completedIn += 123						# fix this
			m.stats.viewed += 1
			m.modified = new Date().toJSON()
			m.status = "complete"
			delete m.undo['photos']
			syncService.set('moment', $scope.moments)
			$location.path drawer.state.route 


		$scope.moment_edit = (id)->
			# ???: should I set challenge to 'active'
			m = _.findWhere $scope.moments, {id: id}
			m.undo = {} if !m.undo?
			m.undo['photos'] = _.cloneDeep m.photos  # save undo info
			m.status = "active"
			$location.path editRroute = drawer.state.route + '/' + id

		$scope.moment_getPhoto = (id)->
			moment = _.findWhere $scope.moments, {id: id}

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
					moment.modified = new Date().toJSON()

					notify.alert "Saved to moment.photos: count= " + moment.photos.length + ", last=" + moment.photos[moment.photos.length-1].src , 'success', 5000 
					syncService.set('moment', $scope.moments)
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

# bootstrap 
if window.Modernizr.touch
	document.addEventListener "deviceready", ()->
		angular.bootstrap document, ['appHappi']
else 
	angular.element(document).ready ()->
	angular.bootstrap document.getElementById('ng-app'), ['appHappi']
