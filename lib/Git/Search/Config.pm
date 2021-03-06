use strict;
use warnings FATAL => 'all';
package Git::Search::Config;
use Moo;

has 'config' => (
    is  => 'rw',
#    isa => HashRef,
    lazy => 1,
    builder => '_build_config',
);

=head2 _build_config

Construct the configuration file.
Config file is looked for in three locations:

    ENV
    git-search-local.conf
    git-search.conf

    The values will be merged with the precedent order being:
    ENV over
    git-search-local.conf over
    git-search.conf

=cut

sub _build_config {
    my ($self) = @_;

    warn "BUILD CONFIG" if $ENV{GIT_SEARCH_DEBUG};
    my $conf_file       =  'git-search.conf';
    my $local_conf_file = 'git-search-local.conf';
    my $env_conf_file   = $ENV{GIT_SEARCH_CONFIG};
    warn "ENV CONFIG: $ENV{GIT_SEARCH_CONFIG}" if ($ENV{GIT_SEARCH_DEBUG} and $ENV{GIT_SEARCH_CONFIG});

    my $conf       = $self->read_config($conf_file);
    my $local_conf = $self->read_config($local_conf_file);
    my $env_conf   = $self->read_config($env_conf_file);

    # The merge happens in pairs
    my $merged_conf = $self->merge_hash($local_conf, $conf);
       $merged_conf = $self->merge_hash($env_conf, $merged_conf);

    return $merged_conf;
}

=head2 read_config

    Args: a configuration file name
    Returns: a HashRef of configuration values

=cut

sub read_config {
    my ($self, $conf_file) = @_;

    my $config = {};
    if ( $conf_file && -r $conf_file ) {
        if ( not $config = do $conf_file ) {
            die qq/Can't do config file "$conf_file" EXCEPTION: $@/ if $@;
            die qq/Can't do config file "$conf_file" UNDEFINED: $!/ if not defined $config;
        }
    }

    return $config;
}

=head2 merge_hash

    Args: ($hash_ref_dominant, $hash_ref_subordinate)
    Returns: HashRef of the two merged with the dominant values
    chosen when they exist otherwise the subordinate values are used.

=cut

sub merge_hash {
    my ($self, $precedent, $subordinate) = @_;
    my @not = grep !exists $precedent->{$_}, keys %{$subordinate};
    @{$precedent}{@not} = @{$subordinate}{@not};
    return $precedent;
}


1;
