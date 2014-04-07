return if !angular? 

angular.module(
	'appHappi'
).service('cordovaImpl', [()->
		# use cameraService from Camera.coffee for now
		return false
	]
).service('html5CameraService', [
	'$q'
	'notifyService'
	'appConfig'
	($q, notify, CFG)->
		#
		# private
		#
		_deferred = {}
		_fsRoot = null

		# pluploader
		_plupload = {
			uploader: null			# new plupload.Uploader(_plupload.defaults)	
			bind: (handlers)->
				up = _plupload.uploader
				return false if !up
				up.unbindAll()
				# bind internal handlers
				_.each handlers, (fn, ev)->
					up.bind ev, fn, up
				return true

			defaults : {
				runtimes : 'html5'
				# TODO: need to let challenge_getPhoto() invoke uploader
				browse_button: 'html5-get-file'
				drop_element: 'html5-get-file'
				multi_selection: true
				url: 'nothing'
				filters :
					max_file_size: '10mb'
					mime_types: [{
							title : "Photos"
							extensions : "jpg,jpeg"
						}]
						prevent_duplicates: true
				# resize: 
				# 	width: 320
				# 	height: 320
				# 	quality: 85
				# 	crop: false		
				# 	preserve_headers : true
				init: 
					PostInit: ()->
							return false;
			}
		}
		_plupload.uploader = new plupload.Uploader(_plupload.defaults)
		window._up = _plupload.uploader 		# for debugging
		


		class Downsizer
			constructor: (options)->
				defaults = {
					deferred: null
					# deferredImgReady: null	# resolve with Img onload
					targetWidth: CFG.camera.targetWidth
					quality: CFG.camera.quality
				}
				self = this

				this.cfg = _.defaults(options||{}, defaults)

				this._canvasElement = document.createElement('canvas')
				this._imageElement = new Image()
				this._imageElement.onload = ()->
					img = this
					if false && "*** resize/DRAW CANVAS in onload"
						targetWidth = self.cfg.targetWidth
						# check EXIF.orientation, auto-rotate 
						if (img.width > targetWidth) 
							resizeH = img.height/img.width * targetWidth
							resizeW = targetWidth
						filesize = [img.src.length]	 
						console.log  "*** downsize canvas, IMG.onload() orig size=" + JSON.stringify [img.width, img.height] + ", downsize=" + JSON.stringify [resizeW, resizeH] 
						ctx = self._canvasElement.getContext("2d");
						ctx.drawImage(img, 0, 0, resizeW, resizeH)
						resizedDataURL = self._canvasElement.toDataURL("image/jpeg")
						filesize.push resizedDataURL.length
						console.log "*** downsize result, filesize=" + JSON.stringify filesize
						self.cfg.deferred.resolve(resizedDataURL)
						return

					self._downsize(img, self.cfg.deferred)
					# self._handleImgOnLoad(self, this)

				
			_downsize: (img, dfd, targetWidth)=>
				# img.src is dataURL
				if (img.width <! targetWidth) 
					dfd.resolve(img.src)
					return dfd.promise


				resizeH = img.height/img.width * targetWidth
				resizeW = targetWidth

				# console.log "downsizer._downsize"
				_.defer (self)->
					console.log "begin downsizing on canvas"
					targetWidth = targetWidth || self.cfg.targetWidth
					img = img || self._imageElement

					# canvas = document.createElement('canvas');
					self._canvasElement.width = resizeW;
					self._canvasElement.height = resizeH;
					ctx = self._canvasElement.getContext("2d");
					console.log  "*** downsize canvas, orig size=" + JSON.stringify [img.width, img.height] + ", downsize=" + JSON.stringify [resizeW, resizeH] 
					console.log "downsize canvas drawImage, src="+img.src[0..80]
					ctx.drawImage(img, 0, 0, resetW, resizeH)
					# get downsized img as dataURL
					dataURL = self._canvasElement.toDataURL("image/jpeg")
					clearTimeout(timeout)	
					console.log "about to resolve, new dataURL=" + dataURL[0..60]
					dfd.resolve(dataURL)
				, this
				timeout = _.delay (dfd)->
					dfd.reject("timeout")
				, CFG.jsTimeout, dfd
				return dfd.promise

			_handleImgOnLoad : (self, img)->
				# console.log "downsizer img.onload"
				self._downsize(img, self.cfg.deferred)
				return 

			downsizeImage : (src, dfd, targetWidth)=>
				throw "Error: downsizeImage() Expecting deferred" if !dfd

				if false && "skip downsize"
					console.log "SKIPPING DOWNSIZE, using dataURL of orig, src=" + src[0..60] 
					dfd.resolve(src)
					return dfd.promise

				this.cfg.deferred = dfd
				this.cfg.targetWidth = targetWidth if targetWidth?	
				this._imageElement.src = src
				promise = this.cfg.deferred.promise.finally ()=>
					this.cfg.deferred = null
				return this.cfg.deferred.promise.finally ()->

		# Downsizer static methods			
		Downsizer.one = ()->
			Downsizer._instances = [] if !Downsizer._instances
			found = _.find Downsizer._instances, (d)->
					return d.cfg.deferred == null
			if !found
				found = new Downsizer()
				Downsizer._instances.push found
			return found

		
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


		_processImageFile = (file, dfd)->
			reader = new FileReader()
			reader.onloadend = (ev)-> 
				# notify.alert "TEST!!! READER #2 readAsDataURL, ev.target.result"+ev.target.result[0..60], "danger", 3000
				dataURL = ev.target.result
				console.log "_processImageFile onloadend file.name= " + file.name  + ", dataurl="+dataURL[0..60]
				_processImageDataURL(dataURL, file, dfd)
			# starts here	...
			reader.readAsDataURL(file);
			# setTimeout( ()->dfd.reject("timeout"), 5000)
			return dfd.promise

		_processImageDataURL = (dataURL, file, dfdFINAL)->
			dfdExif = $q.defer()
			dfdDownsize = $q.defer()
			downsizer = Downsizer.one()
			promises = {
				exif: _parseExif dataURL , dfdExif
				downsized: downsizer.downsizeImage(dataURL, dfdDownsize)
			}
			$q.all(promises).then (o)->
				check = _.filter o, (v)->return v=='timeout'
				if check?.length
					notify.alert "jsTimeout for " + JSON.stringify check, "warning", 10000
				src = '/'+file.name
				photo = _getPhotoObj(src, o.downsized, o.exif || {} )
				console.log "FINAL resolve "+ photo.id
				dfdFINAL.resolve(photo) # goes to getPicture(photo)
				return
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


		#
		# this is the actual service for BROWSER
		#	
		_pluploadHandlers = {
			# @param up plupload.Uploader
			# @param files array of PluploadFile
			FilesAdded: (up, files)->
				# confirm same as below
				$target = angular.element(up.settings.browse_button[0])
				$target.removeClass('active').find('i').addClass('fa-spin')
				# WARNING not enough CPU cycles to show spining icons

				scope = $target.scope()
				done = _deferred[$target.attr('upload-id')] 
				if !done
					###
					# WARNING: CSS modified in application.less for mobile/touch browsers
					#   this is a hack because mobile safari renders the .moxie-shim ABOVE the btn
					# 	so FilesAdded is called BEFORE challenge_getPhoto()
					# 	CSS changes .moxie-shim at z-index: 2 to force same behavior for mobile chrome
					# 	THEN, call challenge_getPhoto() manually here
					###
					# console.log "ERROR: cannot find deferred to resolve" 
					manualNgClick = $target.attr('ng-click')
					fakeEvent = {currentTarget: $target[0]}
					if manualNgClick=="challenge_getPhoto($event)"
						scope.challenge_getPhoto(fakeEvent)
					else if manualNgClick=="moment_getPhoto(card.id, $event)"
						scope.moment_getPhoto(scope.card.id, fakeEvent)
					else
						console.error "ERROR: manualNgClick not set for this controller, ng-click="+ manualNgClick
						throw "ERROR: manualNgClick not set for this controller, ng-click="+ manualNgClick

					done = _deferred[$target.attr('upload-id')] 
					# console.log "done, dfd.id="+done.id

				multi_select_promises = [] # one promise for each file selected
				_.each files, (plFile)->
						console.log "plupload file="+ plFile.name + ", lastModifiedDate=" + plFile.lastModifiedDate 
						# steroids.logger.log "plupload file="+ plFile.name + ", lastModifiedDate=" + pFile.lastModifiedDate 

						# PluploadFile attributes
						# plFile: ["id", "name", "type", "size", "origSize", "loaded", "percent", "status", "lastModifiedDate", "getNative", "getSource", "destroy"]
						# plFile.getNative(): ["webkitRelativePath", "lastModifiedDate", "name", "type", "size"]
						# plFile.getSource(): ["connectRuntime", "getRuntime", "disconnectRuntime", "uid", "ruid", "size", "type", "slice", "getSource", "detach", "isDetached", "destroy", "name", "lastModifiedDate"]

						file = plFile.getNative()
						dfd = $q.defer()
						# name = plFile.name
						# modified = plFile.lastModifiedDate
						
						multi_select_promises.push dfd.promise
						_.delay ()-> 		## allow UI to update 
								_processImageFile(file, dfd)
						, 200 
						return
						
				
				done.resolve(multi_select_promises)
				$q.all(multi_select_promises).then ()->
					console.log "html5CameraService: $q.all(multi_select_promises), all imgs downsized"
					delete _deferred[done.id]
				return
		}
		_otherHandlers = {
			propagateClick : (e)->
				if (e.target.tagName == 'INPUT' && 
									e.target.getAttribute('type') == 'file' && 
									e.target.parentNode.className.indexOf('moxie-shim') > -1)
					angular.element(_plupload.uploader.settings.browse_button[0])?.addClass('active')
				return true
		}

		self = {
			type: "html5CameraService"
			# use HTML5 File api in browser
			prepare: (browse_button="html5-get-file", options={})->
				options['browse_button'] = browse_button
				up = _plupload.uploader

				setTimeout ()->
						isNotLoaded = !up.runtime
						if isNotLoaded
							up.setOption(options) 
							_plupload.bind( _pluploadHandlers )
							up.init() 
							# WARNING: this event handler is not unset on destroy
							# check for zombie buttons	
							$delegate = angular.element(document.getElementById('view'))
							$delegate?.off('click',_otherHandlers.propagateClick).on('click', _otherHandlers.propagateClick)
							console.log "*** Plupload init()"
						else 
							up.setOption(options) 
							# we have to "reload" browse_button every time we reload the card
							console.log "*** Plupload ready"
					,0

			getFilesystem : ()->
				return _fsRoot
			setDeferred: (dfd)->
				# dfd.resolved by plupload FilesAdded handler
				# track dfd by dfd.id
				_deferred[dfd.id] = dfd
				return dfd.promise
					
		} # end self

		window.cameraRoll = self


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