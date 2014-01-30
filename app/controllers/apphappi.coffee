return if !angular? 

appHappi = angular.module( 'appHappi'
, [
	'ngRoute'
	, 'ngSanitize'
	, 'ui.bootstrap'
	, 'drawerModule'
	, 'syncModule'
	, 'angularMoment'
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
).filter('topCard', ()->
	return (cards, deck)->
		deck.index=0 if !deck.index? or deck.index >= cards.length
		if _.isArray(deck.shuffled)
			return cards[deck.shuffled[deck.index]] if deck.shuffled.length==cards.length
			deck.shuffled = 'error';
		return cards[deck.index]

).factory('cardService', [
	'$filter'
	'drawerService'
	($filter, drawer)->
		cardService = {
			validateDeck : (cards, deck, options)->
				return deck.cards && cards.length == deck.cards.length && JSON.stringify options == deck.options

			setupDeck : (cards, deck={}, options={})->
				options = _.pick(options, ['filter', 'query', 'orderBy'])
				if !cardService.validateDeck cards, deck, options
					step = cards
					step = $filter('filter') step, options.filter if options.filter?
					step = $filter('filter') step, options.query if options.query?
					step = $filter('orderBy') step, options.orderBy if options.orderBy?
					deck.cards = step
					deck.options = JSON.stringify options
					deck.index = 0	
				return deck

			shuffleDeck : (deck)->
				unshuffled = []
				unshuffled.push i for i in [0..deck.cards.length-1]
				deck.index = 0;
				deck.shuffled = cardService._shuffleArray unshuffled
				return deck

			_shuffleArray : (o)->
				`for (i = o.length; i; j = Math.floor(Math.random() * i), x = o[--i], o[i] = o[j], o[j] = x)`
				return o		

			topCard : (deck)->
				return $filter('topCard') deck.cards, deck

			nextCard : (cards, deck={}, options={})->
				if cardService.validateDeck cards, deck, options
					deck.index++
				else
					valid = cardService.setupDeck cards, deck, options
				return cardService.topCard deck

			# for use with ng-repeat
			deckCards : (deck)->
				return deck.cards if !deck.shuffled?
				shuffledCards = _.map deck.shuffled, (el)->
					return deck.cards[el]
				return shuffledCards

		}
		return cardService
]		
).factory('cameraService', [
	'$q'
	($q)->
		noCameraService = {
			check: ()->
				alert('the Steriods camera API is not available')
		}
		return noCameraService if !window.Modernizr.touch 
		_deferred = null
		cameraService = {

  		# Camera options
			imageSrc : null

			cameraOptions :
			  fromPhotoLibrary:
			    quality: 100
			    destinationType: navigator.camera.DestinationType.IMAGE_URI
			    sourceType: navigator.camera.PictureSourceType.PHOTOLIBRARY
			    correctOrientation: true # Let Cordova correct the picture orientation (WebViews don't read EXIF data properly)
			    targetWidth: 600
			    popoverOptions: # iPad camera roll popover position
			      width: 768
			      height: 190
			      arrowDir: Camera.PopoverArrowDirection.ARROW_UP
			  fromCamera:
			    quality: 100
			    destinationType: navigator.camera.DestinationType.IMAGE_URI
			    correctOrientation: true
			    targetWidth: 600

			# Camera failure callback
			cameraError : (message)->
			  # navigator.notification.alert 'Cordova says: ' + message, null, 'Capturing the photo failed!'
				_deferred.reject message
				_deferred = null

			  # $scope.showSpinner = false
			  # $scope.$apply()

			# File system failure callback
			fileError : (error)->
			  # navigator.notification.alert "Cordova error code: " + error.code, null, "File system error!"
				_deferred.reject( "Cordova error code: " + error.code + " File system error!" ) if _deferred?
				_deferred = null
			  # $scope.showSpinner = false
			  # $scope.$apply()

			# Take a photo using the device's camera with given options, callback chain starts
			# returns a promise
			getPicture : (options)->
			  navigator.camera.getPicture cameraService.imageUriReceived, cameraService.cameraError, options
			  # $scope.showSpinner = true
			  # $scope.$apply()
			  _deferred.reject 'Camera getPicture cancelled' if _deferred?
			  _deferred = $q.defer()
			  return _deferred.promise


			# Move the selected photo from Cordova's default tmp folder to Steroids's user files folder
			imageUriReceived : (imageURI)->
				if _deferred?
					_deferred.resolve(imageURI) 
					_deferred = null
				alert "image received from CameraRoll, imageURI="+imageURI
				window.resolveLocalFileSystemURI imageURI, cameraService.gotFileObject, cameraService.fileError

			gotFileObject : (file)->
			  # Define a target directory for our file in the user files folder
			  # steroids.app variables require the Steroids ready event to be fired, so ensure that
			  steroids.on "ready", ->
			    targetDirURI = "file://" + steroids.app.absoluteUserFilesPath
			    fileName = "user_pic.png"

			    window.resolveLocalFileSystemURI(
			      targetDirURI
			      (directory)->
			        file.moveTo directory, fileName, cameraService.fileMoved, cameraService.fileError
			      cameraService.fileError
			    )

			# Store the moved file's URL into $scope.imageSrc
			# localhost serves files from both steroids.app.userFilesPath and steroids.app.path
			fileMoved : (file)->
				if _deferred?
					alert "photo copied to App space from CameraRoll, file=/"+file.name
					_deferred.resolve("/" + file.name) 
					_deferred = null
		}
		return cameraService
]		
).controller( 'ChallengeCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'drawerService'
	'syncService'
	'cardService'
	'cameraService'
	($scope, $filter, $q, $route, drawer, syncService, cardService, cameraService)->

		#
		# Controller: ChallengeCtrl
		#

		# attributes
		$scope.$route = $route
		$scope.cameraService = cameraService

		# card + deck iterator
		$scope.deck = {}
		$scope.cards = []
		$scope.card = null			# current challenge
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {  
      group: 'findhappi'  
      item: 'current'
      filter: null
      query: ''
      orderBy: 'category'
    }

		# reset for testing
		syncService.initLocalStorage(['challenge', 'moment', 'drawer'])	

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# init drawer
			state = syncService.get('drawerState')
			state = $scope.initialDrawerState if _.isEmpty(state)
			drawer.init o.challenge, o.moment, state
			
			o.moment = $filter('filter')(o.moment, {status:"!pass"})
			$scope.moments = o.moment
			# syncService.set('moment', $scope.moments)
			$scope.challenges = o.challenge 
			# syncService.set('challenge', $scope.challenges)

			# get nextCard
			$scope.cards = $scope.challenges
			$scope.deck = cardService.setupDeck($scope.cards, $scope.deck, drawer.state)
			$scope.card = cardService.nextCard($scope.cards, $scope.deck, drawer.state)
			return 			

		# methods
		$scope.drawerShowAll = ()->
			drawer.itemClick drawer.getDrawerItem('findhappi', 'all')
			$scope.card = cardService.nextCard($scope.cards, $scope.deck, drawer) 

		$scope.passCard = ()->
			if drawer.state.filter.status=='active' && $scope.card
				# set status=pass if current card, then show all challenges
				$scope.card.status='pass'
				console.warn "save to localStorage"
				return $scope.drawerShowAll()
			return $scope.card = cardService.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.nextCard = ()->
			return $scope.card = cardService.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.itemClick = (groupName, options)->
			options.group = groupName
			options.item = options.name
			return drawer.itemClick options, ()->
				if options.name=='shuffle'
					$scope.deck = cardService.setupDeck $scope.cards, $scope.deck, drawer.state
					cardService.shuffleDeck( $scope.deck )
				return $scope.card = cardService.nextCard($scope.cards, $scope.deck, drawer.state) 

		$scope.shuffleDeck = ()->
			$scope.deck = cardService.setupDeck($scope.cards, $scope.deck, drawer.state)
			cardService.shuffleDeck( $scope.deck )
			return cardService.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.accept = ()->
			# pass current Challenge to FindHappi
			return $scope.challenge

		$scope.later = ()->
			# set current challenge, then put app to sleep
			# on wake, should open to current challenge
			return $scope.challege

		$scope.getPhoto = ()->
			saveToMoment = (uri)->
				alert "camera roll, file $scope.cameraRollSrc=" + uri
				$scope.cameraRollSrc = uri
				
				moment = _.findWhere $scope.card.moments, {status:'active'}

				if moment? && _.isArray moment.photos
					photo = {
						id: `new Date().getTime()`
						src: uri
					}
					moment.photos.push photo
					# alert "moment.photos: " + JSON.stringify _.reduce moment.photos, ((last, o)->
					# 			last.push o.src 
					# 			return last 
					# 		), []
					syncService.set('moment', $scope.moments)

				return


			if !window.Modernizr.touch
				uri = 'http://ww2.hdnux.com/photos/25/76/31/5760625/8/centerpiece.jpg'
				dfd = $q.defer()
				dfd.promise.then saveToMoment
				dfd.resolve(uri) 
			else
				cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary).then saveToMoment
						
		return;
	]
).controller( 'MomentCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'drawerService'
	'syncService'
	'cardService'
	($scope, $filter, $q, $route, drawer, syncService, cardService)->
		#
		# Controller: MomentCtrl
		#

		# attributes
		$scope.$route = $route

		# card + deck iterator
		$scope.deck = {}
		$scope.cards = []
		$scope.card = null			# current moment
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {
			group: 'gethappi'
			item: 'mostRecent'
			filter: null
			query: ''
			orderBy: 'modified'	
		}
		
		# reset for testing
		syncService.clearAll() if $scope.$route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer'])	

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# init drawer
			state = syncService.get('drawerState')
			state = $scope.initialDrawerState if _.isEmpty(state)
			drawer.init o.challenge, o.moment, state
			
			o.moment = $filter('filter')(o.moment, {status:"!pass"})
			$scope.moments = o.moment
			# syncService.set('moment', $scope.moments)
			$scope.challenges = o.challenge 
			# syncService.set('challenge', $scope.challenges)

			# get nextCard
			$scope.cards = $scope.moments
			$scope.deck = cardService.setupDeck($scope.cards, $scope.deck, drawer.state)
			$scope.card = cardService.nextCard($scope.cards, $scope.deck, drawer.state)
			# for use with ng-repeat, card in deckCards
			$scope.deckCards = cardService.deckCards($scope.deck)	
			return 			

		# methods
		$scope.nextCard = ()->
			return $scope.card = cardService.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.itemClick = (groupName, options)->
			options.group = groupName
			options.item = options.name
			return drawer.itemClick options, ()->
				if options.name=='shuffle'
					$scope.deck = cardService.setupDeck $scope.cards, $scope.deck, drawer.state
				$scope.deckCards = cardService.deckCards cardService.shuffleDeck $scope.deck 
				# return $scope.card = cardService.nextCard($scope.cards, $scope.deck, drawer.state) 

		$scope.shuffleDeck = ()->
			$scope.deck = cardService.setupDeck($scope.cards, $scope.deck, drawer.state)
			cardService.shuffleDeck( $scope.deck )
			return $scope.deckCards = cardService.deckCards cardService.shuffleDeck $scope.deck 
			# return cardService.nextCard($scope.cards, $scope.deck, drawer.state)

		return;
	]
)

# bootstrap 
if window.Modernizr.touch
	document.addEventListener "deviceready", ()->
		angular.bootstrap document, ['appHappi']
else 
	angular.element(document).ready ()->
	angular.bootstrap document.getElementById('ng-app'), ['appHappi']
