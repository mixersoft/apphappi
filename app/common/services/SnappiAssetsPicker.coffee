return if !angular? 

angular.module(
	'appHappi'
).factory('snappiAssetsPickerService', [
	'$q'
	'notifyService'
	'appConfig'
	($q, notify, CFG)->
		
		_defaultCameraOptions = {
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
		}

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

		_writeDataUrl2File = (directoryEntry, filename, dataURI, onSuccess)->
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
		_getPhotoObj = (o)->   #(uri, dataURL, exif={}, alAssetId=null)->
			# get hash from EXIF to detect duplicate photo
			# hash photo data to detect duplicates
			# __getPhotoHash = (exif, dataURL)->
			# 	if !(exif?['DateTimeOriginal'])
			# 		exifKeys = _.keys(exif)
			# 		notify.alert "WARNING: EXIF count="+exifKeys.length+", keys="+exifKeys.join(", "), "danger", 30000	
			# 		return false 
			# 	hash = []
			# 	exifKeys = _.keys(exif)
			# 	# notify.alert "EXIF count="+exifKeys.length+", keys="+exifKeys.join(", "), "info", 30000
			# 	compact = exif['DateTimeOriginal']?.replace(/[\:]/g,'').replace(' ','-')
			# 	hash.push(compact)
			# 	# notify.alert "photoHash 1="+hash.join('-'), "danger", 30000
			# 	if dataURL?
			# 		hash.push dataURL.slice(-20)
			# 		# notify.alert "photoHash 2="+hash.join('-'), "danger", 30000
			# 	else 
			# 		hash.push exif['Model']
			# 		hash.push exif['Make']
			# 		hash.push exif['ExposureTime']
			# 		hash.push exif['FNumber']
			# 		hash.push exif['ISOSpeedRatings']
			# 	return hash.join('-')

			now = new Date()
			dateTaken = o.exif?.DateTimeOriginal || now.toJSON()

			id = o.id || now.getTime() 
			# notify.alert "_getPhotoObj() photo.id=="+id, "success", 2000
			return {
				id: o.id
				dateTaken: dateTaken 
				orig_ext: o.orig_ext
				label: o['label']
				Exif: o.exif || {}
				src: o.previewSrc || o.originalSrc 							# resized dataURL or src
				fileURI: if _.isString(o.originalSrc) then o.originalSrc else null 	# original src
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
				photo = _getPhotoObj({originalSrc: src, previewSrc: o.downsized, exif: o.exif})

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
				photo = _getPhotoObj({originalSrc: src, previewSrc: o.downsized, exif: o.exif}) #  _getPhotoObj(src, o.downsized, o.exif)

				notify.alert "FINAL resolve "+ JSON.stringify(photo), "success", 30000
				
				dfdFINAL.resolve(photo) # goes to getPicture(photo)
			return dfdFINAL.promise

		_resample = (img, dfd, targetWidth, mimeType)->
			src = if img.src? then img.src else img  
			dfd = $q.defer() if !dfd
			steroids.logger.log "*** resize using Resample.js ******* IMG.src=" + src[0..60]
			done = (dataURL)->
				steroids.logger.log "resampled data=" + JSON.stringify {
					size: dataURL.length
					data: dataURL[0..60]
				}
				dfd.resolve(dataURL)
				return
			Resample.one()?.resample img
				, 	targetWidth || CFG.camera.targetWidth
				, 	null		# targetHeight
				, 	done
				, 	mimeType
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

		_initOverlay = (options)->
			# options[0] = { src:, name: }
			dfd = $q.defer()
			#load as base64
			icon_check = {
				name: Camera.Overlay.PREVIOUS_SELECTED
				src: '/icons/fa-check_32.png'
			}
			options = [icon_check]	# testing
			# steroids.logger.log "_initOverlay, options=" + JSON.stringify options
			promises = []
			_.each options, (o)->
				if o.src.indexOf('data:image/') != 0
					# load src and convert to base64 dataURL
					# _resample = (img, dfd, targetWidth, mimeType)
					isRetina = true
					iconSize = if isRetina then 64 else 32
					promise = _resample( o.src, null, iconSize, 'image/png' ).then (dataURL)->
							o.src = dataURL.replace(/^data:image\/(png|jpg);base64,/, "")
							return o
						.then (overlay)->
							dfd = $q.defer()
							steroids.logger.log "setOverlay, name="+overlay.name+", src="+overlay.src[0..100]
							try 
								window.plugin.snappi.assetspicker.setOverlay overlay.name
									, overlay.src
									, ()->
										# steroids.logger.log "setOverlay SUCCESS"
										dfd.resolve overlay
									, (error)->
										steroids.logger.log "setOverlay ERROR"
										steroids.logger.log error
										dfd.reject error
								steroids.logger.log "AFTER setOverlay()"
							catch error
								steroids.logger.log error			
							
							return dfd.promise
					promises.push promise



			$q.all(promises).then (retval)->
				# steroids.logger.log "all promises resolved, retval=" + JSON.stringify retval
				dfd.resolve(options)
			return dfd.promise

		_pipelinePromises = {
			# all methods to be used with promise API, e.g. then method()
			getLocalFilesystem : (o)->
				### expecting o = 
						directoryEntry:
							root: File.DirectoryEntry
							preview: File.DirectoryEntry
				###
				return { 'directoryEntry': o.directoryEntry }  # _.pluck o "directoryEntry"


			getPreviewAsDataURL : (o, options, extension='JPG', label='preview')->
				### this method uses snappi.assetspicker.getById() to resize dataURL
				call: then (o)->
						return getPreviewAsDataURL(o, uuid, extension, options)

				expecting o = 
					uuid: 
					orig_ext:
					data: 
					directoryEntry:

				return {
					directoryEntry
					dataURL: 
						'[label]': DataURL
				}
				###
				dfd = $q.defer()

				# steroids.logger.log {
				# 	msg: "**** _initFileStore() ******"
				# 	root: o.directoryEntry.root.fullPath 
				# 	preview: o.directoryEntry.preview.fullPath 
				# }
				options = _.defaults options, {
					quality: 75
					targetWidth: 640
				}
				
				if extension == 'PNG' 
					options.encodingType = Camera.EncodingType.PNG 
					mimeType = 'image/png'
				else 
					options.encodingType = Camera.EncodingType.JPEG
					mimeType = 'image/jpeg'


				# noop, just format retval and return
				if options.destinationType == navigator.camera.DestinationType.DATA_URL && o.data
					o.dataURL = o.dataURL || {}
					o.dataURL[label] = "data:" + mimeType + ";base64," + o.data
					steroids.logger.log "getPreviewAsDataURL(): already dataurl=" + o.dataURL[label][0..100]
					dfd.resolve o
					return dfd.promise

				# destinationType == FILE_URI
				
				options.destinationType = Camera.DestinationType.DATA_URL  # force!
				window.plugin?.snappi?.assetspicker?.getById o.uuid
					, o.orig_ext
					, (data)->
						steroids.logger.log "getPreviewAsDataURL(): getById() for DATA_URL, data="+o.data[0..100]
						o.dataURL = o.dataURL || {}
						o.dataURL[label] = "data:" + mimeType + ";base64," + data.data
						return dfd.resolve o
					, (message)->
						dfd.reject("Error assetspicker.getbyId() to dataURL")
					, options
				return dfd.promise	

			writeDataURL2File : (o, version='preview')->
				### 
				call: then (o)->
						return writeDataURL2File(o, filename)

				expecting o = 
					uuid: 
					directoryEntry:
						root: File.DirectoryEntry
						preview: File.DirectoryEntry
					dataURL:
						'[version]':

				return {
					fileEntry:
						'preview': File.FileEntry
				}
				###
				# TODO: complete preview==false
				steroids.logger.log "writeDataURL2File(): WARNING: write full-res dataURL to file not yet implemented!" if version != 'preview'
				steroids.logger.log "writeDataURL2File(): filename=" + o.uuid	

				folder = version
				if o.dataURL[folder].indexOf('data:image/jpeg')==0
					extension = 'JPG'
				else if o.dataURL[folder].indexOf('data:image/png')==0
					extension = 'PNG'
				else 
					steroids.logger.log "writeDataURL2File(): ERROR: unknown mimetype, dataurl=" + o.dataURL[folder][0...60]

				filename = o.uuid  + "." + version + "." + extension
				# steroids.logger.log "o.directoryEntry" + JSON.stringify( o )[0..300]
				try 
					dfd = $q.defer()
					steroids.logger.log "writeDataURL2File(): destination=" + o.directoryEntry[folder].name
					_writeDataUrl2File o.directoryEntry[folder]
						, filename
						, o.dataURL[folder]
						, (fileEntry)->
							o.fileEntry = o.fileEntry || {}
							o.fileEntry[folder] = fileEntry 	# o.fileEntry['preview']
							dfd.resolve o
				catch error
					steroids.logger.log "writeDataURL2File(): *****  EXCEPTION : reject & try dataURLPipeline"
					steroids.logger.log "writeDataURL2File(): directoryEntry not defined for version=" + folder if !o.directoryEntry?[folder]
					steroids.logger.log error
					dfd.reject(o) # goto .catch() and try dataUrlPipeline

				return dfd.promise	

			resolveLocalFileSystemURI : (o, fileURI, name='selected')->
				### 
				call: then (o)->
						return resolveLocalFileSystemURI(o, fileURI, 'chosen')

				expecting o = {}

				return {
					fileEntry:
						[name]: File.FileEntry
				}
				###
				steroids.logger.log "resolveLocalFileSystemURI(): fileURI="+fileURI[0..120]
				dfd = $q.defer()
				window.resolveLocalFileSystemURI fileURI
					, (fileEntry)->
						steroids.logger.log "resolveLocalFileSystemURI(): fileEntry=" + fileEntry.name
						o.fileEntry = o.fileEntry || {}
						o.fileEntry[name] = fileEntry 	# o.fileEntry['selected']
						dfd.resolve o
					, ()->
						steroids.logger.log "resolveLocalFileSystemURI(): CATCH: resolveLocalFileSystemURI="+fileURI
						# self.fileError
						throw "Error:  resolveLocalFileSystemURI fileURI"
				return dfd.promise

			fileEntryMoveTo	: (o, fileEntry, directoryEntry, filename, label='original')->
				### 
				call: then (o)->
						return fileEntryMoveTo(o, o.fileEntry['selected'], o.directoryEntry['root'], uuid, 'original')

				expecting o =
					uuid:
					orig_ext: 
					directoryEntry:
						root: File.DirectoryEntry
						preview: File.DirectoryEntry
					fileEntry: {}

				return {
					filename: string, UUID
					fileEntry:
						'[label]': File.FileEntry
				}
				###
				# steroids.logger.log "fileEntryMoveTo()"
				dfd = $q.defer()
				
				if label == 'original'
					filename += "." + o.orig_ext 
				else filename +=  "." + label + "." + o.orig_ext

				source = fileEntry.fullPath
				dest = directoryEntry.fullPath + '/' + filename

				if source == dest 
					steroids.logger.log "fileEntryMoveTo SKIP"
					o.fileEntry[label] = fileEntry
					dfd.resolve o
					return dfd.promise
				
				steroids.logger.log "fileEntryMoveTo():  fileEntry=" + fileEntry.fullPath + ", target=dirEntry=" + dest

				fileEntry.moveTo directoryEntry
					, filename
					, (fileEntry)->
						steroids.logger.log "fileEntryMoveTo(): COMPLETE"
						o.fileEntry[label] = fileEntry
						dfd.resolve o				
					, (o)->
						# self.fileError
						steroids.logger.log "fileEntryMoveTo(): Error:  o.fileEntry.chosen.moveTo, dirEntry=" + directoryEntry.fullPath
						steroids.logger.log o
						throw "Error:  o.fileEntry.chosen.moveTo"
				return dfd.promise

			fileEntryCopyTo	: (o, fileEntry, directoryEntry, filename, label='copy')->
				### 
				call: then (o)->
						return fileEntryCopyTo(o, o.fileEntry['original'], o.directoryEntry['preview'], uuid, 'preview')

				expecting o = 
					uuid:
					orig_ext:
					directoryEntry:
						root: File.DirectoryEntry
						preview: File.DirectoryEntry
					fileEntry: {}

				return {
					filename: string
					fileEntry:
						'[label]': File.FileEntry
				}
				###
				filename = filename + "." + label + "." + o.orig_ext
				dfd = $q.defer()
				fileEntry.copyTo directoryEntry
					, filename
					, (fileEntry)->
						o.fileEntry[label] = fileEntry
						o['filename'] = filename
						dfd.resolve o				
					, ()->
						# self.fileError
						teroids.logger.log "Error:  o.fileEntry.chosen.copyTo"
						throw "Error:  o.fileEntry.chosen.copyTo"
				return dfd.promise

			canvasResize : (o, label, quality=0, width=640)->
				### 
				call: then (o)->
						return canvasResize(o, 'preview', 75, 640)

				expecting o = 
					uuid:
					orig_ext:
					directoryEntry: {}
					fileEntry: {
						'[label]'
					}


				return {
					filename: string, UUID
					fileEntry:
						'[label]': File.FileEntry
				}
				###
				steroids.logger.log "8. resize"

				dfd = $q.defer()
				resizer = new steroids.File( {
					path: o.fileEntry[label].name
					relativeTo: steroids.app.userFilesPath 	# should use o.directoryEntry[].fullPath(?)
				})
				resizer.resizeImage( 
					{
						format: 
							type: o.orig_ext || "JPG"
							compression: quality || CFG.camera.quality
						constraint: 
							dimension: "width"	
							# use 2*320=640p since we are saving to FS
							length: width || CFG.camera.targetWidth
					},
					{
						onSuccess: ()->
							# o.fileEntry[label] should be resized
							steroids.logger.log "canvasResized!"
							dfd.resolve(o)
							
						onFailure: ()->
							steroids.logger.log "resize FAILURE!!!"
							throw "Error:  resizer.resizeImage"

					}
				)
				return dfd.promise

			formatResult : (o)->
				### 
				call: then formatResult

				expecting o = 
					uuid:
					orig_ext: [JPG | PNG]
					directoryEntry:
						root: File.DirectoryEntry
						preview: File.DirectoryEntry
					fileEntry: 
						original: File.FileEntry
						preview: File.FileEntry

				###
				retval = {
					# originalSrc: '/' + o.fileEntry['original'].name
					id: o.uuid
					label: o['label']
					orig_ext: o.orig_ext
					extension: o.extension
					originalSrc: null
					previewSrc: null
				}
				retval.originalSrc = '/' + o.fileEntry['original'].name if o.fileEntry?['original']
				retval.previewSrc = '/' + o.fileEntry['preview'].name if o.fileEntry?['preview']
				return retval
		}
		# end _pipelinePromises		



		self = {
			type : "snappiAssetsPickerService"
			# Camera options
			cameraOptions : _defaultCameraOptions

			# Camera failure callback
			cameraError : (message)->
				# navigator.notification.alert 'Cordova says: ' + message, null, 'Capturing the photo failed!'
				if _deferred?
					_deferred.reject( message )
					 

			# File system failure callback
			fileError : (error)->
				# navigator.notification.alert "Cordova error code: " + error.code, null, "File system error!"
				steroids.logger.log  "Cordova error code: " + error.code + " fileError. " 
				if _deferred?
					_deferred.reject( "Cordova error code: " + error.code + " fileError. "  )


			#
			# this is the main API entry point
			#
			getPicture: (options, $event)->
				if !options.overlay?[Camera.Overlay.PREVIOUS_SELECTED]?.length
					self.SAVE_PREVIOUSLY_SELECTED = []
					options.overlay = {} if !options.overlay
					options.overlay[Camera.Overlay.PREVIOUS_SELECTED] = self.SAVE_PREVIOUSLY_SELECTED if !options.overlay[Camera.Overlay.PREVIOUS_SELECTED]
				else if options.overlay[Camera.Overlay.PREVIOUS_SELECTED] != self.SAVE_PREVIOUSLY_SELECTED 
					# steroids.logger.log "1 ##### options.overlay=" + JSON.stringify options.overlay
					self.SAVE_PREVIOUSLY_SELECTED = options.overlay[Camera.Overlay.PREVIOUS_SELECTED]
				# options.overlay[Camera.Overlay.PREVIOUS_SELECTED] = _.map syncService.get['photos']. (o)-> return o.id + '.' + o.orig_ext

				try
					steroids.logger.log "Using snappi-assets-picker"
					if _deferred?
						_deferred.reject(  'Camera getPicture cancelled, _deferred.id='+_deferred.id  )
					_deferred = $q.defer()
					_deferred.id = _deferredCounter++
					
					# steroids.logger.log "*** getPicture() options:" + JSON.stringify options
					window.plugin?.snappi?.assetspicker?.getPicture (dataArray)->

							# steroids.logger.log "SAVE_PREVIOUSLY_SELECTED=" + JSON.stringify self.SAVE_PREVIOUSLY_SELECTED
							photos = []
							promises = []
							# steroids.logger.log "dataArray uuids=" + _.pluck dataArray, 'uuid'
							# steroids.logger.log dataArray
							_.each dataArray, (o)->
								###
								expecting: o = {
									id : ALAssetsLibrary Id, assets-library://asset/asset.{ext}?id={uuid}&ext={ext}
									uuid : uuid,
									label: string
									orig_ext : orig_ext, [JPG | PNG] NOT same as options.encodingType
									data : String, File_URI: path or Data_URL:base64-encoded string
									exif : {
									    DateTimeOriginal : dateTimeOriginal,  format:  "yyyy-MM-dd HH:mm:ss"
									    PixelXDimension : pixelXDimension, 
									    PixelYDimension : pixelYDimension,
									    Orientation : orientation
									};
								### 
								# steroids.logger.log "&&&&&&&&&&&& item=" + JSON.stringify o
								selectedKey =  o.uuid + '.' + o.orig_ext  
								return if self.SAVE_PREVIOUSLY_SELECTED.indexOf(selectedKey) > -1

								self.SAVE_PREVIOUSLY_SELECTED.push selectedKey
								promises.push self.fileURIPipeline(o, options).then (retval)->
										### expecting retval = {
											id: o.uuid
											extension: o.orig_ext
											originalSrc: null
											previewSrc: null
										}
										###
										retval.exif = o.exif || null
										retval.label = o.label || null
										photo = _getPhotoObj(retval)
										photos.push photo
										steroids.logger.log ">>> ONE photo = " + photo.src[0..100]	
										return photo
									, (error)->
										steroids.logger.log "CATCH HERE *******************"
										steroids.logger.log error
										return
								return

							_deferred.resolve promises	

							# $q.all(promises).then (all)->
							# 	steroids.logger.log "DONE: ALL photos, count=" + _.values(all).length
							# 	steroids.logger.log "photos=" + JSON.stringify _.pluck(all, "src")
							# 	_deferred.resolve photos

						, self.cameraError
						, options


					
					return _deferred.promise.finally ()->_deferred = null
				catch error
					JSON.stringify error
	

			# dataURL > resolve with originalSrc as FileURI and previewSrc as DataURL
			dataURLPipeline : (o, options)->
				# dfd = $q.defer() 
				dataURL = o.dataURL['preview'] || null
				extension = if options.encodingType then "PNG" else "JPG"
				if extension == 'PNG' 
					options.encodingType = Camera.EncodingType.PNG 
					mimeType = 'image/png'
				else 
					options.encodingType = Camera.EncodingType.JPEG
					mimeType = 'image/jpeg'

				dataURL = "data:" + mimeType + ";base64," + dataURL if dataURL && dataURL.indexOf("data:") != 0
				# steroids.logger.log dataURL[0..100]
				retval = {
					# originalSrc: '/' + o.fileEntry['original'].name
					id: o.uuid
					label: o.label
					orig_ext: o.orig_ext
					extension: extension
					# label: label || o.uuid
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
			fileURIPipeline : (item, options)->
				###
				expecting: item = {
					id : ALAssetsLibrary Id, assets-library://asset/asset.{ext}?id={uuid}&ext={ext}
					uuid : uuid,
					orig_ext : orig_ext, [JPG | PNG] NOT same as options.encodingType
					data : String, File_URI: path or Data_URL:base64-encoded string
					exif : {
					    DateTimeOriginal : dateTimeOriginal,  format:  "yyyy-MM-dd HH:mm:ss"
					    PixelXDimension : pixelXDimension, 
					    PixelYDimension : pixelYDimension,
					    Orientation : orientation
					};
				### 	
				uuid = item.uuid
				filename = item.filename || item.uuid
				extension = if options.encodingType then "PNG" else "JPG"
				fileURI = item.data 


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
				# steroids.logger.log JSON.stringify( item)[0..150]
				promise = _initFileStore()
				return promise.catch (o)->
					steroids.logger.log {
						msg: "**** _initFileStore().REJECTED! ******"
						root: o.directoryEntry.root.fullPath 
						preview: o.directoryEntry.preview.fullPath 
					}
				.then (o)->
					steroids.logger.log "getLocalFilesystem"
					return _pipelinePromises.getLocalFilesystem(o) # _.pluck o, "directoryEntry"	
				.then (o)->
					o.uuid = item.uuid
					o.orig_ext = item.orig_ext
					o.label = item.label
					o.extension = extension
					if options.destinationType == navigator.camera.DestinationType.FILE_URI
						steroids.logger.log "navigator.camera.DestinationType.FILE_URI"
						filename = item.uuid
						fileURI = item.data
						steroids.logger.log  "************** fileURI=" + fileURI
						return _pipelinePromises.resolveLocalFileSystemURI( o , fileURI, 'original')
							.then (o)->
								fileEntry = o.fileEntry['original']
								return _pipelinePromises.fileEntryMoveTo( o, fileEntry, o.directoryEntry['root'], filename)
							.then (o)->
								# steroids.logger.log "formatResult"
								return _pipelinePromises.formatResult(o)

					else # DATA_URL
						o.data = item.data
						steroids.logger.log "navigator.camera.DestinationType.DATA_URL"

						return _pipelinePromises.getPreviewAsDataURL(o, options, extension)
							.then (o)->
								steroids.logger.log "writeDataURL2File"
								return _pipelinePromises.writeDataURL2File(o, 'preview')
							.then (o)->
								# when is o.fileEntry[root] set?
								return _pipelinePromises.formatResult(o)
				.catch (o)->
					if (o?.dataURL?.preview)
						dfd = $q.defer()
						retval = self.dataURLPipeline(o, options)
						steroids.logger.log "dataURLPipeline COMPLETE, retval=" + JSON.stringify retval[0..200]
						dfd.resolve(retval)
						return dfd.promise

					steroids.logger.log "imagePipeline REJECTED!"
					steroids.logger.log o
					return throw "imagePipeline REJECTED!"
				# end fileURIPipeline

			resample: (img)->
				dfd = $q.defer()
				_resample img, dfd, 640
				return dfd.promise


		}

		_initFileStore().then ()->
			steroids.logger.log "************** calling initOverlay()"
			_initOverlay().catch (error)->
				steroids.logger.log "initOverlay failed"
				steroids.logger.log error
		
		return self
]
)