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
				
				switch (scope.route.controller)
					when 'ChallengeCtrl'
						helpService.template = templatePath + '_challenges.html'
					when 'MomentCtrl'
						edit = !!scope.route.action
						if edit
							helpService.template = templatePath + '_moments_edit.html'
						else helpService.template = templatePath + '_moments.html'
					when 'TimelineCtrl'
						helpService.template = templatePath + '_timeline.html'
					else 
						helpService.hide()


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