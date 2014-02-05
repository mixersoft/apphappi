return if !angular? 

challengeApp = angular.module( 'challengeApp'
, [
	'ngRoute'
	, 'ngSanitize'
	, 'ui.bootstrap'
	, 'drawerModule'
	, 'syncModule'
	, 'angularMoment'
]
).config( [
	'$routeProvider'
	($routeProvider)->
		$routeProvider
		.when('/challenges', {
			templateUrl: 'partials/challenges.html'
			controller: 'ChallengeCtrl'
			})
		.when('/challenges/:id', {
			templateUrl: 'partials/challenge.html'
			controller: 'ChallengeCtrl'
			})
		.otherwise {
			redirectTo: '/challenges'
		}
]
).controller( 'ChallengeCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'drawerService'
	'syncService'
	($scope, $filter, $q, $route, drawer, syncService)->
		#
		# Controller: ChallengeCtrl
		#

		# attributes
		$scope.$route = $route
		$scope.orderProp = 'category'
		$scope.orderBy2 = 'title'
		# card + deck iterator
		$scope.deck = {
			index: null
			shuffled: null
		}
		$scope.cards = []
		$scope.card = null			# current challenge
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {  
      name: 'findhappi'
      state:
        active: 'current'
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
			$scope.card = $scope.nextCard()
			return 			

		# methods
		$scope.drawerShowAll = ()->
			drawer.itemClick $scope, drawer.getDrawerItem('findhappi', 'all')
			$scope.nextCard() 

		$scope.passCard = ()->
			if drawer.filter.status=='active' && $scope.card
				$scope.card.status='pass'
				console.warn "save to localStorage"
				return $scope.drawerShowAll()
			return $scope.nextCard()

		$scope.nextCard = ()->
			$scope.deck.index = if $scope.deck.index? then $scope.deck.index+1 else 0
			step = $scope.cards
			step = $filter('filter') step, drawer.filter if drawer.filter?
			step = $filter('filter') step, drawer.query if drawer.query?
			step = $filter('orderBy') step, $scope.orderProp
			$scope.filteredCards = step
			$scope.card = $filter('topCard') (step || $scope.cards), $scope.deck

		$scope.itemClick = (options)->
			drawer.itemClick $scope, options, ()->
				$scope.cards = drawer._shuffleArray $scope.cards if options.name=='shuffle'
				$scope.nextCard();	

		$scope.shuffleDeck = (list=$scope.cards, deck=$scope.deck)->
			unshuffled = []
			unshuffled.push i for i in [0..list.length-1]
			deck = {
				index: 0
				shuffled: $scope.shuffleArray unshuffled
			}

		$scope.shuffleArray = (o)->
			`for (i = o.length; i; j = Math.floor(Math.random() * i), x = o[--i], o[i] = o[j], o[j] = x)`
			return o

		$scope.accept = ()->
			# pass current Challenge to FindHappi
			return $scope.challenge

		$scope.later = ()->
			# set current challenge, then put app to sleep
			# on wake, should open to current challenge
			return $scope.challege

		return;
	]
)

