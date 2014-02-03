return if !angular?

hostconfig = {
	localhost: 'localhost'
	home: '192.168.1.8'
	'1776': '10.1.10.212'
}

baseurl = [
	'http://'
	hostconfig['home']
	":"
	window.location.port
	'/common/data'
]

angular.module( 
	'appHappi'
).factory( 'AppHappiRestangular', (Restangular)->
		Restangular.withConfig (RestangularConfigurer)->
			RestangularConfigurer.setBaseUrl(baseurl.join(''))
			RestangularConfigurer.setRequestSuffix('.json')
			RestangularConfigurer.setRestangularFields {
					id: "id"
				}
)

