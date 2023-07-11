
project args.projectName, {
    procedure 'Create Test Commit', {
        resourceName = args.resourceName

        formalParameter 'dirName', defaultValue: '', {
            description = ''
            expansionDeferred = '0'
            label = null
            orderIndex = null
            required = '1'
            type = 'entry'
        }

        formalParameter 'filename', defaultValue: '', {
            description = ''
            expansionDeferred = '0'
            label = null
            orderIndex = null
            required = '1'
            type = 'entry'
        }

        formalParameter 'comment', defaultValue: '', {
            type = 'textarea'
        }

        step 'Ensure Directory', {
            command = 'mkdir $[dirName]'
            condition = ''
            errorHandling = 'ignore'
            exclusiveMode = 'none'
        }

        step 'Workfold', {

            command = '''tf workfold /map \"$/test_tfs\" \".\" /collection:\"${args.collection}\" /workspace:\"test1\" /login:\"${args.username},${args.password}\"
tf get /login:\"${args.userName},${args.password}\"'''
            condition = ''
            errorHandling = 'failProcedure'

            workingDirectory = '$[dirName]'
            workspaceName = ''
        }

        step 'Create File', {
            description = ''
            alwaysRun = '0'
            broadcast = '0'
            command = '''def file = new File(\"$[filename]\")
file.append(\"test\")
'''
            condition = ''
            errorHandling = 'failProcedure'
            exclusiveMode = 'none'
            logFileName = ''
            parallel = '0'
            postProcessor = ''
            precondition = ''
            projectName = 'TFS'
            releaseMode = 'none'
            resourceName = ''
            shell = 'ec-groovy'
            subprocedure = null
            subproject = null
            timeLimit = ''
            timeLimitUnits = 'minutes'
            workingDirectory = '$[dirName]'
            workspaceName = ''
        }

        step 'Checkin', {
            description = ''
            alwaysRun = '0'
            broadcast = '0'
            command = '''tf add $[filename] 
tf checkin /comment:"$[comment]" /noprompt /login:\"${args.username},${args.password}\"'''
            condition = ''
            errorHandling = 'failProcedure'
            exclusiveMode = 'none'
            logFileName = ''
            parallel = '0'
            postProcessor = ''
            precondition = ''
            projectName = 'TFS'
            releaseMode = 'none'
            resourceName = ''
            shell = ''
            subprocedure = null
            subproject = null
            timeLimit = ''
            timeLimitUnits = 'minutes'
            workingDirectory = '$[dirName]'
            workspaceName = ''
        }

    }
}