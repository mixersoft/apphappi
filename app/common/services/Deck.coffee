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
	($filter, drawer)->
		deckService = {
			validateDeck : (cards, deck, options)->
				return deck.cards && cards.length == deck.origCount && JSON.stringify(_.pick(options, ['filter', 'query', 'orderBy'])) == deck.options

			setupDeck : (cards, deck={}, options={})->
				options = _.pick(options, ['filter', 'query', 'orderBy'])
				if !deckService.validateDeck cards, deck, options
					step = cards
					step = $filter('filter') step, options.filter if options.filter?
					step = $filter('filter') step, options.query if options.query?
					step = $filter('orderBy') step, options.orderBy if options.orderBy?
					deck.origCount = cards.length
					deck.cards = step
					deck.options = JSON.stringify options
					deck.index = 0  
				return deck

			shuffleDeck : (deck)->
				unshuffled = []
				unshuffled.push i for i in [0..deck.cards.length-1]
				deck.index = 0;
				deck.shuffled = deckService._shuffleArray unshuffled
				return deck

			_shuffleArray : (o)->
				`for (i = o.length; i; j = Math.floor(Math.random() * i), x = o[--i], o[i] = o[j], o[j] = x)`
				return o    

			topCard : (deck)->
				return $filter('topCard') deck

			nextCard : (cards, deck={}, options={})->
				if deckService.validateDeck cards, deck, options
					deck.index += (options.increment || 1)
				else
					valid = deckService.setupDeck cards, deck, options
				return deckService.topCard deck

			# for use with ng-repeat
			deckCards : (deck)->
				return deck.cards if !deck.shuffled?
				shuffledCards = _.map deck.shuffled, (el)->
					return deck.cards[el]
				return shuffledCards

		}
		return deckService
]   
)