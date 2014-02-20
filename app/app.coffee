angular.module( 'appHappi', [
	'ngRoute'
	'ngSanitize'
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
	debug: true
	saveDownsizedJPG: true
	camera: 
		targetWidth : 320
		quality: 85
	$curtain: angular.element(document.getElementById('curtain'))
	drawerUrl: if window.location.protocol=='file:' then 'common/data/drawer.json' else ''
	challengeUrl: if window.location.protocol=='file:' then 'common/data/challenge.json' else '/common/data/challenge.json'
	images: [
		'http://dev.snaphappi.com/svc/STAGING/stage1/.thumbs/bp~51df6d80-6408-4af0-afa9-0a5f0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage0/.thumbs/bp~51df619a-cd60-4b4f-8745-0a5f0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage1/.thumbs/bp~51df6da3-0a04-4a2b-8b69-0a5f0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage5/.thumbs/bp~51df6d8d-8fac-44dd-a016-0a5f0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage1/.thumbs/bp~51df606b-1cb8-4cd0-8f51-0a6d0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage3/.thumbs/bp~51df5fff-f684-480e-9d4a-0a6a0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage6/.thumbs/bp~51df5fef-53a8-4e31-a17e-0a6a0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage4/.thumbs/bp~51df61b6-e8d0-4b52-bdbf-0a5f0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage1/.thumbs/bp~51df5fc2-5ba4-466b-b847-0a6a0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage1/.thumbs/bp~51df5fb3-1928-4c4c-9e9d-0a6a0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage4/.thumbs/bp~51df6029-1f6c-4490-8370-0a6a0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage1/.thumbs/bp~51df6044-fc4c-46a0-8151-0a6d0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage3/.thumbs/bp~51df5fa0-a294-4b37-bb01-0a6a0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage4/.thumbs/bp~51df5f8d-1990-44c6-acce-0a6a0afc6d44.jpg'
		'http://dev.snaphappi.com/svc/STAGING/stage1/.thumbs/bp~51df5f15-2ec0-4f69-902c-0a700afc6d44.jpg'
	]
	nextImgSrc: ()->
		# for testing with remote img.src
		next = this.images.shift();
		this.images.push(next)
		return next
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
);



# bootstrap 
window.deviceReady = false
if window.Modernizr.touch
	document.addEventListener "deviceready", ()->
		angular.bootstrap document.getElementById('ng-app'), ['appHappi']
		location.reload() if !navigator.camera?
		window.deviceReady = navigator.camera
		

else 
	angular.element(document).ready ()->
		angular.bootstrap document.getElementById('ng-app'), ['appHappi']