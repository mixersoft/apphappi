return if !angular? 

angular.module( 
	'appHappi'
).controller( 'ChallengeCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'drawerService'
	'syncService'
	'deckService'
	'cameraService'
	($scope, $filter, $q, $route, drawer, syncService, deck, cameraService)->

		#
		# Controller: ChallengeCtrl
		#

		# attributes
		$scope.$route = $route
		$scope.cameraService = cameraService

		# card + deck iterator
		$scope.deck = {}
		$scope.cards = []
		$scope.card = null      # current challenge
		$scope.$root.drawer = drawer

		$scope.initialDrawerState = {  
			group: 'findhappi'  
			item: 'current'
		}

		# reset for testing
		syncService.initLocalStorage(['challenge', 'moment', 'drawer']) 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='findhappi'
				drawerItemOptions = drawer.getDrawerItem('findhappi', 'current')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

			o.moment = $filter('filter')(o.moment, {status:"!pass"})
			$scope.moments = o.moment
			# syncService.set('moment', $scope.moments)
			$scope.challenges = o.challenge 
			# syncService.set('challenge', $scope.challenges)

			# get nextCard
			$scope.cards = $scope.challenges
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			

			# redirect to all if no active challenge
			if drawer.state.group=='findhappi' &&
          drawer.state.item=='current' &&
          drawer.state.counts['active'] == 0
        $scope.drawerShowAll()
      else   
      	return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)

		# methods
		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			return $scope.drawerItemClick 'findhappi', options

		$scope.passCard = ()->
			if drawer.state.filter.status=='active' && $scope.card
				# set status=pass if current card, then show all challenges
				_.each $scope.card.moments, (o)-> 
					if o.status=='active'
						$scope.card.status=o.status='working'
				$scope.card.status='pass' if $scope.card.status=='active'		

				syncService.set('challenge', $scope.challenges)
				syncService.set('moment', $scope.moments)
				return $scope.drawerShowAll()
			return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.nextCard = ()->
			return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)

		# returns deck.TopCard()
		$scope.drawerItemClick = (groupName, options)->
			options.group = groupName
			options.item = options.name
			return drawer.itemClick options, ()->
				if options.name=='shuffle'
					$scope.deck = deck.setupDeck $scope.cards, $scope.deck, drawer.state
					deck.shuffleDeck( $scope.deck )
				return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state) 

		$scope.shuffleDeck = ()->
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			deck.shuffleDeck( $scope.deck )
			return deck.nextCard($scope.cards, $scope.deck, drawer.state)

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
					alert "moment.photos: " + JSON.stringify _.reduce moment.photos, ((last, o)->
								last.push o.src 
								return last 
							), []
					syncService.set('moment', $scope.moments)

				return


			if !navigator.camera
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
	'deckService'
	($scope, $filter, $q, $route, drawer, syncService, deck)->
		#
		# Controller: MomentCtrl
		#

		# attributes
		$scope.$route = $route

		# card + deck iterator
		$scope.deck = {}
		$scope.cards = []
		$scope.card = null      # current moment
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
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='gethappi'
				drawerItemOptions = drawer.getDrawerItem('gethappi', 'mostRecent')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

			o.moment = $filter('filter')(o.moment, {status:"!pass"})
			$scope.moments = o.moment
			# syncService.set('moment', $scope.moments)
			$scope.challenges = o.challenge 
			# syncService.set('challenge', $scope.challenges)

			# get nextCard
			$scope.cards = $scope.moments
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			$scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)
			# for use with ng-repeat, card in deckCards
			$scope.deckCards = deck.deckCards($scope.deck) 
			return      

		# methods
		$scope.nextCard = ()->
			return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state)

		$scope.drawerItemClick = (groupName, options)->
			options.group = groupName
			options.item = options.name
			return drawer.itemClick options, ()->
				if options.name=='shuffle'
					$scope.deck = deck.setupDeck $scope.cards, $scope.deck, drawer.state
				$scope.deckCards = deck.deckCards deck.shuffleDeck $scope.deck 
				# return $scope.card = deck.nextCard($scope.cards, $scope.deck, drawer.state) 

		$scope.shuffleDeck = ()->
			$scope.deck = deck.setupDeck($scope.cards, $scope.deck, drawer.state)
			deck.shuffleDeck( $scope.deck )
			return $scope.deckCards = deck.deckCards deck.shuffleDeck $scope.deck 
			# return deck.nextCard($scope.cards, $scope.deck, drawer.state)

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
