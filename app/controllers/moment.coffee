return if !angular? 

momentApp = angular.module( 'momentApp'
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
		.when('/moments', {
			templateUrl: 'partials/moments.html'
			controller: 'MomentCtrl'
			})
		.when('/moments/:id', {
			templateUrl: 'partials/moment.html'
			controller: 'MomentCtrl'
			})
		.otherwise {
			redirectTo: '/moments'
		}
]
).filter('topCard', ()->
	# deprecate?
	return (list, deck)->
		deck.index=0 if !deck.index? or deck.index >= list.length
		if _.isArray(deck.shuffled)
			return list[deck.shuffled[deck.index]] if deck.shuffled.length==list.length
			deck.shuffled = 'error';
		return list[deck.index]

).controller( 'MomentCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'drawerService'
	'syncService'
	($scope, $filter, $q, $route, drawer, syncService)->
		#
		# Controller: MomentCtrl
		#

		# attributes
		$scope.$route = $route
		$scope.orderProp = 'modified'
		$scope.orderBy2 = 'name'
		# card + deck iterator
		$scope.deck = {
			index: null
			shuffled: null
		}
		$scope.cards = []
		$scope.card = {}			# current moment
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {
			name: 'gethappi'
			state:
				active: 'mostRecent'
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
			$scope.card = $scope.nextCard()
			return 			

		# methods
		$scope.nextCard = ()->
			$scope.deck.index = if $scope.deck.index? then $scope.deck.index+1 else 0
			step = $scope.cards
			step = $filter('filter') step, drawer.filter if drawer.filter?
			step = $filter('filter') step, drawer.query
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

		return;
	]
)

