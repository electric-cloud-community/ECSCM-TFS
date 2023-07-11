####################################################################
#
# ECSCM::TFS::Cfg: Object definition of a TFS SCM configuration.
#
####################################################################
package ECSCM::TFS::Cfg;
use base qw(ECSCM::Base::Cfg);

####################################################################
# Object constructor for ECSCM::TFS::Cfg
#
# Inputs
#   cmdr  = a previously initialized ElectricCommander handle
#   name  = a name for this configuration
####################################################################
sub new {
    my $class = shift;
    return $class->SUPER::new(@_);
}

####################################################################
# TFSHost
####################################################################
sub getTFSHost {
    my ($self) = @_;
    return $self->get("TFSHost");
}
sub setTFSHost {
    my ($self, $name) = @_;
    print "Setting TFSHost to $name\n";
    return $self->setServer("$name");
}

####################################################################
# TFSPort
####################################################################
sub getTFSPort {
    my ($self) = @_;
    return $self->get("TFSPort");
}
sub setTFSPort {
    my ($self, $name) = @_;
    print "Setting TFSPort to $name\n";
    return $self->set("TFSPort", "$name");
}

####################################################################
# Credential
####################################################################
sub getCredential {
    my ($self) = @_;
    return $self->get("Credential");
}

sub setCredential {
    my ($self, $name) = @_;
    print "Setting Credential to $name\n";
    return $self->set("Credential", "$name");
}

1;

