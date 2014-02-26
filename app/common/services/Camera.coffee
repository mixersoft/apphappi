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
					quality: CFG.camera.quality
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
		_deferredCounter = 0
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
		_fsRoot = null	# cordova.file.DirectoryEntry
		_requestFsPERSISTENT = ()->
		# for devices with access to Cordova camera API
			# notify.alert "1. window.deviceReady. navigator.camera"+JSON.stringify(navigator.camera), null, 10000
			_fsDeferred = $q.defer()
			window.requestFileSystem(
				LocalFileSystem.PERSISTENT
				, 50000*1024
				, (fs)-> 
					_fsRoot = fs.root
					_fsDeferred.resolve(_fsRoot)
					# notify.alert "2. window.requestFileSystem, _fsRoot.toURL()= "+_fsRoot.toURL(), 'success', 60000
				, (ev)->
					notify.alert "3. Error: requestFileSystem failed. "+ev.target.error.code, 'danger', 10000
					_fsDeferred.reject(ev)
			)
			return _fsDeferred.promise

		_fileErrorComment = ""

		self = {
			# Camera options
			cameraOptions :
				fromPhotoLibrary:
					quality: CFG.camera.quality
					destinationType: navigator.camera.DestinationType.FILE_URI
					# destinationType: navigator.camera.DestinationType.IMAGE_URI
					# destinationType: navigator.camera.DestinationType.NATIVE_URI
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
					_deferred.reject( "Cordova error code: " + error.code + " fileError. " + _fileErrorComment )

			# Take a photo using the device's camera with given options, callback chain starts
			# returns a promise
			getPicture : (options, $event)->
				# notify.alert "_fsRoot BEFORE getPicture = "+_fsRoot?.toURL(), null, 30000
				navigator.camera.getPicture self.imageUriReceived, self.cameraError, options
				if _deferred?
					_deferred.reject(  'Camera getPicture cancelled, _deferred.id='+_deferred.id  )
				_deferred = $q.defer()
				_deferred.id = _deferredCounter++
				_deferred.promise.finally ()-> 
					# notify.alert "*** finally, set clear _deferred, id="+_deferred.id, "danger"
					_deferred = null
				# notify.alert "getPicture(): NEW _deferred, id="+_deferred.id, "success"
				return _deferred.promise

			# Move the selected photo from Cordova's default tmp folder to Steroids's user files folder
			imageUriReceived : (imageURI)->
				notify.alert "imageUriReceived() from CameraRoll, imageURI="+imageURI

				if true && "moveTo steroids.app.absoluteUserFilesPath" && _deferred?
					notify.alert "saving file to steroids.app.absoluteUserFilesPath...", "warning"
					_fileErrorComment = "imageUriReceived"
					window.resolveLocalFileSystemURI imageURI, self.gotFileObject, self.fileError
					return
				else if false && CFG.saveDownsizedJPG && imageURI && _deferred?
					# notify.alert "saving downsized JPG as dataURL, w="+_downsizer.cfg.targetWidth+"px...", "warning"
					_downsizer.downsizeImage(imageURI, _deferred).then( ()->
						notify.alert "DONE! saving downsized JPG as dataURL", "success"
					)
					return
				else if false && "use imgeURI directly" && _deferred?
					photo = _getPhotoObj(imageURI)
					_deferred.resolve(photo)
					return
				else
					notify.alert "Error: shouldn't be here, _deferred="+JSON.stringify( _deferred), "danger", 10000 
				return

			gotFileObject : (file)->
				# Define a target directory for our file in the user files folder
				# steroids.app variables require the Steroids ready event to be fired, so ensure that
				return notify.alert "Error: gotFileObject() deferred is null", "warning" if !_deferred?

				# notify.alert "gotFileObject(), file="+JSON.stringify( file), "warning", 20000
				# notify.alert "_fsRoot BEFORE on.ready = "+_fsRoot?.toURL(), null, 30000
				steroids.on "ready", ->
					notify.alert "_fsRoot.toURL()=" +_fsRoot.toURL(), null, 30000	if _fsRoot
					notify.alert "_fsRoot NOT AVAILABLE", 'danger', 30000 if !_fsRoot?
					

					targetDirURI = _fsRoot?.toURL() || "file://" + steroids.app.absoluteUserFilesPath 
					# targetDirURI += "/.."

					# NOTE
					# targetDirURI = file:///var/mobile...
					# _fsRoot.toURL = file://localhost/var/mobile/...
					
					fileName = new Date().getTime()+'.jpg'

					notify.alert "targetDirURI="+targetDirURI, 'info', 60000
					_fileErrorComment = "gotFileObject"

					window.resolveLocalFileSystemURI(
						targetDirURI,
						((directory)->
													_fileErrorComment = "resolveLocalFileSystemURI, path="+directory.fullPath+'/'+fileName
													file.moveTo directory, fileName, self.fileMoved, self.fileError),
						self.fileError
					)
					# _requestFsPERSISTENT()
					return

			# Store the moved file's URL into $scope.imageSrc
			# localhost serves files from both steroids.app.userFilesPath and steroids.app.path
			# @param file cordova.file.FileEntry
			fileMoved : (file)->
				# notify.alert "fileMoved(): BEFORE deferred.resolve() _dfd="+JSON.stringify _deferred
				if _deferred?
					filepath = "/" + file.name
					notify.alert "fileMoved(): success filepath="+filepath, "success"
					notify.alert "fileMoved(): success file.toURL="+file.toURL(), "success", 30000
					notify.alert "fileMoved(): success file.fullPath="+file.fullPath, "success", 30000

					checkMeta = ()->
						dfd = $q.defer()
						file.getMetadata(
							(meta)->
								notify.alert "file.getMetadata()="+JSON.stringify(meta), 'success', 20000
								# keys = [modification_time]
								dfd.resolve(meta)
							, ()->
								msg = 
								notify.alert "file.getMetadata() FAILED, path="+file.fullpath, "warning", 20000	
								dfd.reject(msg)
						)		# meta==undefined
						return dfd.promise
						

					checkSteroidsResize = ()->
						try
							sourceImage = new steroids.File({
										path: file.name
										relativeTo: steroids.app.userFilesPath
									})
							notify.alert "sourceImage=" + JSON.stringify( sourceImage), "info"
							# steroids.File.resizeImage()
							# fails here
							resize = sourceImage.resizeImage || sourceImage.resize
							resize({
									format: 
										type: "jpg"
										compression: _downsizer.cfg.quality
									constraint: 
										dimension: "width"
										length: _downsizer.cfg.targetWidth
								}, {
									onSuccess: (sourceImage)->
										notify.alert "resize SUCCESS", 'success'
										_filepath = sourceImage.relativeTo + '/' + sourceImage.path
										notify.alert "resize SUCCESS, path="+_filepath, 'success'
										photo = _getPhotoObj(filepath)
										_deferred.resolve(photo)

									onFailure: ()->notify.alert "resize FAILED", 'danger'
								}
							)
							notify.alert "resizing..."
						catch error

					if false # these 2 methods do not work
						# getMetaPromise = checkMeta()
						# checkSteroidsResize()
						return


					if CFG.saveDownsizedJPG
						notify.alert "saving downsized JPG as dataURL, w="+_downsizer.cfg.targetWidth+"px...", "warning"
						# # update photo.dateTaken when available
						# # WARNING: only meta.modification_time is available
						# $q.all({
						# 	photo: _deferred
						# 	getMetadata: checkMeta()
						# 	}).then (o)->
						# 		o.photo.dateTaken = o.getMetadata.dateTaken
						_downsizer.downsizeImage(filepath, _deferred).then( ()->
							notify.alert "DONE! saving downsized JPG as dataURL", "success"
						)
					else
						src = filepath
						# src = file.toURL()  # NOTE: cannot serve IMG.src from file.toURL()
						notify.alert "DONE! saving file to "+src, "success", 30000
						photo = _getPhotoObj(src)
						_deferred.resolve(photo)
					return
					# notify.alert "fileMoved(): "+JSON.stringify( file, null, 2)

				self.cleanup()	

			cleanup : ()->
				# doesn't seem to work
				navigator.camera.cleanup (()->notify.alert "Camera.cleanup success"), (()-> notify.alert 'Camera cleanup Failed because: ' + message, "warning" )

		}

		if _.isFunction(window.requestFileSystem)
			# notify.alert "window.requestFileSystem OK, "+window.requestFileSystem, "success" 
			_requestFsPERSISTENT().then (directoryEntry)->
				_fsRoot = directoryEntry
				notify.alert "local.PERSISTENT _fsRoot="+_fsRoot.toURL(), 'success', 60000
		else 
			notify.alert "window.requestFileSystem UNDEFINED, "+window.requestFileSystem, "danger" 
			location.reload() 

		return self
]   
)