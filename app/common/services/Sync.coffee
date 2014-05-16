return if !angular? 

angular.module( 
	'appHappi'
).config([
	'localStorageServiceProvider', 
	(localStorageServiceProvider)->
  	localStorageServiceProvider.setPrefix('snappi');
  # TODO: should config models = ['challenge', 'moment', 'drawer']	
]
).factory('syncService', [
  'localStorageService'
  'appConfig'
  'drawerService'
  '$q'
  '$filter'
  'notifyService'
  '$http' 
  # 'AppHappiRestangular'
# , (localStorageService, CFG, drawer, $q, $filter, notify, $http, AppHappiRestangular)->
, (localStorageService, CFG, drawer, $q, $filter, notify, $http)->
			# private methods
	_asDuration = (secs)->
		duration = moment.duration(secs*1000) 
		formatted = []
		formatted.unshift(duration.seconds()+'s') if duration.seconds()
		formatted.unshift(duration.minutes()+'m') if duration.minutes()
		formatted.unshift(duration.hours()+'h') if duration.hours()
		formatted.unshift(duration.days()+'h') if duration.days()
		return formatted.join(' ')

	syncService = {
			localData: {}
			lastModified: {}
			promises: {}

			serialize: {
				'challenge': (collection)->
					omitKeys = ['moments', 'stale'] # remove circular reference
					saveData = _.reduce collection, ((stale, o)->
						if o.stale && o.type == 'challenge' 	# confirm type matches key
							syncService.parseModel[o.type] o if syncService.parseModel[o.type]?	
							stale[o.id] = _.omit(o, omitKeys ) 
						return stale 
					), {}
					return saveData
				'moment': (collection)->
					omitKeys = ['challenge', 'photos','stale'] # remove circular reference
					# extractedPhotos = {}
					saveData = _.reduce collection, ((stale, o)->
						if o.stale && o.type == 'moment' 	# confirm type matches key
							syncService.parseModel[o.type] o if syncService.parseModel[o.type]?	
							stale[o.id] = _.omit(o, omitKeys ) 
							# momentPhotos = []
							# _.each o.photos, (p)->
							# 	id = _getPhotoId( p )
							# 	extractedPhotos[id] = p
							# 	extractedPhotos[id].stale=true
							# 	momentPhotos.push(id)
						return stale 
					), {}
					# save extractedPhotos
					# syncService.set('photo', extractedPhotos)
					return saveData
				'photo': (collection)->
					omitKeys = ['stale'] # remove circular reference
					saveData = _.reduce collection, ((stale, o)->
						if o.stale && o.type == 'photo' 	# confirm type matches key
							syncService.parseModel[o.type] o if syncService.parseModel[o.type]?	
							stale[o.id] = _.omit(o, omitKeys ) 
						return stale 
					), {}
			}

			# returns a cloned version of cached value, or {} if empty or undefined
			get: (key, id=null)->	
				# load from localStorageServe is not cached
				if !syncService.localData[key] 
					syncService.localData[key] = localStorageService.get( key ) || {}
					# parse 'settings'
					switch key 
						when 'settings'
							# all dates remain as toJSON() string, call new Date(notification.date) before using
							null
						when 'challenge', 'moment', 'photo'
							null

				if id == null
					retval = syncService.localData[key] 
					return _.clone retval, true

				retval = syncService.localData[key][id] || {}
				if retval.stale 
					errmsg = "WARNING: localData cached value is stale, value=" + JSON.stringify syncService.localData[key][id]
					# steroids.logger.log errmsg
					notify.alert errmsg, "danger", 60000
				
				return _.clone retval, true

			# save to localStorageService, checks for o.type=key and o.stale=true
			# updates syncService.localData[key]
			# returns savedData
			set: (key, collection)->
				if _.isPlainObject( collection ) && collection.type == key
					collection = [collection]
				try
					# move to controller, save to localStorage in updateCounte()
					# if key=='challenge' && drawer.json.data?
					# 	drawer.updateCounts collection
					# 	localStorageService.set('drawerState', drawer.state)
					now = new Date()
					switch key
						when 'moment', 'challenge', 'photo'
							saveData = syncService.serialize[key](collection)
						when 'shared_moment', 'shared_photo'
							if collection[0].ownerId == CFG.userId 
								console.log "*** WARNING: syncService: this shared_photo is actually owned by User. handle differently... , key="+key
						when 'drawer'
							return localStorageService.set('drawer', collection)
						when 'drawerState'
							# just a wrapper for localStorageService
							return localStorageService.set('drawerState', drawer.state)
						when 'settings' # collection.type is undefined
							localStorageService.set('settings', collection)
							written = localStorageService.get('settings')
							syncService.parseModel['settings']( written )
							return syncService.localData[key] = written
						else 
							console.log "WARNING: syncService, key="+key

					if !_.isEmpty(saveData)
						model = localStorageService.get(key) || {}	
						_.each saveData, (o)->
							# pk = key+":"+o.id
							# console.info "saving "+pk+" to localStorage..."
							if o.remove
								delete model[o.id] 
							else 
								o.type = key
								model[o.id] = o
								
						#TODO: check if we are wasting cycles by saving entire array to localStorageService
						localStorageService.set(key, model)

						# restore FKs ['challenge', 'moment', 'photos']
						# INCOMPLETE!!!
						# _.each model (o)->
						# 	check = collection[o.id]?.id == o.id

						syncService.localData[key] = model
						# msg =  "syncService.set("+key+") elapsed="+(new Date().getTime() - now.getTime())+"ms"
						# console.log msg
						return saveData
						
				catch
					notify.alert "syncService.set() error"

			# localStorageSet: (key, stale)->
				# all = localStorageService.get(key)


			isSupported: ()->
				# config to use cookies if localStorage not supported?
				localStorageService.isSupported()

			clearAll: ()->
				localStorageService.clearAll()

			clearDrawer: ()->
				syncService.localData['drawer']= null
				localStorageService.set('drawer', syncService.localData['drawer'])
				return syncService.lastModified['drawer'] = false


			# @param o Object, notification payload, see parseModel for example
			# @return notification payload as object of last notification ontrigger
			# 	NOTE: notification.date is a Date.toJSON() string
			notification : (o = null)->
				if o == null # getter
					return syncService.get('settings', 'notification')

				settings = syncService.get('settings')
				if o == false
					settings['notification'] = {}
				else if _.isObject(o)
					settings['notification'] = o
				else return throw "Error: syncService.notification() expecting an object or false"

				syncService.set('settings', settings)
				return syncService.get('settings', 'notification')	



			initLocalStorage: (models=[])->
				if !CFG.userId?
					settings = syncService.get('settings')
					syncService.parseModel['settings']( syncService.localData['settings'] )
					if !settings['userId']?
						settings['userId'] = new Date().getTime() 
						# steroids.logger.log ">>>>> NEW CFG.userId set, userId="+settings['userId']
						syncService.set('settings', settings)
					CFG.userId = settings['userId']
				models = ['challenge', 'moment', 'drawer', 'photo']
				for model in models
					syncService.promises[model] = syncService.initLocalStorageModel model
				return syncService.promises	

			# @return $q.promise
			initLocalStorageModel: (model, sync='later')->
				syncService.get(model)
				if syncService.localData[model] && syncService.localData[model].modified?
					syncService.lastModified[model] = syncService.localData[model].modified
				else syncService.lastModified[model] = _.reduce( syncService.localData[model]
					, (last, o)-> 
						return if o.modified > last then o.modified else last
					, ''
					)
				
				local_lastModified = syncService.lastModified[model] 
				_checkServerLater = (model, local_lastModified)->
					switch model
						when "drawer"
							return syncService.initLocalStorageModel(model, "now")
						else 
							return false

				syncLater = (sync=='later' && syncService.lastModified[model])

				switch model
					when 'drawer' 
						if syncLater
							# load drawer from localData
							drawer.json syncService.localData['drawer']
							drawer.ready = $q.defer()
							drawer.ready.resolve( "ready" )
							_checkServerLater model, local_lastModified
							return drawer.ready.promise
						else 
							# load drawer from $http
							promise = drawer.load( CFG.drawerUrl ).then (resp)->
								drawerJson = resp.data
								server_lastModified = drawerJson.modified
								local_lastModified = syncService.lastModified[model] || 0
								if new Date(server_lastModified) > new Date(local_lastModified)
									drawer.json(drawerJson)
									syncService.set('drawer', drawer.json())
								return drawerJson
							return promise
					when 'challenge'
						if syncLater
							# get data from localService
							# TODO: compare localStorage lastModified against Server to detech sync
							dfd = $q.defer()
							modelData = syncService.localData[model]
							# ???: should we parseFn(modelData), set() calls parseFn
							dfd.resolve(modelData)
							return dfd.promise
						else if "use $http"
							# load challenges from $http
							console.log "*** challenge.load()"  
							dfd = $q.defer()
							$http.get(CFG.challengeUrl)
							.success (data, status, headers, config)->
							  	console.log "*** challenge ready"

							 # return dfd.promise 	
							.then (resp)->
								data = resp.data
								data = {} if _.isEmpty(data)
								_.each data, (o)->
									o.type = model
									o.stale = true
								syncService.set(model, data)	# parseModel in .set()
								dfd.resolve syncService.get('challenge') 
							return dfd.promise

						else if false && "use Restangular"	
							dfd = $q.defer()
							promise = AppHappiRestangular.all(model)
							.getList({'modified':syncService.lastModified[model]})
							.then (data)->
								# mark all as stale and let syncService.set() format
								data = {} if _.isEmpty(data)
								_.each data, (o)->
									o.type = model
									o.stale = true
								# notify.alert "AppHappiRestangular resolved, count="+data.length
								syncService.set(model, data)	# parseModel in .set()
								dfd.resolve syncService.get('challenge') 
							return dfd.promise
					when 'moment', 'photo'	
						if syncLater
							# get data from localService
							# TODO: compare localStorage lastModified against Server to detech sync
							dfd = $q.defer()
							modelData = syncService.localData[model]
							# ???: should we parseFn(modelData), set() calls parseFn
							dfd.resolve(modelData)
							return dfd.promise
						else 	
							
							dfd = $q.defer()
							dfd.resolve( empty = {} )
							return dfd.promise
								
			parseModel: {
				'challenge': (c)->
					defaults = {
			      description: null,
			      icon: "fa fa-smile-o",
			      modified: null,
			      stats: {
			        viewed: 0,
			        accept: 0,
			        pass: 0,
			        completions: [],
			        ratings: []
			      },
			      momentIds: []
			    }
			    c.stats  = _.defaults(c.stats || {}, defaults.stats)
			    _.defaults(c, defaults)
					c.humanize = {
						completions: c.stats.completions.length
						acceptPct: 100*c.stats.accept/c.stats.viewed
						passPct: 100*c.stats.pass/c.stats.viewed
						avgDuration: _asDuration (_.reduce c.stats.completions
							, (a, b)->
								a+b
							, 0
						)/c.stats.completions.length 
						avgRating: $filter('number')( (_.reduce c.stats.ratings
							, (a, b)-> 
								a+b
							, 0
						)/c.stats.ratings.length, 1)
						category : c.category.join(':')
					}
					return c
				'moment': (m)->
					console.log "moment parseModel: "+m.modified
					m.userId = CFG.userId		# clean up test data
					m.humanize = {
						completed: moment.utc(new Date(m.modified)).format("dddd, MMMM Do YYYY, h:mm:ss a")
						completedAgo: moment.utc(new Date(m.modified)).fromNow()
						completedIn: _asDuration m.stats && m.stats.completedIn || 0
					}
					return  m
				'shared_moment': (m)->
					console.log "SHARED moment parseModel: "+m.modified
					# parse m.challenge.stats for custom moments
					return syncService.parseModel['moment'](m)

				'photo': (p)->
					p.rating = 0 if !p.rating?	
					return p

				'shared_photo': (p)->
					console.log "SHARED photo parseModel: "+p.modified
					p.type == 'photo' if p.ownerId == CFG.userId 
					# ???: lookup local version by p.id???
					# check syncService.set('photo', p) should save ratings and views
					return syncService.parseModel['photo'](p)	

				### expecting
				settings = {
				  "userId": 1396483272541,
				  "hideGettingStarted": true,
				  "notification": {
				    "id": 1396411200000,
				    "date": "2014-04-03T04:00:00.000Z",
				    "target": "/moments/shuffle",
				    "message": "This Happi moment was made possible by your '5 minutes a day'. Grab a smile and make another.",
				    "title": "Get Your Happi for the Day"
				    "schedule": {
				      "1": true, "2": true, "3": true, "4": true, "5": true,  "6": true,  "7": true
				    },
				  }
				###
				'settings': (o)->
					return o

			}

			# @return o.challenge, o.moment, o.photo with foreign keys set. clone?
			setForeignKeys: ()->
				# use values directly from syncService.localData to set FK references
				# NOTE: use localData[model][id] to set foreignKeys syncService.get() will return a copy
				now = new Date()
				challengeStatusPriority = ['new', 'sleep', 'pass', 'complete', 'working', 'active']
				momentsAsArray = _.values(syncService.localData['moment'])
				_.each syncService.localData['challenge'], (challenge)->
					# challenge.moments = _.where(momentsAsArray, {challengeId: challenge.id})
					if !challenge.momentIds?.length
						challenge.status = 'new' if !challenge.status  # otherwise status='pass'
					else	
						_.each( challenge.momentIds, (mid,k,l)->
							moment = syncService.localData['moment'][mid]
							if !moment? 
								notify.alert "ERROR: moment not found, possible data corruption. challenge="+challenge.name+", mid="+mid
								return
							missing = []
							moment.photos = _.reduce moment.photoIds, ((result, id)->
								photo = syncService.localData['photo'][id] #  syncService.get('photo', id) 
								if !!photo
									photo.rating = 0 if !photo.rating?
									result.push photo
								else
									notify.alert "WARNING: DB error, photoId not found. photoId="+id
									missing.push id 
								return result ), []
							_.each missing, (id)->moment.photoIds.splice( moment.photoIds.indexOf(id),1)
							moment.challenge = challenge    # moment belongsto challenge assoc
							if challengeStatusPriority.indexOf(moment.status) > challengeStatusPriority.indexOf(challenge.status)
								challenge.status = moment.status 
							return
						)
				console.log "syncService.setForeignKeys(), elapsed="+ (new Date().getTime() - now.getTime()) + "ms"
				return {
					'challenge': syncService.localData['challenge']
					'moment': syncService.localData['moment']
					'photo': syncService.localData['photo']
				}
		}
		# for counts, circular dependency problem, should refactor
		drawer.setSyncService(syncService)
		# for debugging
		window.localData = syncService.localData
		return syncService
])