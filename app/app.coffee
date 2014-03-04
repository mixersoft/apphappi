angular.module( 'appHappi', [
	'ngRoute'
	'ngSanitize'
	'ngAnimate'
	'ui.bootstrap'
	'angularMoment'
	'LocalStorageModule'
	'restangular'
	# 'angular-gestures'
	'pasvaz.bindonce'
	'angular-carousel'
]
).value('appConfig', {
	userId: null
	debug: false
	jsTimeout: 2000							# used by EXIF.getTag, Downsizer._downsize
	notifyTimeout: 5000
	drawerOpenBreakpoint: 768   # bootstrap @screen-sm-min, col-sm breakpoint
	saveDownsizedJPG: true
	# NOTE: only dataURLs are persisting between re-scans
	camera: 
		targetWidth : 320
		quality: 85
	gallery:
		lazyloadOffset: 2
	$curtain: angular.element(document.getElementById('curtain'))
	drawerUrl: if window.location.protocol=='file:' then 'common/data/drawer.json' else ''
	challengeUrl: if window.location.protocol=='file:' then 'common/data/challenge.json' else '/common/data/challenge.json'
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
		.when('/timeline', {
			templateUrl: 'views/timeline/_timeline.html'
			controller: 'TimelineCtrl'
			})
		.otherwise {
			redirectTo: '/challenges'
		}
		# TODO: use html5Mode with /index.html
		$locationProvider.html5Mode(false).hashPrefix('!')
]
).filter('reverse', ()->
  return (items)-> 
    return items.slice().reverse()

)
.directive('onTouch', ()->
	return {
		restrict: "A"
		link : (scope, element, attrs)->
			handleOnTouch = scope.$eval( attrs.onTouch)

			element.bind 'touchstart',(e)->
				 scope.$apply ()->
				 	handleOnTouch.call(scope, e)

			element.bind 'touchend',(e)->
				 scope.$apply ()->
				 	handleOnTouch.call(scope, e)

			# element.bind 'click',(e)->
			# 	 scope.$apply ()->
			# 	 	handleOnTouch.call(scope, e) 
			return
	}
)


# NOTE: adding .force-open as early as possible to prevent flash
# directive 'responsiveDrawerWrap' will update on window.resize
if window.innerWidth >= 768
	try 
		drawer = document.getElementById('drawer')
		if drawer
			classes = drawer.className.split(' ')	
			if classes.indexOf('force-open')==-1
		 		classes.push('force-open')
		 		drawer.className = classes.join(' ')
	catch error


# bootstrap 
window.deviceReady = false
if window.Modernizr.touch
	document.addEventListener "deviceready", ()->
		angular.bootstrap document.getElementById('ng-app'), ['appHappi']
		location.reload() if !navigator.camera?
		window.deviceReady = !!navigator.camera
		# location.reload() if window.requestFileSystem == undefined


angular.element(document).ready ()->
	if !window.Modernizr.touch
		angular.bootstrap document.getElementById('ng-app'), ['appHappi']
	# continue document ready()

