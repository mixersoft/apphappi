angular.module( 'appHappi'
, [
	'ngRoute'
	, 'ngSanitize'
	, 'ui.bootstrap'
	, 'angularMoment'
	, 'LocalStorageModule'
	, 'restangular'
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
)