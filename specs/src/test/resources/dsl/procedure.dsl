def projName = args.projectName
def procName = args.procedureName
def params = args.params

project projName, {
    resourceName = args.resourceName

    procedure procName, {

        params.each { k, v ->
            formalParameter k, defaultValue: v, {
                type = 'textarea'
            }
        }

        step procName, {
            subproject = '/plugins/ECSCM-TFS/project'
            subprocedure = procName

            params.each { k, v ->
                actualParameter k, '$[' + k + ']'
            }
        }
    }
}