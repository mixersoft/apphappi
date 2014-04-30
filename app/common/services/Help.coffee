return if !angular? 

angular.module( 
	'appHappi'
).factory('helpService', [
	'$timeout'
	'$location'
	'appConfig'
	'drawerService'
	'notifyService'
	($timeout, $location, appConfig, drawerService, notifyService)->

		templatePath = '/common/templates/help/'

		helpService = {

			show: (e)->
				notifyService.clearMessages()
				scope = angular.element(document.getElementById('help-wrap'))
					.removeClass('hidden')
					.scope()
				
				switch ($location.url())
					when '/challenges', '/challenges/draw-new'
						helpService.template = templatePath + '_challenges.html'
					when '/moments'
						helpService.template = templatePath + '_moments.html'
					when '/timeline'
						helpService.template = templatePath + '_timeline.html'


				return
			hide: ()->
				angular.element(document.getElementById('help-wrap')).addClass('hidden')
				helpService.template = null
				return

			template: null

			
		}

		return helpService
]   
)