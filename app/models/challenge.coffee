return if !angular? 

angular.module( 'challengeModel'
, ['restangular']

).factory( 'ChallengeRestangular'
, (Restangular)->
		Restangular.withConfig (RestangularConfigurer)->
			RestangularConfigurer.setBaseUrl('http://10.1.10.212:4001/common/data')
			RestangularConfigurer.setRequestSuffix('.json')
			RestangularConfigurer.setRestangularFields {
					id: "id"
				}
)
