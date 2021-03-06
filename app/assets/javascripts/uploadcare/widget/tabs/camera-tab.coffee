{
  utils,
  jQuery: $,
  templates: {tpl}
} = uploadcare


uploadcare.namespace 'widget.tabs', (ns) ->
  isSecure = document.location.protocol == 'https:'

  class ns.CameraTab

    constructor: (@container, @tabButton, @dialogApi, @settings, @name) ->
      if not @__checkCompatibility()
        @dialogApi.hideTab(@name)
        return

      @__loaded = false
      @mirrored = true

      @container.append(tpl('tab-camera'))
      @container.addClass('uploadcare-dialog-padding uploadcare-dialog-camera-requested')
      @container.find('.uploadcare-dialog-camera-capture').on('click', @__capture)
      startRecord = @container.find('.uploadcare-dialog-camera-start-record').on('click', @__startRecording)
      @container.find('.uploadcare-dialog-camera-stop-record').on('click', @__stopRecording)
      @container.find('.uploadcare-dialog-camera-cancel-record').on('click', @__cancelRecording)
      @container.find('.uploadcare-dialog-camera-mirror').on('click', @__mirror)
      @container.find('.uploadcare-dialog-camera-retry').on('click', @__requestCamera)

      if not @MediaRecorder or @settings.imagesOnly
        startRecord.hide()

      @video = @container.find('video')
      @video.on 'loadeddata', ->
        @play()

      @dialogApi.progress (name) =>
        if name == @name
          if not @__loaded
            @__requestCamera()
        else
          if @__loaded and isSecure
            @__revoke()

      @dialogApi.always(@__revoke)

    __checkCompatibility: ->
      @getUserMedia = navigator.getUserMedia or navigator.webkitGetUserMedia or navigator.mozGetUserMedia
      @URL = window.URL or window.webkitURL
      @MediaRecorder = window.MediaRecorder
      if not isSecure
        uploadcare.utils.warn('Camera is not allowed for HTTP. Please use HTTPS connection.');
      isLocalhost = document.location.hostname == 'localhost'
      return !! @getUserMedia and Uint8Array and (isSecure or isLocalhost)

    __setState: (newState) =>
      oldStates = ['', 'ready', 'requested', 'denied', 'not-founded',
                   'recording'].join(' uploadcare-dialog-camera-')
      @container
          .removeClass(oldStates)
          .addClass("uploadcare-dialog-camera-#{newState}")

    __requestCamera: =>
      @__loaded = true
      @getUserMedia.call(navigator,
        audio: true,
        video:
          optional: [
            {minWidth: 320},
            {minWidth: 640},
            {minWidth: 1024},
            {minWidth: 1280},
            {minWidth: 1920},
          ]
      , (stream) =>
        @__setState('ready')

        @__stream = stream
        if @URL
          @video.prop('src', @URL.createObjectURL(stream))
        else
          @video.prop('src', stream)
        @video[0].volume = 0
        @video[0].play()

      , (error) =>
        if error == "NO_DEVICES_FOUND" or error.name == 'DevicesNotFoundError'
          @__setState('not-founded')
        else
          @__setState('denied')
        @__loaded = false
      )

    __revoke: =>
      @__setState('requested')

      @__loaded = false
      if not @__stream
        return
      if @URL
        @URL.revokeObjectURL(@video.prop('src'))
      if @__stream.getTracks
        $.each @__stream.getTracks(), ->
          @stop?()
      @__stream.stop?()
      @__stream = null

    __mirror: =>
      @mirrored = ! @mirrored
      @video.toggleClass('uploadcare-dialog-camera--mirrored', @mirrored)

    __capture: =>
      video = @video[0]
      w = video.videoWidth
      h = video.videoHeight
      canvas = document.createElement('canvas')
      canvas.width = w;
      canvas.height = h;
      ctx = canvas.getContext('2d')
      if @mirrored
        ctx.translate(w, 0)
        ctx.scale(-1, 1)
      ctx.drawImage(video, 0, 0, w, h)

      utils.canvasToBlob canvas, 'image/jpeg', 0.9, (blob) =>
        canvas.width = canvas.height = 1
        blob.name = "camera.jpg"
        @dialogApi.addFiles('object', [[blob, {source: 'camera'}]])
        @dialogApi.switchTab('preview')

    __startRecording: =>
      @__setState('recording')

      @__chunks = []
      @__recorder = new @MediaRecorder(@__stream)
      @__recorder.start()
      @__recorder.ondataavailable = (e) =>
        @__chunks.push(e.data)

    __stopRecording: =>
      @__setState('ready')

      @__recorder.onstop = =>
        # I don't see any way to get correct value in Chrome.
        # Currently Chrome and Firefox both uses webm.
        mime = @__recorder.mimeType
        mime = if mime then mime.split('/')[1] else 'webm'
        blob = new Blob(@__chunks, {'type': "video/#{mime}"})
        blob.name = "record.#{mime}"
        @dialogApi.addFiles('object', [[blob, {source: 'camera'}]])
        @dialogApi.switchTab('preview')
        @__chunks = []
      @__recorder.stop()

    __cancelRecording: =>
      @__setState('ready')

      @__recorder.stop()
      @__chunks = []
