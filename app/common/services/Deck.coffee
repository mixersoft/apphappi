return if !angular? 

angular.module( 
	'appHappi'
).filter('topCard', ()->
	return (deck)->
		deck.index=0 if !deck.index? or deck.index >= deck.cards.length
		deck.index=deck.cards.length-1 if deck.index<0
		if _.isArray(deck.shuffled)
			return deck.cards[deck.shuffled[deck.index]] if deck.shuffled.length==deck.cards.length
			deck.shuffled = 'error';
		return deck.cards[deck.index]	
).factory('deckService', [
	'$filter'
	'drawerService'
	($filter, drawerService)->

		_shuffleArray = (o)->
			`for (i = o.length; i; j = Math.floor(Math.random() * i), x = o[--i], o[i] = o[j], o[j] = x)`
			return o    

		_deckCounter = 0	

		class Deck
			constructor: (cards, options)->
				this.id = _deckCounter++
				this.allCards = null
				if options?.control
					this.control = options?.control 
					delete options.control
				else 
					this.control = {index:0}
				this.deckCards = null
				this.shuffled = this.shuffledCards = null
				# this.options = _.pick(options, ['filter', 'query', 'orderBy'])	
				this.cards(cards, options)
				return this

			index: (i)->
				return this.control = i if i?.index?
				if !_.isNaN( parseInt i)
					i=0 if (this.deckCards?.length <= i)
					i=0 if i<0
					this.control.index = i 
				return	this.control.index
				
			cards: (cards, options)->
				if options?
					options = _.pick(options, ['filter', 'query', 'orderBy']) 
				if _.isEmpty(options) 
					options = _.pick(drawerService.state, ['filter', 'query', 'orderBy']) 

				if cards?
					this.allCards = cards if _.isArray(cards) 
					this.deckCards = null
					this.shuffled = this.shuffledCards = null

				if !_.isEqual(options, this.options) || !this.deckCards
					# deck has changed, update deckCards
					this.index(0)
					this.options = options
					this.shuffled = null
					# filter/orderBy cards
					step = this.allCards
					step = $filter('filter') step, options.filter if !_.isEmpty(options.filter)
					step = $filter('filter') step, options.query if !_.isEmpty(options.query)
					step = $filter('orderBy') step, options.orderBy if !_.isEmpty(options.orderBy)
					this.deckCards = step

					# console.info "deck.deckCards ="+this.deckCards?.length+", options="+JSON.stringify( options) + ", this.options="+JSON.stringify( this.options)
					# console.info "carousel.index = "+this.index()
				
				this.shuffle() if this.deckCards? && this.deckCards?.length == this.allCards?.length && !options.orderBy && !this.shuffled?

				return this.deckCards if !this.shuffled?

				# shuffled
				if !this.shuffledCards?
					this.shuffledCards = _.map this.shuffled, ((el)->
						return this.deckCards[el])
					, this
				return this.shuffledCards

			removeFromDeck : (card)->
				for i in [0...this.allCards.length]
					if this.allCards[i] == card 
						this.allCards.splice(i,1)
						this.cards(this.allCards)
						break
				return

			paginatedCards : (perpage)->
				# initialize with perpage value
				if !_.isNaN parseInt perpage
					this.perpage = perpage
					this.page = 1
					return this.perpage
				# ng-repeat = paginatedCards()	
				end = this.perpage && Math.min(this.page * this.perpage, this.size()) || 0
				if perpage=="more" && end < this.size()
					return ++this.page
				else if perpage=="showing"
					return end
				else
					return this.cards()[0...end]

			size: (all)	->
				return this.allCards.length if all?
				return this.deckCards.length

			shuffle : ()->
				unshuffled = []
				unshuffled.push i for i in [0..this.deckCards.length-1]
				this.index(0)
				this.shuffled = _shuffleArray unshuffled
				this.shuffledCards = _.map this.shuffled, ((el)->
						return this.deckCards[el])
					, this
				return this

			topCard : (options)->
				return this.cards(null, options)[this.index()] if !this.deckCards?
				# check array bounds
				this.index(0) if !this.index()? || this.index() >= this.deckCards.length
				this.index(this.deckCards.length-1) if this.index()<0

				return this.cards(null, options)[this.index()]

			nextCard : (options, increment=1)->
				i = this.index() 
				if i=='new' 
					this.index(0)
				else this.index(i+increment)
				return this.topCard(options)

			# @params options object, deck options.filter/query/orderBy
			validateDeck: (options)->
				if options?
					options = _.pick(options, ['filter', 'query', 'orderBy'])
				else 
					options = _.pick(drawerService.state, ['filter', 'query', 'orderBy']) 	
				isValid = _.isEqual(this.options, options)
				return isValid


		deckService = {
			setupDeck : (cards, options)->
				return new Deck(cards, options)
		}
		return deckService
]   
).factory('sharedDeckService', [
	'$filter'
	'$q'
	'drawerService'
	'syncService'
	'deckService'
	'parseService'
	'uploadService'
	($filter, $q, drawerService, syncService, deckService, parseService, uploadService)->

		PhotoObj = StreamObj = null

		_Parse = {
			lookup: 
				'Stream': {}
				'Photo': {}
			init: ()->
				parseService.init()
				PhotoObj = Parse.Object.extend("Photo")
				StreamObj = Parse.Object.extend("Stream") 

			fetch: (userid)->
				query = new Parse.Query(StreamObj)

				query.equalTo('userId', userId) if userid

				return query.find().then (pMoments)->
						promises = []
						moments = []
						_.each pMoments, (pMoment)->
							# cache locally for updates
							_Parse.lookup[pMoment.className][pMoment.get('momentId')] = pMoment

							r = pMoment.relation('photos')
							m = _Parse.parseMoment(pMoment)
							
							promises.push r.query().find().then (pPhotos)->
								m.stats.count = pPhotos.length
								m.stats.viewed++
								# don't forget to call pMoment.save() or .increment()
								
								pPhotos = _.sortBy pPhotos, 'updatedAt'
								pPhotos.reverse()

								_.each pPhotos, (pPhoto)->
									# cache locally for updates
									_Parse.lookup[pPhoto.className][pPhoto.get('photoId')] = pPhoto

									p = _Parse.parsePhoto(pPhoto)
									m.photoIds.push p.id
									m.photos.push p

								console.log JSON.stringify m
								moments.push m

						
						return Parse.Promise.when(promises).then ()->
							return moments
								
					.fail (error)->
						check = error
						return

			parseMoment: (pMoment)->
				attrs = _.pick pMoment.attributes, ['ownerId', 'challengeId', 'challenge', 'status', 'created', 'modified' ]
				###
				Note: for custom moments, save as moment.challenge with challengeId as a UUID
				###
				if attrs.challengeId && !attrs.challenge
					challenge = syncService.get('challenge', attrs.challengeId)
				if _.isEmpty challenge
					throw "Warning: challenge not found from Shared Moment. was this a custom challenge?"
				moment = _.defaults {
					id: pMoment.get('momentId')
					type: 'shared_moment'
				}, attrs, {
					photoIds: []
					photos: []
					challenge: challenge
					stats:
						count: null
						viewed: 0
						rating: 
							moment: []
				}
				moment = syncService.parseModel['shared_moment'](moment)
				return moment

			parsePhoto: (pPhoto)-> 
				attrs = _.pick pPhoto.attributes, ['ownerId', 'dateTaken', 'Exif', 'src', 'rating', 'created', 'modified']
				
				photo = _.defaults {
						id: pPhoto.get('photoId')
						type: 'shared_photo'
						parse: _.pick pPhoto, ['id', 'createdAt', 'updatedAt']
					}, attrs
				return syncService.parseModel['shared_photo'](photo)

		}




		sharedDeckService = {

			fetch: (userid)->
				_Parse.init()
				return _Parse.fetch(userid) # promise

			post: (photo, sharedMoment)->
				# don't use cached pMoment, fetch before save()
				return uploadService.sharePhoto(photo, sharedMoment)	


			setupDeck : (userid, cards, options)->
				deckOptions = options = {control: $scope.carousel} if !options
				dfd = $q.defer()
				if cards
					dfd.resolve( deckService.setupDeck(cards, deckOptions) )
				else 
					sharedDeckService.fetch(userid).then (cards)->
						dfd.resolve( deckService.setupDeck(cards, deckOptions) )
				return dfd.promise

				
		}
		return sharedDeckService	



]
)