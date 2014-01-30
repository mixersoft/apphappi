return if !angular? 

angular.module( 
	'appHappi'
).controller( 'ChallengeCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'drawerService'
	'syncService'
	'deckService'
	'cameraService'
	($scope, $filter, $q, $route, drawer, syncService, deck, cameraService)->

		#
		# Controller: ChallengeCtrl
		#

		# attributes
		$scope.$route = $route
		$scope.cameraService = cameraService

		# card + deck iterator
		$scope.deck = {}
		$scope.cards = []
		$scope.card = null      # current challenge
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {  
			group: 'findhappi'  
			item: 'current'
			filter: null
			query: ''
			orderBy: 'category'
		}

		# reset for testing
		syncService.initLocalStorage(['challenge', 'moment', 'drawer']) 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# init drawer
			state = syncService.get('drawerState')
			state = $scope.initialDrawerState if _.isEmpty(state)
			drawer.init o.challenge, o.moment, state
			
			o.moment = $filter('filter')(o.moment, {status:"!pass"})
			$scope.moments = o.moment
			# syncService.set('moment', $scope.moments)
			$scope.challenges = o.challenge 
			# syncService.set('challenge', $scope.challenges)

			# get nextCard
			$scope.cards = $scope.challenges
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			$scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)
			return      

		# methods
		$scope.drawerShowAll = ()->
			drawer.itemClick drawer.getDrawerItem('findhappi', 'all')
			$scope.card = deck.nextCard($scope.cards, $scope.deck, drawer) 

		$scope.passCard = ()->
			if drawer.state.filter.status=='active' && $scope.card
				# set status=pass if current card, then show all challenges
				$scope.card.status='pass'
				console.warn "save to localStorage"
				return $scope.drawerShowAll()
			return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.nextCard = ()->
			return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.itemClick = (groupName, options)->
			options.group = groupName
			options.item = options.name
			return drawer.itemClick options, ()->
				if options.name=='shuffle'
					$scope.deck = deck.setupDeck $scope.cards, $scope.deck, drawer.state
					deck.shuffleDeck( $scope.deck )
				return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state) 

		$scope.shuffleDeck = ()->
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			deck.shuffleDeck( $scope.deck )
			return deck.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.accept = ()->
			# pass current Challenge to FindHappi
			return $scope.challenge

		$scope.later = ()->
			# set current challenge, then put app to sleep
			# on wake, should open to current challenge
			return $scope.challege

		$scope.getPhoto = ()->
			saveToMoment = (uri)->
				alert "camera roll, file $scope.cameraRollSrc=" + uri
				$scope.cameraRollSrc = uri
				
				moment = _.findWhere $scope.card.moments, {status:'active'}

				if moment? && _.isArray moment.photos
					photo = {
						id: `new Date().getTime()`
						src: uri
					}
					moment.photos.push photo
					alert "moment.photos: " + JSON.stringify _.reduce moment.photos, ((last, o)->
								last.push o.src 
								return last 
							), []
					syncService.set('moment', $scope.moments)

				return


			if !navigator.camera
				uri = 'http://ww2.hdnux.com/photos/25/76/31/5760625/8/centerpiece.jpg'
				dfd = $q.defer()
				dfd.promise.then saveToMoment
				dfd.resolve(uri) 
			else
				cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary).then saveToMoment
						
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
	($scope, $filter, $q, $route, drawer, syncService, deck)->
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
			# init drawer
			state = syncService.get('drawerState')
			state = $scope.initialDrawerState if _.isEmpty(state)
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

		$scope.itemClick = (groupName, options)->
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
