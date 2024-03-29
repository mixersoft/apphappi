angular.module( 'appHappi', [
	'ngRoute'
	'ngSanitize'
	'ngAnimate'
	'ui.bootstrap'
	'angularMoment'
	'LocalStorageModule'
	# 'restangular'
	'pasvaz.bindonce'
	'angular-carousel'
]
).value('appConfig', {
	userId: null
	debug: false
	jsTimeout: 2000							# used by EXIF.getTag, Downsizer._downsize
	notifyTimeout: 5000
	messageTimeout: 10000
	drawerOpenBreakpoint: 768   # bootstrap @screen-sm-min, col-sm breakpoint
	saveDownsizedJPG: true
	# NOTE: only dataURLs are persisting between re-scans
	# EXCEPT: in adhoc app (test this)
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
		.when('/challenges/draw-new', {
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
		.when('/moments/shuffle', {
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
		.when('/settings/reminders', {
			templateUrl: 'views/settings/_reminders.html'
			controller: 'SettingsCtrl'
			})		
		.when('/getting-started', {
			templateUrl: 'views/settings/_gettingstarted.html'
			controller: 'SettingsCtrl'
		})
		.when('/getting-started/check', {
			templateUrl: 'views/settings/_gettingstarted.html'
			controller: 'SettingsCtrl'
		})
		.when('/about', {
			templateUrl: 'views/settings/_about.html'
			controller: 'SettingsCtrl'
		})		
		.otherwise {
			redirectTo: '/getting-started/check'
		}
		# TODO: use html5Mode with /index.html
		# $locationProvider.html5Mode(true)
		$locationProvider.html5Mode(false).hashPrefix('!')
]
).filter('reverse', ()->
  return (items)-> 
    return items.slice().reverse()

)
# set fallback Img.src for fullres
.directive('photo', ()->
	return {
		restrict: "A"
		scope: {
			photo: "="
		}
		link : (scope, element, attrs)->
			# add class="prefer-fileurl" to ng-include
			if element.parent().parent().parent().parent().hasClass('prefer-fileurl')
				# attrs.ngSrc = scope.photo.fileURI || scope.photo
				element.attr('src', scope.photo.fileURI || scope.photo.src)
				element.bind('error', ()->angular.element(this).attr("src", scope.photo.src) )				
				# TODO: destroy listeners
				scope.$on '$destroy', ()->
					element.unbind()	 	
			else element.attr('src',scope.photo.src)
	}
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

			# TODO: destroy listeners
			scope.$on '$destroy', ()->
				element.unbind()	 	
			return
	}
)
.directive('paginateDeck', [ '$compile', '$timeout', '$window', ($compile, $timeout, $window)->
	return {
		restrict: "A"
		scope:
			perpage: "="
			deck: "=paginateDeck"
		link : (scope, element, attrs)->
			# TODO: use pull down to refresh pattern for pull up
			pager = angular.element '<div class="pager-wrap" on-touch="galleryGlow"><div id="timeline-pager"><i class="fa fa-spinner fa-spin" ng-show="loading"></i> {{remaining}} more</div></div>'
			element.append(pager)
			scope.remaining = 0
			scope.loading = false
			
			_updatePager = (type="loading")->
				total = scope.deck.size()
				showing = scope.deck.paginatedCards("showing")
				scope.remaining = total-showing
				if scope.remaining == 0 
					pager.unbind()
					pager.remove()
					angular.element($window).off 'scroll', _paginateAfterScroll
				scope.loading = type=="loading"
				# use timeout for now
				$timeout (()->_updatePager("done")), 1000

			pager.bind 'touchstart, click',(e)->
				scope.$apply ()->
				 	scope.deck.paginatedCards("more")
				 	_updatePager("loading")

			pager.bind 'touchend',(e)->
				scope.$apply ()->
				 	_updatePager("done")

			# same as infinite-scroll
			_paginateAfterScroll = _.debounce (e)->
						win = this
						el = element[0]
						win_bottom = win.pageYOffset + win.innerHeight
						el_bottom = el.offsetTop + el.offsetHeight
						if scope.remaining && el_bottom < (win_bottom + 100) 
							scope.deck.paginatedCards("more")
							_updatePager("loading")
						return
					, 250		# inifinite-scroll Timeout

			angular.element($window).on 'scroll', _paginateAfterScroll

			# TODO: destroy listeners
			scope.$on '$destroy', ()->
				pager.unbind()
				angular.element($window).off 'scroll', _paginateAfterScroll

			# initialize to page=1, perpage=scope.perpage
			scope.deck.paginatedCards(scope.perpage) 
			_updatePager("done")	 	
			$compile(pager.contents())(scope); 
			return
	}
])


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
# window.Modernizr.touch = false # for loading from port 4000 on mobile browsers
if window.Modernizr.touch
	timeout = setTimeout ()->
			angular.bootstrap document.getElementById('ng-app'), ['appHappi']	
			setTimeout ()->
					notify.alert("WARNING: deviceready TIMEOUT", "warning", 20000)
				, 10000
		,2000	
	document.addEventListener "deviceready", ()->
		clearTimeout timeout
		angular.bootstrap document.getElementById('ng-app'), ['appHappi']
		location.reload() if !navigator.camera?
		window.deviceReady = !!navigator.camera
		# location.reload() if window.requestFileSystem == undefined


angular.element(document).ready ()->
	if !window.Modernizr.touch
		angular.bootstrap document.getElementById('ng-app'), ['appHappi']
	# continue document ready()

