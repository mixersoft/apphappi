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
  'AppHappiRestangular'
, (localStorageService, appConfig, drawer, $q, $filter, AppHappiRestangular)->
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

			get: (key)->				
				return localStorageService.get(key)

			set: (key, value)->
				# remove circular reference
				try
					switch key
						when 'moment', 'challenge'
							circularKey = if key=='moment' then 'challenge' else 'moment'
							value = _.reduce value, ((last, o)->
								last.push _.omit(o, circularKey) 
								return last 
							), []
					return localStorageService.set(key, value)
				catch
					alert "syncService.set() error"	

			isSupported: ()->
				# config to use cookies if localStorage not supported?
				localStorageService.isSupported()

			clearAll: ()->
				localStorageService.clearAll()

			initLocalStorage: (models=[], parser=syncService.parseModel)->
				models = ['challenge', 'moment', 'drawer']
				for model in models
					syncService.promises[model] = syncService.initLocalStorageModel model, parser[model]
				return syncService.promises		 	

			# @return $q.promise
			initLocalStorageModel: (model, parseFn)->
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
							promise = drawer.load( appConfig.drawerUrl ).then (resp)->
								# localStorageService.set(model, resp.data)
								localStorageService.set(model, drawer.json)
								return drawer.json
							# save to localStorageService in drawer.init()?
							return promise
					when 'challenge', 'moment'	
						if !!syncService.lastModified[model] 
							dfd = $q.defer()
							dfd.resolve(syncService.localData[model])
							return dfd.promise
						else 	
							return AppHappiRestangular.all(model).getList({'modified':syncService.lastModified[model]}).then (data)->
								return data if !_.isFunction(parseFn)
								parsed = parseFn data 
								localStorageService.set(model, parsed)
								return parsed 	
								
			parseModel: {
				'challenge': (challenges)->
					for c in challenges
						console.log "challenge parseModel: "+c.modified
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
						}
					return challenges
				'moment': (moments)->
					for m in moments
						console.log "moment parseModel: "+m.modified
						m.humanize = {
							completed: moment.utc(new Date(m.created)).format("dddd, MMMM Do YYYY, h:mm:ss a")
							completedAgo: moment.utc(new Date(m.created)).fromNow()
							completedIn: _asDuration m.stats && m.stats.completedIn || 0
						}
					return  moments
			}

			setForeignKeys: (challenges, moments)->
				challengeStatusPriority = ['new','pass', 'complete','edit','active']
				for challenge in challenges
				  challenge.moments = _.where(moments, {challengeId: challenge.id})
				  if challenge.moments.length
				    _.each challenge.moments, (moment,k,l)->
				        moment.challenge = challenge    # moment belongsto challenge assoc
				        challenge.status = moment.status if challengeStatusPriority.indexOf(moment.status) > challengeStatusPriority.indexOf(challenge.status)
				  else 
				    challenge.status = 'new'
		}
		return syncService
])