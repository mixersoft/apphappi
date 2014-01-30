return if !angular? 

angular.module(
	'appHappi'
).factory('cameraService', [
	'$q'
	($q)->

		# for testing in browser, no access to Cordova camera API
		if !navigator.camera?
			return NO_cameraService = {
				getPicture: ()->
					_deferred = $q.defer().reject('ERROR: the Steriods camera API is not available')
					return _deferred.promise
			}

		# for devices with access to Cordova camera API
		# privabe
		_deferred = null


		cameraService = {
			# Camera options
			cameraOptions :
				fromPhotoLibrary:
					quality: 100
					destinationType: navigator.camera.DestinationType.IMAGE_URI
					sourceType: navigator.camera.PictureSourceType.PHOTOLIBRARY
					correctOrientation: true # Let Cordova correct the picture orientation (WebViews don't read EXIF data properly)
					targetWidth: 600
					popoverOptions: # iPad camera roll popover position
						width: 768
						height: 190
						arrowDir: Camera.PopoverArrowDirection.ARROW_UP
				fromCamera:
					quality: 100
					destinationType: navigator.camera.DestinationType.IMAGE_URI
					correctOrientation: true
					targetWidth: 600

			# Camera failure callback
			cameraError : (message)->
				# navigator.notification.alert 'Cordova says: ' + message, null, 'Capturing the photo failed!'
				if _deferred?
					_deferred.reject( message ).finally ()-> _deferred = null 

			# File system failure callback
			fileError : (error)->
				# navigator.notification.alert "Cordova error code: " + error.code, null, "File system error!"
				if _deferred?
					_deferred.reject( "Cordova error code: " + error.code + " File system error!" ).finally ()-> _deferred = null 

			# Take a photo using the device's camera with given options, callback chain starts
			# returns a promise
			getPicture : (options)->
				navigator.camera.getPicture cameraService.imageUriReceived, cameraService.cameraError, options
				if _deferred?
					_deferred.reject(  'Camera getPicture cancelled'  ).finally ()-> _deferred = null 
				_deferred = $q.defer()
				return _deferred.promise


			# Move the selected photo from Cordova's default tmp folder to Steroids's user files folder
			imageUriReceived : (imageURI)->
				# if _deferred?
				#   _deferred.resolve(imageURI).finally ()-> _deferred = null  
				# alert "image received from CameraRoll, imageURI="+imageURI
				window.resolveLocalFileSystemURI imageURI, cameraService.gotFileObject, cameraService.fileError

			gotFileObject : (file)->
				# Define a target directory for our file in the user files folder
				# steroids.app variables require the Steroids ready event to be fired, so ensure that
				return if !_deferred?

				steroids.on "ready", ->
					targetDirURI = "file://" + steroids.app.absoluteUserFilesPath
					# TODO: need to set filename for each photo
					fileName = "user_pic.png"

					window.resolveLocalFileSystemURI(
						targetDirURI
						(directory)->
							file.moveTo directory, fileName, cameraService.fileMoved, cameraService.fileError
						cameraService.fileError
					)

			# Store the moved file's URL into $scope.imageSrc
			# localhost serves files from both steroids.app.userFilesPath and steroids.app.path
			fileMoved : (file)->
				if _deferred?
					filepath = "/" + file.name
					alert "photo copied to App space from CameraRoll, file="+JSON.stringify file
					_deferred.resolve(filepath).finally ()-> _deferred = null
		}
		return cameraService
]   
)