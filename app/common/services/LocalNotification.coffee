return if !angular? 

angular.module(
	'appHappi'
).factory( 'localNotificationService', [ 
	'$location'
	'$timeout'
	'actionService'
	'notifyService'
	'syncService'
	($location, $timeout, actionService, notify, syncService)->
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
					notify.alert "localNotify, callbacks added", "success"
				else 	
					notify.alert "LocalNotification plugin is NOT available"
					this._notify = false
				return this._notify

			showDefaults: ()->
				return false if !this._notify
				notify.alert JSON.stringify(this._notify.getDefaults()), "warning", 40000

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
					_.extend  jsonData, _.pick(msg, ['repeat', 'date']) 
					delete msg['repeat']			# don't use 'repeat', set manually in onclick
				msg['json'] = JSON.stringify(jsonData) if !_.isEmpty(jsonData)


				# notify.alert "localNotify.add() BEFORE message="+JSON.stringify( msg ), null, 30000
				self = this
				delay = Math.round((date.getTime() - new Date().getTime())/1000)

				try 
					if this.isReady()
						# only 1 reminder at a time
						this._notify.cancelAll()
						syncService.reminder(msg.date)		# save for display in Settings

						this._notify.add(msg)
						notify.alert "localNotify.add()  AFTER message="+JSON.stringify( msg ), "danger", 30000
						if delay < 60
							notify.message({
								title: "A reminder was set to fire in "+ delay+" seconds"
								message: "To see the notification, press the 'Home' button and close this app." 
								}, null, 4500)
					else 
						syncService.reminder(msg.date)		# save for display in Settings
						msg.message = "EMULATED: "+msg.message
						notify.alert "localNotification EMULATED, delay="+delay
						if "emulate"
							this.fakeNotify(delay, notification)
						else 
							$timeout (()->
								notify.message(msg)
							), delay*1000

					syncService.set('')
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

			_setRepeat : (json)->
				_getDateFromRepeat = (date, repeat)->
					now = if date.getTime? then date.getTime() else new Date().getTime()
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
					return target = new Date( now + delay*1000)

				data = JSON.parse(json)
				if data.repeat
						# set new reminder
						actionService._getNotificationMessage()
						nextReminderDate = _getDateFromRepeat(data.date, data.repeat)
						message = actionService._getNotificationMessage()
						message['repeat'] = data.repeat
						this.addByDate nextReminderDate, message
						# notify.alert "faking repeat by setting new reminder in 10 secs", null, 30000	
						return nextReminderDate
				else return false		

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
					repeating = this._setRepeat(json)
					notify.alert "repeat set for "+repeating
				else 
					# can we sample the message here?
					check = this

				return true

			onclick :(id,state,json)=>
				# state=background

				try 
					notify.alert "onclick state="+state+", json="+json, "success"
					# ???: how does cancel affect "repeat" 
					# this._notify.cancel(id)
					this._notify.cancelAll()
					repeating = this._setRepeat(json)
					$location.path(data.target)
				catch error
					notify.alert "EXCEPTION: localNotify.onclick(), error="+JSON.stringify error, "danger", 60000
				try 
					# badge plugin: https://github.com/katzer/cordova-plugin-badge.git
					window.plugin.notification.badge.clear()
				catch error
					notify.alert "EXCEPTION: localNotify.onclick(), badge clear error="+JSON.stringify error, "danger", 60000
				return true

			oncancel :(id,state,json)=>
				notify.alert "CANCEL oncancel state="+state+", json="+json, "info"
				# this.scheduled.slice(this.scheduled.indexOf(id),1)
				return true

			fakeNotify: (delay, notification)=>
				_isAwakeWhenNotificationFired = ()->
					return false
					# simple Toggle
					_isAwakeWhenNotificationFired.toggle = _isAwakeWhenNotificationFired.toggle || {}
					_isAwakeWhenNotificationFired.toggle.value = !_isAwakeWhenNotificationFired.toggle.value 
					return _isAwakeWhenNotificationFired.toggle.value

				_isLongSleep = (sleep)->
					LONG_SLEEP = 4 # 60*60 == 1 hour
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
		return 	new LocalNotify()
		#
		# end Class Notify
		#
]   
)