return if !angular? 

appHappi = angular.module( 'appHappi'
, [
	'ngRoute'
	, 'ngSanitize'
	, 'ui.bootstrap'
	, 'drawerModule'
	, 'syncModule'
	, 'angularMoment'
]
).value('appConfig', {
	drawerUrl: if window.location.protocol=='file:' then 'common/data/drawer.json' else ''
}
).config( [
	'$routeProvider'
	($routeProvider)->
		$routeProvider
		.when('/challenges', {
			templateUrl: 'views/challenge/partials/challenges.html'
			controller: 'ChallengeCtrl'
			})
		.when('/challenges/:id', {
			templateUrl: 'partials/challenge.html'
			controller: 'ChallengeCtrl'
			})
		.when('/moments', {
			templateUrl: 'views/moment/partials/moments.html'
			controller: 'MomentCtrl'
			})
		.when('/moments/:id', {
			templateUrl: 'partials/moment.html'
			controller: 'MomentCtrl'
			})
		.otherwise {
			redirectTo: '/challenges'
		}
]
).filter('topCard', ()->
	return (cards, deck)->
		deck.index=0 if !deck.index? or deck.index >= cards.length
		if _.isArray(deck.shuffled)
			return cards[deck.shuffled[deck.index]] if deck.shuffled.length==cards.length
			deck.shuffled = 'error';
		return cards[deck.index]

).factory('cardService', [
	'$filter'
	'drawerService'
	($filter, drawer)->
		cardService = {
			validateDeck : (cards, deck, options)->
				return deck.cards && cards.length == deck.cards.length && JSON.stringify options == deck.options

			setupDeck : (cards, deck={}, options={})->
				if !cardService.validateDeck cards, deck, options
					step = cards
					step = $filter('filter') step, options.filter if options.filter?
					step = $filter('filter') step, options.query if options.query?
					step = $filter('orderBy') step, options.orderProp if options.orderProp?
					deck.cards = step
					deck.options = JSON.stringify options
					deck.index = 0	
				return deck

			shuffleDeck : (deck)->
				unshuffled = []
				unshuffled.push i for i in [0..deck.cards.length-1]
				deck.index = 0;
				deck.shuffled = cardService._shuffleArray unshuffled
				return deck

			_shuffleArray : (o)->
				`for (i = o.length; i; j = Math.floor(Math.random() * i), x = o[--i], o[i] = o[j], o[j] = x)`
				return o		

			topCard : (deck)->
				return $filter('topCard') deck.cards, deck

			nextCard : (cards, deck={}, options={})->
				if cardService.validateDeck cards, deck, options
					deck.index++
				else
					valid = cardService.setupDeck cards, deck, options
				return cardService.topCard deck

			# for use with ng-repeat
			deckCards : (deck)->
				return deck.cards if !deck.shuffled?
				shuffledCards = _.map deck.shuffled, (el)->
					return deck.cards[el]
				return shuffledCards

		}
		return cardService
]		
).factory('cameraService', [
	()->
		cameraService = {
			check: ()->
				alert('cameraService')
		}
		return cameraService
]		
).controller( 'ChallengeCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'drawerService'
	'syncService'
	'cardService'
	($scope, $filter, $q, $route, drawer, syncService, cardService)->
		#
		# Controller: ChallengeCtrl
		#

		# attributes
		$scope.$route = $route

		# card + deck iterator
		$scope.deck = {}
		$scope.cards = []
		$scope.card = null			# current challenge
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {  
      name: 'findhappi'
      state:
        active: 'current'
        orderProp: 'category'
    }

		# reset for testing
		syncService.clearAll() if $scope.$route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer'])	

		$q.all( syncService.promises ).then (o)->
			# init drawer
			drawer.init o.challenge, o.moment, $scope.initialDrawerState
			
			# skip moments.status=pass
			o.moments = $filter('filter')(o.moments, {status:"!pass"})
			$scope.moments = o.moment
			$scope.challenges = o.challenge
			# get nextCard
			$scope.cards = o.challenge
			deckOptions = _.pick(drawer.drawerItemState.state, ['filter', 'query', 'orderProp'])
			$scope.deck = cardService.setupDeck($scope.cards, $scope.deck, deckOptions)
			$scope.card = cardService.nextCard($scope.cards, $scope.deck, deckOptions)
			return 			

		# methods
		$scope.drawerShowAll = ()->
			drawer.itemClick $scope, drawer.getDrawerItem('findhappi', 'all')
			$scope.card = cardService.nextCard($scope.cards, $scope.deck, drawer) 

		$scope.passCard = ()->
			if drawer.drawerItemState.state.filter.status=='active' && $scope.card
				# set status=pass if current card, then show all challenges
				$scope.card.status='pass'
				console.warn "save to localStorage"
				return $scope.drawerShowAll()
			deckOptions = _.pick(drawer.drawerItemState.state, ['filter', 'query', 'orderProp'])
			return $scope.card = cardService.nextCard($scope.cards, $scope.deck, deckOptions)

		$scope.nextCard = ()->
			deckOptions = _.pick(drawer.drawerItemState.state, ['filter', 'query', 'orderProp'])
			return $scope.card = cardService.nextCard($scope.cards, $scope.deck, deckOptions)

		$scope.itemClick = (options)->
			return drawer.itemClick $scope, options, ()->
				deckOptions = _.pick(drawer.drawerItemState.state, ['filter', 'query', 'orderProp'])
				if options.name=='shuffle'
					$scope.deck = cardService.setupDeck $scope.cards, $scope.deck, deckOptions
					cardService.shuffleDeck( $scope.deck )
				return $scope.card = cardService.nextCard($scope.cards, $scope.deck, deckOptions) 

		$scope.shuffleDeck = ()->
			deckOptions = _.pick(drawer.drawerItemState.state, ['filter', 'query', 'orderProp'])
			$scope.deck = cardService.setupDeck($scope.cards, $scope.deck, deckOptions)
			cardService.shuffleDeck( $scope.deck )
			return cardService.nextCard($scope.cards, $scope.deck, deckOptions)

		$scope.accept = ()->
			# pass current Challenge to FindHappi
			return $scope.challenge

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
	'cardService'
	($scope, $filter, $q, $route, drawer, syncService, cardService)->
		#
		# Controller: MomentCtrl
		#

		# attributes
		$scope.$route = $route
		$scope.orderProp = 'modified'
		# card + deck iterator
		$scope.deck = {}
		$scope.cards = []
		$scope.card = null			# current moment
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {
			name: 'gethappi'
			state:
				active: 'mostRecent'
				orderProp: 'modified'
		}
		
		# reset for testing
		syncService.clearAll() if $scope.$route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer'])	

		$q.all( syncService.promises ).then (o)->
			# init drawer
			drawer.init o.challenge, o.moment, $scope.initialDrawerState
			
			# skip moments.status=pass
			o.moment = $filter('filter')(o.moment, {status:"!pass"})
			$scope.moments = o.moment
			$scope.challenges = o.challenge
			# get nextCard
			$scope.cards = o.moment
			deckOptions = _.pick(drawer.drawerItemState.state, ['filter', 'query', 'orderProp'])
			$scope.deck = cardService.setupDeck($scope.cards, $scope.deck, deckOptions)
			$scope.card = cardService.nextCard($scope.cards, $scope.deck, deckOptions)
			# for use with ng-repeat, card in deckCards
			$scope.deckCards = cardService.deckCards($scope.deck)	
			return 			

		# methods
		$scope.nextCard = ()->
			deckOptions = _.pick(drawer.drawerItemState.state, ['filter', 'query', 'orderProp'])
			return $scope.card = cardService.nextCard($scope.cards, $scope.deck, deckOptions)

		$scope.itemClick = (options)->
			return drawer.itemClick $scope, options, ()->
				deckOptions = _.pick(drawer.drawerItemState.state, ['filter', 'query', 'orderProp'])
				if options.name=='shuffle'
					$scope.deck = cardService.setupDeck $scope.cards, $scope.deck, deckOptions
				$scope.deckCards = cardService.deckCards cardService.shuffleDeck $scope.deck 
				# return $scope.card = cardService.nextCard($scope.cards, $scope.deck, deckOptions) 

		$scope.shuffleDeck = ()->
			deckOptions = _.pick(drawer.drawerItemState.state, ['filter', 'query', 'orderProp'])
			$scope.deck = cardService.setupDeck($scope.cards, $scope.deck, deckOptions)
			cardService.shuffleDeck( $scope.deck )
			return $scope.deckCards = cardService.deckCards cardService.shuffleDeck $scope.deck 
			# return cardService.nextCard($scope.cards, $scope.deck, deckOptions)

		return;
	]
)



