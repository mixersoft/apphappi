return if !angular? 

momentApp = angular.module( 'momentApp'
, [
	'ngRoute'
	, 'ngSanitize'
	, 'ui.bootstrap'
	, 'LocalStorageModule'
	, 'angularMoment'
	, 'momentModel'
	, 'challengeModel'
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
	'$http'
	'localStorageService'
	'MomentRestangular'
	'ChallengeRestangular'
	($scope, $filter, $q, $http, localStorageService, MomentRestangular, ChallengeRestangular)->
		#
		# Controller: MomentCtrl
		#
		# TODO: check of MomentRestangular must match factory

		# attributes
		$scope.query = ''
		$scope.orderProp = 'modified'
		$scope.orderBy2 = 'name'
		# card + deck iterator
		$scope.deck = {
			index: null
			shuffled: null
		}
		$scope.cards = []
		$scope.card = {}			# current moment
		$scope.isDrawerOpen = false;
		$scope.isCardExpanded = false;

		$scope.drawer = {}
		$scope.drawerState = {
			GetHappi:
				state:
					isOpen: true
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

		# drawer
		$http.get('/common/data/drawer.json').success (data, status, headers, config)->
			$scope.drawer = _.merge(data, $scope.drawerState)
			return $scope.drawer
		$scope.drawer_click = (item,options)->
			check
			return
		$scope.drawer_radio = (state)->
			return state.isOpen = false if state.isOpen?


		moments = MomentRestangular.all('moment')
		momentsPromise = moments.getList().then (moments)->
			for m in moments
				m.humanize = {
					completed: moment.utc(new Date(m.created)).format("dddd, MMMM Do YYYY, h:mm:ss a")
					completedAgo: moment.utc(new Date(m.created)).fromNow()
					completedIn: asDuration m.stats && m.stats.completedIn || 0
				}
			$scope.cards = moments;
			$scope.card = $scope.nextCard()
			return moments

		challenges = MomentRestangular.all('challenge')
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
		}).then (o)->
			for moment in o.moments
				# add moment hasMany challenge association
				moment.challenge = _.findWhere(o.challenges, {id: moment.challengeId})
			return moments

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
			# pass current Moment to FindHappi
			return $scope.moment

		$scope.later = ()->
			# set current moment, then put app to sleep
			# on wake, should open to current moment
			return $scope.challege

		return;
	]
)

