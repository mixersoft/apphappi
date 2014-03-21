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

			# syncService.localData[key] should always be valid
			get: (key, id)->	
				if !id?
					# just a wrapper for localStorageService
					return localStorageService.get('drawerState') if key=='drawerState'
					return localStorageService.get('settings') || {} if key=='settings'
					return syncService.localData[key] 

				if syncService.localData[key]?[id]?.stale  # this is WRONG
					o = syncService.localData[key][id]
					switch o && o.type
						when 'moment', 'challenge'
							syncService.set(key, o)
						when 'photo'
							syncService.set(key, o)
						else	
							throw "ERROR: localData was not saved to localStorage, key="+key
				return syncService.localData[key][id]

			# save to localStorageService, checks for o.type=key and o.stale=true
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
						when 'drawerState'
							# just a wrapper for localStorageService
							return localStorageService.set('drawerState', drawer.state)
						when 'settings'
							localStorageService.set('settings', collection)
							syncService.localData[key] = localStorageService.get('settings')
							return syncService.localData[key]
						else 
							console.warn "WARNING: syncService, key="+key

					if !_.isEmpty(saveData)
						localData = localStorageService.get(key) || {}	
						_.each saveData, (o)->
							# pk = key+":"+o.id
							# console.info "saving "+pk+" to localStorage..."
							if o.remove
								delete localData[o.id] 
							else 
								o.type = key
								localData[o.id] = o
								
						#TODO: check if we are wasting cycles by saving entire array to localStorageService
						localStorageService.set(key, localData)
						syncService.localData[key] = localData
						msg =  "syncService.set("+key+") elapsed="+(new Date().getTime() - now.getTime())+"ms"
						console.log msg
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

			initLocalStorage: (models=[])->
				if !CFG.userId?
					settings = syncService.get('settings')
					if !settings['userId']?
						settings['userId'] = new Date().getTime() 
						syncService.set('settings', settings)
					CFG.userId = settings['userId']
				models = ['challenge', 'moment', 'drawer', 'photo']
				for model in models
					syncService.promises[model] = syncService.initLocalStorageModel model
				return syncService.promises		 	

			# @return $q.promise
			initLocalStorageModel: (model)->
				syncService.localData[model] = localStorageService.get(model)
				if syncService.localData[model] && syncService.localData[model].modified?
					syncService.lastModified[model] = syncService.localData[model].modified
				else syncService.lastModified[model] = _.reduce( syncService.localData[model]
					, (last, o)-> 
						return if o.modified > last then o.modified else last
					, ''
					)
				switch model
					when 'drawer' 
						if !!syncService.lastModified[model]
							# load drawer from localData
							drawer.json syncService.localData['drawer']
							drawer.ready = $q.defer()
							drawer.ready.resolve( "ready" )
							return drawer.ready.promise
						else 
							# load drawer from $http
							promise = drawer.load( CFG.drawerUrl ).then (resp)->
								# localStorageService.set(model, resp.data)
								check = resp
								return resp
							# save to localStorageService in drawer.init()?
							return promise
					when 'challenge'
						if !!syncService.lastModified[model] 
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
								_.each data, (o)->
									o.type = model
									o.stale = true
								# notify.alert "AppHappiRestangular resolved, count="+data.length
								syncService.set(model, data)	# parseModel in .set()
								dfd.resolve syncService.get('challenge') 
							return dfd.promise
					when 'moment', 'photo'	
						if !!syncService.lastModified[model] 
							# get data from localService
							# TODO: compare localStorage lastModified against Server to detech sync
							dfd = $q.defer()
							modelData = syncService.localData[model]
							# ???: should we parseFn(modelData), set() calls parseFn
							dfd.resolve(modelData)
							return dfd.promise
						else 	
							#
							# do NOT load moment test data, return empty [] instead
							#
							dfd = $q.defer()
							dfd.resolve([])
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
				'photo': (m)->
					m.rating = 0 if !m.rating?		
			}

			setForeignKeys: (challenges, moments)->
				# notify.alert "set foreign keys"
				now = new Date()
				challengeStatusPriority = ['new', 'sleep', 'pass', 'complete', 'working', 'active']
				momentsAsArray = _.values(moments)
				_.each challenges, (challenge)->
				  # challenge.moments = _.where(momentsAsArray, {challengeId: challenge.id})
				  if !challenge.momentIds?.length
				  	challenge.status = 'new' if !challenge.status  # otherwise status='pass'
				  else	
				    _.each( challenge.momentIds, (mid,k,l)->
				    							moment = syncService.get('moment', mid)
				    							if !moment? 
				    								notify.alert "ERROR: moment not found, possible data corruption. challenge="+challenge.name+", mid="+mid
				    								return
				    							missing = []
				    							moment.photos = _.reduce moment.photoIds, ((result, id)->
				    								photo = syncService.get('photo', id) 
				    								if !!photo
				    									photo.rating = 0 if !photo.rating?
					    								result.push photo
					    							else
				    									notify.alert "WARNING: DB error, photoId not found. photoId="+id
				    									missing =  missing.push id 
				    								return result ), []
			    								_.each missing, (id)->moment.photoIds.splice( moment.photoIds.indexOf(id),1)
				    							moment.challenge = challenge    # moment belongsto challenge assoc
				    							if challengeStatusPriority.indexOf(moment.status) > challengeStatusPriority.indexOf(challenge.status)
				    								challenge.status = moment.status 
				    							return
				    		)
				console.log "syncService.setForeignKeys(), elapsed="+ (new Date().getTime() - now.getTime()) + "ms"
				return
		}
		# for counts, circular dependency problem, should refactor
		drawer.setSyncService(syncService)
		# for debugging
		window.localData = syncService.localData
		return syncService
])