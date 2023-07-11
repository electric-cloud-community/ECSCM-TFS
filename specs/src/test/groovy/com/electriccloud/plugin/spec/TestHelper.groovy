package com.electriccloud.plugin.spec

import com.electriccloud.spec.PluginSpockTestSupport

class TestHelper extends PluginSpockTestSupport {
    static final String pluginName = 'ECSCM-TFS'

    def createConfig() {
        def property = dsl("getProperty('/plugins/ECSCM/project/scm_cfgs/$configName')")?.property?.propertyName
        if (property) {
            logger.info("Configuration exists")
            return
        }
        try {
            createPluginConfiguration(pluginName, configName, [binpath: ''], username, password, [:])
        } catch(Throwable e) {
            logger.info("Configuration creation failed")
        }
    }

    def getConfigName() {
        def colName = collection.replaceAll(/\//, '')
        return colName
    }

    def getUsername() {
        def username =  System.getenv('USERNAME')
        assert username
        return username
    }

    def getPassword() {
        def password = System.getenv('PASSWORD')
        assert password
        return password
    }

    def getCollection() {
        def collection = System.getenv('COLLECTION')
        assert collection
        return collection
    }

    def getResourceName() {
        def resourceName = System.getenv('RESOURCE_NAME')
        assert resourceName
        return resourceName
    }

    def getResourceHostname() {
        def resourceHostname = System.getenv('RESOURCE_HOSTNAME')
        assert resourceHostname
        return resourceHostname
    }

    def getServerFolder() {
        return '$/test_tfs'
    }

    def getTFSProject() {
        return 'test_tfs'
    }

    def ensureResource() {
        def hostname = getResourceHostname()
        def isWindows = System.getenv('IS_WINDOWS') ?: 0

        dsl """
def isWindows = $isWindows
workspace 'windows', {
  description = ''
  agentDrivePath = 'c:/ef/workspace'
  agentUncPath = ''
  agentUnixPath = ''
  local = '1'
  workspaceDisabled = '0'
  zoneName = 'default'
}


resource '${resourceName}', {
    hostName = '$hostname'

    if (isWindows) {
        workspaceName = 'windows'
    }
}
"""
    }

    def createCommit(String projectName, String commitText) {
        dslFile "dsl/commit.dsl", [
            projectName: projectName,
            username: username,
            password: password,
            collection: collection,
        ]

        runProcedure projectName, 'Create Test Commit', [dirName: 'c:\\tmp_tfs', comment: commitText, filename: 'testfile'], [], resourceName
    }
}
