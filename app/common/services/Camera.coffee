return if !angular? 

angular.module(
	'appHappi'
).factory('cameraService', [
	'$q'
	'notifyService'
	($q, notify)->

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
					# destinationType: navigator.camera.DestinationType.IMAGE_URI
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
					_deferred.reject( message )
					_deferred.promise.finally ()-> _deferred = null 

			# File system failure callback
			fileError : (error)->
				# navigator.notification.alert "Cordova error code: " + error.code, null, "File system error!"
				if _deferred?
					_deferred.reject( "Cordova error code: " + error.code + " File system error!" )
					_deferred.promise.finally ()-> _deferred = null 

			# Take a photo using the device's camera with given options, callback chain starts
			# returns a promise
			getPicture : (options)->
				navigator.camera.getPicture cameraService.imageUriReceived, cameraService.cameraError, options
				if _deferred?
					_deferred.reject(  'Camera getPicture cancelled'  )
					_deferred.promise.finally ()-> _deferred = null 
				_deferred = $q.defer()
				# notify.alert "getPicture(): NEW _deferred="+JSON.stringify _deferred, "success"
				return _deferred.promise


			# Move the selected photo from Cordova's default tmp folder to Steroids's user files folder
			imageUriReceived : (imageURI)->
				# if _deferred?
				#   _deferred.resolve(imageURI)
				#   _deferred.promise.finally ()-> _deferred = null  
				notify.alert "image received from CameraRoll, imageURI="+imageURI
				window.resolveLocalFileSystemURI imageURI, cameraService.gotFileObject, cameraService.fileError

			gotFileObject : (file)->
				# Define a target directory for our file in the user files folder
				# steroids.app variables require the Steroids ready event to be fired, so ensure that
				return notify.alert "Error: gotFileObject() deferred is null", "warning" if !_deferred?

				# notify.alert "gotFileObject(), file="+JSON.stringify file, "warning"

				steroids.on "ready", ->
					# notify.alert "steroids.on('ready'): file="+file.name
					targetDirURI = "file://" + steroids.app.absoluteUserFilesPath
					fileName = new Date().getTime()+'.jpg'

					window.resolveLocalFileSystemURI(
						targetDirURI
						(directory)->
							file.moveTo directory, fileName, fileMoved, cameraService.fileError
						cameraService.fileError
					)

				# Store the moved file's URL into $scope.imageSrc
				# localhost serves files from both steroids.app.userFilesPath and steroids.app.path
				fileMoved = (file)->
					# notify.alert "fileMoved(): BEFORE deferred.resolve() _dfd="+JSON.stringify _dfd
					if _deferred?
						filepath = "/" + file.name
						# notify.alert "fileMoved(): BEFORE deferred.resolve() filepath="+filepath
						_deferred.resolve(filepath)
						_deferred.promise.finally (filepath)-> 
							_deferred = null
							# notify.alert "fileMoved(): in deferred.finally(), file="+filepath+", _deferred="+_deferred
							return
						# notify.alert "fileMoved(): photo copied to App space from CameraRoll, file="+JSON.stringify file
					cameraService.cleanup()	

			cleanup : ()->
				navigator.camera.cleanup (()->console.log "Camera.cleanup success"), (()-> notify.alert 'Camera cleanup Failed because: ' + message, "warning" )

		}
		return cameraService
]   
)