return if !angular? 

angular.module( 
	'appHappi'
).service( 'notifyService', [
	'$timeout'
	'appConfig'
	($timeout, appConfig)->
		this.alerts = {}
		this.timeouts = []
		this.alert = (msg=null, type='info', timeout)->
			return if !appConfig.debug || appConfig.debug=='off'
			if msg? 
				timeout = timeout || appConfig.notifyTimeout
				now = new Date().getTime()
				this.alerts[now] = {msg: msg, type:type, key:now} if msg?
				this.timeouts.push({key: now, value: timeout})
			else 
				# start timeouts on ng-repeat
				this.timerStart()
			return this.alerts 
		this.close = (key)->
			delete this.alerts[key]
		this.timerStart = ()->
			_.each this.timeouts, (o)=>
				$timeout (()=>
					delete this.alerts[o.key]
					), o.value
			this.timeouts = []	
		return	
]
).factory( 'actionService', [ 
	'drawerService'
	'deckService'
	'syncService'
	'notifyService'
	'$q'
	'$location'
	'$timeout'
	(drawerService, deckService, syncService, notify, $q, $location, $timeout)->

		self = {

			exports: [
				# 'setCardStatus'
				'persistRating'
				'drawerItemClick'
				'goToMoment'
				'socialShare'
				'markPhotoForRemoval'
				'isMarkedForRemoval'
				'shuffleDeck'
				# 'swipe'
			]

			_getMoments : (c)->
				return [] if c.type != 'challenge'
				return _.map c.momentIds, (id)->
					return syncService.get('moment', id)

			_getPhotos : (m)->
				return [] if m.type != 'moment'
				return _.map m.photoIds, (id)->
					return syncService.get('photo', id)

			_getMomentHasManyPhotos: (p)->
				moments = syncService.get('moment')
				found = _.reduce moments, ((result, m)->
							result.push(m) if m.photoIds.indexOf(p.id)>-1
							return result
						)
						, []
				return _.unique(found)

			_getChallengePhotos : (c)->
				c = c || deckService.topCard()
				return false if c.type=="challenge" && c.status="active"
				m = _.findWhere actionService._getMoments(c), {status:'active'}
				return false if !m
				m.photos = actionService._getPhotos m if !m.photos?
				return false if !m.photos
				c.challengePhotos = $filter('reverse')(m.photos)  	# for display of challenge only 'active'	
				return c.challengePhotos				

			_backgroundDeferred: null

			# set up deferred BEFORE causing app to pause
			prepareToResumeApp : (e)->
				return if !window.deviceReady
				if e?
					if !self._backgroundDeferred?
						notify.alert "App was NOT prepared to resume after being sent to background" 
				else
					notify.alert "App was prepared to resume, then sent to background" 
					self._backgroundDeferred = $q.defer()
					self._backgroundDeferred.finally ()-> self._backgroundDeferred = null
					return self._backgroundDeferred.promise
			
			resumeApp	 : (e)->
				return if !window.deviceReady
				$timeout (()=>
					notify.alert "App was resumed from background"
					self._backgroundDeferred?.resolve(e)
				), 0
				
				

			# do housekeeping when changing status of challenge, moment
			setCardStatus : (card, status, now)->
				now = new Date() if !now?
				card = [card] if _.isPlainObject(card) 
				_.each card, (o)->
					oldStatus = o.status
					o.status = status
					o.stale = o.modified = now.toJSON() 
					# update drawer counts
					isDrawerStale = false
					if oldStatus != status && o.type == 'challenge'
						drawerService.state.counts[o.type][oldStatus] -= 1 if drawerService.state.counts[o.type][oldStatus]?
						drawerService.state.counts[o.type][status] += 1 if drawerService.state.counts[o.type][status]?
						console.log drawerService.state.counts[o.type]
						isDrawerStale = true
					if o.type=='moment' && oldStatus==null
						drawerService.state.counts['gethappi'] += 1
						isDrawerStale = true
					# if (o.type=='challenge')
					# 	notify.alert "setCardStatus: "+oldStatus+" -> "+status+', stale='+isDrawerStale, "success"
					return
				syncService.set('drawerState') if isDrawerStale?


			persistRating : (ev, i)->
				$target = angular.element(ev.currentTarget)
				now = new Date().toJSON()
				ev.preventDefault()
				ev.stopImmediatePropagation()
				switch $target.attr('rating-type')
					when "photo"
						switch this.card && this.card.type || 'timeline'
							when "moment"
								p = this.card.photos[i]
								this.card.stale = this.card.modified = now
								syncService.set('moment', this.card)
							when "challenge"
								p = this.moment.photos[i]
								this.moment.stale = this.card.modified = now
								syncService.set('moment', this.moment)
							when "timeline"
								p = this.photo
						p.stale = now
						syncService.set('photo', p)

					when "moment"
						this.card.stale = this.card.modified = now
						syncService.set('moment', this.card)
					when "challenge"
						this.card.stale = this.card.modified = now

						syncService.set('moment', this.card)
						# also update challenge
						c = this.card.challenge
						c.stats.ratings.push(this.card.stats.rating.challenge)
						c.stale = true	
						syncService.set('challenge', this.card.challenge)

			drawerItemClick : (e, groupName, options)->
				# set active
				scope = this
				if _.isString(e)
					target = {id: e} 
				else 
					target = e.currentTarget 

				[type, group, item] = target.id?.split('-') || []
				if type == 'drawer'
					options = {
						group: group
						item: item
					}
					notify.alert "nav to: "+_.values(options).join("-")
				else 
					# deprecate
					notify.alert "deprecated in drawerItemClick()", 'warning'
					options = {item: options} if _.isString(options)
					options.item = options.name if options?.name?
					options.group = groupName
				
				return drawerService.itemClick options, (route)->
					# drawerService.state is updated with new filter/query/search, setupDeck
					isValid = scope.deck.validateDeck()
					if !isValid
						scope.deck.cards('refresh')
					scope.deck.shuffle() if options.name=='shuffle' || options.shuffle

					# check topCard
					c = scope.deck.topCard()
					self._getChallengePhotos(c) if c.type=="challenge" && c.status="active"

					if route? && route != $location.path()
						$location.path(route)
					# else
					# 	notify.alert "NOT setting NEW route"	, "warning"
						# check = scope.deck.nextCard()

			goToMoment : (ev, i)->
				return if !/\/timeline/.test($location.path()) 
				ev.preventDefault()
				ev.stopImmediatePropagation()
				scope = this
				mids = self._getMomentHasManyPhotos(this.photo)
				# TODO: let user choose which moment
				if !mids.length
					throw "ERROR: matching moment not found for photo, id="+this.photo.id
				if mids.length > 1
					notify.alert "WARNING: found more than 1 moments, just using the first", "warning"

				options = {
					group: 'gethappi'
					item: 'mostrecent'
					filter: 
						id: mids[0].id
				}
				return drawerService.itemClick options, (route)->
					# drawerService.state is updated with new filter/query/search, setupDeck
					# isValid = scope.deck.validateDeck()
					# if !isValid
					# 	scope.deck.cards('refresh')
					if route? && route != $location.path()
						$location.path(route)

			socialShare : (ev, i)->
				ev.preventDefault()
				ev.stopImmediatePropagation()
				photo = this.photo
				isDataURL = /^data\:image\/jpeg/.test(this.photo.src)
				# notify.alert _.keys window.plugins, "info", 5000
				shareViaFB = ()->
					$timeout( window.plugins.socialsharing.shareVia( 
						'com.apple.social.facebook',
						'shared from AppHappi', 
						null, # subject
						photo.src, 
						null, # link
						null, # success cb
						(errormsg)->
							if (errormsg=='not available')
								notify.alert "ShareViaFacebook NOT AVAILABLE, trying shareViaAny()", "warning", 10000
								shareViaAny()
							else 
								notify.alert "ShareViaFacebook NOT AVAILABLE, msg="+errormsg, "danger", 10000
					), 0)
				shareViaAny = ()->
					$timeout( window.plugins.socialsharing.share(
													'shared from AppHappi',  
													null, 
													photo.src, 
													null,
													null, # success cb
													(()->notify.alert "socialsharing FAILED", "warning")
												), 0)
				window.plugins?.socialsharing?.available( 
					(isAvailable)->
						if (!isAvailable)
							console.info "socialsharing plugin is NOT available."
							return
						# shareViaFB()
						shareViaAny()
						return
				)
						



			markPhotoForRemoval : (card, e, i, action)->
				return if !(card && card.status=='active')
				# return if window.Modernizr?.touch && e.type == 'click'  # ng-swipe -> touchend
				notify.alert ".thumb action detected, type="+e.type+", action="+action, 'success'

				el = e.currentTarget;

				card.markPhotoForRemoval = {} if !card.markPhotoForRemoval?
				$card = angular.element(el)

				while $card.length && !$card.hasClass('thumb')
					$card = $card.parent()
				return if !$card.length

				# notify.alert "card, id="+$card.attr('id')

				eventHandled = false
				if !action?
					action = if $card.hasClass('remove') then 'undo' else 'remove'
				switch action
					when 'undo'
						if $card.hasClass('remove')
							eventHandled = true
							if card.markPhotoForRemoval[i]==$card.attr('id')
								delete card.markPhotoForRemoval[i] 
							else throw "markPhotoForRemoval 'undo' index, id mismatch"
					when 'remove'
						if !$card.hasClass('remove')
							notify.alert "marked for removal, id="+$card.attr('id')
							eventHandled = true
							card.markPhotoForRemoval[i] = $card.attr('id')

				if true || eventHandled
					e.preventDefault() 
					e.stopImmediatePropagation()
				return

			isMarkedForRemoval : (i, id)->
				return false if this.card?.status != 'active'
				marked = this.card?.markPhotoForRemoval?[i]==id
				return marked;

			removeMarkedPhotos : (card)->
				return if !card.markPhotoForRemoval?
				now = new Date().toJSON()
				_.each(card.markPhotoForRemoval, (id, index)->
						retval = self._removePhoto(card, index, id)
						card.stale = now
					)
				delete card.markPhotoForRemoval
				return

			_removePhoto : (card, i, id)->
				try
					throw "removePhoto() where card.status != active" if card.status!='active'
					model = card.type 
					switch model 
						when "moment"
							m = card
							momentIndex = i
						when "challenge"
							throw "challengePhotos is ALREADY null" if !card.challengePhotos
							throw "removePhoto() id mismatch" if id != card.challengePhotos[i].id
							m = _.findWhere self._getMoments(card), {status:'active'}
							momentIndex = m.photoIds.length - (i+1)	# reversed array
							challengeIndex = i
						else throw "invalid card type"

					# remove from array
					check1 = m.photoIds.splice(momentIndex, 1) if momentIndex?
					check2 = card.challengePhotos.splice(challengeIndex, 1)[0] if challengeIndex?
					if m.photos?
						check1b = m.photos && m.photos.splice(momentIndex, 1)
						throw "removePhoto() id mismatch" if id != check1[0] != check1b[0].id
					throw "removePhoto() challengePhotos id mismatch" if check2 && id != (check2.id || check2[0].id)

					# check for orphaned photo
					moments = syncService.get('moment')
					found = _.find( moments, (o)->
							return false if o.id == m.id
							return o.photoIds.indexOf(id) > -1
						)
					if !found 
						photo = syncService.get('photo', id)
						photo.remove = photo.stale = true
						syncService.set('photo', photo)


				catch error
					notify.alert error, 'warning', 10000
					return false

			shuffleDeck : ()->
				scope = this
				scope.deck.cards('refresh') if !scope.deck.validateDeck()
				scope.deck.shuffle()
				drawerService.animateClose(500)
				return 
		}

		# send App to background
		document.addEventListener("pause", self.prepareToResumeApp, false);

		# resume from pause (background)
		document.addEventListener("resume", self.resumeApp, false);

		return self
]
).controller( 'ChallengeCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'$location'
	'drawerService'
	'syncService'
	'deckService'
	'cameraService'
	'notifyService'
	'actionService'
	'appConfig'
	($scope, $filter, $q, $route, $location, drawer, syncService, deckService, cameraService, notify, actionService, CFG)->

		#
		# Controller: ChallengeCtrl
		#
		CFG.$curtain.find('h3').html('Loading Challenges...')

		_challenges = _moments = _cards = null

		# attributes
		# $scope.$route = $route
		# $scope.$location = $location
		# $scope.cameraService = cameraService
		$scope.notify = window.notify = notify
		$scope.CFG = CFG
		$scope.carousel = {index:0}

		_.each actionService.exports, (key)->
			$scope[key] = actionService[key] 

		$scope.drawer = drawer;
		$scope.initialDrawerState = {  
			group: 'findhappi'  
			item: 'current'
		}


		# reset for testing
		syncService.clearAll() if $route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer', 'photo']) 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='findhappi'
				drawerItemOptions = drawer.getDrawerItem('findhappi', 'current')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

			if $route.current.params.id?
				# filter challenges by id
				if _.isNaN parseInt $route.current.params.id 
					f = {"name": $route.current.params.id}
				else f = {"id": $route.current.params.id}
				_challenges = $filter('filter')(o.challenge, f)
			else 
				_challenges = o.challenge 

			_cards = _.values _challenges
			$scope.deck = deckService.setupDeck(_cards, _.extend( {control: $scope.carousel}, drawer.state ) )

			# redirect to all if no active challenge
			if (drawer.state.group=='findhappi' && drawer.state.item=='current')
				if drawer.state.counts['challenge']['active'] == 0
					$scope.drawerShowAll()
				else # load moment, challengePhotos
					c = $scope.deck.topCard()
					actionService._getChallengePhotos(c)

			# hide loading
			CFG.$curtain.addClass 'hidden'
			return

		# deactivate any active challenges before activating a new one
		_deactivateChallenges = (active)->
			if active?
				active = [active] if _.isPlainObject(active)
				active = _.where active, {type: 'challenge'}
			else 	
				active = _.where $scope.deck.allCards, {status:'active'}
			stale = []
			_.each active, (c)->
				stale.push c
				_.each actionService._getMoments( c ), (m)-> 
					if m.status=='active'
						stale.push m
			actionService.setCardStatus(stale, 'working')
			return stale				
		
		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			options.shuffle = true
			return $scope.drawerItemClick 'drawer-findhappi-all', 'findhappi', options


		$scope.challenge_getPhoto = ($event)->
			c = $scope.deck.topCard()
			m = $scope.moment || _.findWhere actionService._getMoments( c ), {status:'active'} 
			icon = angular.element($event.currentTarget.parentNode).find('i')
			icon.addClass('fa-spin')

			# @params p object, p.id, p.src
			saveToMoment = (p)->
				# notify.alert "Challenge saveToMoment "+JSON.stringify(p), "success", 20000
				now = new Date()
				if m?
					photo = _.defaults p, {
						type: 'photo'
						stale: now.toJSON()
						modified: now.toJSON()
					}
					# update moment
					syncService.set('photo', photo)
					m.photoIds.push photo.id
					m.stats.count = m.photoIds.length
					m.stats.viewed += 1
					m.photos = actionService._getPhotos m
					actionService.setCardStatus(m, 'active', now)

					# notify.alert "Saved to moment.photos: count= " + m.photos.length + ", last=" + m.photos[m.photos.length-1].src , 'success', 5000 
					$scope.deck.topCard().challengePhotos = $filter('reverse')(m.photos)  	# for display of challenge only 'active'
					syncService.set('moment', m)
					icon.removeClass('fa-spin')
					notify.alert "Challenge saveToMoment, IMG.src="+photo.src[0..60], "success", 20000
				return


			if !navigator.camera
				promise = cameraService.getPicture($event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "danger", 10000 )
				return true	# continue to input[type=file] handler
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary, $event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "danger", 15000 )
			return;

		$scope.challenge_pass = ($index)->
			if drawer.state.filter?.status =='active' && (c = $scope.deck.topCard())
				# set status=pass if current card, then show all challenges
				stale =_deactivateChallenges(c)
				actionService.setCardStatus(c, 'pass')	if c.momentIds.length==0 
				syncService.set('challenge', stale)
				syncService.set('moment', stale)
				# drawer.updateCounts( _challenges )	
				c.challengePhotos = null;
				$scope.moment = null
				return $scope.drawerShowAll()
			return $scope.deck.nextCard()  # $scope.carousel.index++


		$scope.challenge_done = ()->
			c = $scope.deck.topCard()
			now = new Date()
			m = $scope.moment || _.findWhere  actionService._getMoments( c ), {status:'active'} 
			throw "warning: challenge.status != active in $scope.challenge_done()" if c.status != 'active'
			throw "warning: moment.status != active in $scope.challenge_done()" if m.status != 'active'

			stale = [c, m]
			m.stats.completedIn += 123						# fix this
			m.stats.viewed += 1
			c.stats.completions.push m.stats.completedIn
			actionService.removeMarkedPhotos(c)
			c.challengePhotos = null;
			actionService.setCardStatus(stale, 'complete', now)
			syncService.set('challenge', stale)
			syncService.set('moment', stale)
			# drawer.updateCounts( _challenges )

			# clear 'active' challenge photos
			$scope.moment = null

			# goto moment
			return $scope.drawerItemClick 'drawer-gethappi-mostrecent', 'gethappi', {item:'mostrecent'}

		$scope.challenge_open = ()->
			deactivated = _deactivateChallenges()

			c = $scope.deck.topCard()
			stale = [c]
			now = new Date()

			m = $scope.moment || _.findWhere  actionService._getMoments( c ), {status:'working'} 

			if !m? && c.momentIds.length
					# working moment not found, just activate the first moment
					m = actionService._getMoments( c )[0]
			if !m?		
				throw "WARNING: open challenge without moment"
			stale.push m
			m.photos = actionService._getPhotos m
			moment = m
			$scope.moment = moment
			c.challengePhotos = $filter('reverse')(moment.photos)  	# for display of challenge only 'active'
			actionService.setCardStatus(stale, 'active', now)
			stale = stale.concat(deactivated)
			syncService.set('challenge', stale)
			syncService.set('moment', stale)		
			# drawer.updateCounts( _challenges)
			return $scope.drawerItemClick 'drawer-findhappi-current', 'findhappi', {item:'current'}


		# TODO: change to accept
		$scope.challenge_new_moment = ()->
			deactivated = _deactivateChallenges()

			c = $scope.deck.topCard()
			c.stats.accept += 1
			now = new Date()
			stale = [c]
			m = {
				id: now.getTime()+'-moment'
				type: 'moment'
				userId: CFG.userId
				challengeId: c.id
				stats: 
					count: 0
					completedIn: 0
					viewed: 0
					rating:
						moment: 0
						challenge: 0
				status: null
				created: now
				modified: now
				stale: now
				photoIds: []
				photos: []
			}

			stale.push m
			c.momentIds.push(m.id)
			$scope.moment = m
			c.challengePhotos = []  	# for display of challenge only 'active'

			actionService.setCardStatus(stale, 'active', now)
			stale = stale.concat(deactivated)
			syncService.set('challenge', stale)
			syncService.set('moment', stale)

			# debug
			check = syncService.get('challenge', c.id)
			notify.alert("challenge status="+check.status, 'success')


			# drawer.updateCounts( _challenges, syncService.localData['moment'] )
			return $scope.drawerItemClick 'drawer-findhappi-current', 'findhappi', {item:'current'}

		$scope.challenge_sleep = ()->
			# set current challenge, then put app to sleep
			# on wake, should open to current challenge
			notify.alert "Sleep Challenge clicked at "+new Date().toJSON(), "success", 5000
			return $scope.challege	

		return;
	]
).controller( 'MomentCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'$location'
	'$timeout'
	'drawerService'
	'syncService'
	'deckService'
	'cameraService'
	'notifyService'
	'actionService'
	'appConfig'
	($scope, $filter, $q, $route, $location, $timeout, drawer, syncService, deckService, cameraService, notify, actionService, CFG)->
		#
		# Controller: MomentCtrl
		#
		CFG.$curtain.find('h3').html('Loading Moments...')

		_challenges = _moments = _cards = null

		# attributes
		# $scope.$route = $route
		# $scope.$location = $location
		# $scope.cameraService = cameraService
		$scope.notify = window.notify = notify
		$scope.CFG = CFG
		$scope.carousel = {index:0}
		_.each actionService.exports, (key)->
			$scope[key] = actionService[key] 

		$scope.drawer = drawer;
		$scope.initialDrawerState = {
			group: 'gethappi'
			item: 'mostrecent'
		}
		
		# reset for testing
		syncService.clearAll() if $route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer', 'photo']) 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='gethappi'
				drawerItemOptions = drawer.getDrawerItem('gethappi', 'mostrecent')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

			# wrap challenges in a Deck
			_challenges = deckService.setupDeck(o.challenge)

			if $route.current.params.id?
				# filter moments by id
				if _.isNaN parseInt $route.current.params.id 
					f = {"name": $route.current.params.id}
				else f = {"id": $route.current.params.id}
				_moments = $filter('filter')(_.values( o.moment ), f)
			else 
				o.moment = $filter('filter')(o.moment, {status:"!pass"})
				_moments = o.moment



			# get nextCard
			_cards = _.values _moments 
			$scope.deck = deckService.setupDeck(_cards, _.extend( {control: $scope.carousel}, drawer.state ) )

			m = $scope.deck.topCard()
			if $route.current.params.id? && m?.status=='active'
				$scope.set_editMode(m) 


			# hide loading
			CFG.$curtain.addClass 'hidden'
			return      

		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			return $scope.drawerItemClick 'drawer-findhappi-all', 'findhappi', options

		$scope.moment_cancel = (id)->
			m = $scope.deck.topCard()
			throw "ERROR: moment.id mismatch" if m.id != id 
			notify.alert "Warning: no undo[photos] NOT found", "warning" if !m.undo['photos']?

			m.photos = m.undo['photos']
			delete m.undo['photos']

			actionService.setCardStatus(m, 'complete')	
			syncService.set('moment', m)
			# drawer.updateCounts( null, _moments )

			$location.path drawer.state.route 

		$scope.moment_done = (id)->
			m = $scope.deck.topCard()
			throw "ERROR: moment.id mismatch" if m.id != id 
			throw "warning: moment.status != active in $scope.moment_done()" if m.status != 'active'

			m.stats.count = m.photos.length
			m.stats.completedIn += 123						# fix this
			m.stats.viewed += 1
			delete m.undo['photos'] if m.undo?
			notify.alert( "warning: undo['photos'] not found", "warning" ) if !m.undo?

			actionService.removeMarkedPhotos(m)
			actionService.setCardStatus(m, 'complete')	
			syncService.set('moment', m)
			# drawer.updateCounts( null, _moments )

			$location.path drawer.state.route 

		$scope.moment_edit = (id)->
			m = $scope.deck.topCard()
			throw "ERROR: moment.id mismatch" if m.id != id 

			actionService.setCardStatus(m, 'active')	
			syncService.set('moment', m)
			# drawer.updateCounts( null, _moments )
			# nav to new route, then open in editMode
			$location.path editRroute = drawer.state.route + '/' + id

		$scope.set_editMode = (m)->
			# ???: should I set challenge to 'active'
			m.undo = {} if !m.undo?
			m.undo['photos'] = _.cloneDeep m.photos  # save undo info
			m.isCardExpanded = true

		$scope.moment_getPhoto = (id, $event)->
			m = $scope.deck.topCard() || _.findWhere _cards, {id: id}
			throw "moment id mismatch" if m.id != id
			icon = angular.element($event.currentTarget.parentNode).find('i')
			icon.addClass('fa-spin')

			saveToMoment = (p)->
				now = new Date()
				if m?
					photo = _.defaults p, {
						type: 'photo'
						stale: now.toJSON()
						modified: now.toJSON()
					}
					# update moment
					syncService.set('photo', photo)
					m.photoIds.push photo.id
					m.stats.count = m.photoIds.length
					m.stats.viewed += 1
					m.photos = actionService._getPhotos m
					actionService.setCardStatus(m, 'active', now)

					# notify.alert "Saved to moment.photos: count= " + m.photos.length + ", last=" + m.photos[m.photos.length-1].src , 'success', 5000 
					syncService.set('moment', m)
					icon.removeClass('fa-spin')
				return

			if !navigator.camera
				promise = cameraService.getPicture($event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )
				return true	# continue to input[type=file] handler
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary, $event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "warning", 10000 )			


		return;
	]
).controller( 'TimelineCtrl', [
	'$scope'
	'$filter'
	'$q'
	'$route'
	'$location'
	'drawerService'
	'syncService'
	'deckService'
	'notifyService'
	'actionService'
	'appConfig'
	($scope, $filter, $q, $route, $location, drawer, syncService, deckService, notify, actionService, CFG)->
		#
		# Controller: MomentCtrl
		#
		CFG.$curtain.find('h3').html('Loading Timeline...')

		_challenges = _moments = _cards = null

		# attributes
		# $scope.$route = $route
		# $scope.$location = $location
		# $scope.cameraService = cameraService
		$scope.notify = window.notify = notify
		$scope.CFG = CFG
		$scope.carousel = {index:0}
		_.each actionService.exports, (key)->
			$scope[key] = actionService[key] 

		$scope.drawer = drawer;
		$scope.initialDrawerState = {
			group: 'timeline'
			item: 'photos'
		}
		
		# reset for testing
		syncService.clearAll() if $route.current.params.reset
		syncService.initLocalStorage(['challenge', 'moment', 'drawer', 'photo']) 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='timeline'
				drawerItemOptions = drawer.getDrawerItem('timeline', 'photos')
				state = _.defaults $scope.initialDrawerState, drawerItemOptions 
			drawer.init o.challenge, o.moment, state

			if $route.current.params.id?
				# filter moments by id
				f = {"id": $route.current.params.id}
				_photos = $filter('filter')(_.values( o.photo ), f)
			else 
				_photos = o.photo

			# get nextCard
			_cards = _.values _photos 
			$scope.deck = deckService.setupDeck(_cards, _.extend( {control: $scope.carousel}, drawer.state ) )

			# hide loading
			CFG.$curtain.addClass 'hidden'
			return      

		$scope.drawerShowAll = ()->
			options = drawer.getDrawerItem('findhappi', 'all')
			return $scope.drawerItemClick 'drawer-findhappi-all', 'findhappi', options

		return;
	]
)