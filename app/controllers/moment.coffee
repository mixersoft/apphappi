return if !angular? 

momentApp = angular.module( 'momentApp'
, [
	'ngRoute'
	, 'ngSanitize'
	, 'ui.bootstrap'
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
	'$http'
	'localStorageService'
	'AppHappiRestangular'
	($scope, $filter, $q, $route, $http, localStorageService, AppHappiRestangular)->
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

		$scope.$root.drawer = {
			isDrawerOpen: false
			isCardExpanded: false
			query: ''
			drawer: {}		# drawer config object 
			drawerState: {
				name: 'gethappi'
				state:
					isOpen: true
					active: 'mostRecent'
			}
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
			drawer = $scope.$root.drawer
			active = _.findWhere data, {name: drawer.drawerState.name}
			_.merge(active.state, drawer.drawerState.state)
			drawer.drawer = data
			return drawer.drawer

		$scope.drawer_click = (options)->
			drawer = $scope.$root.drawer
			if $scope.$route.current.originalPath==options.route
				# same drawer-group, stay on page
				$scope.orderProp = options.orderBy if options.orderBy?
				$scope.$root.drawer.query = options.filter if options.filter?
				# set .item.active
				drawerGroup = _.findWhere(drawer.drawer, {name:drawer.drawerState.name})
				drawerGroup.state.active = options.name
				# shuffle?
				$scope.cards = $scope.shuffleArray $scope.cards if options.name=='shuffle'
			else 
				# navigate to options.route, set initial state
				console.log "navigate to href="+options.route
			return

		$scope.drawer_radio = (state)->
			return state.isOpen = false if state.isOpen?


		moments = AppHappiRestangular.all('moment')
		momentsPromise = moments.getList().then (moments)->
			moments = $filter('filter')(moments, {status:"!pass"})
			for m in moments
				m.humanize = {
					completed: moment.utc(new Date(m.created)).format("dddd, MMMM Do YYYY, h:mm:ss a")
					completedAgo: moment.utc(new Date(m.created)).fromNow()
					completedIn: asDuration m.stats && m.stats.completedIn || 0
				}
			$scope.cards = moments;
			$scope.card = $scope.nextCard()
			return moments

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
		}).then (o)->
			for moment in o.moments
				# add moment hasMany challenge association
				moment.challenge = _.findWhere(o.challenges, {id: moment.challengeId})
			return moments

		# methods
		$scope.nextCard = ()->
			$scope.deck.index = if $scope.deck.index? then $scope.deck.index+1 else 0
			step = $filter('filter') $scope.cards, $scope.$root.drawer.query
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

		return;
	]
)

