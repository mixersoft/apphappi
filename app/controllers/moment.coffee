return if !angular? 

momentApp = angular.module( 'momentApp'
, [
	'ngRoute'
	, 'ngSanitize'
	, 'ui.bootstrap'
	, 'drawerModule'
	, 'LocalStorageModule'
	, 'angularMoment'
	, 'restangularModel'
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
).config([
	'localStorageServiceProvider', 
	(localStorageServiceProvider)->
  	localStorageServiceProvider.setPrefix('snappi');
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
	'localStorageService'
	'AppHappiRestangular'
	($scope, $filter, $q, $route, drawer, localStorageService, AppHappiRestangular)->
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
		

		# private methods
		asDuration = (secs)->
				duration = moment.duration(secs*1000) 
				formatted = []
				formatted.unshift(duration.seconds()+'s') if duration.seconds()
				formatted.unshift(duration.minutes()+'m') if duration.minutes()
				formatted.unshift(duration.hours()+'h') if duration.hours()
				formatted.unshift(duration.days()+'h') if duration.days()
				return formatted.join(' ')

		moments = AppHappiRestangular.all('moment')
		momentsPromise = moments.getList().then (moments)->
			for m in moments
				m.humanize = {
					completed: moment.utc(new Date(m.created)).format("dddd, MMMM Do YYYY, h:mm:ss a")
					completedAgo: moment.utc(new Date(m.created)).fromNow()
					completedIn: asDuration m.stats && m.stats.completedIn || 0
				}
			return $scope.moments = moments

		challenges = AppHappiRestangular.all('challenge')
		challengesPromise = challenges.getList().then (challenges)->
			for c in challenges
				c.humanize = {
					completions: c.stats.completions.length
					acceptPct: 100*c.stats.accept/c.stats.viewed
					passPct: 100*c.stats.pass/c.stats.viewed
					avgDuration: asDuration (_.reduce c.stats.completions
						, (a, b)->
							a+b
						, 0
					)/c.stats.completions.length 
					avgRating: $filter('number')( (_.reduce c.stats.ratings
						, (a, b)-> 
							a+b
						, 0
					)/c.stats.ratings.length, 1)
				}
			return $scope.challenges = challenges

		$q.all({
			moments: momentsPromise
			challenges: challengesPromise
			drawer: drawer.load()
		}).then (o)->
			drawer.init o.challenges, o.moments, $scope.initialDrawerState
			# skip moments.status=pass
			o.moments = $filter('filter')(o.moments, {status:"!pass"})
			$scope.cards = o.moments
			# get nextCard
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

