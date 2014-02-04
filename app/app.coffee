angular.module( 'appHappi'
, [
	'ngRoute'
	'ngSanitize'
	'ui.bootstrap'
	'angularMoment'
	'LocalStorageModule'
	'restangular'
]
).value('appConfig', {
	userId: null,
	drawerUrl: if window.location.protocol=='file:' then 'common/data/drawer.json' else ''
	testPics: [
		'http://ww2.hdnux.com/photos/25/76/31/5760625/8/centerpiece.jpg'
		'http://i1.nyt.com/images/2014/01/30/science/30MOTH_MONARCH/30MOTH_MONARCH-moth.jpg'
		'http://i1.nyt.com/images/2014/01/31/sports/football/31pads-1/31pads-1-largeHorizontal375.jpg'
	]
}
).config( [
	'$routeProvider'
	'$locationProvider'
	($routeProvider, $locationProvider)->
		$routeProvider
		.when('/challenges', {
			templateUrl: 'views/challenge/_challenges.html'
			controller: 'ChallengeCtrl'
			})
		.when('/challenges/:id', {
			templateUrl: 'views/challenge/_challenges.html'
			controller: 'ChallengeCtrl'
			})
		.when('/challenge/:id', {
			templateUrl: 'views/challenge/_challenges.html'
			controller: 'ChallengeCtrl'
			})
		.when('/moments', {
			templateUrl: 'views/moment/_moments.html'
			controller: 'MomentCtrl'
			})
		.when('/moments/:id', {
			templateUrl: 'views/moment/_moments.html'
			controller: 'MomentCtrl'
			})
		.when('/moment/:id', {
			templateUrl: 'views/moment/_moments.html'
			controller: 'MomentCtrl'
			})
		.otherwise {
			redirectTo: '/challenges'
		}
		# TODO: use html5Mode with /index.html
		$locationProvider.html5Mode(false).hashPrefix('!')
]
).filter('topCard', ()->
	return (cards, deck)->
		deck.index=0 if !deck.index? or deck.index >= cards.length
		if _.isArray(deck.shuffled)
			return cards[deck.shuffled[deck.index]] if deck.shuffled.length==cards.length
			deck.shuffled = 'error';
		return cards[deck.index]
).filter('reverse', ()->
  return (items)-> 
    return items.slice().reverse()
);
