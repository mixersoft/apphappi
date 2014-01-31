return if !angular? 

angular.module( 
	'appHappi'
).service( 'notifyService', [
	'$timeout'
	($timeout)->
		this.alerts = []
		this.alert = (msg=null, type='danger', timeout=5000)->
			this.alerts.push( {msg: msg, type:type} )	if msg?
			that = this
			$timeout (()->that.alerts=[]), timeout
			return this.alerts 
		this.close = (index)->
			this.alerts.splice(index, 1)
		return	
]
).controller( 'ChallengeCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'drawerService'
	'syncService'
	'deckService'
	'cameraService'
	'notifyService'
	($scope, $filter, $q, $route, drawer, syncService, deck, cameraService, notify)->

		#
		# Controller: ChallengeCtrl
		#

		# attributes
		$scope.$route = $route
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
			$scope.challenges = o.challenge 
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
				return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state) 

		$scope.shuffleDeck = ()->
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			deck.shuffleDeck( $scope.deck )
			return deck.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.getPhoto = ()->
			saveToMoment = (uri)->
				notify.alert "getPhoto() resolved(). $scope.cameraRollSrc=" + uri
				$scope.cameraRollSrc = uri
				
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
					moment.modified = new Date()

					notify.alert "Saved to moment.photos: count= " + moment.photos.length + ", last=" + moment.photos[moment.photos.length-1].src
					syncService.set('moment', $scope.moments)
				return


			if !navigator.camera
				dfd = $q.defer()
				dfd.promise.then saveToMoment
				uri = $scope.testPics.shift()
				dfd.resolve(uri)
				$scope.testPics.push(uri)
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary)
				promise.then( saveToMoment ).catch( (message)->notify.alert message )


		$scope.testPics = [
			'http://ww2.hdnux.com/photos/25/76/31/5760625/8/centerpiece.jpg'
			'http://i1.nyt.com/images/2014/01/30/science/30MOTH_MONARCH/30MOTH_MONARCH-moth.jpg'
			'http://i1.nyt.com/images/2014/01/31/sports/football/31pads-1/31pads-1-largeHorizontal375.jpg'
		]

		$scope.challenge_pass = ()->
			if drawer.state.filter.status=='active' && $scope.card
				# set status=pass if current card, then show all challenges
				_.each $scope.card.moments, (o)-> 
					if o.status=='active'
						$scope.card.status=o.status='working'
						$scope.card = o.modified = new Date()
				$scope.card.status='pass' if $scope.card.status=='active'		

				syncService.set('challenge', $scope.challenges)
				syncService.set('moment', $scope.moments)
				return $scope.drawerShowAll()
			return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)


		$scope.challenge_done = ()->
			throw "warning: challenge.status != active in $scope.challenge_done()" if $scope.card.status != 'active'

			c = $scope.card
			_.each c.moments, (m)-> 
				if m.status=='active'
					c.status = m.status='complete'
					c.modified = m.modified = new Date()
					m.stats.completedIn += 123						# fix this
					c.stats.completions.push m.stats.completedIn

			syncService.set('challenge', $scope.challenges)
			syncService.set('moment', $scope.moments)

			# goto moment
			return $scope.drawerItemClick 'gethappi', {name:'mostRecent'}

		$scope.challenge_open = ()->
			# TODO: check for existing 'active' and set to 'pass'/'working'
			c = $scope.card
			_.each c.moments, (m)-> 
				if m.status=='working'
					c.status = m.status='active'
					c.modified = m.modified = new Date()
			if c.status !='active' && c.moments.length
					# working moment not found, just activate the first moment
					m = c.moments[0]
					c.status = m.status='active'
					c.modified = m.modified = new Date()

			syncService.set('challenge', $scope.challenges)
			syncService.set('moment', $scope.moments)		
			return $scope.drawerItemClick 'findhappi', {name:'current'}

		$scope.challenge_new = ()->
			# TODO: check for existing 'active' and set to 'pass'/'working'
			challenge = $scope.card
			challenge.stats.accept += 1
			now = new Date()
			blankMoment = {
				id: _.reduce $scope.moments, (last, m)->return if last.id > m.id then last.id else m.id
				userId: $scope.moments[0].userId
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
			return $scope.drawerItemClick 'findhappi', {name:'current'}

		$scope.later = ()->
			# set current challenge, then put app to sleep
			# on wake, should open to current challenge
			return $scope.challege	

		return;
	]
).controller( 'MomentCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'drawerService'
	'syncService'
	'deckService'
	'notifyService'
	($scope, $filter, $q, $route, drawer, syncService, deck, notify)->
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

		$scope.drawerItemClick = (groupName, options)->
			options.group = groupName
			options.item = options.name
			return drawer.itemClick options, ()->
				if options.name=='shuffle'
					$scope.deck = deck.setupDeck $scope.cards, $scope.deck, drawer.state
				$scope.deckCards = deck.deckCards deck.shuffleDeck $scope.deck 
				# return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state) 

		$scope.shuffleDeck = ()->
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			deck.shuffleDeck( $scope.deck )
			return $scope.deckCards = deck.deckCards deck.shuffleDeck $scope.deck 
			# return deck.nextCard($scope.cards, $scope.deck, drawer.state)

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
