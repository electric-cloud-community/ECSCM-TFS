use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 29;
use Test::VirtualModule qw(ElectricCommander ECSCM::Base::Driver ECSCM::TFS::Cfg);
use ECSCM::TFS::Driver;
use DateTime::Format::Strptime;

# Get caller sub name
sub whowasi { (caller(2))[3] }

# Read entire file into string
sub read_file {
    my ($file) = @_;

    return do {
        local $/ = undef;
        open my $fh, "<", $file or die "could not open $file: $!";
        <$fh>;
    };    
}

Test::VirtualModule->mock_sub('ElectricCommander',
    new => sub {
        return bless {}, 'ElectricCommander'
    }
);

Test::VirtualModule->mock_sub('ECSCM::Base::Driver',
    new => sub {
        my ($class) = @_;
        my $self = {_cfg => new ECSCM::TFS::Cfg()};
        return bless $self, $class;
    },
    getCfg => sub {
        my ($self) = @_;
        return $self->{_cfg};
    }
);

Test::VirtualModule->mock_sub('ECSCM::TFS::Cfg',
    new => sub {
        return bless {}, 'ECSCM::TFS::Cfg'
    },
    getSCMPluginName => sub {
        'ECSCM-TFS';
    },
    getName => sub {
        'ECSCM-TFS';
    },
    getRow => sub {
        ();
    }
);

Test::VirtualModule->mock_sub('ECSCM::TFS::Driver',
    retrieveUserCredential => sub {
        ('domain\\login', 'password');
    },
    issueWarningMsg => sub {},
    RunCommand => sub {
        my $self = shift;
        
        my $cmd = (split(/ /, $_[0]))[1];
        my $subname = (split(/::/, whowasi()))[-1];
    
        return read_file("t/$self->{runCommandSequence}-".$cmd.'-'.$subname.'.log');
    }
);

# Patterns for datetime formats
my $ftspec = DateTime::Format::Strptime->new(
   pattern => '%A, %h %d, %Y %l:%M:%S %p',
   time_zone => 'local'
);

my $stspec = DateTime::Format::Strptime->new(
   pattern => '%b %d, %Y %l:%M:%S %p',
   time_zone => 'local'
);

my $ec = new ElectricCommander();
my $tfs = new ECSCM::TFS::Driver($ec, 'ECSCM-TFS');
$tfs->{runCommandSequence} = '00';
$tfs->{isOnLinux} = 0;

$tfs->_bootstrap_options({binpath => ''});
is($tfs->{tf}, 'tf', 'Default command without path 1 - Windows');

$tfs->_bootstrap_options({});
is($tfs->{tf}, 'tf', 'Default command without path 2 - Windows');

$tfs->_bootstrap_options({binpath => 'C:\Program Files\TEE-1.2.0'});
is($tfs->{tf}, '"C:\Program Files\TEE-1.2.0\tf"', 'Quoted command path - Windows');

$tfs->_bootstrap_options({binpath => 'C:\ProgramFiles\TEE-1.2.0'});
is($tfs->{tf}, 'C:\ProgramFiles\TEE-1.2.0\tf', 'Unquoted command path - Windows');

$tfs->{isOnLinux} = 1;
$tfs->_bootstrap_options({binpath => ''});
is($tfs->{tf}, 'tf', 'Default command without path 1 - Linux');

$tfs->_bootstrap_options({});
is($tfs->{tf}, 'tf', 'Default command without path 2 - Linux');

$tfs->_bootstrap_options({binpath => '/Program Files/TFS-1.2.0'});
is($tfs->{tf}, '"/Program Files/TFS-1.2.0/tf"', 'Quoted command path - Linux');

$tfs->_bootstrap_options({binpath => '/opt/bin'});
is($tfs->{tf}, '/opt/bin/tf', 'Unquoted command path - Linux');

my $ft = 'Thursday, October 28, 2010 4:24:12 PM';
is($ftspec->parse_datetime($ft)->epoch, ECSCM::TFS::Driver::TFSstr2time($ft), 'TFSstr2time - 1');

my $st = 'Feb 11, 2015 1:01:05 PM';
is($stspec->parse_datetime($st)->epoch, ECSCM::TFS::Driver::TFSstr2time($st), 'TFSstr2time - 3');

is_deeply($tfs->_get_login_option({}), {login => 'domain\\\\login,password'}, '_get_login_option - lin');
is_deeply($tfs->_get_server_option({}), {}, '_get_server_option - empty');
is_deeply($tfs->_get_server_option({collection => 'collection'}), {collection => 'collection'}, '_get_server_option - collection');
is_deeply($tfs->_get_server_option({server => 'server'}), {server => 'server'}, '_get_server_option - server');
is_deeply($tfs->_get_server_option({collection => 'collection', server => 'server'}), {server => 'server'}, '_get_server_option - choose');

is($tfs->option("login", 'login,password'), '-login:"login,password"', '$tfs->option("server")');
is($tfs->option("server"), '-server', '$tfs->option("server")');
is($tfs->option("server", "server"), '-server:"server"', '$tfs->option("server", "server")');

is($tfs->options([
        'new',
        {},
        {"force" => 1},
        {"server" => "server"}
    ]), ' -new -force:1 -server:"server"', '$tfs->option("server", "server")');

my $history = $tfs->_tf('history', [
        {'_plain', '.'},
        'new',
        {"force" => 1},
        {"server" => "server"}]);
    
is($history, '/opt/bin/tf history . -new -force:1 -server:"server"', '$tfs->_tf history');

my ($pstart, $plen) = $tfs->_get_password_offsets({}, $history);
ok($pstart == 0 && $plen == 0, '$tfs->_get_password_offsets - nopass');

$history = $tfs->_tf('history', [
        {'_plain', '.'},
        'new',
        $tfs->_get_login_option(),
        {'force' => 1},
        {'server' => "server"}]);

is($history, '/opt/bin/tf history . -new -login:"domain\\\\login,password" -force:1 -server:"server"', '$tfs->_tf history pass');

($pstart, $plen) = $tfs->_get_password_offsets({tfsPassword => 'password'}, $history);
ok($pstart == 49 && $plen == 8, '$tfs->_get_password_offsets - pass');

$tfs->{isOnLinux} = 0;
is("/server", $tfs->option("server"), '$tfs->option("server")');
is("/server:\"server\"", $tfs->option("server", "server"), '$tfs->option("server", "server")');
is_deeply($tfs->_get_login_option({}), {'login' => 'domain\\login,password'}, '_get_login_option - win');

my ($changeset, $changeTimestamp) = $tfs->getSCMTag({});
ok($changeset == 7 && $changeTimestamp == $stspec->parse_datetime($st)->epoch, 'ECSCM::TFS:getSCMTag');

$tfs->{isOnLinux} = 1;
ok($tfs->isCommandOptionSupported('location') , 'Location option is supported');
$tfs->{runCommandSequence} = '01';
ok(!$tfs->isCommandOptionSupported('location'), 'Location option is not supported');
