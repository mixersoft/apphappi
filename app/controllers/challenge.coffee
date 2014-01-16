return if !angular? 

challengeApp = angular.module( 'challengeApp'
, [
	'ngRoute'
	, 'challengeModel'
]
).config( [
	'$routeProvider'
	($routeProvider)->
		$routeProvider
		.when('/challenges', {
			templateUrl: 'partials/summary.html'
			controller: 'ChallengeCtrl'
			})
		.when('/challenges/:id', {
			templateUrl: 'partials/card.html'
			controller: 'ChallengeCtrl'
			})
		.otherwise {
			redirectTo: '/challenges'
		}
]
).controller( 'ChallengeCtrl'
# TODO: check of ChallengeRestangular must match factory
, ($scope, ChallengeRestangular)->
	$scope.orderBy = 'category'
	$scope.orderBy2 = 'title'
	$scope.challenges = ChallengeRestangular
	.all('challenge')
	.getList()
	.then (challenges)->
		$scope.challenges = challenges;
		console.log JSON.stringify $scope.challenges
)

