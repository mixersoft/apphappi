module.exports = (grunt)->

  # Run 'grunt' for steroids connect
  grunt.registerTask("default", ["steroids"]);
  grunt.registerTask("steroids", [
      "steroids-make", 
      "steroids-compile-sass", 
      "copy", 
      "less"    
  ]);

  # Run `grunt server` for live-reloading development environment
  grunt.registerTask('server', [ 'steroids', 'express', 'watch' ])
  
  # Optimize pre-built, web-accessible resources for production, primarily `usemin`
  # run after `grunt server`
  # grunt.registerTask('optimize', [ 'copy:fonts', 'useminPrepare', 'concat', 'uglify', 'cssmin', 'rev', 'usemin', 'express', 'watch' ])
  # grunt.registerTask('optimize', [ 'copy:fonts', 'useminPrepare', 'concat', 'uglify', 'cssmin', 'rev', 'usemin', 'watch' ])
  grunt.registerTask('optimize', [ 
    'copy:optimize'
    'useminPrepare'
    'uglify'
    'cssmin' 
    # 'concat:app-build'
    # 'concat:vendor-build'
    'concat:app-min'
    'concat:vendor-min'
    'usemin'
  ])

  uglifyNew = require('grunt-usemin-uglifynew');
  # grunt.loadNpmTasks('grunt-usemin-uglifynew')
  

  # Configuration
  grunt.config.init

    # Directory CONSTANTS (see what I did there?)
    BUILD_DIR:      'dist/'
    WWW_DIR:        'www/'
    APP_DIR:        'app/'
    COMPONENTS_DIR: 'www/components/'
    SERVER_DIR:     'server/'

    # Glob CONSTANTS
    ALL_FILES:      '**/*'
    CSS_FILES:      '**/*.css'
    HTML_FILES:     '**/*.html'
    IMG_FILES:      '**/*.{png,gif,jpg,jpeg}'
    JS_FILES:       '**/*.js'
    SASS_FILES:     '**/*.scss'
    LESS_FILES:     '**/*.less'
    FONT_FILES:     '**/font'
    DATA_FILES:     '**/*.json'

    copy:
      optimize:
        src:'<%= WWW_DIR %>/apphappi.html'
        dest:'<%= BUILD_DIR %>/apphappi.html'
      #
      # "steroids-copy-www": 
      #     src:  '<%= WWW_DIR %>' 
      #     dest: '<%= BUILD_DIR %>'  
      #
      # App images from Bower `components` & `client`
      xxximages:
        xxxfiles:      [
          expand:   true
          cwd:      '<%= WWW_DIR %>'
          src:      '<%= IMG_FILES %>'
          dest:     '<%= BUILD_DIR %>'
        ]

      data:
        files:      [
          expand:   true
          cwd:      '<%= APP_DIR %>'
          src:      '**/data/<%= DATA_FILES %>'
          dest:     '<%= BUILD_DIR %>'
        ]

      fonts:
        files:      [
          expand:   true
          cwd:      '<%= WWW_DIR %>'
          src:      '**/fonts/*'
          dest:     '<%= BUILD_DIR %>fonts/'
          flatten:  true
          filter:   'isFile'
          
        , # for snappi fonts 
          expand:   true
          cwd:      '<%= WWW_DIR %>vendor/fonts/'
          src:      ['Roboto/*','HomemadeApple/*','GeoSansLight/*','SourceSansPro/*']
          dest:     '<%= BUILD_DIR %>fonts/'
          flatten:  false
          filter:   'isFile'

        , # for use with Topcoat ONLY         
          expand:   true
          cwd:      '<%= WWW_DIR %>vendor/topcoat/'
          src:      ['css/*', 'font/*']
          dest:     '<%= BUILD_DIR %>font/'
          flatten:  true
          filter:   'isFile'
        ]  

          # app (non-Bower) HTML in `client`
      html:     # WARING: overwrites results from steroids-compile-views
        files:      [
          expand:   true
          cwd:      '<%= APP_DIR %>'
          src:      ['**/templates/<%= HTML_FILES %>', '**/_*.html']
          dest:     '<%= BUILD_DIR %>'
        ,
          expand:   true
          cwd:      '<%= WWW_DIR %>'
          src:      ['<%= HTML_FILES %>', '!**/vendor/**', '!**/components/**']
          dest:     '<%= BUILD_DIR %>'
        ]

      usemin:
        files: [
          expand: true
          cwd: '.tmp/concat/'
          src: '<%= ALL_FILES %>'
          dest: '<%= BUILD_DIR %>'
        ]

    # Ability to run `jshint` without errors terminating the development server
    parallel:
      less:         [ grunt: true, args: [ 'less' ] ]
      jshint:       [ grunt: true, args: [ 'jshint' ] ]
      # compass:      [ grunt: true, args: [ 'compass' ] ]

    # WARNING: use the following in steroids.compile.sass.coffee to exclude font-awesome
    sass:
        dist:
          xxxfiles: [
            {
              expand: true
              cwd: 'www/'
              src: ['**/*.scss', '**/*.sass','!**/font-awesome/**']
              dest: 'dist/'
              ext: '.css'
            }
          ]

    # Support live-reloading of all non-Bower resources
    # changed from livereload to watch
    watch:
      # changes to js should copy to BUILD, trigger watch:build
      js:     
        files:      [ '<%= APP_DIR + JS_FILES %>'
                    '<%= SERVER_DIR + JS_FILES %>' 
                    ] 
        tasks:      ['copy:js', 'jshint']
        # tasks:      [ 'copy:js', 'parallel:jshint' ]
        options: 
          spawn:    false

      html:
        files:      [ '<%= APP_DIR + HTML_FILES %>'] 
        tasks:      ['copy:html']
        options: 
          spawn:    false
          

      # Changes to LESS styles should re-compile, triggers watch:build
      less:
        files:      ['<%= APP_DIR + LESS_FILES %>'
                    '<%= WWW_DIR + LESS_FILES %>']
        tasks:      [ 'less', 'cssmin' ]
        # tasks:      [ 'parallel:less', 'parallel:cssmin' ]  
        options:
          spawn: false

      coffee:
        files:
          expand: true
          cwd: "<%= APP_DIR %>"
          src: ["**/*.coffee"]
          dest: "<%= BUILD_DIR %>"
          ext: ".js"
        tasks: ['coffee:app']  
            

      # WARNING: NOT TESTED
      build:        
        files:      '<%= BUILD_DIR + ALL_FILES %>'
        # tasks:      [ 'karma:background:run' ]
        options:
          livereload: 3330


      # Changes to server-side code should validate, restart the server, & refresh the browser
      server:
        files:      '<%= SERVER_DIR + ALL_FILES %>'
        # tasks:      [ 'parallel:jshint', 'express' ]
        tasks:      [ 'parallel:jshint', 'express' ]
        options:
          livereload: 3330

    # Validate app `client` and `server` JS
    jshint:
      files:        [
                    '<%= APP_DIR + JS_FILES %>' 
                    '<%= WWW_DIR + "javascripts/" + JS_FILES %>'
                    '<%= SERVER_DIR + JS_FILES %>'
                    ]
      options:
        es5:        true
        laxcomma:   true  # Common in Express-derived libraries

    # Compile less files
    less:
      development:
        options:
          paths:  [
                  '<%= COMPONENTS_DIR %>bootstrap/less'
                  '<%= COMPONENTS_DIR %>font-awesome/less'
                  ]
          compress: false
          yuicompress: false
          optimization: 2
        files: [
          expand:  true
          cwd:      '<%= APP_DIR %>'
          src:      '<%= LESS_FILES %>'
          dest:     '<%= BUILD_DIR %>'
          ext:      '.css'
        ,
          expand:  true
          cwd:      '<%= WWW_DIR %>'
          src:      'stylesheets/<%= LESS_FILES %>'
          dest:     '<%= BUILD_DIR %>'
          ext:      '.css'
        ,  
          # bootstrap
          '<%= BUILD_DIR %>stylesheets/bootstrap.css': '<%= WWW_DIR %>components/bootstrap/less/bootstrap.less'
        , # font-awesome
          '<%= BUILD_DIR %>stylesheets/font-awesome.css': '<%= WWW_DIR %>components/font-awesome/less/font-awesome.less'


        ]

    # Browser-based testing
    # Minify app `.css` resources -> `.min.css`
    cssmin: 
      minify: 
        expand: true,
        cwd: '<%= BUILD_DIR %>stylesheets',
        src: ['*.css', '!*.min.css'],
        dest: '<%= BUILD_DIR %>stylesheets',
        ext: '.min.css'

    # Express requires `server.script` to reload from changes
    express:
      server:
        options:
          script:   '<%= SERVER_DIR %>/server.js'
          port:     3333

    # Prepend a hash on file names for versioning
    rev:
      files:
        src:  ['<%= BUILD_DIR %>/app/scripts/all.min.js','<%= BUILD_DIR %>/app/styles/app.min.css']

    # Output for optimized app index
    usemin:
      html:         '<%= BUILD_DIR %>index.html'



    # Input for optimized app index
    useminPrepare:
      html:         '<%= BUILD_DIR %>index.html'
      options: 
        flow: 
          steps: 
            # js: ['uglifyjs', 'concat']
            js: [uglifyNew, 'concat']
            # js: ['concat']
            css: ['concat', 'cssmin']
          post: []

    uglify:
      options:
        mangle:
          except: ['**/*.min.js']

    concat:
      'app-min':
        files: [
          dest: '<%= BUILD_DIR %>/javascripts/app.min.js',
          src: [
            '.tmp/uglify/app.js',
            '.tmp/uglify/common/services/Drawer.js',
            '.tmp/uglify/common/services/Sync.js',
            '.tmp/uglify/common/services/Deck.js',
            '.tmp/uglify/common/services/Camera.js',
            '.tmp/uglify/models/restangular.js',
            '.tmp/uglify/controllers/apphappi.js'
            '.tmp/uglify/common/data/json.js'
          ]
        ]
      'vendor-min':
        files: [
          dest: '<%= BUILD_DIR %>/javascripts/vendor-BODY.min.js'
          src: [ 
           # '<%= BUILD_DIR %>/components/parse-js-sdk/lib/parse-1.2.16.min.js',
           '.tmp/uglify/components/modernizr/modernizr.js',
           '.tmp/uglify/components/lodash/dist/lodash.min.js',
           # '.tmp/uglify/components/angular/angular.min.js',
           '<%= BUILD_DIR %>/components/angular/angular.js',
           '.tmp/uglify/components/angular-bootstrap/ui-bootstrap-tpls.min.js',
           '.tmp/uglify/components/angular-animate/angular-animate.min.js',
           '.tmp/uglify/components/angular-route/angular-route.min.js',
           # '.tmp/uglify/components/restangular/dist/restangular.min.js',
           '.tmp/uglify/components/angular-local-storage/angular-local-storage.min.js',
           '.tmp/uglify/components/moment/min/moment.min.js',
           '.tmp/uglify/components/angular-moment/angular-moment.min.js',
           '.tmp/uglify/components/angular-sanitize/angular-sanitize.min.js' 
           '.tmp/uglify/components/angular-bindonce/bindonce.min.js'
           '.tmp/uglify/javascripts/angular-touch.longtap.js'
           # '.tmp/uglify/components/angular-carousel/dist/angular-carousel.js'
           '.tmp/uglify/javascripts/angular-carousel.requestAnimationFrame.js',
           '.tmp/uglify/javascripts/jpegmeta.js'
          ]   
        ]  
      'app-build':
        xxxfiles: [
          dest: '<%= BUILD_DIR %>/javascripts/app.min.js',
          src: [
            '<%= BUILD_DIR %>/app.js',
            '<%= BUILD_DIR %>/common/services/Drawer.js',
            '<%= BUILD_DIR %>/common/services/Sync.js',
            '<%= BUILD_DIR %>/common/services/Deck.js',
            '<%= BUILD_DIR %>/common/services/Camera.js',
            '<%= BUILD_DIR %>/models/restangular.js',
            '<%= BUILD_DIR %>/controllers/apphappi.js' 
            '<%= BUILD_DIR %>/common/data/json.js' 
          ]
        ]
      'vendor-build':
        XXXfiles: [
          dest: '<%= BUILD_DIR %>/javascripts/vendor-BODY.min.js'
          src: [ 
           # '<%= BUILD_DIR %>/components/parse-js-sdk/lib/parse-1.2.16.min.js',
           '<%= BUILD_DIR %>/components/modernizr/modernizr.js',
           '<%= BUILD_DIR %>/components/lodash/dist/lodash.min.js',
           '<%= BUILD_DIR %>/components/angular/angular.js',
           '<%= BUILD_DIR %>/components/angular-bootstrap/ui-bootstrap-tpls.min.js',
           '<%= BUILD_DIR %>/components/angular-animate/angular-animate.min.js',
           '<%= BUILD_DIR %>/components/angular-route/angular-route.min.js',
           # '<%= BUILD_DIR %>/components/restangular/dist/restangular.js',
           '<%= BUILD_DIR %>/components/angular-local-storage/angular-local-storage.min.js',
           '<%= BUILD_DIR %>/components/moment/min/moment.min.js',
           '<%= BUILD_DIR %>/components/angular-moment/angular-moment.min.js',
           '<%= BUILD_DIR %>/components/angular-sanitize/angular-sanitize.min.js' 
           '<%= BUILD_DIR %>/components/angular-bindonce/bindonce.min.js'
           '<%= BUILD_DIR %>/javascripts/angular-touch.longtap.js'
           # '<%= BUILD_DIR %>/components/angular-carousel/dist/angular-carousel.js'
           '<%= BUILD_DIR %>/javascripts/angular-carousel.requestAnimationFrame.js'
           '<%= BUILD_DIR %>/javascripts/jpegmeta.js'
          ]   
        ]

    # "Compile CoffeeScript files from app/ and www/ to dist/"
    coffee:
      app:
        expand: true
        cwd: "<%= APP_DIR %>"
        src: ["**/*.coffee"]
        dest: "<%= BUILD_DIR %>"
        ext: ".js"



    # "watch" distinct types of files and re-prepare accordingly
    # change from regarde to watch
    XXXregarde:
      compass:
        files:      '<%= WWW_DIR + SASS_FILES %>'
        tasks:      [ 'parallel:compass' ]

      # Changes to server-side code should validate, restart the server, & refresh the browser
      server:
        files:      '<%= SERVER_DIR + ALL_FILES %>'
        tasks:      [ 'parallel:jshint', 'express', 'livereload' ]


    XXXkarma:
      options:
        configFile: 'karma.conf.js'

      # Used for running tests while the server is running
      background:
        background: true
        singleRun:  false

      # Used for testing site across several browser profiles
      browsers:
        browsers:   [ 'PhantomJS' ] # 'Chrome', 'ChromeCanary', 'Firefox', 'Opera', 'Safari', 'IE', 'bin/browsers.sh'
        background: true
        singleRun:  false

      # Used for one-time validation (e.g. `grunt test`, `npm test`)
      unit:
        singleRun:  true

  grunt.loadNpmTasks('grunt-steroids')  
  grunt.loadNpmTasks('grunt-contrib-copy')
  grunt.loadNpmTasks('grunt-contrib-jshint')
  grunt.loadNpmTasks('grunt-contrib-less')
  grunt.loadNpmTasks('grunt-contrib-cssmin')
  grunt.loadNpmTasks('grunt-contrib-uglify')

  uglifyNew = require('grunt-usemin-uglifynew');
  # grunt.loadNpmTasks('grunt-usemin-uglifynew')
  
  grunt.loadNpmTasks('grunt-parallel')
  grunt.loadNpmTasks('grunt-contrib-watch')
  grunt.loadNpmTasks('grunt-express-server')
  grunt.loadNpmTasks('grunt-usemin')
  grunt.loadNpmTasks('grunt-rev')
  grunt.loadNpmTasks "grunt-contrib-coffee"



