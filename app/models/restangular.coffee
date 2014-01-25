return if !angular?

hostconfig = {
	localhost: 'localhost'
	home: '192.168.1.8'
	'1776': '10.1.10.212'
}

baseurl = [
	'http://'
	hostconfig.localhost
	':4001'
	'/common/data'
]

angular.module( 'restangularModel'
, ['restangular']

).factory( 'AppHappiRestangular'
, (Restangular)->
		Restangular.withConfig (RestangularConfigurer)->
			RestangularConfigurer.setBaseUrl(baseurl.join(''))
			RestangularConfigurer.setRequestSuffix('.json')
			RestangularConfigurer.setRestangularFields {
					id: "id"
				}
)

