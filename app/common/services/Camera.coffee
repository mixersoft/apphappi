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
					deferred: null
					# deferredImgReady: null	# resolve with Img onload
					targetWidth: CFG.camera.targetWidth
					quality: CFG.camera.quality
				}
				self = this

				this.cfg = _.defaults(options, defaults)

				this._canvasElement = document.createElement('canvas')
				this._imageElement = new Image()
				this._imageElement.onload = ()->
					img = this
					self._downsize(img, self.cfg.deferred)
					# self._handleImgOnLoad(self, this)
				
			_downsize: (img, dfd, targetWidth)=>
				_.defer (self)->
					targetWidth = targetWidth || self.cfg.targetWidth
					img = img || self._imageElement
					tempW = img.width;
					tempH = img.height;
					if (tempW > targetWidth) 
						 tempH *= targetWidth / tempW;
						 tempW = targetWidth;

					# canvas = document.createElement('canvas');
					self._canvasElement.width = tempW;
					self._canvasElement.height = tempH;
					ctx = self._canvasElement.getContext("2d");
					notify.alert "downsize canvas drawImage, src="+img.src[0..20], "danger", 40000
					ctx.drawImage(img, 0, 0, tempW, tempH)
					# get downsized img as dataURL
					dataURL = self._canvasElement.toDataURL("image/jpeg")
					clearTimeout(timeout)	
					dfd.resolve(dataURL)
				, this
				timeout = _.delay (dfd)->
					dfd.reject("timeout")
				, CFG.jsTimeout, dfd
				return dfd.promise

			_handleImgOnLoad : (self, img)->
				self._downsize(img, self.cfg.deferred)
				return 

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
		
		# get formatted photo = {} for resolve		
		_getPhotoObj = (uri, dataURL, exif)->
			# get hash from EXIF to detect duplicate photo
			# hash photo data to detect duplicates
			__getPhotoHash = (exif, dataURL)->
				if !(exif?['DateTimeOriginal'])
					exifKeys = _.keys(exif)
					notify.alert "WARNING: EXIF count="+exifKeys.length+", keys="+exifKeys.join(", "), "danger", 30000	
					return false 
				hash = []
				exifKeys = _.keys(exif)
				# notify.alert "EXIF count="+exifKeys.length+", keys="+exifKeys.join(", "), "info", 30000
				compact = exif['DateTimeOriginal']?.replace(/[\:]/g,'').replace(' ','-')
				hash.push(compact)
				# notify.alert "photoHash 1="+hash.join('-'), "danger", 30000
				if dataURL?
					hash.push dataURL.slice(-20)
					# notify.alert "photoHash 2="+hash.join('-'), "danger", 30000
				else 
					hash.push exif['Model']
					hash.push exif['Make']
					hash.push exif['ExposureTime']
					hash.push exif['FNumber']
					hash.push exif['ISOSpeedRatings']
				return hash.join('-')

			now = new Date()
			dateTaken = now.toJSON()

			id = __getPhotoHash( exif, dataURL)
			if id
				isoDate = exif["DateTimeOriginal"]
				isoDate = isoDate.replace(':','-').replace(':','-').replace(' ','T')
				dateTaken = new Date(isoDate).toJSON()
			else
				id = now.getTime() + "-photo"

			notify.alert "_getPhotoObj() photo.id=="+id, "success", 2000
			return {
				id: id
				dateTaken: dateTaken
				Exif: exif || {}
				src: dataURL || uri
				fileURI: if _.isString(uri) then uri else null
				rating: 0		# required for orderBy:-rating to work				
			}

		_processImageSrc = (src, dfd)->
			_downsizer.downsizeImage(src, dfd)
			rerturn dfd.promise

		_filepathTEST = null

		_processImageFileEntry = (fileEntry, dfd)->
			fileEntry.file(
				(file)->
					_processImageFile(file, dfd)
				, (error)->
					notify.alert "fileMoved() error, CODE="+error.code, "danger", 60000
			)
			return dfd.promise

		_processImageFile = (file, dfd)->
			reader = new FileReader()
			reader.onloadend = (ev)-> 
				# notify.alert "TEST!!! READER #2 readAsDataURL, ev.target.result"+ev.target.result[0..60], "danger", 3000
				dataURL = ev.target.result
				_processImageDataURL(dataURL, file, dfd)
			# starts here	...
			reader.readAsDataURL(file);
			# setTimeout( ()->dfd.reject("timeout"), 5000)
			return dfd.promise

		_processImageDataURL = (dataURL, file, dfdFINAL)->
			dfdExif = $q.defer()
			dfdDownsize = $q.defer()
			promises = {
				exif: _parseExif dataURL , dfdExif
				downsized: _downsizer.downsizeImage(dataURL, dfdDownsize)
			}
			$q.all(promises).then (o)->
				check = _.filter o, (v)->return v=='timeout'
				if check?.length
					notify.alert "jsTimeout for " + JSON.stringify check, "warning", 10000
				src = '/'+file.name
				photo = _getPhotoObj(src, o.downsized, o.exif)

				notify.alert "FINAL resolve "+ JSON.stringify(photo), "success", 30000
				
				dfdFINAL.resolve(photo) # goes to getPicture(photo)
			return dfdFINAL.promise

		
		_parseExif = (dataURL, dfd)->
			_.defer ()->
				start = new Date().getTime()
				dataURL = atob(dataURL.replace(/^.*?,/,''))
				# notify.alert "*** _parseExif with JpegMeta ***, atob(dataURL)="+dataURL[0..60], "info", 3000
				meta = new JpegMeta.JpegFile(dataURL, 'data:image/jpeg');
				# groups: metaGroups, general, jfif, tiff, exif, gps
				_.defaults meta.exif, meta.tiff
				exif = _.reduce( meta.exif
												,(result,v,k)->
													result[v.fieldName] = v.toString() if v.fieldName?
													return result
												,{}	)
				elapsed = new Date().getTime() - start
				notify.alert "JpegMeta.JpegFile parse, elapsed MS="+elapsed
				delete exif['MakerNote']
				# notify.alert "EXIF="+_.values(_.pick(exif,['DateTimeOriginal','Make','Model'])).join('-'), null, 3000
				# notify.alert "EXIF="+JSON.stringify(exif), null, 3000
				dfd.resolve(exif)
				clearTimeout(timeout)

			timeout = _.delay (dfd)->
				dfd.reject("timeout")
			, 10000, dfd	
			return dfd.promise	

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
				# _downsizer.downsizeImage(event.target.result, _deferred)
				_processImageSrc(event.target.result, _deferred).finally( ()->
						_icon.removeClass('fa-spin')
					)

			#
			# this is the actual service for BROWSER
			#	
			return NO_cameraService = {
				# use HTML5 File api in browser
				getFilesystem : ()->
					return null
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
									_processImageFile(file, _deferred)
									# _fileReader.readAsDataURL(file)
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

			getFilesystem : ()->
				return _fsRoot

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
				# notify.alert "_fsRoot BEFORE getPicture = "+_fsRoot?.toURL(), null, 3000
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
				# notify.alert "imageUriReceived() from CameraRoll, imageURI="+imageURI

				if true && "moveTo steroids.app.absoluteUserFilesPath" && _deferred?
					# notify.alert "saving file to steroids.app.absoluteUserFilesPath...", "warning"
					_fileErrorComment = "imageUriReceived"
					window.resolveLocalFileSystemURI imageURI, self.gotFileObject, self.fileError
					return
				else if false && CFG.saveDownsizedJPG && imageURI && _deferred?
					# notify.alert "saving downsized JPG as dataURL, w="+_downsizer.cfg.targetWidth+"px...", "warning"
					# _downsizer.downsizeImage(imageURI, _deferred).then( ()->
					# 	notify.alert "DONE! saving downsized JPG as dataURL", "success"
					# )
					_processImageSrc(imageURI, _deferred).then( ()->
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
				# notify.alert "_fsRoot BEFORE on.ready = "+_fsRoot?.toURL(), null, 3000
				steroids.on "ready", ->
					# notify.alert "_fsRoot.toURL()=" +_fsRoot.toURL(), null, 3000	if _fsRoot
					# notify.alert "_fsRoot NOT AVAILABLE", 'danger', 3000 if !_fsRoot?
					
					targetDirURI = self.getFilesystem()?.toURL() || "file://" + steroids.app.absoluteUserFilesPath 
					# targetDirURI = "file://" + steroids.app.absoluteUserFilesPath 
					# targetDirURI += "/.."

					# NOTE
					# targetDirURI = file:///var/mobile...
					# _fsRoot.toURL = file://localhost/var/mobile/...
					
					fileName = new Date().getTime()+'.jpg'

					# notify.alert "targetDirURI="+targetDirURI, 'info'
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
					# notify.alert "fileMoved(): success filepath="+filepath, "success"
					# notify.alert "fileMoved(): success file.toURL="+file.toURL(), "success", 3000
					# notify.alert "fileMoved(): success file.fullPath="+file.fullPath, "danger", 3000

					_filepathTEST = filepath


					if CFG.saveDownsizedJPG
						notify.alert "saving downsized JPG as dataURL, w="+_downsizer.cfg.targetWidth+"px...", "warning", 3000
						_processImageFileEntry(file, _deferred).then( ()->
							notify.alert "DONE! saving downsized JPG as dataURL", "success", 30000
						)
					else
						src = filepath
						# src = file.toURL()  # WARNING: cannot serve IMG.src from file.toURL()
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
				notify.alert "local.PERSISTENT _fsRoot="+_fsRoot.toURL(), 'success', 10000
		else 
			notify.alert "window.requestFileSystem UNDEFINED, "+window.requestFileSystem, "danger" 
			location.reload() 

		return self
]   
)