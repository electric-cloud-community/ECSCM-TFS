@files = (
    ['//property[propertyName="ECSCM::TFS::Cfg"]/value',    'ECSCM/TFS/Cfg.pm'],
    ['//property[propertyName="ECSCM::TFS::Driver"]/value', 'ECSCM/TFS/Driver.pm'],
    ['//property[propertyName="checkout"]/value',           'tfsCheckoutForm.xml'],
    ['//property[propertyName="preflight"]/value',          'tfsPreflightForm.xml'],
    ['//property[propertyName="sentry"]/value',             'tfsSentryForm.xml'],
    ['//property[propertyName="trigger"]/value',            'tfsTriggerForm.xml'],
    ['//property[propertyName="createConfig"]/value',       'tfsCreateConfigForm.xml'],
    ['//property[propertyName="editConfig"]/value',         'tfsEditConfigForm.xml'],
    ['//property[propertyName="ec_setup"]/value',           'ec_setup.pl'],

    ['//procedure[procedureName="CheckoutCode"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'tfsCheckoutForm.xml'],
    ['//procedure[procedureName="Preflight"]/propertySheet/property[propertyName="ec_parameterForm"]/value',    'tfsPreflightForm.xml'],

         );
