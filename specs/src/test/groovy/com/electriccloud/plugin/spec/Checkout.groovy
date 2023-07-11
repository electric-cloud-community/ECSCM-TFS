package com.electriccloud.plugin.spec

import spock.lang.Unroll
import spock.lang.Ignore


class Checkout extends TestHelper {
    static def projectName = 'ECSCM-TFS Checkout Specs'
    static def procedureName = 'CheckoutCode'

    def doSetupSpec() {
        deleteProject(projectName)
        createConfig()
        ensureResource()
        dslFile "dsl/procedure.dsl", [
            projectName: projectName,
            procedureName: procedureName,
            params: [
                config: configName,
                collection: '',
                createw: '',
                dest: '',
                serverfolder: '',
                workspace_location: '',
                workspacename: '',
                all: '',
                deletew: '',
                force: '',
                itemspec: '',
                overwrite: '',
                recursive: '',
                server: '',
                shelvesetName: '',
                shelvesetOwner: '',
                undoPendingChanges: '',
                version: '',
                workspace_template_name: ''
            ],
            resourceName: getResourceName()
        ]
    }

    @Unroll
    def 'local workspace server folder #sFolder, #itemspec'() {
        setup:
        dsl "deleteProperty('/projects/$projectName/procedures/$procedureName/ecscm_snapshots')"
        when:
        def workspaceName = randomize('test')
        def result = runProcedure(projectName, procedureName, [
            collection: collection,
            createw: '1',
            deletew: '1',
            dest: 'workspace',
            serverfolder: sFolder,
            workspace_location: 'local',
            workspacename: workspaceName,
            itemspec: itemspec,
        ], [], getResourceName())
        then:
        debug(result)
        assert result.outcome == 'success'
        logger.info(result.logs)
        checkProperties(result.jobId, itemspec)
        where:
        sFolder                    | itemspec
        serverFolder               | ''
        TFSProject + '/'           | 'test*'
        TFSProject                 | 'README*'
        "$TFSProject/"             | 'README*'
        TFSProject                 | '*'
        ''                         | '$/' + TFSProject + '/test*'
        TFSProject                 | '$/' + TFSProject + '/README*'
        '$/' + TFSProject          | 'README.md'
        '$/' + "$TFSProject/test1" | ''
    }


    @Ignore
    def 'remote workspace'() {
        when:
        def result = runProcedure(projectName, procedureName, [
            collection: collection,
            createw: '0',
            dest: 'workspace',
            serverfolder: serverFolder,
            workspace_location: 'server',
            workspacename: 'win'
        ], [], getResourceName())
        then:
        debug(result)
        assert result.outcome == 'success'
        checkProperties(result.jobId)
    }

    def checkProperties(jobId, itemspec) {
        def properties = getJobProperties(jobId)
        assert properties.ecscm_changeLogs
        logger.info(objectToJson(properties))
        def history = properties.ecscm_changeLogs.values().getAt(0)
        assert history
        if (itemspec) {
            itemspec = itemspec.replaceAll(/\*/, '')
            assert history =~ /\Q$itemspec/
        }
        return true
    }
}
