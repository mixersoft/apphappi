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
  'AppHappiRestangular'
, (localStorageService, CFG, drawer, $q, $filter, notify, AppHappiRestangular)->
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

			# syncService.localData[key] should always be valid
			get: (key)->	
				if syncService.localData[key]?.stale
					o = syncService.localData[key]
					switch o && o.type
						when 'moment', 'challenge'
							syncService.set(o.type, o)
						else	
							throw "ERROR: localData was not saved to localStorage, key="+key
				return syncService.localData[key]

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
						when 'moment', 'challenge'
							
							# CHECK if modified
							# remove circular reference
							circularKey = if key=='moment' then 'challenge' else 'moments'
							saveData = _.reduce collection, ((stale, o)->
								if o.stale && o.type == key 	# confirm type matches key
									syncService.parseModel[o.type] o if syncService.parseModel[o.type]?	
									stale[o.id] = _.omit(o, [circularKey,'stale']) 

								return stale 
							), {}

							if !_.isEmpty(saveData)
								localData = localStorageService.get(key) || {}	
								_.each saveData, (o)->
									pk = key+":"+o.id
									console.info "saving "+pk+" to localStorage..."
									o.type = key
									localData[o.id] = o
								localStorageService.set(key, localData)
								syncService.localData[key] = localData
								notify.alert "syncService.set() elapsed="+(new Date().getTime() - now.getTime())
								return saveData

							return null
						else 
							console.warn "WARNING: syncService, key="+key
				catch
					notify.alert "syncService.set() error"

			localStorageSet: (key, stale)->
				all = localStorageService.get(key)


			isSupported: ()->
				# config to use cookies if localStorage not supported?
				localStorageService.isSupported()

			clearAll: ()->
				localStorageService.clearAll()

			initLocalStorage: (models=[])->
				CFG.userId = new Date().getTime() if !CFG.userId?
				models = ['challenge', 'moment', 'drawer']
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
							drawer.json = syncService.localData['drawer']
							drawer.ready = $q.defer()
							drawer.ready.resolve(drawer.json)
							return drawer.ready.promise
						else 
							# load drawer from $http
							promise = drawer.load( CFG.drawerUrl ).then (resp)->
								# localStorageService.set(model, resp.data)
								localStorageService.set(model, drawer.json)
								return drawer.json
							# save to localStorageService in drawer.init()?
							return promise
					when 'challenge', 'moment'	
						if !!syncService.lastModified[model] 
							# get data from localService
							# TODO: compare localStorage lastModified against Server to detech sync
							dfd = $q.defer()
							modelData = syncService.localData[model]
							# ???: should we parseFn(modelData), set() calls parseFn
							dfd.resolve(modelData)
							return dfd.promise
						else 	
							# get data from Server
							if true && model=='moment'	
								#
								# do NOT load moment test data, return empty {} instead
								#
								dfd = $q.defer()
								dfd.resolve([])
								return dfd.promise
							else 
								promise = AppHappiRestangular.all(model)
								.getList({'modified':syncService.lastModified[model]})
								.then (data)->
									# return data if !_.isFunction(parseFn)
									# parsed = parseFn data 
									# localStorageService.set(model, parsed)

									# mark all as stale and let syncService.set() format
									_.each data, (o)->
										o.type = model
										o.stale = true

									syncService.set(model, data)	# parseModel in .set()
									return localStorageService.get(model)
								return promise
								
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
			      }
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
			}

			setForeignKeys: (challenges, moments)->
				challengeStatusPriority = ['new', 'sleep', 'pass', 'complete', 'working', 'active']
				momentsAsArray = _.values(moments)
				_.each challenges, (challenge)->
				  challenge.moments = _.where(momentsAsArray, {challengeId: challenge.id})
				  if challenge.moments.length
				    _.each challenge.moments, (moment,k,l)->
				        moment.challenge = challenge    # moment belongsto challenge assoc
				        challenge.status = moment.status if challengeStatusPriority.indexOf(moment.status) > challengeStatusPriority.indexOf(challenge.status)
				  else 
				    challenge.status = 'new'
				return
		}
		return syncService
])