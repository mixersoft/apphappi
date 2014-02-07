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

		_shuffleArray : (o)->
			`for (i = o.length; i; j = Math.floor(Math.random() * i), x = o[--i], o[i] = o[j], o[j] = x)`
			return o    

		_deckCounter = 0	

		class Deck
			constructor: (cards, options)->
				this.id = _deckCounter++
				this.allCards = null
				this._index = this.deckCards = null
				this.options = _.pick(options, ['filter', 'query', 'orderBy'])
				this.shuffled = this.shuffledCards = null
				this.cards(cards, options)
				return this

			index: (i)->
				this._index = i if typeof i != 'undefined'
				return	this._index
				
			cards: (cards, options)->
				if options?
					options = _.pick(options, ['filter', 'query', 'orderBy']) 
				else 
					options = _.pick(drawerService.state, ['filter', 'query', 'orderBy']) 

				if cards?
					this.allCards = cards 
					this.deckCards = null
					this.index(0)
					this.shuffled = this.shuffledCards = null

				if !_.isEqual(options, this.options) || !this.deckCards
					# deck has changed, update deckCards
					# filter/orderBy cards
					step = this.allCards
					step = $filter('filter') step, options.filter if !_.isEmpty(options.filter)
					step = $filter('filter') step, options.query if !_.isEmpty(options.query)
					step = $filter('orderBy') step, options.orderBy if !_.isEmpty(options.orderBy)
					this.deckCards = step
				return this.deckCards if !this.shuffled?
				# shuffled
				if !this.shuffledCards?
					this.shuffledCards = _.map this.shuffled, (el)->
						return this.deckCards[el]
				return this.shuffledCards

			size: (all)	->
				return this.allCards.length if all?
				return this.deckCards.length

			shuffle : ()->
				unshuffled = []
				unshuffled.push i for i in [0..this.deckCards.length-1]
				this.index(0)
				this.shuffled = _shuffleArray unshuffled
				return this

			topCard : (options)->
				return this.cards(null, options)[this.index()] if !this.deckCards?
				# check array bounds
				this.index(0) if !this.index()? or this.index() >= this.deckCards.length
				this.index(this.deckCards.length-1) if this.index()<0

				return this.cards(null, options)[this.index()]

			nextCard : (options, increment=1)->
				i = this.index() 
				if i=='new' 
					this.index(0)
				else this.index(i+increment)
				return this.topCard(options)

			validateDeck: (cards, options)->
				if options?
					options = _.pick(options, ['filter', 'query', 'orderBy'])
				else 
					options = _.pick(drawerService.state, ['filter', 'query', 'orderBy']) 	
				return this.deckCards.length == cards.length  &&  _.isEqual(this.options, options)


		deckService = {
			setupDeck : (cards, options)->
				return new Deck(cards, options)
		}
		return deckService
]   
)