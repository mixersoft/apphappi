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
  grunt.registerTask('optimize', [ 'copy:fonts', 'useminPrepare', 'concat', 'uglify', 'cssmin', 'rev', 'usemin', 'express', 'watch' ])

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
          cwd:      '<%= WWW_DIR %>'
          src:      ['**/font/*', '!**/font-awesome/**']
          dest:     '<%= BUILD_DIR %>font/'
          flatten:  true
          filter:   'isFile'
        ]  

          # app (non-Bower) HTML in `client`
      html:     # WARING: overwrites results from steroids-compile-views
        files:      [
          expand:   true
          cwd:      '<%= APP_DIR %>views/'
          src:      '**/partials/<%= HTML_FILES %>'
          dest:     '<%= BUILD_DIR %>views/'
        ,
          expand:   true
          cwd:      '<%= WWW_DIR %>'
          src:      ['<%= HTML_FILES %>', '!**/vendor/**', '!**/components/**']
          dest:     '<%= BUILD_DIR %>'
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
  grunt.loadNpmTasks('grunt-parallel')
  grunt.loadNpmTasks('grunt-contrib-watch')
  grunt.loadNpmTasks('grunt-express-server')
  grunt.loadNpmTasks('grunt-usemin')
  grunt.loadNpmTasks('grunt-rev')
  grunt.loadNpmTasks "grunt-contrib-coffee"



