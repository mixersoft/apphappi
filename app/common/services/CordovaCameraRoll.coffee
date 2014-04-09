return if !angular? 

angular.module(
	'appHappi'
).factory('cordovaCameraService', [
	'$q'
	'notifyService'
	'appConfig'
	($q, notify, CFG)->
		


		# private object for downsizing via canvas
		_deferred = null
		_deferredCounter = 0

		
		# get formatted photo = {} for resolve		
		_getPhotoObj = (uri, dataURL, exif={})->
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
				src: dataURL || uri 							# resized dataURL or src
				fileURI: if _.isString(uri) then uri else null 	# original src
				rating: 0		# required for orderBy:-rating to work				
			}

		# use IMG.src string directly
		_processImageSrc = (src, dfdFINAL)->
			dfdDownsize = $q.defer()
			promises = {
				# exif: _parseExif dataURL , dfdExif
				downsized: _resample src, dfdDownsize
			}
			$q.all(promises).then (o)->
				check = _.filter o, (v)->return v=='timeout'
				if check?.length
					notify.alert "jsTimeout for " + JSON.stringify check, "warning", 10000
				photo = _getPhotoObj(src, o.downsized, o.exif)

				notify.alert "FINAL resolve "+ JSON.stringify(photo), "success", 30000
				
				dfdFINAL.resolve(photo) # goes to getPicture(photo)
			return dfdFINAL.promise

		_filepathTEST = null

		# use fileEntry > file > readAsDataURL()
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
				downsized: _resample dataURL, dfdDownsize
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

		_resample = (img, dfd)->
			src = if img.src? then img.src else img  
			console.log "*** resize using Resample.js ******* IMG.src=" + src[0..60]
			done = (dataURL)->
				console.log "resampled data=" + JSON.stringify {
					size: dataURL.length
					data: dataURL[0..60]
				}
				dfd.resolve(dataURL)
				return
			Resample.one()?.resample img
				, 	CFG.camera.targetWidth
				, 	null		# targetHeight
				, 	done
			return dfd.promise
		
		_parseExif = (dataURL, dfd)->
			dfd.resolve {
				"WARNING": "skipping Exif parsing on iOS, it doesn't work"
			}
			return dfd.promise

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
		# ### for DEVICE ###
		#

		# private
		_fileStoreReady = null

		# usage: _initFileStore().then (o)
		_initFileStore = ()->
			return _fileStoreReady if _fileStoreReady

			dfd0 = $q.defer()
			_fileStoreReady = dfd0.promise
			### pattern: 
			(o)->
				dfd = $q.defer()
				asyncFn (retval)->
					dfd.resolve {
						retval: reval
					}
				return dfd.promise
			###
			steroids.on "ready", ()->
				dfd = $q.defer()
				if _.isFunction(window.requestFileSystem)
					window.requestFileSystem  LocalFileSystem.PERSISTENT
						, 50000*1024
						, (fs)-> 
							steroids.logger.log "Success: requestFileSystem PERSISTENT=" + fs.root.fullPath
							dfd.resolve( {
									directoryEntry:
										'root': fs.root
									})
						, (ev)->
							steroids.logger.log "Error: requestFileSystem failed. "+ev.target.error.code
							dfd.resolve( {
									directoryEntry:
										'root': null
									})
				else dfd.resolve({
							directoryEntry:
								'root': null
							})
				dfd.promise.then (o)->
					# steroids.logger.log "0. got o.root"
					return o if o.directoryEntry['root']?

					steroids.logger.log "1. failed o.root, trying userFilesPath"
					# else get directoryEntry for steroids.app.userFilesPath	
					dfd = $q.defer()
					window.resolveLocalFileSystemURI steroids.app.userFilesPath
						, (directoryEntry)->
							dfd.resolve {
								directoryEntry:
									root: directoryEntry
							}
						, ()->
							self.fileError
							throw "Error:  resolveLocalFileSystemURI steroids.app.userFilesPath"
					return dfd.promise
				.then (o)->
					# get preview directoryEntry
					dfd = $q.defer()
					# # use directoryEntry.getDirectory() to create preview directoryEntry
					o.directoryEntry['preview'] = o.directoryEntry['root']  # placeholder, resolve immediately
					dfd.resolve(o)
					return dfd.promise	
				.then (o)->
					# final resolve
					dfd0.resolve o 
					return 
					# o = {
					# 	root: directoryEntry
					# 	preview: directoryEntry
					# }
				return
					
			return dfd0.promise



		_fileErrorComment = ""

		self = {
			type : "cordovaCameraService"
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
					popoverOptions: new CameraPopoverOptions(
							460,
							260,
							100,
							100, 
							Camera.PopoverArrowDirection.ARROW_UP
						)
					# iPad camera roll popover position
						# width: 768
						# height: 
						# arrowDir: Camera.PopoverArrowDirection.ARROW_UP
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
				steroids.logger.log  "Cordova error code: " + error.code + " fileError. " + _fileErrorComment
				if _deferred?
					_deferred.reject( "Cordova error code: " + error.code + " fileError. " + _fileErrorComment )


			#
			# this is the main API entry point
			#
			getPicture: (options, $event)->
				try
					steroids.logger.log "Using SAVE PICTURE!!!"
					if _deferred?
						_deferred.reject(  'Camera getPicture cancelled, _deferred.id='+_deferred.id  )
					_deferred = $q.defer()
					_deferred.id = _deferredCounter++

					navigator.camera.getPicture (imageURI)->
							steroids.logger.log "imageURI=" + imageURI
							self.imagePipeline(imageURI).then (o)->
								photo = _getPhotoObj(o.originalSrc, o.previewSrc)
								# steroids.logger.log "resize Success!!! FINAL resolve "+ JSON.stringify(photo)
								_deferred.resolve(photo) # goes to getPicture(photo)
						, self.cameraError
						, options
					
					return _deferred.promise.finally ()->_deferred = null
				catch error
					JSON.stringify error

			# use promises to pipeline image handling
			# fileURI > FileEntry > FileEntry.moveTo  > FileEntry.copyTo > steroids.File.resizeImage
			imagePipeline : (fileURI)->
				try 
					### pattern: 
					(o)->
						dfd = $q.defer()
						asyncFn (retval)->
							dfd.resolve {
								retval: reval
							}
						return dfd.promise
					###
					# steroids.logger.log "imagePipeline !!!"
					promise = _initFileStore()
					promise.catch (o)->
						steroids.logger.log {
							msg: "**** _initFileStore().REJECTED! ******"
							root: o.directoryEntry.root.fullPath 
							preview: o.directoryEntry.preview.fullPath 
						}
					.then (o)->
						# steroids.logger.log "5. fileEntry"
						# steroids.logger.log {
						# 	msg: "**** _initFileStore().resolved ******"
						# 	fileURI: fileURI
						# 	root: o.directoryEntry.root.fullPath 
						# 	preview: o.directoryEntry.preview.fullPath 
						# }


						dfd = $q.defer()
						window.resolveLocalFileSystemURI fileURI
							, (fileEntry)->
								# steroids.logger.log "5. fileEntry=" + fileEntry.fullPath
								dfd.resolve _.extend o, {
									fileEntry: 
										'chosen': fileEntry
								}
							, ()->
								self.fileError
								throw "Error:  resolveLocalFileSystemURI fileURI"
						return dfd.promise
					.then (o)->
						# steroids.logger.log "6. moveTo"

						filename = new Date().getTime()  
						# moveTo
						dfd = $q.defer()
						o.fileEntry['chosen'].moveTo o.directoryEntry['root']
							, filename + '.jpg'
							, (fileEntry)->
								o.fileEntry['original'] = fileEntry
								o['filename'] = filename
								dfd.resolve o				
							, ()->
								self.fileError
								throw "Error:  o.fileEntry.chosen.moveTo"
						return dfd.promise
					.then (o)->
						# steroids.logger.log "7. copyTo"

						dfd = $q.defer()
						o.fileEntry['original'].copyTo o.directoryEntry['root']
							, o['filename']+'.preview.jpg'
							, (fileEntry)->
								o.fileEntry['copy'] = fileEntry
								dfd.resolve o				
							, ()->
								self.fileError
								throw "Error:  o.fileEntry.chosen.copyTo"
						return dfd.promise	
					.then (o)->
						# steroids.logger.log "8. resize"

						dfd = $q.defer()
						resizer = new steroids.File( {
							path: o.fileEntry['copy'].name
							relativeTo: steroids.app.userFilesPath 	# should use o.preview
						})
						resizer.resizeImage( 
							{
								format: 
									type: "jpg"
									compression: CFG.camera.quality
								constraint: 
									dimension: "width"	
									# use 2*320=640p since we are saving to FS
									length: CFG.camera.targetWidth * 2  	
							},
							{
								onSuccess: ()->
									retval = {
										originalSrc: '/' + o.fileEntry['original'].name
										previewSrc: '/' + o.fileEntry['copy'].name
									}
									steroids.logger.log "imagePipeline COMPLETE, retval=" + JSON.stringify retval
									dfd.resolve(retval)
									
								onFailure: ()->
									steroids.logger.log "resize FAILURE!!!"
									throw "Error:  resizer.resizeImage"

							}
						)
						return dfd.promise
					.catch (o)->
						steroids.log.logger "imagePipeline REJECTED!"
						
				catch error
					JSON.stringify error	


		}

		_initFileStore()
		
		return self
]   
)