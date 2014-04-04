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
					# steroids.logger.log "####### LocalNotification handlers added ##################"
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

			# @param reminderTime Date.toJSON(), only use time compoment
			# NOTE: reminderTime will be modified to fit notification.schedule, only time component is used
			addByDate: (reminderTime, notification={})->
				try
					# avoid circular references because we will serialize notification
					# reminder is formatted for syncService.notification(reminder)
					if !notification.target || !notification.message
						throw "ERROR: addByDate() param format error"

					check = moment(new Date(reminderTime)) # parse date with moment.js
					if !check.isValid() 
						throw "ERROR: reminderTime is not a valid date string, reminderTime="+reminderTime
					
					reminderTimeAsDate = check.toDate()

					if notification['schedule']	&& _.isObject(notification['schedule'])
						reminderTimeAsDate = this._getDateFromRepeat(reminderTimeAsDate, notification['schedule'])
						if reminderTimeAsDate == false
							notify.message "You must select at least one day of the week for this reminder."
							return false

					now = new Date()
					if now > reminderTimeAsDate
						notify.message "You are setting a reminder for a time in the past"
						return false

					delay = Math.round((reminderTimeAsDate.getTime() - now.getTime())/1000)

					reminder = {
						id: now.getTime()		# seems to crash on id:0 
						date: reminderTimeAsDate
						target: notification['target']
						message: notification['message']
						schedule: notification['schedule'] || null
					}
					reminder['title'] = notification.title if notification.title?
					# steroids.logger.log "*** addByDate reminder="+JSON.stringify reminder

					saved = syncService.notification(reminder)

					useNotificationPlugin = this.isReady()
					if useNotificationPlugin
						# now format for LocalNotification plugin because add() will change reminder.date to unixtime
						reminder2 = _.pick reminder, ['id','date','message']
						reminder2['badge'] = notification.badge || 1
						reminder2['autoCancel'] = true 
						reminder2['json'] = reminder 	# passed to onclick/ontrigger json param

					
						# only 1 reminder at a time, cancel notifications and badges
						this.cancelAll()

						this._notify.add( reminder2 )
						

						# steroids.logger.log "localNotify.add()  AFTER message="+JSON.stringify( reminder2 )
						if delay < 60
							notify.message({
								title: "A reminder was set to fire in "+ delay + " seconds"
								message: "To see the notification, press the 'Home' button and close this app." 
								})
						else 
							nextReminder = moment(reminder.date)
							# steroids.logger.log " LocalNotification plugin set, date="+ reminder.date + ", nextReminder.calendar()=" + nextReminder.calendar()
							return false if !nextReminder.isValid()

							notify.message( {
									title: "A Reminder was Set"
									message: "Your next reminder will be at " + nextReminder.calendar() + "."
								})
								
					else # not useng LocalNotification plugin
						reminder.message = "EMULATED: "+reminder.message
						saved = syncService.notification(reminder)
						notify.alert "localNotification EMULATED, delay="+delay
						this.fakeNotify(delay, reminder)
					# steroids.logger.log "addByDate COMPLETE"	
					return reminder.date
				catch error
					msg = "EXCEPTION: addByDate(), error="+JSON.stringify error, null, 2
					# steroids.logger.log msg
					notify.alert msg, "danger", 600000
		
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

			# @param date Date object or Date.toJSON()
			# 	schedule Object or String, 
			# 		Object: example { "1": true, "2": true, "3": true, "4": true, "5": true,  "6": true,  "7": true }
			#		String: 'daily', 'weekly', etc, see LocalNotification plugin docs
			# @return Date object or false if repeat == object and no days of week are enabled
			_getDateFromRepeat : (date, schedule=null)->
				check = moment(new Date(date)) # parse date with moment.js
				if !check.isValid() 
					throw "ERROR: _getDateFromRepeat(), date is not a valid date string, date="+date

				reminder = check 
				reminderTime = reminder.toDate().getTime()
				now = new Date()

				if _.isObject( schedule )
					# check day of week
					dayOfWeek = reminder.day()
					nextDayOfWeek = _.reduce schedule, (result, set, day)->
							if set
								day = parseInt(day)
								# 
								day += 7 if day<dayOfWeek
								day += 7 if day==dayOfWeek && reminder < now
								result = if result!=false then Math.min(result, day) else day
							return result
						, false
					return false if nextDayOfWeek == 0
					return reminder.day(nextDayOfWeek).toDate()	

				switch schedule
					when 'weekly'
						delay = 2600 * 24 * 7
					when 'daily'
						delay = 3600 * 24
						# delay = 10
					else
						delay = 10
				return new Date( reminderTime + delay*1000)
								
			# @params options Object
			# 	options.schedule Object or string, 
			#	options.date Date.toJSON()
			_setRepeat : (options)->
				# options = JSON.parse(options) if _.isString(options)
				if !_.isEmpty(options.schedule)

					# get next random message for Notification Center 
					message = this.getNotificationMessage()
					message['schedule'] = options.schedule 	# copy schedule from lastReminder
					# set new reminder
					# note addByDate will get nextReminderDate from _getDateFromRepeat()
					lastReminderDate = new Date(options.date)
					nextReminderDate = this.addByDate lastReminderDate, message
					return nextReminderDate
				else return false

			getNotificationMessage : ()->
				# also defined in actionService, but wanted to avoid circular dependency
				# TODO: notification.data.target is used to route, message is set by route
				return _.sample CFG.notifications	

			handleNotification : (options)->
				# steroids.logger.log "*** handleNotification(), options=" + JSON.stringify options, null, 2 
				# state=background
				try 
					# notify.alert "onClick state="+state+", json="+json, "success", 60000
					this.cancelAll()
					reminder = syncService.notification()
					# steroids.logger.log " %%%% CONFIRM same as json, reminder=" + JSON.stringify reminder, null, 2
					syncService.notification(false) # mark as Handled before setRepeat()
					repeating = this._setRepeat(reminder)
					if repeating
						# reminder.target controller will set the actual notify.message()
						# make sure it matches reminder.message, as shown in Notification Center
						notify.alert "setting NEXT reminder for " + syncService.notification()['date'], "success", 60000
						# prepare for transitions
						# steroids.logger.log ">>>>  onlick going to " + reminder.target + " setting NEXT reminder for " + syncService.notification()['date']
					$location.path(reminder.target)
					return true

				catch error
					msg = "EXCEPTION: localNotify.onclick(), error="+JSON.stringify error, null, 2
					# steroids.logger.log msg
					notify.alert msg, "danger", 600000

				return true			

			# @params state = [foreground | background]
			onadd :(id,state,json)=>
				return true # skip this because we are using this.cancelAll()

				# notify.alert "onadd state="+state+", json="+json, "info"
				# except = id
				# this._cancelScheduled(except)
				# return true

			# resume sequence of events - from trigger of notification in foreground 
			#	onlick -> wakeApp -> resumeApp
			ontrigger :(id,state,json)=>
				# steroids.logger.log "*** 2 ***** onTRIGGER state="+state+", json="+json 
				this.handleNotification(json)
				return true
				# this.cancelAll()
				# reminder = syncService.notification()
				# # steroids.logger.log " %%%% CONFIRM same as json, reminder="+JSON.stringify reminder
				# syncService.notification(false) # mark as Handled before setRepeat()
				# repeating = this._setRepeat(reminder)
				# if repeating
				# 	# reminder.target controller will set the actual notify.message()
				# 	# make sure it matches reminder.message, as shown in Notification Center
				# 	notify.alert "setting NEXT reminder. repeat="+reminder.schedule+", next reminder at "+syncService.notification()?['date'], "success", 60000
				# # prepare for transitions
				# steroids.logger.log ">>>>  onlick going to "+reminder.target
				# $location.path(reminder.target)
				# return true	

			
			# resume sequence of events - from click on item in iOS Notification Center 
			#	onlick -> wakeApp -> resumeApp
			# NOTE: using resumeApp to call onclick from App icon, vs Notification Center
			onclick :(id,state,json)=>
				# steroids.logger.log "*** 3 ***** onClick state="+state+", json="+json 
				this.handleNotification(json)
				return true
				# state=background
				# try 
				# 	# notify.alert "onClick state="+state+", json="+json, "success", 60000
				# 	this.cancelAll()
				# 	reminder = syncService.notification()
				# 	# steroids.logger.log " %%%% CONFIRM same as json, reminder="+JSON.stringify reminder
				# 	syncService.notification(false) # mark as Handled before setRepeat()
				# 	repeating = this._setRepeat(reminder)
				# 	if repeating
				# 		# reminder.target controller will set the actual notify.message()
				# 		# make sure it matches reminder.message, as shown in Notification Center
				# 		notify.alert "setting NEXT reminder. repeat="+reminder.schedule+", next reminder at "+syncService.notification()?['date'], "success", 60000
				# 	# prepare for transitions
				# 	steroids.logger.log ">>>>  onlick going to "+reminder.target
				# 	$location.path(reminder.target)


				# catch error
				# 	msg = "EXCEPTION: localNotify.onclick(), error="+JSON.stringify error
				# 	steroids.logger.log msg
				# 	notify.alert msg, "danger", 600000
				# return true

			oncancel :(id,state,json)=>
				# steroids.logger.log "*** 4 ***** onCancel state="+state+", json="+json 
				return true

				# notify.alert "CANCEL oncancel state="+state+", json="+json, "info"
				# # this.scheduled.slice(this.scheduled.indexOf(id),1)
				# return true

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
					notify.alert "fakeNotify: resuming with o="+JSON.stringify o
					reminder = syncService.notification()
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
				promise = AppManager.prepareToResumeApp()
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
			prepareToResumeApp : (e)->
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
					# o.notification = notification 
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
					# steroids.logger.log "WARNING: wakeApp without window.deviceReady!!! check resolve()"
					null

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
			# 			see: https://github.com/katzer/cordova-plugin-local-notifications/issues/150
			# @params o Object, expecting o.pauseDuration, o.resumeTime, o.event
			resumeApp: (o)->
				# steroids.logger.log "*** 1 - resumeApp, o="+JSON.stringify o
				# notify.alert "App was prepared to resume, then sent to background, pauseDuration=" +o.pauseDuration
				try 
					nextReminder = syncService.notification()
					# 	- check for notification here in resumeApp
					# steroids.logger.log "### RESUME APP WITH NOTIFICATION"
					now = new Date()
					isNotificationTriggered = nextReminder.date && now > new Date(nextReminder.date) || false
					steroids.logger.log "### RESUME APP WITH NOTIFICATION, trigger="+isNotificationTriggered+", date="+nextReminder.date+", reminder="+JSON.stringify nextReminder
					if true && isNotificationTriggered 
						# same as LocalNotify.onclick
						localNotify.handleNotification()
						CFG.$curtain.removeClass('hidden')
						# steroids.logger.log "### RESUME APP COMPLETE ###"
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