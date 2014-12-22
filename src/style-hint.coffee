exec = require('child_process').exec
fs = require('fs')
async = require('async')

walker = (dir,ext) ->
  paths = []
  if /\.[\w]+$/gi.test(dir)
    paths.push(dir)
  else
    dir = dir + '/' if dir.slice(-1) isnt '/' 
    for path in fs.readdirSync(dir)
      unless /^\./gi.test(path)
        stat = fs.statSync(dir+path)
        reg = new RegExp('\\.'+ext+'$','gi')
        if stat.isFile() and reg.test(path)
          paths.push(dir+path)
        else if stat.isDirectory() and path isnt 'node_modules'
          for sub in walker(dir+path, ext)
            paths.push(sub)
  
  paths

FILES =
  JSCS: __dirname+'/../.jscs.json'
  JSHINT: __dirname+'/../.jshintrc'
  COFFEELINT: __dirname+'/../coffeelint.json'

setUp = (configs) ->
  fs.writeFileSync(FILES.JSCS, JSON.stringify(configs.APP_CONFIGS.JSCS, null, 2))
  fs.writeFileSync(FILES.JSHINT, JSON.stringify(configs.APP_CONFIGS.JSHINT, null, 2))
  fs.writeFileSync(FILES.COFFEELINT, JSON.stringify(configs.APP_CONFIGS.COFFEELINT, null, 2))

parseArgs = (args) ->
  ob = {}
  args = args.slice(2)  
  
  if not args.length
    ob.DIR = process.cwd() + '/'
  else
    for c in args
      if not /^--\w/gi.test(c)
        ob.DIR = process.cwd() + '/' + c
      else
        c = c.substring(2).split("=")
        switch c[0].toLowerCase()
          when 'globals'
            ob.GLOBALS = c[1].split(',').map((i)->
              i.trim()
            )
          when 'coffee'
            ob.COFFEE_ONLY = true
          when 'js'
            ob.JS_ONLY = true
          when 'limit'
            ob.LIMIT = parseInt(c[1])
          when 'no-char-limit'
            ob.CHARLIMIT = 1000000000000
          else
            console.error('Unknown argument '+c[0])
            process.exit()
      
  ob

tearDown = () ->
  fs.unlinkSync(FILES.JSCS)
  fs.unlinkSync(FILES.JSHINT)
  fs.unlinkSync(FILES.COFFEELINT)

getConfigs = () ->
  args = parseArgs(process.argv)

  CONFIGS =
    DIR: '.'
    APP_CONFIGS: require('./../config.json')
    PROCESS_JS: true
    PROCESS_COFFEE: true
    LIMIT: 10
    COMMANDS:
      JSCS: __dirname+'/../node_modules/.bin/jscs #{path} --reporter=inline --no-colors --config='+FILES.JSCS
      JSHINT: __dirname+'/../node_modules/.bin/jshint #{path} --config='+FILES.JSHINT
      COFFEELINT: __dirname+'/../node_modules/.bin/coffeelint -f '+FILES.COFFEELINT+' #{path}'
  
  if args.LIMIT
    CONFIGS.LIMIT = args.LIMIT
  
  if args.DIR
    CONFIGS.DIR = args.DIR
    
  if args.GLOBALS
    CONFIGS.APP_CONFIGS.JSHINT.predef = CONFIGS.APP_CONFIGS.JSHINT.predef.concat(args.GLOBALS)
  
  if args.COFFEE_ONLY
    CONFIGS.PROCESS_JS = false
  
  if args.JS_ONLY
    CONFIGS.PROCESS_COFFEE = false
    
  if args.CHARLIMIT?
    CONFIGS.APP_CONFIGS.JSCS.maximumLineLength.value = args.CHARLIMIT
    CONFIGS.APP_CONFIGS.COFFEELINT.max_line_length.value = args.CHARLIMIT
  
  CONFIGS.APP_CONFIGS.JSCS.maxErrors = CONFIGS.LIMIT
  CONFIGS.APP_CONFIGS.JSHINT.maxerr = CONFIGS.LIMIT
  
  CONFIGS
  
displayReport = (report) ->
  for own file, lines of report
    console.log('\x1b[1m','\x1b[31m')
    console.log(file+' :','\x1b[0m')
    max = 5    

    for own number, msgs of lines
      for msg in msgs

        if number.toString().length < max
          displayNumber = ''
          i = max - number.toString().length
          while i--
            displayNumber += ' '

          displayNumber += number
        else
          displayNumber = number

        console.log('\x1b[2m', displayNumber+' |','  ','\x1b[0m', msg)

module.exports =
  run: () ->
    CONFIGS = getConfigs()
    
    FOUNDERRORS = 
      JSCS: 0
      JSHINT: 0
      COFFEELINT: 0
      
    setUp(CONFIGS)
    
    report = {}

    targets = walker(CONFIGS.DIR, 'js')
    queue = []
  
    if CONFIGS.PROCESS_JS
      for target in targets
        do (target) ->
          queue.push(
            (cb) ->
              if FOUNDERRORS.JSCS >= CONFIGS.LIMIT
                cb(null,null)
                return
              
              exec(CONFIGS.COMMANDS.JSCS.replace(/#\{path\}/gi, target), (error, stdout, stderr) ->
                if stderr
                  cb(stderr,null)
                else
                  issues = stdout.split('\n').filter((i)->
                    i.length
                  )

                  obs = []

                  for issue in issues
                    reg = new RegExp('(.+?):\\sline\\s(\\d+),\\scol\\s\\d+,\\s(.+)','gi')
                    if reg.test(issue)
                      split = issue.split(reg)
                      if split[3].indexOf('[stdin]') is -1 and FOUNDERRORS.JSCS < CONFIGS.LIMIT
                        FOUNDERRORS.JSCS++

                        obs.push(
                          file: split[1].replace(CONFIGS.DIR,'')
                          line: split[2]
                          msg: split[3]
                        )

                  cb(null, if not obs.length then null else obs)
            )
          )
          
          queue.push(
            (cb) ->
              if FOUNDERRORS.JSHINT >= CONFIGS.LIMIT
                cb(null,null)
                return
            
              exec(CONFIGS.COMMANDS.JSHINT.replace(/#\{path\}/gi, target), (error, stdout, stderr) ->
                if stderr
                  cb(stderr,null)
                else
                  issues = stdout.split('\n').filter((i)->
                    i.length
                  )

                  obs = []

                  for issue in issues
                    reg = new RegExp('(.+?):\\sline\\s(\\d+),\\scol\\s\\d+,\\s(.+)','gi')
                    if reg.test(issue)
                      split = issue.split(reg)
                      if split[3].indexOf('Too many errors') is -1 and split[3].indexOf('[stdin]') is -1 and FOUNDERRORS.JSHINT < CONFIGS.LIMIT
                        FOUNDERRORS.JSHINT++

                        obs.push(
                          file: split[1].replace(CONFIGS.DIR,'')
                          line: split[2]
                          msg: split[3]
                        )

                  cb(null, if not obs.length then null else obs)
            )
          )
    
    if CONFIGS.PROCESS_COFFEE
      targets = walker(CONFIGS.DIR, 'coffee')

      for target in targets
        do (target) ->
          queue.push(
            (cb) ->
              if FOUNDERRORS.COFFEELINT >= CONFIGS.LIMIT
                cb(null,null)
                return
            
              exec(CONFIGS.COMMANDS.COFFEELINT.replace(/#\{path\}/gi, target), (error, stdout, stderr) ->
                if stderr
                  cb(stderr,null)
                else
                  issues = stdout.split('\n').filter((i)->
                    i.length
                  )

                  obs = []

                  if issues.length
                    file = issues[0].replace(/(.*?)([A-Za-z0-9\-_\.\/\\]+)/gi, '$2')
                    issues = issues.slice(1)

                    for issue in issues
                      if /#\d+/.test(issue)
                        split = issue.split(/(.*?)#(\d+):\s+(.*?)/gi)
                        if split[4].indexOf('[stdin]') is -1 and FOUNDERRORS.COFFEELINT < CONFIGS.LIMIT
                          FOUNDERRORS.COFFEELINT++
                          
                          obs.push(
                            file: file.replace(CONFIGS.DIR,'')
                            line: split[2]
                            msg: split[4]
                          )

                  cb(null, if not obs.length then null else obs)
            )
          )
    
    if not queue.length
      console.log('No files found to process')
      process.exit(1)
    
    async.series(queue,(err,results)->
      console.log(
        '\x1b[2m',
        '__________________________________________________________________________________________________',
        '\x1b[0m'
      )

      if err
        console.log('\x1b[31m',err,'\x1b[0m')
      else
        if not results.length or results.every((i)->
          i is null
        )
          console.log('\x1b[1m','\x1b[32m', 'No errors found!','\x1b[0m')
        else
          for res in results
            if res isnt null
              for sub in res
                if not report[sub.file]
                  report[sub.file] = {}

                if not report[sub.file][sub.line]
                  report[sub.file][sub.line] = []  

                report[sub.file][sub.line].push(sub.msg)
          
          displayReport(report)

      tearDown()
    )
