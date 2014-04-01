return if !angular? 

angular.module(
	'appHappi'
).factory( 'localNotificationService', [ 
	'$location'
	'$timeout'
	'$q'
	'appConfig'
	'notifyService'
	'drawerService'
	'syncService'
	($location, $timeout, $q, appConfig, notify, drawerService, syncService)->
		CFG = appConfig

		_isLongSleep = (sleep)->
			LONG_SLEEP = CFG.longSleepTimeout # 60*60 == 1 hour
			return sleep > LONG_SLEEP

		# wrapper class for working with the localNotification plugin
		# includes 'emulated' mode for desktop browser testing without the plugin
		class LocalNotify 
			constructor: (options)->
				self = this
				# self._notify = self.loadPlugin()
				document.addEventListener "deviceready", ()->
					self.loadPlugin()
				return

			init: ()->
				this.loadPlugin()	if !this.isReady()

			isReady: ()->
				return !!this._notify

			loadPlugin: ()->
				if window.plugin?.notification?.local? 
					this._notify = window.plugin.notification.local
					this._notify.setDefaults({ autoCancel: true })

				if this.isReady()
					this._notify.onadd = this.onadd
					this._notify.ontrigger = this.ontrigger
					this._notify.onclick = this.onclick
					this._notify.oncancel = this.oncancel
					# notify.alert "localNotify, callbacks added", "success"
				else 	
					notify.alert "LocalNotification plugin is NOT available"
					this._notify = false
				return this._notify

			showDefaults: ()->
				return false if !this._notify
				notify.alert JSON.stringify(this._notify.getDefaults()), "warning", 40000

			isLongSleep	: _isLongSleep

			addByDelay: (delay=5, notification={})->
				# notify.alert "window.plugin.notification.local"+ JSON.stringify (window.plugin.notification.local ), "info", 60000
				# notify.alert "LocalNotify._notify="+ JSON.stringify (this._notify ), "warning"

				now = new Date().getTime()
				target = new Date( now + delay*1000)
				this.addByDate target, notification

			addByDate: (date, notification={})->
				msg = {
						id: date.getTime() 				# seems to crash on id:0 (?)
					date: date
				}
				msg['title'] = notification.title if notification.title?
				msg['message'] = notification.message if notification.message?
				msg['badge'] = notification.badge || 1
				msg['autoCancel'] = true 								# set as Default, doesn't clear badge
				jsonData = notification.data || {}

				if notification.repeat?			# add repeat to JSON to manually reset
					msg['repeat'] = notification.repeat 		
					jsonData = _.extend  jsonData, _.pick(msg, ['repeat', 'date']) 
					delete msg['repeat']			# don't use 'repeat', set manually in onclick
				# msg['jsonString'] = JSON.stringify(jsonData) if !_.isEmpty(jsonData)
				msg['data'] = jsonData


				# notify.alert "localNotify.add() BEFORE message="+JSON.stringify( msg ), null, 30000
				self = this
				delay = Math.round((date.getTime() - new Date().getTime())/1000)

				try 
					if this.isReady()
						# only 1 reminder at a time
						this._notify.cancelAll()

						# save in localData for resumeApp
						syncService.notification(msg)
						this._notify.add(msg)
						

						notify.alert "localNotify.add()  AFTER message="+JSON.stringify( msg ), "success", 30000
						if delay < 60
							notify.message({
								title: "A reminder was set to fire in "+ delay+" seconds"
								message: "To see the notification, press the 'Home' button and close this app." 
								}, null, 4500)
					else 
						syncService.notification(msg)
						msg.message = "EMULATED: "+msg.message
						notify.alert "localNotification EMULATED, delay="+delay
						if "emulate"
							this.fakeNotify(delay, notification)
						else 
							$timeout (()->
								notify.message(msg)
							), delay*1000
					return
				catch error
					notify.alert "EXCEPTION: notification.local.add(), error="+JSON.stringify error, "danger", 600000
		
			# @param except string or array of Strings
			cancelAll : ()=>
				this._notify.cancelAll() if this.isReady()
				this.clearBadge()
				# syncService.notification(false)

			clearBadge : ()=>
				try # sometimes autoCancel does not reset badge
					# badge plugin: https://github.com/katzer/cordova-plugin-badge.git
					window.plugin.notification.badge.clear()
				catch error
					notify.alert "EXCEPTION: localNotify.onclick(), BADGE CLEAR error="+JSON.stringify error, "danger", 600000

			_cancelScheduled : (except)->
				self = this
				except = [except] if !_.isArray(except) 
				this._notify.getScheduledIds (ids)->
					_.each ids, (id)->
						return if except.indexOf(id) > -1
						notify.alert "_cancelScheduled, id="+id, "warning", 30000
						self._notify.cancel(id)
			# expecting options.repeat, options.date, options.target
			_setRepeat : (options)->
				_getDateFromRepeat = (date, repeat)->
					# now = if _.isDate( date ) then date.getTime() else new Date().getTime()
					if _.isDate( date )
						now = date.getTime()
						# notify.alert "*** _getDateFromRepeat DATE, raw date="+date+", CONVERT TO now="+now , 'success', 200000
					else 
						# notify.alert "*** _getDateFromRepeat DATE, raw date="+date, 'danger', 200000
						date = new Date(date) 
						now = if isNaN(date.getTime()) then new Date().getTime() else date.getTime()
						# notify.alert ">>> last reminder= " + new Date(now) + ", repeat="+repeat+", now="+now, 'success', 200000
					if _.isArray repeat
						# check day of week
						delay = 10
					else 	
						switch repeat
							when 'weekly'
								delay = 2600 * 24 * 7
							when 'daily'
								delay = 3600 * 24
								# delay = 10
							else
								delay = 10
					return reminder = new Date( now + delay*1000)

				options = JSON.parse(options) if _.isString(options)
				if !_.isEmpty(options.repeat)
					# set new reminder
					# options.date = new Date(options.date) if options.date
					# notify.alert "*** OPTIONS.DATE, isDate="+_.isDate(options.date)+", value="+options.date, 'danger', 20000
					nextReminderDate = _getDateFromRepeat(options.date, options.repeat)
					message = this.getNotificationMessage()
					message['repeat'] = options.repeat
					this.addByDate nextReminderDate, message
					# notify.alert "faking repeat by setting new reminder in 10 secs", null, 30000	
					return nextReminderDate
				else return false

			getNotificationMessage : ()->
				# also defined in actionService, but wanted to avoid circular dependency
				# TODO: notification.data.target is used to route, message is set by route
				return _.sample CFG.notifications			

			# @params state = [foreground | background]
			onadd :(id,state,json)=>
				notify.alert "onadd state="+state+", json="+json, "info"
				except = id
				this._cancelScheduled(except)
				return true

			# resume sequence of events - from trigger of notification in foreground 
			#	onlick -> wakeApp -> resumeApp
			ontrigger :(id,state,json)=>
				# steroids.logger.log "*** 2 ***** onTRIGGER state="+state+", json="+json 

				# BUG: for some reason, json==""
				if !json
					msg = syncService.notification()
				else msg = if _.isString(json) then JSON.parse(json) else json

				# state=foreground
				if state=='foreground'
					notify.alert "***** onTRIGGER state="+state+", json="+json, "info", 60000
					# Note: The ontrigger callback is only invoked in background if the app is not suspended!
					this.cancelAll()
					syncService.notification(false) # mark as Handled before setRepeat()

				else # state = 'background'
					# according to docs, this is never fired
					notify.alert "***** onTRIGGER BACKGROUND state="+state+", json="+json, "info", 60000
					# notification fired but NOT handled
				
				if msg.data?.repeat
					repeating = this._setRepeat(msg.data)
				if repeating
					notify.alert "setting NEXT reminder. repeat="+msg.data.repeat+", next reminder at "+repeating, "success", 60000
				return true

			
			# resume sequence of events - from click on item in iOS Notification Center 
			#	onlick -> wakeApp -> resumeApp
			# NOTE: using resumeApp to call onclick from App icon, vs Notification Center
			onclick :(id,state,json)=>
				# steroids.logger.log "*** 3 ***** onClick state="+state+", json="+json 
				# state=background
				try 
					# notify.alert "onClick state="+state+", json="+json, "success", 60000
					this.cancelAll()
					msg = if _.isString(json) then JSON.parse(json) else json
					repeating = this._setRepeat(msg.data)
					if repeating
						# steroids.logger.log "setting NEXT reminder. repeat="+msg.data.repeat+", next reminder at "+syncService.notification()['date']
						# WARNING: make sure next controller does not call notify.clearMessage()
						notify.alert "setting NEXT reminder. repeat="+msg.data.repeat+", next reminder at "+syncService.notification()['date'], "success", 60000
					# prepare for transitions
					# CFG.$curtain.removeClass 'hidden'
					$location.path(msg.data.target) if msg.data?.target
				catch error
					notify.alert "EXCEPTION: localNotify.onclick(), error="+JSON.stringify error, "danger", 600000

				this.clearBadge()
				return true

			oncancel :(id,state,json)=>
				notify.alert "CANCEL oncancel state="+state+", json="+json, "info"
				# this.scheduled.slice(this.scheduled.indexOf(id),1)
				return true

			# for testing in browser WITHOUT plugin
			fakeNotify: (delay, notification)=>
				_isAwakeWhenNotificationFired = ()->
					return false
					# simple Toggle
					_isAwakeWhenNotificationFired.toggle = _isAwakeWhenNotificationFired.toggle || {}
					_isAwakeWhenNotificationFired.toggle.value = !_isAwakeWhenNotificationFired.toggle.value 
					return _isAwakeWhenNotificationFired.toggle.value

				_isLongSleep = (sleep)->
					# use 4 sec just for fakeNotify testing
					LONG_SLEEP = 4 
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
						notify.alert "LocalNotify RESUME detected, pauseDuration=" + o.pauseDuration, "success"
						if wasAlreadyAwake
							context =  "<br /><p>(Pretend this notification fired while the app was already in use.)</p>" 
						else 
							context =  "<br /><p><b>(Pretend you got here after clicking from the Notification Center.)</b><p>" 
						o.notification.message += context	
						type = if wasAlreadyAwake then "info" else "success"
						notify.message(o.notification, type, 20000)
						# after LONG_SLEEP, goto active challenge 'drawer-findhappi-current'
						$timeout (()->
							drawerService.drawerItemClick('drawer-findhappi-current')
						), 2000
					else if !wasAlreadyAwake
						# resume from shortSleep should just resume, not alert
						# localNotify from shortSleep should just show notification as alert, do not navigate
						type = if wasAlreadyAwake then "info" else "success"
						notify.message(o.notification, type)

					return

				window.deviceReady = "fake" if !window.deviceReady
				promise = AppManager.prepareToResumeApp(null, notification)
					.then( _handleResumeOrLocalNotify )
				$timeout (()->
					# notify.alert "FAKE localNotification fired, delay was sec="+delay
					AppManager.wakeApp("LocalNotify")
				), delay*1000
				notify.message({message: "LocalNotify set to fire, delay="+delay}, "warning", 2000)
				return	


		#
		# Object for managing the background/resume behavior for the app
		#
		
		AppManager = {	

			_backgroundDeferred: null

			# set up deferred BEFORE causing app to pause
			prepareToResumeApp : (e, notification)->
				return notify.alert "WARNING: already paused..." if self._backgroundDeferred?

				pauseTime = new Date().getTime()
				# return if !window.deviceReady
				notify.alert "Preparing to send App to background..." 
				AppManager._backgroundDeferred = $q.defer()
				promise = AppManager._backgroundDeferred.promise
				promise.finally( 
					# race condition? clear first, then resolve...
					()-> AppManager._backgroundDeferred = null
				)
				promise.then( (o)->
									# calculare pauseDuration
									o.pauseDuration = (o.resumeTime - (pauseTime || 0))/1000
									o.notification = notification
									return o
								)
				.then( 
					AppManager.resumeApp 
				)				
				return promise
			
			# record resumeTime to allow calculation of pauseDuration downstream
			wakeApp	 : (e)->
				# steroids.logger.log "*** 0 - wakeApp"
				if !window.deviceReady
					steroids.logger.log "WARNING: wakeApp without window.deviceReady!!! check resolve()"

				$timeout (()=>
					if e == "LocalNotify" 
						notify.alert "App was resumed from FAKE LocalNotify", "success"
					else 	
						notify.alert "App was resumed from background"
					o = {
						event: e
						resumeTime: new Date().getTime() 
					}
					AppManager._backgroundDeferred?.resolve( o )
				), 0
				
			# resumeApp from background, check o.pauseDuration to determine next action
			# 	possible states:
			# 		- resume from Notification Center triggers LocalNotification.onclick()
			# 		- resume by clicking App icon does NOT trigger LN.onclick()
			# 			???: how do you detect this state and clear badge?
			# 			see: https://github.com/katzer/cordova-plugin-local-notifications/issues/150
			resumeApp: (o)->
				# steroids.logger.log "*** 1 - resumeApp, o="+JSON.stringify o
				# notify.alert "App was prepared to resume, then sent to background, pauseDuration=" +o.pauseDuration
				try 
					nextReminder = syncService.notification()
					# badge plugin: https://github.com/katzer/cordova-plugin-badge.git
					# NOTE: click on app Icon does NOT clear notification badge
					# 	- only works if item in Notification Center was clicked 
					# 	- check for notification here in resumeApp
					
					now = new Date()
					isNotificationTriggered = nextReminder.date && now > nextReminder.date
					# steroids.logger.log "### RESUME APP WITH NOTIFICATION, trigger="+isNotificationTriggered+", reminder="+JSON.stringify nextReminder
					if isNotificationTriggered 
						try 
							# force onclick
							notificationAsJson = JSON.stringify(nextReminder) 
							syncService.notification(false) # mark handled before setting Repeat()
							localNotify.onclick(nextReminder.id || 0, "resumeApp", notificationAsJson)
							# NOTE: onclick will call 
							# 	setRepeat() > syncService.notification() if nextReminder.repeat
							# 	$location.path(data.target) if nextReminder.data.target
						catch error
						CFG.$curtain.removeClass('hidden')
						return

				catch error
					notify.alert "EXCEPTION: resumeApp(), error="+JSON.stringify error, "danger", 600000


				if _isLongSleep(o.pauseDuration)
					CFG.$curtain.removeClass('hidden')
					$location.path('/challenges/draw-new')
				return	
		}





		# send App to background event
		document.addEventListener("pause", AppManager.prepareToResumeApp, false);

		# resume from pause background event
		document.addEventListener("resume", AppManager.wakeApp, false);		

		localNotify = new LocalNotify()
		return 	localNotify
		#
		# end Class Notify
		#
]   
)