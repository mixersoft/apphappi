return if !angular? 

challengeApp = angular.module( 'challengeApp'
, [
	'ngRoute'
	, 'challengeModel'
]
).config( [
	'$routeProvider'
	($routeProvider)->
		$routeProvider
		.when('/challenges', {
			templateUrl: 'partials/summary.html'
			controller: 'ChallengeCtrl'
			})
		.when('/challenges/:id', {
			templateUrl: 'partials/card.html'
			controller: 'ChallengeCtrl'
			})
		.otherwise {
			redirectTo: '/challenges'
		}
]
).filter('topCard', ()->
	return (list, deck)->
		deck.index=0 if !deck.index? or deck.index >= list.length
		if _.isArray(deck.shuffled)
			return list[deck.shuffled[deck.index]] if deck.shuffled.length==list.length
			deck.shuffled = 'error';
		return list[deck.index]

).controller( 'ChallengeCtrl', [
	'$scope'
	'$filter'
	'ChallengeRestangular'
	($scope, $filter, ChallengeRestangular)->
		#
		# Controller: ChallengeCtrl
		#
		# TODO: check of ChallengeRestangular must match factory

		# attributes
		$scope.query = ''
		$scope.orderProp = 'category'
		$scope.orderBy2 = 'title'

		$scope.deck = {
			index: null
			shuffled: null
		}
		$scope.card = null			# current challenge
		$scope.cards = ChallengeRestangular
		.all('challenge')
		.getList()
		.then (challenges)->
			$scope.cards = challenges;
			$scope.card = $scope.nextCard()
			return

		# methods
		$scope.nextCard = ()->
			$scope.deck.index = if $scope.deck.index? then $scope.deck.index+1 else 0
			step = $filter('filter') $scope.cards, $scope.query
			step = $filter('orderBy') step, $scope.orderProp
			$scope.card = $filter('topCard') (step || $scope.cards), $scope.deck

		$scope.shuffleDeck = (list=$scope.cards, deck=$scope.deck)->
			unshuffled = []
			unshuffled.push i for i in [0..list.length-1]
			$scope.deck = {
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

