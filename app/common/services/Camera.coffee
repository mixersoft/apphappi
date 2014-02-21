return if !angular? 

angular.module(
	'appHappi'
).factory('cameraService', [
	'$q'
	'notifyService'
	'appConfig'
	($q, notify, CFG)->

		class Downsizer
			constructor: (options)->
				defaults = {
					deferred: _deferred
					targetWidth: CFG.camera.targetWidth
				}
				self = this

				this.cfg = _.defaults(options, defaults)
				this._canvasElement = document.createElement('canvas')
				this._imageElement = new Image()
				
				this._imageElement.onload = ()->
					dataURL = self._downsize(this)		# this == self.imageElement
					photo = _getPhotoObj(null, dataURL)
					self.cfg.deferred.resolve(photo)

				return this

			_downsize: (img, targetWidth)=>
				targetWidth = targetWidth || this.cfg.targetWidth
				img = img || this._imageElement
				tempW = img.width;
				tempH = img.height;
				if (tempW > targetWidth) 
					 tempH *= targetWidth / tempW;
					 tempW = targetWidth;

				# canvas = document.createElement('canvas');
				this._canvasElement.width = tempW;
				this._canvasElement.height = tempH;
				ctx = this._canvasElement.getContext("2d");
				ctx.drawImage(img, 0, 0, tempW, tempH)
				return dataURL = this._canvasElement.toDataURL("image/jpeg")	

			downsizeImage : (src, dfd, targetWidth)=>
				this.cfg.deferred = dfd if dfd?
				this.cfg.targetWidth = targetWidth if targetWidth?	
				this._imageElement.src = src
				return this.cfg.deferred.promise

		# private object for downsizing via canvas
		_deferred = null
		_downsizer = new Downsizer({
			deferred: _deferred
			targetWidth: CFG.camera.targetWidth
		})	
		
		_getPhotoObj = (uri, dataURL)->
			# get hash from EXIF to detect duplicate photo
			now = new Date()
			id = now.getTime() + "-photo"
			return {
				id: id
				dateTaken: now.toJSON()
				Exif: {}
				src: uri || dataURL
			}


		#  ### BROWSER TESTING ###
		#  for testing in browser, no access to Cordova camera API
		#
		if !navigator.camera?
			#
			# private
			#
			_fileReader = new FileReader()
			_icon = null

			_fileReader.onload = (event)->
				# _imageElement.src = event.target.result
				_downsizer.downsizeImage(event.target.result, _deferred).then( ()->
						_icon.removeClass('fa-spin')
					)

			#
			# this is the actual service for BROWSER
			#	
			return NO_cameraService = {
				# use HTML5 File api in browser
				getPicture: (e)->
					if _deferred?
						_deferred.reject(  '(HTML5 getPicture() cancelled'  )
					_deferred = $q.defer()
					_deferred.promise.finally ()-> _deferred = null
					_icon =  angular.element(e.currentTarget.parentNode).find('i')

					if (e.currentTarget.tagName=='INPUT' && 
											e.currentTarget.type=='file' && 
											!e.currentTarget.onchange?)
						# input[type="file"]
						e.currentTarget.onchange = (e)->
								e.preventDefault();
								file = e.currentTarget.files[0]
								if file 
									_fileReader.readAsDataURL(file)
									_icon.addClass('fa-spin') if _icon?
								return false
					# notify.alert "getPicture(): NEW _deferred="+JSON.stringify _deferred, "success"
					return _deferred.promise
			} # end NO_cameraService

		#
		# ### for DEVICE ###
		#

		# private
		_fsRoot = null
		_requestFsPERSISTENT = ()->
		# for devices with access to Cordova camera API
			notify.alert "1. window.deviceReady. navigator.camera"+JSON.stringify(navigator.camera), null, 10000
			_fsDeferred = $q.defer()
			window.requestFileSystem(
				LocalFileSystem.PERSISTENT, 
				50000*1024, 
				(fs)-> 
					notify.alert "2. window.requestFileSystem, FS= "+JSON.stringify(fs), null, 10000
					_fsRoot = fs.root
					_fsDeferred.resolve(_fsRoot)
				(ev)->
					notify.alert "3. Error: requestFileSystem failed. "+ev.target.error.code, 'danger', 10000
					_fsDeferred.reject(ev)
			)
			_fsDeferred.promise.finally ()-> 
				notify.alert "4. window.requestFileSystem(), Deferred.promise.finally(), args"+JSON.stringify arguments, 'success', 10000
			notify.alert "5. continue with cameraService init"	


		cameraService = {
			# Camera options
			cameraOptions :
				fromPhotoLibrary:
					quality: CFG.camera.quality
					# destinationType: navigator.camera.DestinationType.IMAGE_URI
					destinationType: navigator.camera.DestinationType.IMAGE_URI
					sourceType: navigator.camera.PictureSourceType.PHOTOLIBRARY
					correctOrientation: true # Let Cordova correct the picture orientation (WebViews don't read EXIF data properly)
					targetWidth: CFG.camera.targetWidth
					popoverOptions: # iPad camera roll popover position
						width: 768
						height: 190
						arrowDir: Camera.PopoverArrowDirection.ARROW_UP
				fromCamera:
					quality: CFG.camera.quality
					destinationType: navigator.camera.DestinationType.IMAGE_URI
					correctOrientation: true
					targetWidth: CFG.camera.targetWidth

			# Camera failure callback
			cameraError : (message)->
				# navigator.notification.alert 'Cordova says: ' + message, null, 'Capturing the photo failed!'
				if _deferred?
					_deferred.reject( message )
					 

			# File system failure callback
			fileError : (error)->
				# navigator.notification.alert "Cordova error code: " + error.code, null, "File system error!"
				if _deferred?
					_deferred.reject( "Cordova error code: " + error.code + " File system error!" )

			# Take a photo using the device's camera with given options, callback chain starts
			# returns a promise
			getPicture : (options, $event)->
				navigator.camera.getPicture cameraService.imageUriReceived, cameraService.cameraError, options
				if _deferred?
					_deferred.reject(  'Camera getPicture cancelled'  )
				_deferred = $q.defer()
				_deferred.promise.finally ()-> _deferred = null
				# notify.alert "getPicture(): NEW _deferred="+JSON.stringify _deferred, "success"
				return _deferred.promise


			# Move the selected photo from Cordova's default tmp folder to Steroids's user files folder
			imageUriReceived : (imageURI)->
				# if _deferred?
				# 	photo = {
				# 		id: _getPhotoId(imageURI, null)
				# 		src: imageURI
				# 	}
				#   _deferred.resolve(photo)
				# notify.alert "image received from CameraRoll, imageURI="+imageURI
				window.resolveLocalFileSystemURI imageURI, cameraService.gotFileObject, cameraService.fileError

			gotFileObject : (file)->
				# Define a target directory for our file in the user files folder
				# steroids.app variables require the Steroids ready event to be fired, so ensure that
				return notify.alert "Error: gotFileObject() deferred is null", "warning" if !_deferred?

				# notify.alert "gotFileObject(), file="+JSON.stringify file, "warning"

				steroids.on "ready", ->
					# notify.alert "steroids.on('ready'): file="+file.name
					# targetDirURI = _fsRoot.fullpath		
					targetDirURI = "file://" + steroids.app.absoluteUserFilesPath + "/../photos"
					fileName = new Date().getTime()+'.jpg'

					window.resolveLocalFileSystemURI(
						targetDirURI
						((directory)->file.moveTo directory, fileName, fileMoved, cameraService.fileError)
						cameraService.fileError
					)

					# _requestFsPERSISTENT()

				# Store the moved file's URL into $scope.imageSrc
				# localhost serves files from both steroids.app.userFilesPath and steroids.app.path
				fileMoved = (file)->
					# notify.alert "fileMoved(): BEFORE deferred.resolve() _dfd="+JSON.stringify _dfd
					if _deferred?
						filepath = "/" + file.name
						# notify.alert "fileMoved(): BEFORE deferred.resolve() filepath="+filepath
						if CFG.saveDownsizedJPG
							targetWidth = CFG.camera.targetWidth
							_downsizer.downsizeImage(filepath,_deferred).then( ()->
								notify.alert "saving JPG as dataURL, w="+targetWidth+"px", "success"
							)
						else
							photo = _getPhotoObj(filepath)
							_deferred.resolve(photo)
							# notify.alert "fileMoved(): in deferred.finally(), file="+filepath+", _deferred="+_deferred
						return
						# notify.alert "fileMoved(): "+JSON.stringify( file, null, 2)
					cameraService.cleanup()	

			cleanup : ()->
				navigator.camera.cleanup (()->console.log "Camera.cleanup success"), (()-> notify.alert 'Camera cleanup Failed because: ' + message, "warning" )

		}
		return cameraService
]   
)