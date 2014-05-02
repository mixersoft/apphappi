return if !angular? 

angular.module(
	'appHappi'
).factory('snappiAssetsPickerService', [
	'$q'
	'notifyService'
	'appConfig'
	($q, notify, CFG)->
		


		# private object for downsizing via canvas
		_deferred = null
		_deferredCounter = 0

		# see: http://stackoverflow.com/questions/4998908/convert-data-uri-to-file-then-append-to-formdata
		_dataURItoBlob = (dataURI)-> 
			###
			function dataURItoBlob(dataURI) {
			    var byteString = atob(dataURI.split(',')[1]);
			    var ab = new ArrayBuffer(byteString.length);
			    var ia = new Uint8Array(ab);
			    for (var i = 0; i < byteString.length; i++) {
			        ia[i] = byteString.charCodeAt(i);
			    }
			    return new Blob([ab], { type: 'image/jpeg' });
			}###

			data = dataURI.split(',')[1]
			
			try 
				data = data.replace(/\r\n/g,'')
				byteString = atob(data)           # crashes here!!!
				steroids.logger.log "**** SUCCESS, base64 decoded! byteString.length=" + byteString.length +  ", data=" + data[0..100]
			catch error
				steroids.logger.log "**** EXCEPTION: atob() doesn't work properly in Safari/iOS ****"	
				steroids.logger.log "_dataURItoBlob(): dataURI.length=" + data.length
				# steroids.logger.log data
				throw error

			ab = new ArrayBuffer(byteString.length)
			ia = new Uint8Array(ab)
			ia[i] = byteString.charCodeAt(i) for i in [0...byteString.length]
			return new Blob([ia], { type: 'image/jpeg' })

		writeDataUrl2File = (directoryEntry, filename, dataURI, onSuccess)->
			# steroids.logger.log "Success: requestFileSystem=" + directoryEntry.fullPath

			dataURI = "data:image/jpeg;base64," + dataURI if dataURI.indexOf("data:") != 0

			blob = _dataURItoBlob(dataURI)

			directoryEntry.getFile filename
				, {create:true, exclusive:false}
				, (fileEntry)->
					# steroids.logger.log "5. writeDataUrl2File() fileEntry=" + fileEntry.toURL()
					fileEntry.createWriter (fileWriter)->
						fileWriter.onwriteend = (e)->
							# steroids.logger.log "write complete for filename=" + fileEntry.name
							return if fileWriter.isError
							# steroids.logger.log "fileEntry: fullpath=" + fileEntry.fullPath
							# steroids.logger.log "fileEntry: toURL()=" + fileEntry.toURL()
							onSuccess(fileEntry) if onSuccess
							return

						fileWriter.onerror = (e)->
							steroids.logger.log "write failed for filename="+fileEntry.name
							fileWriter.isError = true
							return throw "ERROR: writeDataUrl2File()"
							

						return fileWriter.write(blob);

			return

		
		# get formatted photo = {} for resolve		
		_getPhotoObj = (uri, dataURL, exif={}, alAssetId=null)->
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

			id = alAssetId || __getPhotoHash( exif, dataURL)
			if id && !alAssetId
				isoDate = exif["DateTimeOriginal"]
				isoDate = isoDate.replace(':','-').replace(':','-').replace(' ','T')
				dateTaken = new Date(isoDate).toJSON()
			else if !id
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
			type : "snappiAssetsPickerService"
			# Camera options
			cameraOptions :
				fromPhotoLibrary:
					quality: CFG.camera.quality
					destinationType: navigator.camera.DestinationType.FILE_URI
					# destinationType: navigator.camera.DestinationType.DATA_URL
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
				options.selectedAssets = self.SAVE_PREVIOUSLY_SELECTED || []

				try
					steroids.logger.log "Using snappi-assets-picker"
					if _deferred?
						_deferred.reject(  'Camera getPicture cancelled, _deferred.id='+_deferred.id  )
					_deferred = $q.defer()
					_deferred.id = _deferredCounter++
					

					window.plugin?.snappi?.assetspicker?.getPicture (dataArray)->
							self.SAVE_PREVIOUSLY_SELECTED = options.selectedAssets.concat dataArray
							photos = []
							promises = []
							steroids.logger.log "dataArray ids=" + _.pluck dataArray, 'id'
							# steroids.logger.log dataArray
							_.each dataArray, (o)->
								# expecting
								# o.id, data, exif
								# steroids.logger.log ">>> o.keys=" + _.keys o
								

								# get UUID from o.id
								# o.id = "assets-library://asset/asset.JPG?id=CA17E38E-089A-4287-82C0-12EE960DBB4F&ext=JPG"
								uuid = o.id.match(/id=(.*)&ext/)?.pop()
								o.filename = uuid if uuid
								# steroids.logger.log ">>> ALAssetsId " + JSON.stringify(o)[0..200]
								# 

								# if options.destinationType == navigator.camera.DestinationType.DATA_URL
								# 	retval = self.dataURLPipeline(o.id, o.data)
								# else 
								promises.push self.fileURIPipeline(o, options.destinationType).then (retval)->
										### expecting retval = {
											filename: o.filename
											originalSrc: o.filename
											previewSrc: '/' + o.fileEntry['preview'].name
										}
										###
										retval.exif = o.exif || null
										photo = _getPhotoObj(retval.originalSrc, retval.previewSrc, retval.exif , o.filename || o.id)
										photos.push photo
										if options.success
											options.success(photo) 
										steroids.logger.log ">>> ONE photo = " + photo.src	
										return photo
									, (error)->
										steroids.logger.log "CATCH HERE *******************"
										return
								return

							$q.all(promises).then (all)->
								steroids.logger.log "DONE: ALL photos, count=" + _.values(all).length
								steroids.logger.log "photos=" + JSON.stringify _.pluck(all, "src")
								_deferred.resolve photos

						, self.cameraError
						, options


					
					return _deferred.promise.finally ()->_deferred = null
				catch error
					JSON.stringify error
	

			# dataURL > resolve with originalSrc as FileURI and previewSrc as DataURL
			dataURLPipeline : (id, dataURL)->
				# dfd = $q.defer() 
				dataURL = "data:image/jpeg;base64," + dataURL if dataURL && dataURL.indexOf("data:image/jpeg;base64,") != 0
				# steroids.logger.log dataURL[0..100]
				retval = {
					filename: id
					originalSrc: null
					previewSrc: dataURL
				}
				steroids.logger.log "dataURLPipeline COMPLETE, retval=" + JSON.stringify(retval)[0..200]
				# dfd.resolve(retval)
				# return dfd.promise
				return retval
					

			# use promises to pipeline image handling
			# fileURI > FileEntry > FileEntry.moveTo  > FileEntry.copyTo > steroids.File.resizeImage
			# params item {id: data: exif:}, see onSuccess in https://github.com/mixersoft/snappi-assets-picker
			# returns a promise
			fileURIPipeline : (item, destinationType)->
				filename = item.filename || item.id
				fileURI = item.data # not a real fileURI
				exif = item.exif

				### pattern: 
				(o)->
					dfd = $q.defer()
					asyncFn (retval)->
						dfd.resolve {
							retval: reval
						}
					return dfd.promise
				###
				steroids.logger.log "imagePipeline !!!"
				promise = _initFileStore()
				return promise.catch (o)->
					steroids.logger.log {
						msg: "**** _initFileStore().REJECTED! ******"
						root: o.directoryEntry.root.fullPath 
						preview: o.directoryEntry.preview.fullPath 
					}

				# get DataURL from FileURI (ALAssetsId), using getById(0)	
				.then (o)->
					o = { 'directoryEntry': o.directoryEntry }
					steroids.logger.log {
						msg: "**** _initFileStore() ******"
						root: o.directoryEntry.root.fullPath 
						preview: o.directoryEntry.preview.fullPath 
					}
					if destinationType == navigator.camera.DestinationType.DATA_URL
						_.extend o, {
							dataURL: 
								'preview': "data:image/jpeg;base64," + item.data
						}
						return o

					# destinationType == FILE_URI
					dfd = $q.defer()
					options = options = {
	                    quality: 75
	                    destinationType: Camera.DestinationType.DATA_URL
	                    encodingType: Camera.EncodingType.JPEG
	                    targetWidth: 640
	                };
					window.plugin?.snappi?.assetspicker?.getById item.id
						, (data)->
							steroids.logger.log "*** getById(), data="+data.data[0..100]
							_.extend o, {
								dataURL: 
									'preview': "data:image/jpeg;base64," + data.data
							}
							# steroids.logger.log "*** getById(), keys=" + _.keys o
							return dfd.resolve o
						, (message)->
							dfd.reject("Error assetspicker.getbyId() to dataURL")
						, options
					return dfd.promise

				# new FileEntry in o.root, o.preview
				.then (o)->
					steroids.logger.log "4a. filename=" + filename	
					# steroids.logger.log "o.directoryEntry" + JSON.stringify( o )[0..300]
					try 
						dfd = $q.defer()
						o['filename'] = filename
						steroids.logger.log "4b. previewDir=" + o.directoryEntry['preview'].name
						writeDataUrl2File o.directoryEntry['preview']
							, filename + ".preview.JPG"
							, o.dataURL['preview']
							, (fileEntry)->
								dfd.resolve _.extend o, {
									fileEntry: 
										'preview': fileEntry
								}
					catch error
						steroids.logger.log "*****  EXCEPTION : reject & try dataURLPipeline"
						steroids.logger.log error
						dfd.reject(o) # goto .catch() and try dataUrlPipeline

					return dfd.promise		
				.then (o)->
					return o if "skip"	# skip this step

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
							steroids.logger.log "5. fileEntry=" + fileEntry.name
							dfd.resolve _.extend o, {
								fileEntry: 
									'chosen': fileEntry
							}
						, ()->
							self.fileError
							throw "Error:  resolveLocalFileSystemURI fileURI"
					return dfd.promise
				.then (o)->
					return o if "skip" 	# skip this step

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
					return o if "skip" 	# skip this step

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
					if "do not resize"
						retval = {
							# originalSrc: '/' + o.fileEntry['original'].name
							filename: o.filename
							originalSrc: '/'+  (o.fileEntry['root']?.name || o.filename + '.JPG')
							previewSrc: '/' + o.fileEntry['preview'].name
						}
						steroids.logger.log "imagePipeline COMPLETE, retval=" + JSON.stringify retval
						return retval




					steroids.logger.log "8. resize"

					o.fileEntry['copy'].name = o.fileEntry['preview'].name

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
									# originalSrc: '/' + o.fileEntry['original'].name
									filename: o.filename
									originalSrc: o.filename
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
					if (o?.dataURL?.preview)
						dfd = $q.defer()
						retval = self.dataURLPipeline(o['filename'], o.dataURL['preview'])
						steroids.logger.log "dataURLPipeline COMPLETE, retval=" + JSON.stringify retval[0..200]
						dfd.resolve(retval)
						return dfd.promise

					steroids.log.logger "imagePipeline REJECTED!"
					steroids.logger.log o
					throw "imagePipeline REJECTED!"
						
		}

		_initFileStore()
		
		return self
]   
)