return if !angular? 

angular.module( 
	'appHappi'
).service( 'notifyService', [
	'$timeout'
	'appConfig'
	($timeout, CFG)->
		this.alerts = {}
		this.messages = {}
		this.timeouts = []
		this.alert = (msg=null, type='info', timeout)->
			return this.alerts if !CFG.debug || CFG.debug=='off'
			if msg? 
				timeout = timeout || CFG.notifyTimeout
				now = new Date().getTime()
				`while (this.alerts[now]) {
					now += 0.1;
				}`
				this.alerts[now] = {msg: msg, type:type, key:now} if msg?
				this.timeouts.push({key: now, value: timeout})
			else 
				# start timeouts on ng-repeat
				this.timerStart()
			return this.alerts
		# same as alert, but always show, ignore CFG.debug	
		this.message = (msg=null, type='info', timeout)->
			if msg? 
				timeout = timeout || CFG.messageTimeout
				now = new Date().getTime()
				`while (this.alerts[now]) {
					now += 0.1;
				}`
				if _.isObject(msg)
					# force notify.alert
					if msg.title?
						msg = "<h4>"+msg.title+"</h4><p>"+msg.message+"</p>"
					else 
						msg = msg.message

				this.messages[now] = {msg: msg, type:type, key:now} if msg?
				this.timeouts.push({key: now, value: timeout})
			else 
				# start timeouts on ng-repeat
				this.timerStart()
			return this.messages
		this.clearMessages = ()->
			this.messages = {}
		this.close = (key)->
			delete this.alerts[key] if this.alerts[key]
			delete this.messages[key] if this.messages[key]
		this.timerStart = ()->
			_.each this.timeouts, (o)=>
				$timeout (()=>
					delete this.alerts[o.key] if this.alerts[o.key]
					delete this.messages[o.key] if this.messages[o.key]
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
				'persistRating'
				'galleryGlow'
				'glowOnClick'
				'drawerItemClick'
				'goToMoment'
				'socialShare'
				'markPhotoForRemoval'
				'isMarkedForRemoval'
				'shuffleDeck'
			]

			_preventDefault : (e)->
				#export to window._preventDefault()
				e.preventDefault()
				e.stopImmediatePropagation()

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

			_backgroundDeferred: null

			# set up deferred BEFORE causing app to pause
			prepareToResumeApp : (e, notification)->
				return notify.alert "WARNING: already paused, check fake notify..." if self._backgroundDeferred?

				pauseTime = new Date().getTime()
				# return if !window.deviceReady
				notify.alert "Preparing to send App to background..." 
				self._backgroundDeferred = $q.defer()
				promise = self._backgroundDeferred.promise
				.then (o)->
					o.pauseDuration = (o.resumeTime - (pauseTime || 0))/1000
					o.notification = notification
					# notify.alert "App was prepared to resume, then sent to background, pauseDuration=" +o.pauseDuration
					return o
				.finally ()-> self._backgroundDeferred = null
				return promise
			
			resumeApp	 : (e)->
				return if !window.deviceReady
				$timeout (()=>
					if e == "LocalNotify" 
						notify.alert "App was resumed from FAKE LocalNotify", "success"
					else 	
						notify.alert "App was resumed from background"
					o = {
						event: e
						resumeTime: new Date().getTime() 
					}
					self._backgroundDeferred?.resolve( o )
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

			# on-touch="galleryGlow", imitates :bottom-row:hover
			galleryGlow : (e)->	
				$el = angular.element(e.currentTarget)
				switch e.type
					when "touchstart"
						$el.addClass 'touch'
					when "touchend"
						setTimeout( (()->$el.removeClass 'touch')
								, 5000)
				return

			# glow i.fa element on click
			glowOnClick : (e)->
				if e.target?.tagName
					$target = angular.element( e.target )
					$target.addClass('glow')
					e.preventDefault()
					e.stopImmediatePropagation()
					setTimeout( (()->$target.removeClass 'glow')
							, 2000)
				return true

			persistRating : (ev, i)->
				$target = angular.element(ev.currentTarget)
				now = new Date().toJSON()
				ev.preventDefault()
				# ev.stopImmediatePropagation() # bubble to glowOnClick
				switch $target.attr('rating-type')
					when "photo"
						switch this.card && this.card.type || 'timeline'
							when "moment"
								p = this.card.photos[i]
								this.card.stale = this.card.modified = now
								syncService.set('moment', this.card)
							when "challenge"
								p = this.card.challengePhotos[i]
								this.card.modified = now
								syncService.set('challenge', this.card)
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

			# deprecate, move to Drawer.coffee
			drawerItemClick : (e, callback)->

				return drawerService.drawerItemClick.apply(this, arguments)

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
				# ev.stopImmediatePropagation()  # pass to glowOnClick
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
				# e.type = {dblclick:remove, click:undo} for desktop, 'touchend' for touch
				notify.alert "markPhotoForRemoval, e.target="+e.target.tagName, 'info', 4000
				return if !(card && card.status=='active')
				return false if e.type=='click' && action=="remove" # discard
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
				# sort by key/index DESC
				removalIndexes = _.keys card.markPhotoForRemoval
				removalIndexes = removalIndexes.sort().reverse()
				_.each(removalIndexes, (index)->
						id = card.markPhotoForRemoval[index]
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
							momentIndex = m.photoIds.length - (parseInt(i)+1)	# reversed array
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

		# for element.ondragstart handler outside angular
		window._preventDefault = self._preventDefault

		return self
]
).controller( 'ChallengeCtrl', [
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
		# Controller: ChallengeCtrl
		#
		CFG.$curtain.find('h3').html('Loading Challenges...')
		notify.clearMessages() 

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

		# reset for testing
		syncService.clearAll() if $route.current.params.reset
		syncService.initLocalStorage() 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='findhappi'
				state = drawer.getDrawerItem('findhappi', 'current')
			drawer.init o.challenge, o.moment, state

			id = $route.current.params.id
			if !id?
				# route = '/challenges'
				_challenges = o.challenge 
			else if $location.path()=='/challenges/draw-new'
				_challenges = o.challenge 
				# draw new challenge after $scope.deck is set
			else if _.isNaN parseInt id 
				# route = '/challenges/birthday'
				f = {"name": id}
				_challenges = $filter('filter')(o.challenge, f)
			else if !_.isNaN parseInt id
				# route = '/challenges/23'
					f = {"id": id}
				_challenges = $filter('filter')(o.challenge, f)

			_cards = _.values _challenges
			deckOptions = {control: $scope.carousel}
			$scope.deck = deckService.setupDeck(_cards, deckOptions )

			if $location.path()=='/challenges/draw-new'
				_drawNewChallenge(_challenges)
				notify.message {
					title: "Your Challenge Awaits!"
					message: "Welcome back. We dare you to take on this Challenge! <span class='nowrap'>(But feel free to choose another.)</span>"
				}, null
				# 'drawer-findhappi-current'

			# redirect to all if no active challenge
			if (drawer.state.group=='findhappi' && drawer.state.item=='current')
				if drawer.state.counts['challenge']['active'] == 0
					$scope.drawerShowAll()
					if window.Modernizr.touch 
						# drawerItem.active not updating correctly on iOS
						# NOT WORKING on iOS
						angular.element(document.getElementById("drawer-findhappi-current")).removeClass('active')

				else # load moment, challengePhotos
					$scope.getChallengePhotos()

			# hide loading
			CFG.$curtain.addClass 'hidden'
			return

		# pick a new challenge to feature
		_drawNewChallenge = (challenges)->
			pickFrom = _.where challenges, {status:'new'}
			pickFrom = _.where challenges, {status:'pass'} if _.isEmpty(pickFrom) 
			pickFrom = _.where challenges, {status:'working'} if _.isEmpty(pickFrom) 
			pickFrom = _.where challenges, {status:'completed'} if _.isEmpty(pickFrom)
			pickFrom = challenges if _.isEmpty(pickFrom)
			# pick a challenge
			selected = _.sample(pickFrom)
			switch selected.status
				when "new","pass", "completed"
					$scope.challenge_new_moment(selected)
				when "working"
					$scope.challenge_open(selected)



		# deactivate any active challenges before activating a new one
		# set status to 'pass' if moment.photoIds.length=0
		# otherwise set status to 'working'
		_deactivateChallenges = (active)->
			if active?
				active = [active] if _.isPlainObject(active)
				active = _.where active, {type: 'challenge'}
			else 	
				active = _.where $scope.deck.allCards, {status:'active'}
			stale = []
			_.each active, (c)->
				hasMany = [c]
				newStatus = 'pass'
				stale.push c
				_.each actionService._getMoments( c ), (m)-> 
					if m.status=='active'
						stale.push m
						hasMany.push m
						newStatus = 'working' if m.photoIds.length
				actionService.setCardStatus(hasMany, newStatus)
			return stale		

		# get photos for 'active' challenge in reverse order
		$scope.getChallengePhotos = (c)->
				c = c || $scope.deck.topCard()
				return false if c.type=="challenge" && c.status!="active"
				m = _.findWhere actionService._getMoments(c), {status:'active'}
				return false if !m
				m.photos = actionService._getPhotos m if !m.photos?
				return false if !m.photos
				c.challengePhotos = m.photos.reverse()  	# for display of challenge only 'active'	
				return c.challengePhotos			
		
		$scope.drawerShowAll = ()->
			after_handleItemClick = (route)->
        $scope.deck.cards('refresh') 
        # $scope.deck.shuffle()
        return
			return actionService.drawerItemClick 'drawer-findhappi-all', after_handleItemClick


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
					if m.photoIds.indexOf(photo.id) == -1
						syncService.set('photo', photo)
						m.photoIds.push photo.id
						m.stats.count = m.photoIds.length
						m.stats.viewed += 1
						m.photos = actionService._getPhotos m
						actionService.setCardStatus(m, 'active', now)

						# notify.alert "Saved to moment.photos: count= " + m.photos.length + ", last=" + m.photos[m.photos.length-1].src , 'success', 5000 
						$scope.deck.topCard().challengePhotos = $filter('reverse')(m.photos)  	# for display of challenge only 'active'
						syncService.set('moment', m)
						
						# notify.alert "Challenge saveToMoment, IMG.src="+photo.src[0..60], "success", 20000
					else 
						notify.alert "That photo was already added", "warning"
					icon.removeClass('fa-spin')
				return


			if !navigator.camera
				promise = cameraService.getPicture($event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "danger", 10000 )
				return true	# continue to input[type=file] handler
			else
				promise = cameraService.getPicture(cameraService.cameraOptions.fromPhotoLibrary, $event)
				promise.then( saveToMoment ).catch( (message)->notify.alert message, "danger", 15000 )
			return;

		$scope.challenge_pass = ()->
			if drawer.state.filter?.status =='active' && (c = $scope.deck.topCard())
				# set status=pass if current card, then show all challenges
				stale =_deactivateChallenges(c)
				m = _.findWhere stale, {type:'moment'}
				# m = $scope.moment || _.findWhere  actionService._getMoments( c ), {status:'active'} 
				
				if m.photoIds.length==0 
					m.remove = true 		# remove empty moment
					c.momentIds.splice(c.momentIds.indexOf(m.id), 1)
					drawer.state.counts['gethappi'] -= 1
					# actionService.setCardStatus(c, 'pass')

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
			if m.photoIds.length
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
				return actionService.drawerItemClick 'drawer-gethappi-mostrecent'
			else # no photos selected
				_onConfirm = (isCallback=false)->
					$scope.challenge_pass()
					return $scope.$apply() if isCallback
				if navigator.notification
					navigator.notification.confirm("You haven't found any photos for this Challenge.", # message
									(index)->return _onConfirm("callback") if index==2 ,
									"Are you sure you are Done?" # title	
									['Cancel', 'Yes']
								)
				else 
					 resp = window.confirm("Are you sure you are Done? You haven't found any photos for this Challenge.")
						_onConfirm() if (resp==true)

			

		$scope.challenge_open = (c)->
			deactivated = _deactivateChallenges() 

			c = $scope.deck.topCard() if !c
			stale = [c]
			now = new Date()

			m = _.findWhere  actionService._getMoments( c ), {status:'working'} 

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

			after_handleItemClick = (route)->
        $scope.deck.cards('refresh') 
        return

			return actionService.drawerItemClick 'drawer-findhappi-current', after_handleItemClick


		# @param challenge c
		# @return moment 

		# TODO: change to accept
		$scope.challenge_new_moment = (c)->
			deactivated = _deactivateChallenges()

			c = $scope.deck.topCard() if !c
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

			after_handleItemClick = (route)->
        $scope.deck.cards('refresh') 
        return

			return actionService.drawerItemClick 'drawer-findhappi-current', after_handleItemClick


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
		notify.clearMessages() 

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
		
		# reset for testing
		syncService.clearAll() if $route.current.params.reset
		syncService.initLocalStorage()  

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='gethappi'
				state = drawer.getDrawerItem('gethappi', 'mostrecent')

			# wrap challenges in a Deck
			_challenges = deckService.setupDeck(o.challenge)

			id = $route.current.params.id
			if !id?
				# route = '/moments'
				# TODO: deprecate, confirm moments should not be saved as pass...
				_moments = $filter('filter')(o.moment, {status:"!pass"})
			else if $location.path()=='/moments/shuffle'
				_moments = $filter('filter')(o.moment, {status:"!pass"})
			else if _.isNaN parseInt id 
				# route = '/moments/birthday'
				f = {"name": $route.current.params.id}
				_moments = $filter('filter')(_.values( o.moment ), f)
			else if !_.isNaN parseInt id
				# route = '/moments/23'
				f = {"id": $route.current.params.id}
				_moments = $filter('filter')(_.values( o.moment ), f)


			# get nextCard
			_cards = _.values _moments 
			deckOptions = {control: $scope.carousel} 
			$scope.deck = deckService.setupDeck(_cards, deckOptions )
			if $location.path()=='/moments/shuffle'
				$scope.deck.shuffle()
				state = drawer.getDrawerItem('gethappi', 'shuffle')
				notify.message {
					title: "Enjoy a Moment of Happi!"
					message: "Welcome back. Enjoy this Moment, then take a moment to make another.
					<span class='nowrap'>(Find yourself another Challenge...)</span>"
				}, null

			drawer.init o.challenge, o.moment, state

			m = $scope.deck.topCard()
			if $route.current.params.id? && m?.status=='active'
				$scope.set_editMode(m) 

			# check if user just completed first challenge of the day
			_showSupportAfterFirstChallenge(m) if drawer.state['item']=='mostrecent' 
				
			# hide loading
			CFG.$curtain.addClass 'hidden'
			return  

		_showSupportAfterFirstChallenge = (m)->
			_wasJustNow = (m)->
				# moment was just created
				return false if !m || !(m.modified == m.challenge?.modified)
				return new Date() - new Date(m.modified) < 5000	  # 5 sec delay
			_wasYesterday = (last2)-> 
				# prev moment was created yesterday
				return true if last2.length < 2
				last = new Date(last2[0].created).getDate()
				prev = new Date(last2[1].created).getDate()
				return true if last >  prev || last == 1
			_showReminder = ()->
				# show reminder after loading MomentCtrl
				notify.message {
					title: "Congratulations!"
					message: "You got your 5 minutes in for the day. Enjoy this Moment of Happi and remember to pace yourself by setting a Reminder for the next time."
				}, null, 30000
				return true
			if _wasJustNow(m)
				last2 = $filter('orderBy')($scope.deck.allCards, '-created')[0...2]
				# ask to set reminder if first challenge of the day
				_showReminder() if _wasYesterday(last2)
			return
			    

		$scope.drawerShowAll = ()->
			return drawer.drawerItemClick 'drawer-findhappi-all'

		$scope.lazyLoadGallery = ($index, offset)->
			# BUG: $index no longer accurately represents card.index, why?
			# use carouselBufferSize for "lazyLoad"
			return true
			offset = offset || CFG.gallery?.lazyloadOffset || 2
			isVisible = Math.abs($index - $scope.carousel.index) <= offset
			return isVisible


		$scope.moment_rating = (ev, value)->
			ev.preventDefault()
			ev.stopImmediatePropagation()
			card = $scope.deck.topCard()
			card.stats.rating.moment += value
			card.stats.rating.moment = 0 if card.stats.rating.moment<0
			card.stats.rating.moment = 5 if card.stats.rating.moment>5
			actionService.persistRating.call {card:card}, ev

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
					if m.photoIds.indexOf(photo.id) == -1
						syncService.set('photo', photo)
						m.photoIds.push photo.id 
						m.stats.count = m.photoIds.length
						m.stats.viewed += 1
						m.photos = actionService._getPhotos m
						actionService.setCardStatus(m, 'active', now)

						# notify.alert "Saved to moment.photos: count= " + m.photos.length + ", last=" + m.photos[m.photos.length-1].src , 'success', 5000 
						syncService.set('moment', m)
					else 
						notify.alert "That photo was already added", "warning"
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
		notify.clearMessages() 

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
		
		# reset for testing
		syncService.clearAll() if $route.current.params.reset
		syncService.initLocalStorage() 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			syncService.setForeignKeys(o.challenge, o.moment)
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='timeline'
				state = drawer.getDrawerItem('timeline', 'photos')
			drawer.init o.challenge, o.moment, state

			if $route.current.params.id?
				# filter moments by id
				f = {"id": $route.current.params.id}
				_photos = $filter('filter')(_.values( o.photo ), f)
			else 
				_photos = o.photo

			# get nextCard
			_cards = _.values _photos 
			deckOptions = {
				control: $scope.carousel
			} 
			$scope.deck = deckService.setupDeck(_cards, deckOptions )

			# hide loading
			CFG.$curtain.addClass 'hidden'
			return  

		$scope.drawerShowAll = ()->
			return drawer.drawerItemClick 'drawer-findhappi-all'

		$scope.showImgSrc = ($event)->
			# target = $event.target
			thumb = $event.target.parentNode.parentNode.parentNode.parentNode
			img = thumb.querySelector('img')
			scope = angular.element(thumb).scope()
			notify.alert "img.src="+img.src[0..60], "warning", 3000
			notify.alert "img.fileURI="+scope.photo.fileURI, "danger", 3000
			return

		return;
	]
).controller( 'SettingsCtrl', [
	'appConfig'
	'notifyService'
	'actionService'
	'syncService'
	'drawerService'
	'$location'
	'$timeout'
	'$scope'
	'$q'
	(CFG, notify, actionService, syncService, drawer, $location, $timeout, $scope, $q)->
		# localNotification Plugin
		class LocalNotify 
			constructor: (options)->
				self = this
				self._notify = self.loadPlugin()
				return

			isReady: ()->
				return !!this._notify

			loadPlugin: ()->
				if window.plugin?.notification?.local? 
					this._notify = window.plugin.notification.local
				if this.isReady()
					this._notify.onadd = this.onadd
					this._notify.ontrigger = this.ontrigger
					this._notify.onclick = this.onclick
					this._notify.oncancel = this.oncancel
					notify.alert "localNotify, callbacks added", "success"
				else 	
					notify.alert "LocalNotification plugin is NOT available"
					this._notify = false
				return this._notify

			showDefaults: ()->
				return false if !this._notify
				notify.alert JSON.stringify(this._notify.getDefaults()), "warning", 40000

			add: (delay=5, notification={})->
				# notify.alert "window.plugin.notification.local"+ JSON.stringify (window.plugin.notification.local ), "info", 60000
				# notify.alert "LocalNotify._notify="+ JSON.stringify (this._notify ), "warning"

				now = new Date().getTime()
				target = new Date( now + delay*1000)
				msg = {
						id: now 				# seems to crash on id:0 (?)
					date: target
				}
				msg['title'] = notification.title if notification.title?
				msg['message'] = notification.message if notification.message?
				msg['repeat'] = notification.repeat if notification.repeat?
				msg['badge'] = notification.badge || 1
				msg['autoCancel'] = true
				msg['json'] = JSON.stringify(notification.data) if notification.data?

				# notify.alert "localNotify.add() BEFORE message="+JSON.stringify( msg ), null, 30000
				self = this
				try 
					if this.isReady()
						this._notify.add(msg)
						notify.alert "localNotify.add()  AFTER message="+JSON.stringify( msg ), "danger", 30000
						notify.message({
							title: "A reminder was set to fire in "+ delay+" seconds"
							message: "To see the notification, press the 'Home' button and close this app." 
							}, null, 4500)
					else 
						# msg.message = "EMULATED: "+msg.message
						# notify.alert "localNotification EMULATED, delay="+delay
						# $timeout (()->
						# 	notify.message(msg)
						# ), delay*1000
						this.fakeNotify(delay, notification)
				catch error
					notify.alert "EXCEPTION: notification.local.add(), error="+JSON.stringify error, "danger", 60000
		
			# @param except string or array of Strings
			_cancelScheduled : (except)->
				self = this
				except = [except] if !_.isArray(except) 
				this._notify.getScheduledIds (ids)->
					_.each ids, (id)->
						return if except.indexOf(id) > -1
						notify.alert "_cancelScheduled, id="+id, "warning", 30000
						self._notify.cancel(id)

			# @params state = [foreground | background]
			onadd :(id,state,json)=>
				notify.alert "onadd state="+state+", json="+json, "info"
				except = id
				this._cancelScheduled(except)
				return true

			ontrigger :(id,state,json)=>
				# state=foreground
				if state=='foreground'
					notify.alert "ontrigger state="+state+", json="+json, "success"
					# Note: The ontrigger callback is only invoked in background if the app is not suspended!
					this._notify.cancel(id)
				else this.onclick.apply(this, arguments)
				return true

			onclick :(id,state,json)=>
				# state=background
				try 
					notify.alert "onclick state="+state+", json="+json, "success"
					# this._notify.cancel(id)
					this._notify.cancelAll()
					target = JSON.parse(json).target
					$location.path(target)
				catch error
					notify.alert "EXCEPTION: localNotify.onclick(), error="+JSON.stringify error, "danger", 60000
				return true

			oncancel :(id,state,json)=>
				notify.alert "CANCEL oncancel state="+state+", json="+json, "info"
				# this.scheduled.slice(this.scheduled.indexOf(id),1)
				return true

			fakeNotify: (delay, notification)=>
				_isAwakeWhenNotificationFired = ()->
					# simple Toggle
					_isAwakeWhenNotificationFired.toggle = _isAwakeWhenNotificationFired.toggle || {}
					_isAwakeWhenNotificationFired.toggle.value = !_isAwakeWhenNotificationFired.toggle.value 
					return _isAwakeWhenNotificationFired.toggle.value

				_isLongSleep = (sleep)->
					LONG_SLEEP = 10 # 60*60 == 1 hour
					return sleep > LONG_SLEEP
				#
				# FAKE notification emulating steroids api pause/resume
				# for testing on desktop & touch 
				# until touch localNotification plugin works
				#
				_handleResumeOrLocalNotify = (o)->
					notify.alert "resuming with o="+JSON.stringify o

					wasAlreadyAwake = _isAwakeWhenNotificationFired()

					if wasAlreadyAwake && o.event=="LocalNotify"
						# just show notification as alert, do not navigate
						context =  "<br /><p>(Pretend this notification fired while the app was already in use.)</p>" 
						o.notification.message += context
						notify.alert "LocalNotify fired when already awake", "warning"
						type = if wasAlreadyAwake then "info" else "success"
						notify.message(o.notification, type)
					
					else if _isLongSleep(o.pauseDuration) 
						# resume/localNotify from LongSleep should navigate to notification target, 
						# 		i.e. active challenge, moment, or photo of the day

						# pick a random challenge and activate
						notify.alert "LocalNotify LONG SLEEP detected, pauseDuration=" + o.pauseDuration, "success"
						if wasAlreadyAwake
							context =  "<br /><p>(Pretend this notification fired while the app was already in use.)</p>" 
						else 
							context =  "<br /><p><b>(Pretend you got here after clicking from the Notification Center.)</b><p>" 
						o.notification.message += context	
						type = if wasAlreadyAwake then "info" else "success"
						notify.message(o.notification, type, 20000)
						# after LONG_SLEEP, goto active challenge 'drawer-findhappi-current'
						$timeout (()->
							actionService.drawerItemClick('drawer-findhappi-current')
						), 2000
					else if !wasAlreadyAwake
						# resume from shortSleep should just resume, not alert
						# localNotify from shortSleep should just show notification as alert, do not navigate
						type = if wasAlreadyAwake then "info" else "success"
						notify.message(o.notification, type)

					return

				window.deviceReady = "fake" if !window.deviceReady
				promise = actionService.prepareToResumeApp(null, notification)
					.then( _handleResumeOrLocalNotify )
				$timeout (()->
					# notify.alert "FAKE localNotification fired, delay was sec="+delay
					actionService.resumeApp("LocalNotify")
				), delay*1000
				notify.message({message: "LocalNotify set to fire, delay="+delay}, "warning", 2000)
				return			
		#
		# end Class Notify
		#


		# 
		#	settingsCtrl
		#
		# redirect to /getting-started if necessary
		if $location.path()=='/getting-started/check' && syncService.get('settings')?['hideGettingStarted']
			$location.path('/challenges') 

		CFG.$curtain.find('h3').html('Loading Settings...')
		notify.clearMessages() 	

		$scope.notify = window.notify = notify
		_.each actionService.exports, (key)->
			$scope[key] = actionService[key] 

		$scope.drawer = drawer

		# reset for testing
		syncService.initLocalStorage() 

		$q.all( syncService.promises ).then (o)->
			# reload or init drawer
			state = syncService.get('drawerState')
			if _.isEmpty(state) || state.group !='settings'
				state = drawer.getDrawerItem('settings', 'gettingstarted')
			drawer.init o.challenge, o.moment, state		# load to get counts
			# hide loading
			CFG.$curtain.addClass 'hidden'




		# ************************* Reminders ******************************
		localNotify = new LocalNotify()

		# need more copy for notifications
		notifications = [
			{
				title: "Your 5 Minutes of Happi Starts Now"
				message: "Spend 5 minutes to find some Happi - a new challenge awaits!"
				data: {
					target: "/challenges/draw-new"
				}
			},
			{
				title: "Get Your Happi for the Day"
				message: "This Happi moment was made possible by your '5 minutes a day'. Grab a smile and make another."
				data: {
					target: "/moments/shuffle"	
				}
				
			}
		]


		$scope.localNotification = (sec)->
			localNotify.loadPlugin() if !localNotify.isReady()
			message = _.sample notifications
			# notify.alert "$scope.localNotification(): message="+JSON.stringify message
			localNotify.add sec, message
			


		# ************************* Getting Started ******************************8
		$scope.carouselIndex = null
		$scope.formatCardBody = (body)->
			body = body.join("</p><p>") if _.isArray(body) 
			return "<p>"+body+"</p>"
		$scope.gettingStartedDone = ()->
			settings = syncService.get('settings')
			settings['hideGettingStarted']=true
			syncService.set('settings', settings)
			drawer.drawerItemClick('drawer-findhappi-current')
				

		$scope.gettingStarted = [
			{
				icon: "fa-bullhorn"
				subhead: "Getting Started"
				title:"#TooManyPhotos #Overwhelmed #<i class='fa fa-frown-o'>"
				body:[
					"Forever scrolling through your CameraRoll? Can't find the photo you know is there?"
					"""
					Snaphappi is here to help. 
					We take the 'work' out of your CameraRoll by making it <u><b>Play</b></u>. 
					Find the Happi moments in your CameraRoll and put them at the tip of your fingers.
					"""
					"""
					Re-living moments, telling stories, sharing photos — 
					everything is <u><b>Easy</b></u> when you can see the big picture.
					"""
				]
				footer: ""
			}
			{
				icon: "fa-clock-o"
				subhead: "Getting Started"
				title:"Just 5 Minutes a Day"
				body:[
					"Don't be overwhelmed. Just 5 minutes a day gets you a Happi CameraRoll."
					"""
					<ul>
					<li>Find <i class='fa fa-picture-o'></i> and build Happi Moments from your CameraRoll.</li>
					</li><li>Set <i class='fa fa-bell'></i> to catch you when you have a few minutes to spare.
					</li><li>Re-live a Moment and brighten your day <i class='fa fa-smile-o'></i> !
					</li><li>Share <i class='fa fa-picture-o'></i> with your <i class='fa fa-users'></i>.
					</li></ul>
					"""
				]
				footer: "Think of this as a personal trainer for your CameraRoll"
			}
			{
				icon: "fa-search"
				subhead: "Find Happi"
				title:"Your Challenge Awaits!"
				body:[
					"We've got fun Challenges that cover every corner of your CameraRoll."
					"""
					We'll offer a new Challenge every day, or feel free to pick your own.
					<i class='fa fa-search'></i> your CameraRoll with a fresh perspective and build a Happi Moment.
					"""
					"""
					<ul>
					<li>swipe <i class='fa fa-arrows-h'></i> to see more Challenges
					</li><li><i class='fa fa-hand-o-down'></i> 'Accept' to take on a Challenge, or <i class='fa fa-hand-o-down'></i> 'Repeat'
					</li><li>tap <i class='fa fa-picture-o'></i> to access your CameraRoll
					</li></ul>
					"""
					"No pressure — you can always add to your Moments later."
				]
				# footer:"Rise to the Challenge, it's your destiny"
			}
			{
				icon: "fa-smile-o"
				subhead: "Get Happi"
				title:"Take a Moment to Get Happi"
				body:[
					"Re-live all your best Moments from one place."
					"""
					<ul>
					<li>tap <i class='fa fa-chevron-down'></i> for details
					</li><li><i class='fa fa-star'></i><i class='fa fa-star'></i><i class='fa fa-star'></i><i class='fa fa-star'></i><i class='fa fa-star'></i> your favorite Moments for quick access
					</li><li>tap <i class='fa fa-pencil-square-o'></i> to edit your Moments
					</li><li>tap <i class='fa fa-picture-o'></i> to add more photos
					</li><li>long-tap a photo in <i class='fa fa-pencil-square-o'></i> mode to remove
					</li></ul>
					"""
					"Make this your 'go-to' place for those times when you're feeling <i class='fa fa-meh-o'></i>, or even <i class='fa fa-frown-o'></i>"
				]
			}
			{
				icon: "fa-calendar"
				subhead: "Timeline"
				title:"This is Easy"
				body:[
					"""
					The Timeline is where all your hard work pays off.  
					No more digging through your CameraRoll — all your <i class='fa fa-heart'></i> photos are at the tip of your fingers(!) 
					"""
					"""
					<ul>
					<li><i class='fa fa-star'></i><i class='fa fa-star'></i><i class='fa fa-star'></i><i class='fa fa-star'></i><i class='fa fa-star'></i> your favorite Photos for quick access
					</li><li>tap <i class='fa fa-arrow-up'></i> for easy sharing through <i class='fa fa-envelope'>, <i class='fa fa-facebook-square'></i>, <i class='fa fa-twitter-square'></i> 
					</li><li>tap <i class='fa fa-arrow-right'></i> to open the Moment
					</li></ul>
					"""
				]
				# footer:"This is Easy!"
			}
			{
				icon: "fa-bell"
				subhead: "Reminders"
				title:"Reminders"
				body:[
					"""
					Set a <i class='fa fa-bell'></i> to get your 5 minutes a day — every day. 
					Pick a <i class='fa fa-clock-o'></i> when you know you'll be playing games on your <i class='fa fa-mobile'></i> anyways.
					"""
					"Think of all the <i class='fa fa-smile-o'></i><i class='fa fa-smile-o'></i><i class='fa fa-smile-o'></i> you'll have!"
					"<br /><div class='title text-center'>That's it, you're ready to go!</div>"
				]
				footer:""
			}
		]
	]	
)
