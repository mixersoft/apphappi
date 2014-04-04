return if !angular? 

angular.module(
	'appHappi'
).service('cordovaImpl', [()->
		# use cameraService from Camera.coffee for now

	]
).service('html5CameraService', [
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
			return self = {
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
			} # end self


		}

		if _.isFunction(window.requestFileSystem)
			# notify.alert "window.requestFileSystem OK, "+window.requestFileSystem, "success" 
			_requestFsPERSISTENT().then (directoryEntry)->
				_fsRoot = directoryEntry
				notify.alert "local.PERSISTENT _fsRoot="+_fsRoot.toURL(), 'success', 10000

		return self
]   
)
###
usage: add the following factory to the app to inject the correct module

.factory('cameraRoll', [
	'$window'
	'$injector'
	'$timeout'
	($window, $injector, $timeout)->
		#
		# load the correct service for the device
		# 	uses html5/plupload when run in browser
		#   navigator.camera.getPicture() when run as app in cordova
		#
		cancel = $timeout ()->
					null
			, 2000		
		document.addEventListener "deviceready", ()->
			$timeout.cancel cancel
			# if ($window.navigator?.camera) 
			if (true || $window.cordova) 
				# return $injector.get('cordovaImpl')
				return $injector.get('cameraService')
			else
				return $injector.get('html5CameraService')

	]
)
###