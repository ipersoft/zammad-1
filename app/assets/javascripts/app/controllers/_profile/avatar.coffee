class Index extends App.Controller
  elements:
    '.js-upload':      'fileInput'
    '.avatar-gallery': 'avatarGallery'

  events:
    'click .js-openCamera': 'openCamera'
    'change .js-upload':    'onUpload'
    'click .avatar':        'onSelect'
    'click .avatar-delete': 'onDelete'

  constructor: ->
    super
    return if !@authenticate()
    @title 'Avatar', true
    @avatars = []
    @loadAvatarList()

  loadAvatarList: =>
    @ajax(
      id:   'avatar_list'
      type: 'GET'
      url:  @apiPath + '/users/avatar'
      processData: true
      success: (data, status, xhr) =>
        @avatars = data.avatars
        @render()
    )

  # check if the browser supports webcam access
  # doesnt render the camera button if not
  hasGetUserMedia: ->
    return !!(navigator.getUserMedia || navigator.webkitGetUserMedia ||
            navigator.mozGetUserMedia || navigator.msGetUserMedia)

  render: =>
    @html App.view('profile/avatar')
      webcamSupport: @hasGetUserMedia()
      avatars:       @avatars
    @$('.avatar[data-id="' + @Session.get('id') + '"]').attr('data-id', '').attr('data-avatar-id', '0')

  onSelect: (e) =>
    @pick( $(e.currentTarget) )

  onDelete: (e) =>
    e.stopPropagation()
    if confirm App.i18n.translateInline('Delete Avatar?')

      params =
        id: $(e.currentTarget).parent('.avatar-holder').find('.avatar').data('avatar-id')

      $(e.currentTarget).parent('.avatar-holder').remove()
      @pick @$('.avatar').last()

      # remove avatar globally
      @ajax(
        id:   'avatar_delete'
        type: 'DELETE'
        url:  @apiPath + '/users/avatar'
        data: JSON.stringify( params )
        processData: true
    )

  pick: (avatar) =>
    @$('.avatar').removeClass('is-active')
    avatar.addClass('is-active')
    avatar_id = avatar.data('avatar-id')
    params    =
      id: avatar_id

    # update avatar globally
    @ajax(
      id:   'avatar_set_default'
      type: 'POST'
      url:  @apiPath + '/users/avatar/set'
      data: JSON.stringify( params )
      processData: true
      success: (data, status, xhr) =>

        # update avatar in app at runtime
        activeAvatar = @$('.avatar.is-active')
        style = activeAvatar.attr('style')

        # set correct background size
        if activeAvatar.text()
          style += ';background-size:auto'
        else
          style += ';background-size:cover'

        # find old avatars and update them
        replaceAvatar = $('.avatar[data-id="' + @Session.get('id') + '"]')
        replaceAvatar.attr('style', style)

        # update avatar text if needed
        if activeAvatar.text()
          replaceAvatar.text(activeAvatar.text())
          replaceAvatar.addClass('unique')
        else
          replaceAvatar.text( '' )
          replaceAvatar.removeClass('unique')
    )
    avatar

  openCamera: =>
    new Camera
      callback: @storeImage

  storeImage: (src) =>

    # store avatar globally
    @oldDataUrl = src

    # store on server site
    store = (newDataUrl) =>
      @ajax(
        id:   'avatar_new'
        type: 'POST'
        url:  @apiPath + '/users/avatar'
        data: JSON.stringify(
          avatar_full:   @oldDataUrl
          avatar_resize: newDataUrl
        )
        processData: true
        success: (data, status, xhr) =>
          avatarHolder = $(App.view('profile/avatar-holder')( src: src, avatar: data.avatar ) )
          @avatarGallery.append(avatarHolder)
          @pick avatarHolder.find('.avatar')
      )

    # add resized image
    App.ImageService.resizeForAvatar( src, 'auto', 160, store )

  onUpload: (event) =>
    callback = @storeImage
    EXIF.getData event.target.files[0], ->
      orientation   = @exifdata.Orientation
      reader        = new FileReader()
      reader.onload = (e) ->
        new ImageCropper
          imageSource: e.target.result
          callback:    callback
          orientation: orientation

      reader.readAsDataURL(@)

App.Config.set( 'Avatar', { prio: 1100, name: 'Avatar', parent: '#profile', target: '#profile/avatar', controller: Index }, 'NavBarProfile' )


class ImageCropper extends App.ControllerModal
  buttonClose: true
  buttonCancel: true
  buttonSubmit: 'Save'
  head: 'Crop Image'

  elements:
    '.imageCropper-image': 'image'
    '.imageCropper-holder': 'holder'

  content: ->
    App.view('profile/imageCropper')()

  post: =>
    @size = 256

    orientationTransform =
      1: 0
      3: 180
      6: 90
      8: -90

    @angle = orientationTransform[ @orientation ]

    if @angle == undefined
      @angle = 0

    if @angle != 0
      @isOrientating = true
      image = new Image()
      image.addEventListener 'load', @orientateImage
      image.src = @imageSource
    else
      @image.attr src: @imageSource

  orientateImage: (e) =>
    image  = e.currentTarget
    canvas = document.createElement('canvas')
    ctx    = canvas.getContext('2d')

    if @angle is 180
      canvas.width  = image.width
      canvas.height = image.height
    else
      canvas.width  = image.height
      canvas.height = image.width

    ctx.translate(canvas.width/2, canvas.height/2)
    ctx.rotate(@angle * Math.PI/180)
    ctx.drawImage(image, -image.width/2, -image.height/2, image.width, image.height)

    @image.attr src: canvas.toDataURL()
    @isOrientating = false
    @initializeCropper() if @isShown

  onShown: =>
    @isShown = true
    @initializeCropper() if not @isOrientating

  initializeCropper: =>
    @image.cropper
      aspectRatio: 1
      guides: false
      autoCrop: true
      autoCropArea: 1
      minContainerWidth: 500
      minContainerHeight: 300
      preview: '.imageCropper-preview'

  onSubmit: =>
    @callback( @image.cropper('getCroppedCanvas').toDataURL() )
    @image.cropper('destroy')
    @close()


class Camera extends App.ControllerModal
  buttonClose: true
  buttonCancel: true
  buttonSubmit: 'Save'
  buttonClass: 'btn--success is-disabled'
  centerButtons: [{
    className: 'btn--success js-shoot is-disabled',
    text: 'Shoot'
  }]
  head: 'Camera'

  elements:
    '.js-shoot':       'shootButton'
    '.js-submit':      'submitButton'
    '.camera-preview': 'preview'
    '.camera':         'camera'
    'video':           'video'

  events:
    'click .js-shoot:not(.is-disabled)': 'onShootClick'

  content: ->
    App.view('profile/camera')()

  post: =>
    @size            = 256
    @photoTaken      = false
    @backgroundColor = 'white'

    @ctx = @preview.get(0).getContext('2d')

    requestWebcam = Modernizr.prefixed('getUserMedia', navigator)
    requestWebcam({video: true}, @onWebcamReady, @onWebcamError)

    @initializeCache()

  onShootClick: =>
    if @photoTaken
      @photoTaken = false
      @submitButton.addClass 'is-disabled'
      @shootButton
        .removeClass 'btn--danger'
        .addClass 'btn--success'
        .text App.i18n.translateInline('Shoot')
      @updatePreview()
    else
      @shoot()
      @shootButton
        .removeClass 'btn--success'
        .addClass 'btn--danger'
        .text App.i18n.translateInline('Discard')

  shoot: =>
    @photoTaken = true
    @submitButton.removeClass 'is-disabled'

  onWebcamReady: (stream) =>
    @shootButton.removeClass 'is-disabled'

    # in case the modal is closed before the
    # request was fullfilled
    if @hidden
      @stream.stop()
      return

    # cache stream so that we can later turn it off
    @stream = stream

    # setup the offset to center the webcam image perfectly
    # when the stream is ready
    @video.on 'canplay', @setupPreview

    # start to update the preview once its playing
    @video.on 'playing', @updatePreview

    @video.attr 'src', window.URL.createObjectURL(stream)

    # start the stream
    @video.get(0).play()

  onWebcamError: (error) =>
    # in case the modal is closed before the
    # request was fullfilled
    if @hidden
      return

    convertToHumanReadable =
      'PermissionDeniedError':       App.i18n.translateInline('You have to allow access to your webcam.')
      'ConstraintNotSatisfiedError': App.i18n.translateInline('No camera found.')

    alert convertToHumanReadable[error.name]
    @close()

  setupPreview: =>
    @video.attr 'height', @size
    @preview.attr
      width: @size
      height: @size
    @centerX = @size/2
    @centerY = @size/2

    # create circle clip area
    @ctx.translate @centerX, @centerY

    # flip the image to look like a mirror
    @ctx.scale -1, 1

    # settings for anti-aliasing
    @ctx.strokeStyle = @backgroundColor
    @ctx.lineWidth = 2

  updatePreview: =>
    # try catch fixes a Firefox error
    # were the drawImage wouldn't work
    # because the video didn't get inizialized
    # yet internally
    # http://stackoverflow.com/questions/18580844/firefox-drawimagevideo-fails-with-ns-error-not-available-component-is-not-av
    try
      @ctx.globalCompositeOperation = 'source-over'
      @ctx.clearRect 0, 0, @size, @size
      @ctx.beginPath()
      @ctx.arc 0, 0, @size/2, 0, 2 * Math.PI, false
      @ctx.closePath()
      @ctx.fill()
      @ctx.globalCompositeOperation = 'source-atop'

      # draw video frame
      @ctx.drawImage @video.get(0), -@video.width()/2, -@size/2, @video.width(), @size

      # add anti-aliasing
      # http://stackoverflow.com/a/12395939
      @ctx.beginPath()
      @ctx.arc 0, 0, @size/2, 0, 2 * Math.PI, false
      @ctx.closePath()
      @ctx.stroke()

      # update the preview again as soon as
      # the browser is ready to draw a new frame
      if not @photoTaken
        requestAnimationFrame @updatePreview
      else
        # cache raw video data
        @cacheScreenshot()
    catch e
      if e.name is 'NS_ERROR_NOT_AVAILABLE'
        setTimeout @updatePreview, 200
      else
        throw e

  initializeCache: ->
    # create virtual canvas
    @cache = $('<canvas>')
    @cacheCtx = @cache.get(0).getContext('2d')

  cacheScreenshot: ->
    # reset video height
    @video.attr height: ''

    # cache screenshot as big as possible (native webcam dimensions)
    size = Math.min @video.height(), @video.width()

    @cache.attr
      width:  size
      height: size

    # draw full resolution screenshot
    @cacheCtx.save()

    # transform and flip image
    @cacheCtx.translate size/2, size/2
    @cacheCtx.scale -1, 1

    @cacheCtx.drawImage @video.get(0), -@video.width()/2, -@video.height()/2, @video.width(), @video.height()

    @cacheCtx.restore()

    # reset video height
    @video.attr height: @size

  onClose: =>
    @stream.stop() if @stream
    @hidden = true

  onSubmit: =>
    # send picture to the callback
    console.log @cache.get(0).toDataURL()
    window.file = @cache.get(0).toDataURL()
    @callback @cache.get(0).toDataURL()
    @close()
