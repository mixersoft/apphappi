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
				notification = {type:type, key:now} 
				if _.isObject(msg)
					if msg.template?
						notification['template'] = msg.template
					else if msg.title?
						notification['msg'] = "<h4>"+msg.title+"</h4><p>"+msg.message+"</p>"
					else 
						notification['msg'] = msg.message

				this.messages[now] = notification
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
).factory('cameraRoll', [
	'appConfig'
	'$window'
	'$injector'
	'$timeout'
	'$q'
	(CFG, $window, $injector, $timeout, $q)->
		#
		# load the correct service for the device
		# 	uses html5/plupload when run in browser
		#   navigator.camera.getPicture() when run as app in cordova
		#
		_cameraRollService = {}
		dfd = $q.defer()

		use_fallback = ()->
			type = "html5CameraService"
			_cameraRollService = $injector.get(type)
			dfd.resolve {
				type : type
				cameraRoll: _cameraRollService
			}

		use_snappiAssetsPickerService = ()->
			# return $injector.get('cordovaImpl')
			type = "snappiAssetsPickerService"
			_cameraRollService = $injector.get(type)
			dfd.resolve {
				type : type
				cameraRoll: _cameraRollService
			}	

		use_cordova = ()->
			# return $injector.get('cordovaImpl')
			type = "cordovaCameraService"
			_cameraRollService = $injector.get(type)
			dfd.resolve {
				type : type
				cameraRoll: _cameraRollService
			}

		if CFG.cameraRoll == "html5CameraService"
			use_fallback()
		if $window.deviceready	# already known, resolve immediately
			if ($window.cordova) 
				use_cordova()
			else 
				use_fallback()
		else 
			CAMERA_ROLL_TIMEOUT = 500
			cancel = $timeout use_fallback, CAMERA_ROLL_TIMEOUT	
			document.addEventListener "deviceready", ()->
				$timeout.cancel cancel
				if CFG.cameraRoll=='snappiAssetsPickerService'
					use_snappiAssetsPickerService()
				else if (CFG.cameraRoll=='cordovaCameraService' && $window.cordova) 
					use_cordova()
				else 
					use_fallback()
				return

		self = {
			isReady: false
			promise : null
			getPicture : ()-> 
				throw "WARNING: cameraRoll service is not ready yet. use cameraRoll.promise() " if !self.isReady
		}

		self.promise = dfd.promise.then (o)->
			self.isReady = true
			_.extend self, o.cameraRoll
			return self

		return self
	]
).factory( 'actionService', [ 
	'drawerService'
	'deckService'
	'cameraRoll'
	'syncService'
	'localNotificationService'
	'notifyService'
	'appConfig'
	'$location'
	'$timeout'
	'$rootScope'
	(drawerService, deckService, cameraRoll, syncService, localNotify, notify, appConfig, $location, $timeout, $rootScope)->
		CFG = $rootScope.CFG || appConfig
		self = {

			# export to $scope
			exports: [					
				'persistRating'
				'galleryGlow'
				'glowOnClick'
				'drawerItemClick'
				'goToMoment'
				'serverShare'
				'socialShare'
				'markPhotoForRemoval'
				'removeMarkedPhotoNow'
				'isMarkedForRemoval'
				'shuffleDeck'
				'nextReminder'	# SettingsCtrl only
				# 'reminderDays'	# SettingsCtrl only
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

			# share on server, post to apphappi.parseapp.com
			# view at http://apphappi.parseapp.com/stream/[uuid]
			serverShare : (ev, i, scope)-> 
				ev.preventDefault()
				target = ev.currentTarget
				photo = this.photo
				isDataURL = /^data\:image\/jpeg/.test(this.photo.src)

				###
				parse code
				###
				parseAPPID = "ksv7tSSSheFcPB4rk8mtYWzkpH8bXH4JWBAeTwFm";
				parseJSID = "c6OAp6Vr5qvCQSPgQFfY4I8t4u4tySea6K4KwUkN";
				 
				# //Initialize Parse
				Parse.initialize(parseAPPID,parseJSID);
				
				PhotoObj = Parse.Object.extend("Photo")
				StreamObj = Parse.Object.extend("Stream")

				
				# photo keys = [id, dateTaken, orig_ext, label, Exif, src, fileURI, rating ]
				checkPhoto = (photo)->
					return new Parse.Query(PhotoObj).get(photo.id).then (photoObj)->
							check = photoObj
							return photoObj
						, (error)->
							if error.code == 101
								return photo
							else 
								console.log "checkPhoto, not found?"
								console.log error

				uploadToParse = (base64src, streamId)->
					# query to find 
					parseFile = new Parse.File(photo.id + ".JPG", {
							base64: base64src
						})
					return parseFile.save().then (parseFile)->
								# save parseFile as photoObj
								serverPhoto = _.pick photo, ['dateTaken', 'label', 'Exif', 'rating']
								serverPhoto.src = parseFile.url()
								serverPhoto.fileObjId = parseFile.id
								serverPhoto.id = photo.id
								steroids.logger.log "uploadToParse() photo="+ JSON.stringify serverPhoto
								photoObj = new PhotoObj(serverPhoto)
								return photoObj
							, (err)->
								steroids.logger.log "ERROR: parse.save() JPG file"

				saveToStream = (photoObj)->
						serverPhoto = _.pick photo, ['dateTaken', 'label', 'Exif', 'rating']
						serverPhoto.src = photoObj.src
						

						if streamId? 
							return new Parse.Query(StreamObj).get(streamId).then (streamObj)->
								return streamObj.addUnique("photos", serverPhoto).save()
							.catch (err)->
									steroids.logger.log "parse.query.get() StreamObk id=" + streamId
						else 		
							streamObj = new StreamObj()
							return streamObj.set("photos",[serverPhoto]).save()

				if true || !isDataURL
					return checkPhoto(photo).then (photoObj)->
							return saveToStream( photoObj ).then (streamObj)->
									return streamObj
								, (error)->
									steroids.logger.log error

						, (photo)->
							# not found, new Photo 
							promise = cameraRoll.resample(photo.src)
								.then( uploadToParse)
								.then( saveToStream
									, (error)->
										steroids.logger.log error
										)

				else 
					base64src = photo.src
					uploadToParse( base64src )
					.then (parseFile)->
							saveToStream( parseFile ).then (streamObj)->
								photos = streamObj.get("photos")
								console.log photos
						, (error)->
							steroids.logger.log error			


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
				return if !(card && card.status=='active')
				return false if e.type=='click' && action=="remove" # discard
				notify.alert "markPhotoForRemoval, e.target="+e.target.tagName, 'info', 4000
				# return if window.Modernizr?.touch && e.type == 'click'  # ng-swipe -> touchend
				notify.alert ".thumb action detected, type="+e.type+", action="+action, 'success'

				el = e.currentTarget || e.target
				loop # same as $el.closest('.thumb')
					break if /\bthumb\b/.test(el.className)
					el = el.parentNode	
					return false if !el

				card.markPhotoForRemoval = {} if !card.markPhotoForRemoval?
				$card = angular.element(el)

				# while $card.length && !$card.hasClass('thumb')
				# 	$card = $card.parent()
				# return if !$card.length

				# notify.alert "card, id="+$card.attr('id')

				eventHandled = false
				if !action? || action=='toggle'
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

			# called by [done], remove ALL marked photos on save
			removeMarkedPhotos : (card)->
				return if _.isEmpty(card.markPhotoForRemoval)
				now = new Date().toJSON()
				# sort by key/index DESC
				removalIndexes = _.keys card.markPhotoForRemoval
				removalIndexes = removalIndexes.sort().reverse()
				_.each(removalIndexes, (index)->
						id = card.markPhotoForRemoval[index]
						retval = self._removePhoto(card, index, id)
						card.modified = card.stale = now
					)
				delete card.markPhotoForRemoval
				return

			# remove ONE marked photo immediately
			removeMarkedPhotoNow : ($event)->
				now = new Date().toJSON()
				scope = this
				p = scope.$parent.photo
				card = scope.$parent.$parent.card
				index = null
				_.find card.markPhotoForRemoval, (v,k)->
					return index = k if v==p.id
				if !index?	
					return throw "ERROR: removeMarkedPhotoNow, index not found in card.markPhotoForRemoval" 
				retval = self._removePhoto(card, index, p.id)
				if retval
					delete card.markPhotoForRemoval[index]
					card.modified = card.stale = now
					syncService.set(card.type, card)


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
						# TODO: remove photo.fileURL from filesystem


				catch error
					notify.alert error, 'warning', 10000
					return false

			shuffleDeck : ()->
				scope = this
				scope.deck.cards('refresh') if !scope.deck.validateDeck()
				scope.deck.shuffle()
				drawerService.animateClose(500)
				return 

			nextReminder : ()->
				reminder = syncService.notification()['date']
				return null if !reminder
				reminder = moment(reminder)
				return if reminder.isValid() then reminder.toDate() else null

			reminderDays : ()->
				days = syncService.notification().data?.repeat
				return days if days?
				# init to everyDay
				return _everyDay = {1:true,2:true,3:true,4:true,5:true,6:true,7:true} 

			getNotificationMessage : ()->
				return _.sample CFG.notifications	

			isLongSleep : localNotify.isLongSleep
		}


		# for element.ondragstart handler outside angular
		# used by thumbnail.html, deprecate(?)
		window._preventDefault = self._preventDefault

		return self
]
).controller( 'ChallengeCtrl', [
	'$scope'
	'$rootScope'
	'$filter'
	'$q'
	'$route'
	'$location'
	'$timeout'
	'drawerService'
	'syncService'
	'deckService'
	'cameraRoll'
	'actionService'
	'notifyService'
	'appConfig'
	($scope, $rootScope, $filter, $q, $route, $location, $timeout, drawer, syncService, deckService, cameraRoll, actionService, notify, appConfig)->

		#
		# Controller: ChallengeCtrl
		#
		CFG = $rootScope.CFG || appConfig
		drawer = $rootScope.drawer || drawer
		notify = $rootScope.notify || notify

		CFG.$curtain.find('h3').html('Loading Challenges...')
		notify.clearMessages() 

		_challenges = _moments = _cards = null

		# attributes
		$rootScope.title = "Challenges"
		$scope.carousel = {index:0}

		_.each actionService.exports, (key)->
			$scope[key] = actionService[key] 

		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			o = syncService.setForeignKeys()
			_.extend($rootScope.route, drawer.getRoute())
			drawer.init o.challenge, o.moment, $rootScope.route.drawerState

			id = $route.current.params.id
			# id = $scope.route.params[0]
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

			welcomeBack = _forceNewChallenge(_challenges)
			if $location.path()=='/challenges/draw-new' || welcomeBack
				_drawNewChallenge(_challenges)
				msg = {
					title: "Your Challenge Awaits!"
					message: "We dare you to take on this Challenge! <span class='nowrap'>(But feel free to choose another.)</span>"
				}
				msg.message = "Welcome back. " + msg.message if welcomeBack
				notify.message msg, null

			# redirect to all if no active challenge
			if (drawer.state.group=='findhappi' && drawer.state.item=='current')
				if drawer.state.counts['challenge']['active'] == 0
					$scope.drawerShowAll()
					# if window.Modernizr.touch 
					# 	# drawerItem.active not updating correctly on iOS
					# 	# NOT WORKING on iOS
					# 	angular.element(document.getElementById("drawer-findhappi-current")).removeClass('active')

				else # load moment, challengePhotos
					cameraRoll.promise.then ()->cameraRoll.prepare?()
					$scope.getChallengePhotos()

			# hide loading
			CFG.$curtain.addClass 'hidden'
			return

		# forceNewChallenge on longSleep...
		_forceNewChallenge = (challenges)->
			# pause since last challenge, use mostrecent
			pickFrom = _.where challenges, {status:'active'}
			return false if !_.isEmpty(pickFrom)
			pickFrom = _.where challenges, {status:'complete'} if _.isEmpty(pickFrom)
			return false if _.isEmpty(pickFrom)
			# find most recent by modified
			lastModifiedString = _.reduce pickFrom, (result, o)->
					return if o.modified > result then o.modified else result
				, ""
			sinceLastChallenge = (new Date().getTime() - new Date(lastModifiedString).getTime())/1000
			return actionService.isLongSleep(sinceLastChallenge)


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
		        $scope.deck.shuffle()
		        return
			return actionService.drawerItemClick 'drawer-findhappi-all', after_handleItemClick

		# called by either ng-click or FilesAdded.FilesAdded handler
		$scope.challenge_getPhoto = ($event)->
			
			$target = angular.element($event.currentTarget) 
			icon = $target.find('i')
			# icon.addClass('fa-spin') # spin AFTER we confirm some files were added

			c = $scope.deck.topCard()
			m = $scope.moment || _.findWhere actionService._getMoments( c ), {status:'active'} 
			duplicates = []
			isFirst = drawer.state.counts.challenge.complete==0 && m.photoIds.length == 0


			# @params p object, p.id, p.src
			saveToMoment = (p)->
				steroids.logger.log "saveToMoment, p=" + JSON.stringify p
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
						
						steroids.logger.log "Challenge saveToMoment, IMG.src="+photo.src
						steroids.logger.log "Challenge saveToMoment, photoIds="+JSON.stringify m.photoIds
					else 
						steroids.logger.log "************* DUPLICATE PHOTO ID ************"
						duplicates.push photo.id
					
					# check if this is the first photo
					if isFirst
						notify.message {
								title: "You Found Your First Photo!"
								message: "Good job. You can continue to add more photos, or just be done with this Challenge."
							}
				return

			# plupload supports multi-select!!
			if cameraRoll.type == 'html5CameraService' 
				# for plupload, JUST set the deferred/promise and let up.FilesAdded() do the rest
				#
				# console.log "challenge_getPhoto() at time=" + moment().format("ss.sss")
				dfd = $q.defer()
				dfd.id = moment().unix()
				$event.currentTarget.setAttribute('upload-id', dfd.id)

				promise = cameraRoll.setDeferred(dfd).then( (promises)->
					console.log "count of promises=" + promises.length
					$q.all(promises).finally ()->return icon.removeClass('fa-spin')	
					_.each promises, (promise)->
						promise.then( saveToMoment, (error)->
								console.error "deferred error=" + error
								notify.alert message, "danger", 10000 
						)	
				)
				return promise	
			else if cameraRoll.type == 'snappiAssetsPickerService' 
				# using cordova-plugin-assets-picker, change to snappi-assets-picker
				icon.addClass('fa-spin')
				dfd = $q.defer()
				dfd.id = moment().unix()
				$event.currentTarget.setAttribute('upload-id', dfd.id)
				options = cameraRoll.cameraOptions.fromPhotoLibrary
				# steroids.logger.log "##### m.photoIds=" + JSON.stringify m.photoIds
				options.overlay = {}
				if m.photoIds?.length
					m.photos = actionService._getPhotos m if m.photos?.length != m.photoIds.length
					options.overlay[Camera.Overlay.PREVIOUS_SELECTED] = _.reduce m.photos, (retval, o)->
							retval.push o.id + '.' + o.orig_ext if o.orig_ext?
							return retval
						,[]
					# steroids.logger.log "0 ##### options.overlay=" + JSON.stringify options.overlay	
				else options.overlay[Camera.Overlay.PREVIOUS_SELECTED] = []


				steroids.logger.log "challenge_getPhoto()" + JSON.stringify options
				promise = cameraRoll.getPicture(options, $event)
				.then (promises)->
					_.each promises, (promise)->
						promise.then( saveToMoment )
						.catch (error)->
							steroids.logger.log "deferred error=" + error
							notify.alert message, "danger", 10000 

					$q.all(promises).finally (all)->
						icon.removeClass('fa-spin')
						if duplicates.length	
							notify.message {
								title: "Duplicate Photos Selected"
								message: duplicates.length + " photo(s) were skipped because they were already added."
							},
							2000
						steroids.logger.log "DONE: ALL photos, count=" + _.values(all).length
						steroids.logger.log "photos=" + JSON.stringify _.pluck(all, "src")
						return 	
					return
				.catch (error)->
					icon.removeClass('fa-spin')	
					steroids.logger.log "deferred error=" + error
					notify.alert message, "danger", 10000 
				

				return promise		
			else if cameraRoll.type == 'cordovaCameraService' 
				icon.addClass('fa-spin')
				options = _.clone cameraRoll.cameraOptions.fromPhotoLibrary
				promise = cameraRoll.getPicture(options, $event)
				promise.then( saveToMoment )
				.catch (message)->
					steroids.logger.log message
					notify.alert message, "danger", 15000 
				.finally ()->
					return icon.removeClass('fa-spin')	

				return promise
			else 
				console.warn "Error: Invalid cameraRoll."	
				return false

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

		$scope.isDoneEnabled = ()->
			return false if $scope.deck.topCard().challengePhotos?.length==0
			return false if angular.element(document.getElementById('html5-get-file')).hasClass('fa-spin') 
			return true


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
				cameraRoll.promise.then ()->cameraRoll.prepare?()
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
				cameraRoll.promise.then ()->cameraRoll.prepare?()
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
	'$rootScope'
	'$filter'
	'$q'
	'$route'
	'$location'
	'$timeout'
	'drawerService'
	'syncService'
	'deckService'
	'cameraRoll'
	'actionService'
	'notifyService'
	'appConfig'
	($scope, $rootScope, $filter, $q, $route, $location, $timeout, drawer, syncService, deckService, cameraRoll,  actionService, notify, appConfig)->
		#
		# Controller: MomentCtrl
		#
		CFG = $rootScope.CFG || appConfig
		drawer = $rootScope.drawer || drawer
		notify = $rootScope.notify || notify

		CFG.$curtain.find('h3').html('Loading Moments...')
		notify.clearMessages() 

		_challenges = _moments = _cards = null

		# attributes
		$rootScope.title = "Moments"
		$scope.carousel = {index:0}
		_.each actionService.exports, (key)->
			$scope[key] = actionService[key] 

		syncService.initLocalStorage()  
		$q.all( syncService.promises ).then (o)->
			# rebuild FKs
			o = syncService.setForeignKeys()
			# wrap challenges in a Deck
			_challenges = deckService.setupDeck(o.challenge)

			id = $route.current.params.id
			# id = $scope.route.params[0]
			if !id?
				# route = '/moments'
				# TODO: deprecate, confirm moments should not be saved as pass...
				_moments = $filter('filter')(o.moment, {status:"!pass"})
			else if $location.path()=='/moments/shuffle'
				_moments = $filter('filter')(o.moment, {status:"!pass"})
			else if _.isNaN parseInt id 
				# route = '/moments/birthday'
				f = {"name": id}
				_moments = $filter('filter')(_.values( o.moment ), f)
			else if !_.isNaN parseInt id
				# route = '/moments/23'
				f = {"id": id}
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

			# drawer.init o.challenge, o.moment, state
			_.extend($rootScope.route, drawer.getRoute())
			drawer.init o.challenge, o.moment, $rootScope.route.drawerState

			m = $scope.deck.topCard()
			if id? && m?.status=='active'
				$scope.set_editMode(m) 
			else 
				_collapseCardOnChange()	

			# check if user just completed first challenge of the day
			_showSupportAfterFirstChallenge(m) if m.state=="complete" && drawer.state['item']=='mostrecent' 
			
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
					template: '/common/templates/notify/_setAReminder.html'
					# title: "Congratulations!"
					# message: "You got your 5 minutes in for the day. Enjoy this Moment of Happi and remember to pace yourself by setting a Reminder for the next time."
				}, null, 30000
				return true
			if _wasJustNow(m)
				last2 = $filter('orderBy')($scope.deck.allCards, '-created')[0...2]
				# ask to set reminder if first challenge of the day
				_showReminder() if _wasYesterday(last2)
			return

		# return card to default on carousel change
		_collapseCardOnChange = ()->
			$scope.$watch 'carousel.index', (newVal, prevVal)->
				try 
					delete $scope.deck.cards()[prevVal].isCardExpanded = false if !!prevVal
				catch error
			    

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

		$scope.isDoneEnabled = ()->
			return false if $scope.deck.topCard().photoIds.length==0
			# disable [Done] button if waiting for img downsizing to complete
			return false if angular.element(document.getElementById('html5-get-file')).hasClass('fa-spin') 
			return true	

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
			cameraRoll.promise.then ()->cameraRoll.prepare?()

		$scope.moment_delete = (id)->	
			m = $scope.deck.topCard()
			throw "ERROR: moment.id mismatch" if m.id != id 
			throw "warning: moment.status == active in $scope.moment_delete()" if m.status == 'active'

			# delete moment & photos as necessary
			_deleteCb = ()->
				moment = syncService.get('moment', id)

				# remove moment photos
				markPhotoForRemoval = {}
				_.each moment.photoIds, (v,i,l)->
						markPhotoForRemoval[i] = v
				moment.markPhotoForRemoval = markPhotoForRemoval
				moment.status = 'active'
				actionService.removeMarkedPhotos moment

				# remove belongsTo Challenge
				c = moment.challenge
				found = c.momentIds.indexOf(moment.id)
				if found >  -1
					c.momentIds.splice(found, 1)
					if c.momentIds.length == 0 
						actionService.setCardStatus(c, 'pass')
				else 
					return throw "Error: moment does not belongTo challenge" 

				# remove moment
				moment.remove = moment.stale = true
				syncService.set('moment', moment)
				syncService.set('challenge', c)
				drawer.updateCounts()

				# reload
				$scope.deck.removeFromDeck(moment)
				$location.path('/moments')
				# window.location.reload()
				return	# end remove Callback

			# confirm delete
			if navigator.notification
			  _onConfirm = (index)->
			    _deleteCb() if index==2
			    return
			  navigator.notification.confirm(
			          "You are about to delete everything and reset the App.", # message
			          _onConfirm,
			          "Are you sure?", # title 
			          ['Cancel', 'OK']
			        )
			else
			  resp = window.confirm('Are you sure you want to delete this moment?')
			  _deleteCb() if resp
			  return


		$scope.moment_getPhoto = (id, $event)->
			m = $scope.deck.topCard() || _.findWhere _cards, {id: id}
			throw "moment id mismatch" if m.id != id
			$target = angular.element($event.currentTarget) 
			icon = $target.find('i')
			duplicates = []
			# icon.addClass('fa-spin') # spin AFTER we confirm some files were added

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
						steroids.logger.log "************* DUPLICATE PHOTO ID ************"
						duplicates.push photo.id

				return

			# plupload supports multi-select!!
			if cameraRoll.type == 'html5CameraService' 
				# for plupload, JUST set the deferred/promise and let up.FilesAdded() do the rest
				#
				# console.log "moment_getPhoto() at time=" + moment().format("ss.sss")
				dfd = $q.defer()
				dfd.id = moment().unix()
				$event.currentTarget.setAttribute('upload-id', dfd.id)

				promise = cameraRoll.setDeferred(dfd).then( (promises)->
					console.log "count of promises=" + promises.length
					$q.all(promises).finally ()->return icon.removeClass('fa-spin')	
					_.each promises, (promise)->
						promise.then( saveToMoment, (error)->
								console.error "deferred error=" + error
								notify.alert message, "danger", 10000 
						)	
				)
				return promise
			else if cameraRoll.type == 'snappiAssetsPickerService' 
				# using cordova-plugin-assets-picker, change to snappi-assets-picker
				icon.addClass('fa-spin')
				dfd = $q.defer()
				dfd.id = moment().unix()
				$event.currentTarget.setAttribute('upload-id', dfd.id)
				options = cameraRoll.cameraOptions.fromPhotoLibrary
				options.overlay = {}
				if m.photoIds?.length
					m.photos = actionService._getPhotos m if m.photos?.length != m.photoIds.length
					options.overlay[Camera.Overlay.PREVIOUS_SELECTED] = _.reduce m.photos, (retval, o)->
							retval.push o.id + '.' + o.orig_ext if o.orig_ext?
							return retval
						,[]
					# steroids.logger.log "0 ##### options.overlay=" + JSON.stringify options.overlay	
				else options.overlay[Camera.Overlay.PREVIOUS_SELECTED] = []		

				steroids.logger.log "moment_getPhoto()" + JSON.stringify options
				promise = cameraRoll.getPicture(options, $event)
				.then (promises)->
					_.each promises, (promise)->
						promise.then( saveToMoment )
						.catch (error)->
							steroids.logger.log "deferred error=" + error
							notify.alert message, "danger", 10000 

					$q.all(promises).finally (all)->
						icon.removeClass('fa-spin')
						if duplicates.length	
							notify.message {
								title: "Duplicate Photos Selected"
								message: duplicates.length + " photo(s) were skipped because they were already added."
							},
							2000
						steroids.logger.log "DONE: ALL photos, count=" + _.values(all).length
						steroids.logger.log "photos=" + JSON.stringify _.pluck(all, "src")
						return 	
					return
				.catch (error)->
					icon.removeClass('fa-spin')	
					steroids.logger.log "deferred error=" + error
					notify.alert message, "danger", 10000 
				

				return promise		
			else if cameraRoll.type == 'cordovaCameraService' 
				icon.addClass('fa-spin')
				options = _.clone cameraRoll.cameraOptions.fromPhotoLibrary
				promise = cameraRoll.getPicture(options, $event)
				promise.then( saveToMoment )
				.catch (message)->
					steroids.logger.log message
					notify.alert message, "danger", 15000 
				.finally ()->
					return icon.removeClass('fa-spin')	

				return promise
			else 
				console.warn "Error: Invalid cameraRoll."	
				return false


		return
	]
).controller( 'TimelineCtrl', [
	'$scope'
	'$rootScope'
	'$filter'
	'$q'
	'$route'
	'$location'
	'drawerService'
	'syncService'
	'deckService'
	'actionService'
	'notifyService'
	'appConfig'
	($scope, $rootScope, $filter, $q, $route, $location, drawer, syncService, deckService,  actionService, notify, appConfig)->
		#
		# Controller: TimelineCtrl
		#
		CFG = $rootScope.CFG || appConfig
		drawer = $rootScope.drawer || drawer
		notify = $rootScope.notify || notify

		CFG.$curtain.find('h3').html('Loading Timeline...')
		notify.clearMessages() 

		_challenges = _moments = _cards = null

		# attributes
		$scope.CFG = CFG
		$rootScope.title = "Timeline"
		$scope.carousel = {index:0}
		_.each actionService.exports, (key)->
			$scope[key] = actionService[key] 

		syncService.initLocalStorage() 
		$q.all( syncService.promises ).then (o)->
			# rebuild FKs 
			# NOTE: o.challenge == localData.challenge, etc. THESE OBJECTS ARE ORIGINALS, not CLONES
			o = syncService.setForeignKeys()
			_.extend($rootScope.route, drawer.getRoute())
			drawer.init o.challenge, o.moment, $rootScope.route.drawerState

			id = $route.current.params.id?
			# id = $scope.route.params[0]
			if id	
				# filter moments by id
				f = {"id": id}
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
	'$scope'
	'$rootScope'
	'syncService'
	'drawerService'
	'$location'
	'$timeout'
	'$q'
	'localNotificationService'
	'actionService'
	'notifyService'
	'appConfig'
	($scope, $rootScope, syncService, drawer, $location, $timeout, $q, localNotify, actionService, notify, appConfig)->
		try 
			# 
			#	settingsCtrl
			#
			# redirect to /getting-started if necessary
			if $location.path()=='/getting-started/check' && syncService.get('settings')?['hideGettingStarted']
				return $location.path('/challenges') # goto /challenges/all or /challenges/draw-new???

			CFG = $rootScope.CFG || appConfig
			drawer = $rootScope.drawer || drawer
			notify = $rootScope.notify || notify

			CFG.$curtain.find('h3').html('Loading Settings...')
			# notify.clearMessages() 	

			if $location.path() == '/getting-started/check'
				try 
					# badge plugin: https://github.com/katzer/cordova-plugin-badge.git
					localNotify.clearBadge()
				catch error
					CFG.$curtain.addClass 'hidden'
					notify.alert "EXCEPTION: localNotify.onclick(), badge clear error="+JSON.stringify error, "danger", 60000

				$rootScope.title = "AppHappi"
			else $rootScope.title = "Settings"

			_.each actionService.exports, (key)->
				$scope[key] = actionService[key] 


			# ************************* Reminders ******************************
			now  = new Date()
			if $location.path()=='/settings/reminders' 
				# localNotify = new LocalNotify()
				if !localNotify.isReady()
					notify.message {
							title: "Note: Reminders Are Emulated"
							message: """
								Reminders are emulated in this desktop configuration because Notifications are <u>not</u> available. 
								To get actual notifications you will need to install the AppHappi app.
								"""
						}
					, null, 10000

			_roundToQuarterHour = (date, today)->
				date = new Date() if !date?
				minutes = date.getMinutes()
				hours = date.getHours()
				m = (((minutes + 7.5)/15 | 0) * 15) % 60
				h = (((minutes/105 + .5) | 0) + hours) % 24
				if today		# convert future datetime to today at same time
					now = new Date()
					return new Date now.getFullYear(), now.getMonth(), now.getDate(), h, m
				return new Date date.getFullYear(), date.getMonth(), date.getDate(), h, m

			$scope.reminderTime = _roundToQuarterHour(actionService.nextReminder(), "today")
			$scope.reminderDays = actionService.reminderDays()
			notify.alert "Timepicker time= " + $scope.reminderTime + ", next reminder="+actionService.nextReminder(), 'info', 30000

			# repeat:  ['secondly', 'minutely', 'hourly', 'daily', 'weekly', 'monthly' or 'yearly']
			$scope.localNotificationTime = (date, schedule)->
				localNotify.loadPlugin() if !localNotify.isReady()
				# sample message from ontrigger()
				# date = new Date(date.getTime() + 24*3600*1000) if date < new Date()
				message = actionService.getNotificationMessage()
				message['schedule'] = schedule || null
				# notify.alert "$scope.localNotification(): message="+JSON.stringify message
				localNotify.addByDate date, message
				# steroids.logger.log "$scope.localNotificationTime: addByDate() COMPLETE"

			$scope.localNotificationDelay = (sec)->
				localNotify.loadPlugin() if !localNotify.isReady()
				# notify.alert "$scope.localNotification(): message="+JSON.stringify message
				localNotify.addByDelay sec, actionService.getNotificationMessage()
				


			# ************************* Getting Started ******************************8
			$scope.carouselIndex = null
			$scope.formatCardBody = (body)->
				body = body.join("</p><p>") if _.isArray(body) 
				return "<p>"+body+"</p>"
			$scope.gettingStartedDone = ()->
				settings = syncService.get('settings')
				settings['hideGettingStarted'] = true
				syncService.set('settings', settings)
				$location.path('/challenges/draw-new')
					

			syncService.initLocalStorage() 
			$q.all( syncService.promises ).then (o)->
				_.extend($rootScope.route, drawer.getRoute())
				drawer.init o.challenge, o.moment, $rootScope.route.drawerState
				CFG.$curtain.addClass 'hidden'
		catch error
			# steroids.logger.log "EXCEPTION: error="+JSON.stringify error

	]	
)
