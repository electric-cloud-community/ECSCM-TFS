####################################################################
#
# ECSCM::TFS::Driver  Object to represent interactions with TFS.
#
####################################################################
package ECSCM::TFS::Driver;
use base qw(ECSCM::Base::Driver);

use ElectricCommander;
use Time::Local;
use File::Basename;
use File::Copy;
use File::Path;
use File::Spec;
use File::stat;
use File::Temp;
use FindBin;
use Sys::Hostname;
use Cwd;
use Getopt::Long;
use strict;


$|=1;

####################################################################
# Object constructor for ECSCM::TFS::Driver
#
# Inputs
#    cmdr          previously initialized ElectricCommander handle
#    name          name of this configuration
#
####################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;

    my ($cmdr, $name) = @_;

    my $cfg = new ECSCM::TFS::Cfg($cmdr, $name);
    if ($name ne "") {
        my $sys = $cfg->getSCMPluginName();
        if ($sys ne "ECSCM-TFS") { die "SCM config $name is not type ECSCM-TFS"; }
    }

    my $self = $class->SUPER::new($cmdr, $cfg);

    if ($^O =~ /MSWin/) {
        $self->{isOnLinux} = 0;
    } else {
        $self->{isOnLinux} = 1;
    }

    return $self;
}

sub _bootstrap_options {
    my ($self, $opts) = @_;

    my $tf = defined $opts->{binpath} ? $opts->{binpath} : '';

    if ($tf ne '') {
        if($self->{isOnLinux}) {
            $self->{tf} = qq|$tf/tf|;
        } else {
            $self->{tf} = qq|$tf\\tf|;
        }
    } else {
        $self->{tf} = qq|tf|;
    }

    if(defined $opts->{serverfolder}) {
        my $serverfolder = $opts->{serverfolder};

        if (!(substr($serverfolder, 0, 2) eq "\$/")) {
           $serverfolder = "\$/$serverfolder";
        }

        $opts->{serverfolder} = $serverfolder;
    }

    # Quote command if it contains spaces in path
    if ($self->{tf} =~ / /) {
        $self->{tf} = qq|"$self->{tf}"|;
    }
}

####################################################################
# isImplemented
####################################################################
sub isImplemented {
    my ($self, $method) = @_;

    if ($method eq 'getSCMTag' ||
        $method eq 'checkoutCode' ||
        $method eq 'apf_driver' ||
        $method eq 'cpf_driver') {
        return 1;
    } else {
        return 0;
    }
}

####################################################################
# get scm tag for sentry (continuous integration)
####################################################################
####################################################################
# getSCMTag
#
# Get the latest changelist on this branch/client
#
# Args:
# Return:
#    changeNumber - a string representing the last change sequence #
#    changeTime   - a time stamp representing the time of last change
####################################################################
sub getSCMTag {
    my ($self, $opts) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);

    foreach my $k (keys %row) {
        $self->debug("Reading $k=$row{$k} from config");
        $opts->{$k}="$row{$k}";
    }

    $self->_bootstrap_options($opts);

    if(!(defined $opts->{itemspec}) || ($opts->{itemspec} eq "")) {
        $opts->{itemspec} = ".";
    }

    my $itemspec = $opts->{itemspec};
    if (!(substr($itemspec, 0,2) eq "\$/")) {
        $itemspec = "\$/" . $opts->{itemspec};
    }

    my $serverOption = $self->_get_server_option($opts);
    my $loginOption = $self->_get_login_option($opts);

    # set the generic tfs command
    my $history = $self->_tf('history', [
        {'_plain' => qq|"$itemspec"|},
        $serverOption,
        $loginOption,
        'recursive',
        'noprompt',
        {'stopafter' => 1},
        {'format' => 'detailed'}]);

    my ($passwordStart, $passwordLength) = $self->_get_password_offsets($opts, $history);

    # run tfs
    my $cmdReturn = $self->RunCommand($history,
                {LogCommand=>1, LogResult => 1, IgnoreError=>1, HidePassword => 1,
                passwordStart => $passwordStart,
                passwordLength => $passwordLength} );

    #Changeset: 8
    #User: build
    #Date: Thursday, October 28, 2010 4:24:12 PM
    my $changeset = 0;
    my $changeTimestamp = 0;

    if($cmdReturn =~ /Changeset: ([\d]+)/){
        $changeset = $1;
        $cmdReturn =~ /Date: (.*)/;
        my $date = $1;
        $changeTimestamp = TFSstr2time($date);

        if ($changeTimestamp == 0) {
            $self->issueWarningMsg("Unexpected date output format for value: $date");
        }
    } else {
        $self->issueWarningMsg("tf history command failed to execute and couldn't retrieve data.");
    }

    return ($changeset, $changeTimestamp);
}

####################################################################
# createWorkspace
#
# Creates new TFS workspace
#
# Args:
#   expected in the $opts hash
#
# Return:
#    1      = success
#    undef  = failure
####################################################################
sub createWorkspace {
    my ($self, $opts) = @_;

    my $serverOption = $self->_get_server_option($opts);
    my $loginOption = $self->_get_login_option($opts);

    my $cmdopts = [
        'new',
        $serverOption,
        {'_plain' => qq|"$opts->{workspacename}"|},
        'noprompt',
        $loginOption
    ];

    if($opts->{workspace_location} && $self->isCommandOptionSupported('location')) {
        push(@{$cmdopts}, {'location' => $opts->{workspace_location}});
    }

    if($opts->{workspace_template_name}) {
        push(@{$cmdopts}, {'template' => $opts->{workspace_template_name}});
    }

    my $tfsCmd = $self->_tf('workspace', $cmdopts);

    my ($passwordStart, $passwordLength) = $self->_get_password_offsets($opts, $tfsCmd);

    # run command
    $self->RunCommand($tfsCmd, {
        LogCommand => 1,
        LogResult => 1,
        HidePassword => 1,
        passwordStart => $passwordStart,
        passwordLength => $passwordLength
    });

    1;
}

####################################################################
# isWorkspaceExists
#
# Checks whether TFS workspace exists
#
# Args:
#   expected in the $opts hash
#
# Return:
#    1      = workspace exists
#    0      = workspace does not exists
####################################################################
sub isWorkspaceExists {
    my ($self, $opts) = @_;

    my $serverOption = $self->_get_server_option($opts);
    my $loginOption = $self->_get_login_option($opts);

    #check if the workspace already exists
    #tf workfold -workspace:name
    my $tfsCmd = $self->_tf('workfold', [
        {workspace => $opts->{workspacename}},
          $serverOption,
          $loginOption
        ]);

    my @output=`$tfsCmd 2>&1`;
    my $found=1;

    foreach (@output) {
        # Windows:   TF14061: The workspace foo;Laurent Rochette does not exist.
        # Linux:     An argument error occurred: The workspace foo could not be found.
        if ((/TF\d+:\s+The workspace.*does not exist/) || (/An argument error occurred: The workspace .+ could not be found/)) {
            $found=0;
            last;
        }
    }

    return $found;
}

####################################################################
# isCommandOptionSupported
#
# Checks whether tf command supports option
#
# Args:
#   name - name of option
#
# Return:
#    1      = option supported
#    ''       = option is not supported
####################################################################
sub isCommandOptionSupported {
    my ($self, $name) = @_;

    my $output = $self->RunCommand($self->_tf('help', []), {
        LogCommand => 0,
        LogResult => 0
    });

    my $separator = $self->{isOnLinux} ? '-' : '/';
    return $output =~ /$separator$name:/;
}

###############################################################################
# code checkout routines
###############################################################################

####################################################################
# checkoutCode
#
# Checkout code
#
# Args:
#   expected in the $opts hash
#
#   dest
#   template (optional)
#
# Return:
#    1      = success
#    undef  = failure
####################################################################
sub checkoutCode {
    my ($self,$opts) = @_;

    #method variable
    my $here = getcwd();
    my $tfsCmd = "";
    $self->_bootstrap_options($opts);

    #Check for the required fields.
    if (! (defined $opts->{workspacename})) {
        warn "workspacename argument required in checkoutCode";
        return;
    }

    if (! (defined $opts->{dest})) {
        warn "dest argument required in checkoutCode";
        return;
    }

    if ( ($opts->{undoPendingChanges}) && ($opts->{itemspec} eq "")) {
       warn("Error: undo pending changes requires itemSpec to be defined");
       return;
    }

    #Change working directory.
    if (defined ($opts->{dest}) && ("$opts->{dest}" ne "." && "$opts->{dest}" ne "" )) {
        $opts->{dest} = File::Spec->rel2abs($opts->{dest});
        print "Changing to directory $opts->{dest}\n";
        mkpath($opts->{dest});
        if (!chdir $opts->{dest}) {
            print "could not change to directory $opts->{dest}\n";
            exit 1;
        }
    }

    my $serverOption = $self->_get_server_option($opts);
    my $loginOption = $self->_get_login_option($opts);

    #Create a workspace when requested.
    if($opts->{createw}) {
        if (!($opts->{serverfolder} eq "")) {
            if (!$self->isWorkspaceExists($opts)) {
                #create a new workspace
                $self->createWorkspace($opts);

            } else {
                printf("Workspace '%s' already exists. Skipping creation!\n", $opts->{workspacename});
            }

            #map the workspace to a local folder.
            $tfsCmd = $self->_tf('workfold', [
                'map',
                {'_plain' => qq|"$opts->{serverfolder}"|},
                {'_plain' => '"'.getcwd().'"'},
                $serverOption,
                $loginOption,
                {workspace => $opts->{workspacename}}
            ]);

            my ($passwordStart, $passwordLength) = $self->_get_password_offsets($opts, $tfsCmd);

            # run command
            $self->RunCommand($tfsCmd, {
                LogCommand => 1,
                LogResult => 1,
                HidePassword => 1,
                passwordStart => $passwordStart,
                passwordLength => $passwordLength
            });
        } else {
            $self->issueWarningMsg("Cannot map the workspace without the serverfolder agument");
        }
    }

    my $result=1;

    # tf undo command to Discards one or more pending changes to files or folders.
    # tf undo [/workspace:workspacename[;workspaceowner]]
    #         [/recursive] itemspec [/noprompt] [/login:username,[password]]
    #         [/collection:TeamProjectCollectionUrl]
    if ($opts->{undoPendingChanges}) {
        my $cmdopts = [{workspace => $opts->{workspacename}}];

        if($opts->{recursive}) {
            push(@{$cmdopts}, 'recursive');
        }

        if($opts->{itemspec}) {
            push(@{$cmdopts}, {'_plain' => qq|"$opts->{itemspec}"|});
        }

        push(@{$cmdopts}, ('noprompt', $loginOption, $serverOption));

        $tfsCmd = $self->_tf('undo', $cmdopts);

        my ($passwordStart, $passwordLength) = $self->_get_password_offsets($opts, $tfsCmd);

        $result |= $self->RunCommand($tfsCmd, {
            LogCommand => 1,
            IgnoreError => 1,
            LogResult => 1,
            HidePassword => 1,
            passwordStart => $passwordStart,
            passwordLength => $passwordLength
        });
    }

    #tf get command for downloading and updating the files.
    my $cmdopts = ['noprompt'];

    if($opts->{itemspec}) {
        push(@{$cmdopts}, {'_plain' => qq|"$opts->{itemspec}"|});
    }

    if($opts->{version}) {
        push(@{$cmdopts}, {'version' => $opts->{version}});
    }

    if($opts->{recursive}) {
        push(@{$cmdopts}, 'recursive');
    }

    if($opts->{all}) {
        push(@{$cmdopts}, 'all');
    }

    if($opts->{overwrite}) {
        push(@{$cmdopts}, 'overwrite');
    }

    if($opts->{force}) {
        push(@{$cmdopts}, 'force');
    }

    push(@{$cmdopts}, $loginOption);

    $tfsCmd = $self->_tf('get', $cmdopts);
    my ($passwordStart, $passwordLength) = $self->_get_password_offsets($opts, $tfsCmd);

    $result |= $self->RunCommand($tfsCmd, {
        LogCommand => 1,
        LogResult => 1,
        HidePassword => 1,
        passwordStart => $passwordStart,
        passwordLength => $passwordLength
    });

    # tf unshelve  for restoring shelved files.
    # tf unshelve [/move] [shelvesetname[;username]] itemspec
    #             [/recursive] [/noprompt][/login:username,[password]]
    my $shelvesetName = $opts->{shelvesetName};

    if ($shelvesetName ne '') {
        $cmdopts = [];

        if ($^O=~ /MSWin/) {
            $shelvesetName .= qq|;$opts->{shelvesetOwner}|;
        } else {
            $shelvesetName .= qq|\\;$opts->{shelvesetOwner}|;
        }

        push(@{$cmdopts}, {'_plain' => $shelvesetName});

        if($opts->{recursive}) {
            push(@{$cmdopts}, 'recursive');
        }

        push(@{$cmdopts}, ($loginOption, 'noprompt'));

        $tfsCmd = $self->_tf('unshelve', $cmdopts);
        my ($passwordStart, $passwordLength) = $self->_get_password_offsets($opts, $tfsCmd);

        $result |= $self->RunCommand($tfsCmd, {
            LogCommand => 1,
            LogResult => 1,
            HidePassword => 1,
            passwordStart => $passwordStart,
            passwordLength => $passwordLength
        });


    }

    $self->generateChangelog($opts);

    if($opts->{deletew}) {
        $tfsCmd = $self->_tf('workspace', [
            'delete',
            {'_plain' => qq|"$opts->{workspacename}"|},
            'noprompt',
            $loginOption
        ]);

        ($passwordStart, $passwordLength) = $self->_get_password_offsets($opts, $tfsCmd);

        $self->RunCommand($tfsCmd, {
            LogCommand => 1,
            LogResult => 1,
            HidePassword => 1,
            passwordStart => $passwordStart,
            passwordLength => $passwordLength
        });
    }

    chdir $here;
    return $result;
}


sub generateSCMKey {
    my ($self, $opts) = @_;

    my @parts = qw(TFS);
    # workspace name is required
    push @parts, $opts->{workspacename};
    return join('-', @parts);
}


sub generateChangelog {
    my ($self, $opts) = @_;

    my $workspace = $opts->{workspacename};
    my $collection = $opts->{collection};
    $collection =~ s/\///g;
    my $scmKey = $self->generateSCMKey($opts);

    my $serverOption = $self->_get_server_option($opts);
    my $loginOption = $self->_get_login_option($opts);
    my $start = $self->getStartForChangeLog($scmKey);

    my $tfsCmd;

    my $folder = $opts->{serverfolder};
    if ($opts->{itemspec}) {
        if ($opts->{itemspec} =~ /^\$\// || $folder eq '$/') {
            $folder = $opts->{itemspec};
        }
        else {
            $folder .= '/' . $opts->{itemspec};
        }
        $folder =~ s{//}{/}g;
    }

    if ($start) {
        # Diff between two changesets
        $tfsCmd = $self->_tf('history', [
            {_plain => qq|"$folder"|},
            'noprompt',
            'recursive',
            $serverOption,
            {format => 'detailed'},
            {version => "C$start~T"},
            $loginOption
        ]);
    }
    else {
        # Only the last changeset
        $tfsCmd = $self->_tf('history', [
            {_plain => $folder},
            'noprompt',
            'recursive',
            $serverOption,
            {format => 'detailed'},
            {version => "T"},
            {stopafter => 1},
            $loginOption
        ]);
    }
    my ($passwordStart, $passwordLength) = $self->_get_password_offsets($opts, $tfsCmd);
    my $result = '';
    eval {
        # It will not die....
        $result = $self->RunCommand($tfsCmd, {
            LogCommand => 1,
            LogResult => 1,
            HidePassword => 1,
            passwordStart => $passwordStart,
            passwordLength => $passwordLength,
        });
        1;
    } or do {
        print "history command failed, the history will not be retrieved\n";
    };

    my $changelog = $self->parseChangelog($result);
    unless (scalar @$changelog) {
        print "No changelogs found\n";
        return;
    }
    my $last = shift @$changelog;
    my $snapshot = $last->{changeset};

    $self->setPropertiesOnJob($scmKey, $snapshot, $result);
    $self->updateLastGoodAndLastCompleted($opts);
}

sub parseChangelog {
    my ($self, $history) = @_;

    my @parts = split(/-{10,}/, $history);
    my $log = [];
    for my $part (@parts) {
        my ($changeset) = $part =~ /Changeset:\s(\d+)/m;
        next unless $changeset;
        my ($user) = $part =~ /User:\s(\w+)/;
        # TODO

        push @$log, {changeset => $changeset, user => $user};
    }
    return $log;
}

####################################################################
# agent preflight functions
####################################################################

#------------------------------------------------------------------------------
# apf_getScmInfo
#
#       If the client script passed some SCM-specific information, then it is
#       collected here.
#------------------------------------------------------------------------------

sub apf_getScmInfo
{
    my ($self,$opts) = @_;

    my $scmInfo = $self->pf_readFile("ecpreflight_data/scmInfo");
    $scmInfo =~ m/(.*)\n(.*)\n(.*)\n(.*)\n(.*)\n(.*)/;
    $opts->{collection} = $2;
    $opts->{server} = $3;
    $opts->{scm_lastchange} = $4;
    $opts->{serverfolder} = $5;
    $opts->{workspacename} = "temp.workspace.jobid." . $opts->{rt_jobId};
    $opts->{createw} = 1;
    $opts->{deletew} = 1;
    print("TFS information received from client:\n"
            . "TFS URL: $opts->{TFSUrl}\n"
            . "Version: $opts->{TFSVersion}\n"
            . "Collection: $opts->{collection}\n"
            . "Server: $opts->{server}\n"
            . "Workspace name: $opts->{workspacename}\n"
            . "createw: $opts->{createw}\n"
            . "deletew: $opts->{deletew}\n\n");
}

#------------------------------------------------------------------------------
# apf_createSnapshot
#
#       Create the basic source snapshot before overlaying the deltas passed
#       from the client.
#------------------------------------------------------------------------------

sub apf_createSnapshot
{
    my ($self,$opts) = @_;
    $self->checkoutCode($opts);
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------

sub apf_driver()
{
    my ($self,$opts) = @_;

    if ($opts->{test}) { $self->setTestMode(1); }
    $opts->{delta} = "ecpreflight_files";

    $self->_bootstrap_options($opts);

    $self->apf_downloadFiles($opts);
    $self->apf_transmitTargetInfo($opts);
    $self->apf_getScmInfo($opts);
    $self->apf_createSnapshot($opts);
    $self->apf_deleteFiles($opts);
    $self->apf_overlayDeltas($opts);
}


####################################################################
# client preflight file
####################################################################

#------------------------------------------------------------------------------
# tfs
#
#       Runs an tf command.  Also used for testing, where the requests and
#       responses may be pre-arranged.
#------------------------------------------------------------------------------
sub cpf_tfs {
    my ($self,$opts,$command, $options) = @_;

    $self->cpf_debug("Running TF command \"$command\"");

    if ($opts->{opt_Testing}) {
        my $request = uc("tf_$command");
        $request =~ s/[^\w]//g;
        if (defined($ENV{$request})) {
            return $ENV{$request};
        } else {
            $self->cpf_error("Pre-arranged command output not found in ENV");
        }
    } else {
        return $self->RunCommand($command, $options);
    }
}

#------------------------------------------------------------------------------
# copyDeltas
#
#       Finds all new and modified files, and calls putFiles to upload them
#       to the server.
#------------------------------------------------------------------------------
sub cpf_copyDeltas()
{
    my ($self,$opts) = @_;
    my $numFiles = 0;
    my $here = getcwd();

    $self->cpf_display("Collecting delta information");

    $self->cpf_saveScmInfo($opts,$opts->{workspace} ."\n"
            . $opts->{collection} ."\n"
            . $opts->{server} ."\n"
            . $opts->{scm_lastchange} ."\n"
            . $opts->{serverfolder} ."\n"
            . $opts->{localfolder});

    $self->cpf_findTargetDirectory($opts);
    $self->cpf_createManifestFiles($opts);

    if (defined ($opts->{localfolder}) && ("$opts->{localfolder}" ne "." && "$opts->{localfolder}" ne "" )) {
        $opts->{localfolder} = File::Spec->rel2abs($opts->{localfolder});
        print "Changing to directory $opts->{localfolder}\n";
        mkpath($opts->{localfolder});
        if (!chdir $opts->{localfolder}) {
            print "could not change to directory $opts->{localfolder}\n";
            exit 1;
        }
    }

    # Collect a list of opened files.
    my $cmd = $self->_tf('status', [
        {'workspace' => $opts->{workspace}},
        {'format' => 'detailed'}
    ]);

    my $output = $self->cpf_tfs($opts, $cmd);
    my @lines = split(/\n\n/, $output);
    my $openedFiles = "";
    my $target = length($opts->{serverfolder});
    foreach my $line (@lines) {
        # Parse the output from tf status and figure out the file name and what
        # type of change is being made.
        if($line =~ /Local item : \[([\w\ ]+)\] ([\w\.\:\ \/\\]+)/) {
            my $source = $2;
            $openedFiles .= $source;

            $line =~ /(\$\/)([\w\.\:\ \/]+)/;
            my $dest = $1 . $2;
            if(substr($dest, 0, $target) eq $opts->{serverfolder}) {
                $dest = substr($dest, $target + 1);
            }

            $line =~ /Change     : ([\w\ ]+)/;
            my $type = $1;

            # Add all files that are not deletes to the putFiles operation.
            if ($type ne "delete") {
                $self->cpf_addDelta($opts, $source, $dest);
            } else {
                $self->cpf_addDelete($dest);
            }
            $numFiles ++;
        }
    }

    $opts->{rt_openedFiles} = $openedFiles;
    chdir $here;
    # If there aren't any modifications, warn the user, and turn off auto-
    # commit if it was turned on.

    if ($numFiles == 0) {
        my $warning = "No files are currently open";
        if ($opts->{scm_autoCommit}) {
            $warning .= ".  Auto-commit has been turned off for this build";
            $opts->{scm_autoCommit} = 0;
        }
        $self->cpf_error($warning);
    } else {
        $self->cpf_closeManifestFiles($opts);
        $self->cpf_uploadFiles($opts);
    }
}

#------------------------------------------------------------------------------
# autoCommit
#
#       Automatically commit changes in the user's client.  Error out if:
#       - A check-in has occurred since the preflight was started, and the
#         policy is set to die on any check-in.
#       - A check-in has occurred and opened files are out of sync with the
#         head of the branch.
#       - A check-in has occurred and non-opened files are out of sync with
#         the head of the branch, and the policy is set to die on any changes
#         within the client workspace.
#------------------------------------------------------------------------------
sub cpf_autoCommit()
{
    my ($self,$opts) = @_;

    # Make sure none of the files have been touched since the build started.
    $self->cpf_checkTimestamps($opts);

    if (defined ($opts->{localfolder}) && ("$opts->{localfolder}" ne "." && "$opts->{localfolder}" ne "" )) {
        $opts->{localfolder} = File::Spec->rel2abs($opts->{localfolder});
        print "Changing to directory $opts->{localfolder}\n";
        mkpath($opts->{localfolder});
        if (!chdir $opts->{localfolder}) {
            print "could not change to directory $opts->{localfolder}\n";
            exit 1;
        }
    }

    # Collect a list of opened files.
    my $cmd = $self->_tf('status', [
        {'workspace' => $opts->{workspace}},
        {'format' => 'detailed'}
    ]);

    my $output = $self->cpf_tfs($opts, $cmd);
    my @lines = split(/\n\n/, $output);
    my $openedFiles = "";

    foreach my $line (@lines) {
        # Parse the output from tf status and figure out the file name and what
        # type of change is being made.

        if($line =~ /Local item : \[([\w\ ]+)\] ([\w\.\:\ \/\\]+)/) {
            my $source = $2;
            $openedFiles .= $source;
        }
    }

    # If any file have been added or removed, error out.
    if ($openedFiles ne $opts->{rt_openedFiles}) {
        $self->cpf_error("Files have been added and/or removed from the selected "
                . "changelists since the preflight build was launched");
    }

    # Commit the changes.
    $self->cpf_display("Committing changes");

    $cmd = $self->_tf('checkin', [
        'noprompt',
        {'comment' => $opts->{scm_commitComment}}
    ]);

    $self->cpf_tfs($opts, $cmd);
    $self->cpf_display("Changes have been successfully submitted");
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------
sub cpf_driver
{
    my ($self,$opts) = @_;
    my $here = getcwd();

    $::gHelpMessage .= "
TFS Options:
  --server <url>        This is the equivalent value to Collection in VS2008
                        andunder. If you fill this entry, it will assume that
                        you're using TF version VS2008 or under. It will use
                        the option /server in the preflight. This field is
                        required if you have VS2008.
  --collection <url>    This is the URL that points to the /collection. This
                        value is used for VS2010. If you specify this value,
                        the command will use the option /collection when
                        executing the tf query for the preflight. This field
                        is required if you have VS2010.
  --localfolder         The path to the locally accessible source directory
                        in which changes have been made.  This is generally
                        the path to the root of the workspace.
  --workspace <workspace>      The value of the workspace where is the
                               data for the preflight.

  --binpath <path>      Path to the TFS bin directory, If not specified the plugin will
                        assume that TFS is in the PATH of the agent machine.
";

    $self->cpf_display("Executing TFS actions for ecpreflight");

    my %ScmOptions = (
        "server=s"                => \$opts->{server},
        "collection=s"            => \$opts->{collection},
        "workspace=s"             => \$opts->{workspace},
        "localfolder=s"           => \$opts->{localfolder},
        "binpath=s"               => \$opts->{binpath},
    );

    Getopt::Long::Configure("default");
    if (!GetOptions(%ScmOptions)) {
        $self->cpf_error($::gHelpMessage);
    }

    if ($::gHelp eq "1") {
        $self->cpf_display($::gHelpMessage);
        return;
    }

    $self->extractOption($opts,"server", { env => "SERVER"});
    $self->extractOption($opts,"collection", { env => "COLLECTION" });
    $self->extractOption($opts,"workspace", { env => "WORKSPACE", required => 1 });
    $self->extractOption($opts,"localfolder", { env => "LOCALFOLDER" });
    $self->extractOption($opts,"binpath", { env => "BINPATH" });

    # If the preflight is set to auto-commit, require a commit comment.
    if ($opts->{scm_autoCommit} &&
            (!defined($opts->{scm_commitComment})|| $opts->{scm_commitComment} eq "")) {
        $self->cpf_error("Required element \"scm/commitComment\" is empty or absent in "
                . "the provided options.  May also be passed on the command "
                . "line using --commitComment");
    }

    $self->_bootstrap_options($opts);

    my $workspaces = $self->_tf('workspaces', [
        {'_plain' => qq|"$opts->{workspace}"|},
        {'format' => 'detailed'}
    ]);

    # run tfs
    my $cmdReturn = $self->RunCommand($workspaces, {IgnoreError=>1} );
    $cmdReturn =~ /Working folders:\n ([\$\/\w\d\ ]+): (.*)/;
    $opts->{serverfolder} = $1;
    $opts->{localfolder} = $2;

    #TODO: tf history
    my $serverOption = $self->_get_server_option($opts);

    #Change working directory.
    if (defined ($opts->{localfolder}) && ("$opts->{localfolder}" ne "." && "$opts->{localfolder}" ne "" )) {
        $opts->{localfolder} = File::Spec->rel2abs($opts->{localfolder});
        print "Changing to directory $opts->{localfolder}\n";
        mkpath($opts->{localfolder});
        if (!chdir $opts->{localfolder}) {
            print "could not change to directory $opts->{localfolder}\n";
            exit 1;
        }
    }

    my $history = $self->_tf('history', [
        {'_plain' => qq|\$/.|},
        $serverOption,
        'recursive',
        'noprompt',
        {'stopafter' => 1},
        {'format' => 'detailed'}
    ]);

    # run tfs
    $cmdReturn = $self->RunCommand($history, {IgnoreError=>1} );
    $cmdReturn =~ /Changeset: ([\d]+)/;
    $opts->{scm_lastchange} = $1;

    $self->cpf_debug("Workspace: ".$opts->{workspace});
    $self->cpf_debug("Latest revision: ".$opts->{scm_lastchange});
    $self->cpf_debug("Collection: ".$opts->{collection});
    $self->cpf_debug("Server: ".$opts->{server});
    $self->cpf_debug("Server folder: ".$opts->{serverfolder});

    chdir $here;

    # Copy the deltas to a specific location.
    $self->cpf_copyDeltas($opts);

    # Auto commit if the user has chosen to do so.
    if ($opts->{scm_autoCommit}) {
        if (!$opts->{opt_Testing}) {
            $self->cpf_waitForJob($opts);
        }
        $self->cpf_autoCommit($opts);
    }
}

##########################################################################
#  _get_password_offsets
#
#  Get password offset and length in passed command line string
#
#   Params:
#       cmd      - name of tf command
#       opts     - reference to driver options
#       cmd      - command line
#
#   Returns:
#       Array consisting of password offset and length
#
##########################################################################
sub _get_password_offsets {
    my ($self, $opts, $cmd) = @_;
    my ($passwordStart, $passwordLength) = (0, 0);

    my $password = defined $opts->{tfsPassword} ? $opts->{tfsPassword} : '';

    #Get the lenght of the tfs password for hidding it in the commands.
    if (length($password) > 0) {
         if ($cmd =~ /login:.*\Q$password\E/) {
            $passwordStart = $+[0] - length($password);
        }

        $passwordLength = length($password);
    }

    return ($passwordStart, $passwordLength);
}

##########################################################################
#  _tf
#
#  Format tf command line
#
#   Params:
#       cmd      - name of tf command
#       options - reference to options array
#
#   Returns:
#       Formatted command line suitable for RunCommand
#
##########################################################################
sub _tf {
    my ($self, $cmd, $cmdopts) = @_;
    return $self->{tf}.' '.$cmd.$self->options($cmdopts);
}

##########################################################################
#  option
#
#  Option formatting helper function
#
#   Params:
#       name  - option's name
#       value - option's value
#
#   Returns:
#       Formatted option
#
##########################################################################
sub option
{
    my ($self, $name, $value) = @_;

    # Non -option, just plain argument
    if($name eq '_plain') {
        return $value;
    }

    my $option = ($self->{isOnLinux} ? '-' : '/') . $name;

    if(defined $value) {

        # Quote value, if its non-digit
        if($value =~ /^\d+$/) {
            $option .= ":$value";
        } else {
            $option .= ":\"$value\"";
        }
    }

    return $option;
}

##########################################################################
#  options
#
#  Options formatting helper function
#
#   Params:
#       options - reference to array of options
#
#   Returns:
#       Formatted options
#
##########################################################################
sub options
{
    my ($self, $opts) = @_;
    my $options = "";
    my $pwdloc = [];

    for my $option (@$opts) {
        my $type = ref $option;

        if(not $type) {
            $options .= " " . $self->option($option);
        } else {
            my ($name, $value) = %$option;

            if(defined $name && defined $value) {
                $options .= " " . $self->option($name, $value);
            }
        }
    }

    return $options;
}

##########################################################################
#  _get_login_option
#
#  Get login credentials, and format them as option hashref
#
#   Params:
#       opts     - reference to driver options
#
#   Returns:
#       Hashref, containing credentials, e.g. {login => 'login,password'}
#
##########################################################################
sub _get_login_option {
    my ($self, $opts) = @_;
    my $login = {};

    # Load userName and password from the credential
    ($opts->{tfsUserName}, $opts->{tfsPassword}) =
        $self->retrieveUserCredential($opts->{credential},
        $opts->{tfsUserName}, $opts->{tfsPassword});

    # The potential \ in username i.e. DOMAIN\username needs to be escaped on
    # linux
    if ($self->{isOnLinux} && $opts->{tfsUserName} =~ m/\\/) {
        $opts->{tfsUserName} =~ s/\\/\\\\/;
    }

    if(length ($opts->{tfsUserName})) {
        my $credentials = $opts->{tfsUserName};

        if(length ($opts->{tfsPassword})) {
            $credentials .= ',' . $opts->{tfsPassword};
        }

        $login = {'login' => $credentials};
    }

    return $login;
}

##########################################################################
#  _get_login_option
#
#  Get server option depending of TFS version selected
#
#   Params:
#       opts     - reference to driver options
#
#   Returns:
#       Hashref, containing server information,
#        {server => 'server_opt'}
#        {collection => 'collection_opt'}
#
##########################################################################
sub _get_server_option {
    my ($self, $opts) = @_;

    # Depending on the TFS version, it must be use the option /collection (VS2010) or
    # /server (VS2008 or earliear). If the two values are provided, it will take the server
    # option. If no value is provided, it can't perform the tf history query.
    my $serverOption = {};

    my $collection = defined $opts->{collection} ? $opts->{collection} : '';
    my $server = defined $opts->{server} ? $opts->{server} : '';

    if ($collection eq "" && $server eq "") {
        $self->issueWarningMsg("You must specify either a server or a team collection. Driver requires at least one of these values.");
    } elsif (!($collection eq "") && !($server eq "")) {
        $serverOption = {"server" => $server};
        $self->issueWarningMsg("There are two values for server and collection. You must choose one according with your TFS Version.");
    } elsif (!($collection eq "")) {
        $serverOption = {"collection" => $collection};
    } elsif (!($server eq "")) {
        $serverOption = {"server" => $server};
    }

    return $serverOption;
}

##########################################################################
#  TFSstr2time
#
#  Convert a date/time string in TFS format to standard time representation.
#
#   Params:
#       timeStr - a string containing the time/date in TFS form
#
#   Returns:
#       t - integer number of seconds since epoch
#
##########################################################################
sub TFSstr2time
{
    my $timeStr = shift;
    my $changeTimestamp = 0;
    my $hr = 0;

    if($timeStr =~ /([\w]+), ([\w]+) ([\d]+), ([\d]+) ([\d]+):([\d]+):([\d]+) (\w{2})/){
        #Thursday, October 28, 2010 4:24:12 PM
        my @months = ("January", "February", "March", "April", "May", "June", "July",
                            "August", "September", "October", "November", "December" );

        # Handle AM/PM (convert to 24-hour time)
        $hr = $5;
        $hr = $hr + 12 if ($8 eq 'PM' && $hr < 12);
        $hr = 0        if ($8 eq 'AM' && $hr == 12);

        my $search_for = $2;
        my( $index )= grep { $months[$_] eq $search_for } 0..$#months;

        if(defined $index){
            $changeTimestamp =  timelocal($7, $6, $hr, $3, $index, $4-1900);
        }
    }

    if ($changeTimestamp==0 && $timeStr =~ /([\w]+) ([\d]+), ([\d]+) ([\d]+):([\d]+):([\d]+) (\w{2})/) {
        #Aug 5, 2010 6:22:00 PM
        my @shortMonth = ( "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul",
                            "Aug", "Sep", "Oct", "Nov", "Dec" );

        # Handle AM/PM (convert to 24-hour time)
        $hr = $4;
        $hr = $hr + 12 if ($7 eq 'PM' && $hr < 12);
        $hr = 0        if ($7 eq 'AM' && $hr == 12);

        my $search_for = $1;
        my( $index )= grep { $shortMonth[$_] eq $search_for } 0..$#shortMonth;

        if(defined $index){
            $changeTimestamp =  timelocal($6, $5, $hr, $2, $index, $3-1900);
        }
    }

    if ($changeTimestamp==0 && uc($timeStr) =~ /(\d+):(\d+):(\d+)(\ )?(AM|PM)?/) {
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

        # Handle AM/PM (convert to 24-hour time)
        $hr = $1;
        if(defined $5) {
            $hr = $hr + 12 if ($5 eq 'PM' && $hr < 12);
            $hr = 0        if ($5 eq 'AM' && $hr == 12);
        }
        $changeTimestamp =  timelocal($3, $2, $hr, $mday, $mon, $year);

        if($changeTimestamp > timelocal(localtime)) {
            $changeTimestamp -= (24 * 60 * 60);
        }
    }

    return $changeTimestamp;
}

1;
