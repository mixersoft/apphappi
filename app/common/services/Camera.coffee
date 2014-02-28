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
					self._handleImgOnLoad(self, this)
				
			# NOTE: extracting Exif here to wait for img.onload	
			_exif: (img, dfd)->
				_.defer ()->
					exif = {} # = EXIF.getAllTags img
					try 
						isDataURL = /^data\:image\/jpeg/.test(img.src)
						if isDataURL
							data = atob(img.src.replace(/^.*?,/,''))
						else
							throw "JpegMeta.JpegFile not implemented for img.src=filepath"
						start = new Date().getTime()
						meta = new JpegMeta.JpegFile(data, 'data:image/jpeg');
						# groups: metaGroups, general, jfif, tiff, exif, gps
						_.defaults meta.exif, meta.tiff
						exif = _.reduce( meta.exif
														,(result,v,k)->
															result[v.fieldName] = v.value
															return result
														,{}	)
						elapsed = new Date().getTime() - start
						notify.alert "JpegMeta.JpegFile parse, elapsed MS="+elapsed, "success", 30000
						delete exif['MakerNote']
						clearTimeout(timeout)	
						# notify.alert "EXIF="+_.values(_.pick(exif,['DateTimeOriginal','Make','Model'])).join('-'), null, 30000
						# notify.alert "EXIF="+JSON.stringify(exif), null, 30000
						dfd.resolve(exif)
						
					catch error
						notify.alert "Exception new JpegMeta.JpegFile(), err="+JSON.stringify(error), "danger", 20000
						dfd.resolve(exif)
				timeout = _.delay (dfd)->
					dfd.reject("timeout")
				, 10000, dfd	
				return dfd.promise
			# NOTE: extracting Exif here to wait for img.onload	

			# exif.js, not working for chrome, ipad
			_exifJS: (img, dfd)->
				_.defer ()->
					exif = {} # = EXIF.getAllTags img
					try 
						start = new Date().getTime()
						EXIF.getData img, ()->
							elapsed = new Date().getTime() - start
							notify.alert "exif.js parse, elapsed MS="+elapsed, "success", 30000
							exif = img.exifdata || {}
							delete exif['MakerNote']
							clearTimeout(timeout)	
							# notify.alert "EXIF="+_.values(_.pick(exif,['DateTimeOriginal','Make','Model'])).join('-'), null, 30000
							# notify.alert "EXIF="+JSON.stringify(exif), null, 30000
							dfd.resolve(exif)
					catch error
						notify.alert "Exception EXIF.getData", "danger", 20000
						dfd.resolve(exif)
				timeout = _.delay (dfd)->
					dfd.reject("timeout")
				, 10000, dfd	
				return dfd.promise

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
					ctx.drawImage(img, 0, 0, tempW, tempH)
					dataURL = self._canvasElement.toDataURL("image/jpeg")
					clearTimeout(timeout)	
					dfd.resolve(dataURL)
				, this
				timeout = _.delay (dfd)->
					dfd.reject("timeout")
				, CFG.jsTimeout, dfd
				return dfd.promise

			_handleImgOnLoad : (self, img)->
				dfdDownsize = $q.defer()
				dfdExif = $q.defer()
				promises = {
					exif: self._exif(img, dfdExif)
					# exifJS: self._exifXXX(img, dfdExif)
					downsize: self._downsize(img, dfdDownsize)		# this == self.imageElement
				}
				$q.all(promises).then (o)->
					check = _.filter o, (v)->return v=='timeout'
					if check?.length
						notify.alert "jsTimeout for " + JSON.stringify check

					photo = _getPhotoObj(null, o.downsize, o.exif)

					# notify.alert "FINAL resolve "+ JSON.stringify(photo), "success", 3000
					
					self.cfg.deferred.resolve(photo) # goes to getPicture(photo)
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
		
		# hash photo data to detect duplicates
		_getPhotoHash = (exif, dataURL)->
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

		_getPhotoObj = (uri, dataURL, exif)->
			# get hash from EXIF to detect duplicate photo
			now = new Date()
			dateTaken = now.toJSON()

			if exif?
				id = _getPhotoHash exif, dataURL
				if exif["DateTimeOriginal"]?
					isoDate = exif["DateTimeOriginal"]
					isoDate = isoDate.replace(':','-').replace(':','-').replace(' ','T')
					dateTaken = new Date(isoDate).toJSON()
			else
				id = now.getTime() + "-photo"

			notify.alert "photo.id=="+id, "success", 30000
			return {
				id: id
				dateTaken: dateTaken
				Exif: exif || {}
				src: uri || dataURL
			}

		_processImageSrc = (src, dfd)->
			_downsizer.downsizeImage(src, dfd)


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

					notify.alert "targetDirURI="+targetDirURI, 'info', 10000
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
					notify.alert "fileMoved(): success file.fullPath="+file.fullPath, "danger", 30000

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
						# _downsizer.downsizeImage(filepath, _deferred).then( ()->
						# 	notify.alert "DONE! saving downsized JPG as dataURL", "success"
						# )
						_processImageSrc(filepath, _deferred).then( ()->
							notify.alert "DONE! saving downsized JPG as dataURL", "success"
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