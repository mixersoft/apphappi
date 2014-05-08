angular.module( 'appHappi', [
	'ngRoute'
	'ngSanitize'
	'ngAnimate'
	'ui.bootstrap'
	'angularMoment'
	'LocalStorageModule'
	'pasvaz.bindonce'
	'angular-carousel'
]
).value('appConfig', {
	userId: null
	debug: false
	jsTimeout: 2000							# used by EXIF.getTag, Downsizer._downsize
	notifyTimeout: 5000
	messageTimeout: 10000
	longSleepTimeout: 4*3600			# 4 hours
	drawerOpenBreakpoint: 768   		# bootstrap @screen-sm-min, col-sm breakpoint
	saveDownsizedJPG: true
	# NOTE: only dataURLs are persisting between re-scans
	# EXCEPT: in adhoc app (test this)
	cameraRoll : 'snappiAssetsPickerService'  # values: [ snappiAssetsPickerService | cordovaCameraService | html5CameraService ]  # force "html5CameraService" or auto
	camera: 
		targetWidth : 320
		quality: 85
	gallery:
		lazyloadOffset: 2
	$curtain: angular.element(document.getElementById('curtain'))
	drawerUrl: if window.location.protocol=='file:' then 'common/data/drawer.json' else ''
	challengeUrl: if window.location.protocol=='file:' then 'common/data/challenge.json' else '/common/data/challenge.json'
	# Note: title/message for notify.message() is set in ChallgenCtrl/MomentCtrl, 
	# must duplicate message here, which is sent to Notification Center
	notifications: [
			{
				title: "Your 5 Minutes of Happi Starts Now"
				message: "Spend 5 minutes to find some Happi - a new challenge awaits!"
				target: "/challenges/draw-new"
			},
			{
				title: "Get Your Happi for the Day"
				message: "This Happi moment was made possible by your '5 minutes a day'. Grab a smile and make another."
				target: "/moments/shuffle"	
				# target: "/challenges/draw-new"
			}
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
			templateUrl: 'views/settings/_gettingstarted.1.html'
			controller: 'SettingsCtrl'
		})
		.when('/getting-started/check', {
			templateUrl: 'views/settings/_gettingstarted.1.html'
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
	_getSrc = (index, scope, fallback=false)->
		if scope.preferFileUrl && !fallback
			return scope.photo.fileURI || scope.photo.src
		else return scope.photo.src	

	return {
		restrict: "A"
		scope: {
			photo: "="
		}
		link : (scope, element, attrs)->
			# add class="prefer-fileurl" to ng-include
			parent = scope.$parent
			ngRepeat = element.parent().parent().parent().parent().parent()
			scope.preferFileUrl = ngRepeat.hasClass('prefer-fileurl')
			# ???: why do I need to define in both scope and scope.$parent???
			scope.index = parent.$index
			scope.getSrc = parent.getSrc = ngRepeat.getSrc = (index)->
				# console.log "getSrc, index="+index
				return _getSrc(index, scope)

			if scope.preferFileUrl 
				# attrs.ngSrc = scope.photo.fileURI || scope.photo
				# element.attr('src', scope.photo.fileURI || scope.photo.src)
				element.bind('error', ()->
					# angular.element(this).attr("src", scope.photo.src) 
					angular.element(this).attr( "src", _getSrc( scope.index, scope, "fallback")  )
					scope.$apply()

				)				
				# TODO: destroy listeners
				scope.$on '$destroy', ()->
					element.unbind()

			return
	}
)
.directive('lazyload', ['$window', ($window)->
	_inView = (img, docViewTop, docViewBottom)-> 
		el = img.parentNode.parentNode.parentNode	# .thumb
		elemTop = el.offsetTop
		elemBottom = elemTop + el.clientHeight
		return ((elemBottom >= docViewTop) && (elemTop <= docViewBottom) && (elemBottom <= docViewBottom) &&  (elemTop >= docViewTop) )

	_getFocus = (imgs)->
		doc = $window.document
		docViewTop = doc.body.scrollTop
		docViewBottom = docViewTop + doc.documentElement.clientHeight
		for i in [imgs.length-1..0]
			return i if _inView(imgs[i], docViewTop, docViewBottom)

	return {
		restrict: "A"
		scope: false
		link : (scope, element, attrs)->
			# ???: how do I set scope.focus and have photos watch that value?
			cache = attrs.lazyload/2

			_lazyload = _.debounce (e)->
					imgs = element.find('IMG')
					focus =  _getFocus(imgs)
					_.each imgs, (img, i, l)->
						return if !img.hasAttribute('photo')

						isVisible =  focus - cache <= i && i <= focus + cache
						if isVisible
							stashed = img.getAttribute('stash-src')
							if stashed
								img.src = stashed
								# console.warn "RESTORE i="+i+" ,src=" + img.getAttribute('stash-src')[0..100]
								img.setAttribute('stash-src','')
						else 
							return if img.getAttribute('stash-src')
							img.style.height = img.clientHeight+'px'
							img.setAttribute('stash-src', img.src)
							img.src = ''	
				, 100


			angular.element($window).on 'scroll', _lazyload
			scope.$on '$destroy', ()->
				# pager.unbind()
				angular.element($window).off 'scroll', _lazyload

	}
])
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
.directive('paginateDeck', [ '$compile', '$window', ($compile, $window)->
	return {
		restrict: "A"
		scope:
			perpage: "="
			deck: "=paginateDeck"
		link : (scope, element, attrs)->
			# TODO: use pull down to refresh pattern for pull up
			scope.remaining = 0
			element.append('<div ng-include="\'/common/templates/_pager.html\'"></div>')
			
			_updatePager = ()->
				total = scope.deck.size()
				showing = scope.deck.paginatedCards("showing")
				scope.remaining = total-showing
				if scope.remaining == 0 
					angular.element($window).off 'scroll', _paginateAfterScroll


			# same as infinite-scroll
			_paginateAfterScroll = _.debounce (e)->
						win = this
						el = element[0]
						win_bottom = win.pageYOffset + win.innerHeight
						el_bottom = el.offsetTop + el.offsetHeight
						if scope.remaining && el_bottom < (win_bottom + 100) 
							scope.deck.paginatedCards("more")
							_updatePager()
							scope.$apply()
						return
					, 100		# inifinite-scroll Timeout
					, {leading: false, trailing: true}

			angular.element($window).on 'scroll', _paginateAfterScroll

			scope.$on '$destroy', ()->
				# pager.unbind()
				angular.element($window).off 'scroll', _paginateAfterScroll

			# initialize to page=1, perpage=scope.perpage
			scope.deck.paginatedCards(scope.perpage) 
			_updatePager()	 	
			# ???: how do I use compile: and connect with link: scope?
			$compile(element.contents())(scope); 
			return
	}
])



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

