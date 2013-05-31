use strict;
use warnings;

package Git::Search;
use Git::Search::Config;
use Moo;
use IO::All;
use JSON;
use IPC::System::Simple qw/ capture /;
use Furl;
use Data::Dumper;

our $VERSION = 0.01;

has config => (
    is      => 'lazy',
    builder => sub { Git::Search::Config->new->config },
);
has work_tree => (
    is      => 'lazy',
    builder => sub { shift->config->{work_tree} },
);
has index_url => (
    is      => 'lazy',
    builder => sub { 
        my $self = shift;
        my $config = $self->config;
        my $index_url = 'http://' . $config->{host} . ':' . $config->{port}
               . '/' . $config->{index} . '/';
        return $index_url;
    },
);
has base_url => (
    is      => 'lazy',
    builder => sub { 
        my $self = shift;
        my $config = $self->config;
        my $base_url= $self->index_url . $config->{type} . '/';
    },
);
has path_query_index => (
    is      => 'lazy',
    builder => sub { 
        my $self = shift;
        return '/' . $self->config->{index} . '/';
    },
);
has path_query_base => (
    is      => 'lazy',
    builder => sub { 
        my $self = shift;
        return $self->path_query_index . $self->config->{type} . '/';
    },
);
has furl => (is => 'lazy', builder => sub { Furl::HTTP->new });
has file_list => (is => 'lazy',);
has docs      => (is => 'lazy',);
has query     => (is => 'lazy', clearer => 1);
has results   => (is => 'lazy', clearer => 1);
has hits => (
    is      => 'lazy',
    builder => sub { shift->results->{hits}->{hits} },
    clearer => 1,
);
has size          => (is => 'lazy', builder => sub { 25 },);
has search_phrase => (is => 'rw',   builder => sub { $ARGV[0] });
after search_phrase => sub {
    my $self = shift;
    $self->clear_query;
    $self->clear_results;
    $self->clear_hits;
};
has mappings => (is => 'lazy');
has settings => (is => 'lazy');
has analyzers => (is => 'lazy');

sub _build_file_list {
    my ($self,) = @_;

    my $work_tree = $self->work_tree;
    my $git_dir   = $work_tree . '.git';
    my @files =
      capture('git', "--git-dir=${git_dir}", "--work-tree=${work_tree}",
        'ls-tree', '--full-tree', '-r', 'HEAD');
    @files = map { [ split /\s+/, $_ ] } @files;

    # Possibly use a set of sub-directories
    my $name     = 3;
    my @sub_dirs = @{ $self->config->{sub_dirs} };
    @sub_dirs = map { '^' . $_ } @sub_dirs;
    my $sub_dirs = join '|', @sub_dirs;
    @files = grep { $_->[$name] =~ m!($sub_dirs)! } @files;
    # Filter out non-text files
    my @text_files = grep {
        $self->is_text_file($self->work_tree . $_->[$name]) 
    } @files;

    return \@text_files;
}

sub is_text_file {
    my ($self, $file) = @_;
    my $size = -s $file;
    my $size_threshold = 100_00;
    warn "file size: $size for $file\n" if $size > 1_000_000;
    return if ($size > $size_threshold); 
    -f $file && -T $file;
}

sub _build_docs {
    my ($self,) = @_;

    my @docs;
    my $mode = 0;
    my $type = 1;
    my $id   = 2;
    my $name = 3;
    foreach my $file (@{ $self->file_list }) {
        my $filename = $self->work_tree . $file->[$name];
        my $io       = io $filename;
        my $content  = $io->slurp;
        push @docs,
          {
            content   => $content,
            name      => $file->[$name],
            commit_id => $file->[$id],
            type      => $file->[$type],
            mode      => $file->[$mode],
          };
    }

    return \@docs;
}

sub insert_docs {
    my ($self,) = @_;

    my $docs_inserted_count = 0;
    $self->recreate_index;

    # Insert (and index) the docs
    foreach my $doc (@{ $self->docs }) {
        if ($ENV{GIT_SEARCH_DEBUG}) { warn "creating doc: ", $doc->{name}, "\n"; }
        if (my $success = $self->create_doc($doc)) {
            $docs_inserted_count++;
        }
    }

    return $docs_inserted_count;
}

sub recreate_index {
    my ($self, ) = @_;
    $self->delete_index;
    $self->create_index;
}

sub create_index {
    my ($self, ) = @_;

    my $index = {
        settings => $self->settings,
        mappings => $self->mappings,
    };
    my %args = (
        request_method => 'POST',
        content_type   => 'application/json',
        content        =>  encode_json($index),
        path_query     => $self->path_query_index,
    );
    my $response = $self->crud(%args);
    if ($response->{code} != 200) {
        die "Index creation failed ", $response->{msg};
    }
    return 1;
}

sub delete_index {
    my ($self, ) = @_;

    # Check if index exists
    my $index_status_url = $self->index_url . '_status';
    warn "Getting $index_status_url\n";
    my @status_response = $self->furl->get($index_status_url);

    # If we already have an index we'll need to delete it so we don't
    # have redundant records with this bulk load.
    # TODO: Use file name is unique id for the docs on insertion
    if ($status_response[2] eq 'OK') {
        warn "Have an index already, going to delete it\n";
        my @delete_response = $self->furl->delete($self->index_url);

        # Remove existing data?
        if ($delete_response[2] ne 'OK') {
            warn "DELETE of ", $self->index_url,
              " failed with response status: ",
              $delete_response[1], ':', $delete_response[2];
            return;
        }
        else {
            warn "DELETE went $delete_response[2]\n";
            return 1;
        }
    }

    return 1;
}

sub create_doc {
    my ($self, $doc) = @_;

    # Note: automatic ID generation requires a POST
    #       (with op_type auto set to 'create')
    my %args = (
        request_method => 'POST',
        content_type   => 'application/json',
        content        =>  encode_json($doc),
        path_query     => $self->path_query_base,
    );
    my $response = $self->crud(%args);

    if ($response->{msg} ne 'Created') {
        warn "Request failed with message: ", $response->{msg};
        warn Dumper $response;
        return;
    }

    return 1;
}

sub match_query {
    my ($self, ) = @_;

    return {
        match => {
            content => {
                query          => $self->search_phrase,
                operator       => 'and',
                fuzziness      => 0.75,
                prefix_length  => 1,
                max_expansions => 25,
                analyzer => 'verbatim',
            },
        }
    };
}

sub match_phrase_query {
    my ($self, ) = @_;

    return {
        match => {
            content => {
                query          => $self->search_phrase,
                type           => 'phrase',
                operator       => 'and',
                fuzziness      => 0.75,
                prefix_length  => 1,
                max_expansions => 25,
                slop           => 12,
                analyzer => 'verbatim',
            },
        }
    };
}

sub match_phrase_prefix_query {
    my ($self, ) = @_;

    return {
        match => {
            content => {
                query          => $self->search_phrase,
                type           => 'phrase_prefix',
                operator       => 'and',
                fuzziness      => 0.75,
                prefix_length  => 1,
                max_expansions => 25,
                slop           => 12,
                analyzer => 'verbatim',
            },
        }
    };
}

sub _build_query {
    my ($self,) = @_;

    my $query = {
        query => $self->match_phrase_prefix_query,
        highlight => {
            tags_schema => 'styled',
            order => 'score',
            fields      => {
                content => {
                    number_of_fragments => 36,
                    fragment_size       => 128,
                }
            },
        },
        size => $self->size,
    };

    return $query;
}

sub _build_results {
    my ($self,) = @_;

    my %args = (
        request_method => 'POST',
        content_type   => 'application/json',
        content        => encode_json($self->query),
        path_query     => $self->path_query_base . '_search',
    );
    my $response = $self->crud(%args);
    return decode_json($response->{body});
}

sub crud {
    my ($self, %arg) = @_;

    my ($request_method, $path_query, $content_type, $content) =
      @arg{qw/request_method path_query content_type content/};
    my %request = (
        method     => $request_method,
        host       => $self->config->{host},
        port       => $self->config->{port},
        path_query => $path_query,
    );
    $request{content_type} = $content_type if $content_type;
    $request{content} = $content if $content;
    my %response;
    @response{qw(minor_version code msg headers body)} = $self->furl->request( %request);
    return \%response;
}

sub check_response {
    my ($self, $request_method, $code, $msg ) = @_;
    my $check_response = {
        'HEAD' => sub { },
        'GET' => sub { 
            if ($code !~ m/200/) { die "Error, expected reponse code of 200 but got $code:$msg"; }
            if ($msg ne 'OK') { die "Error, expected message of OK but got $msg"; }
        },
        'PUT' => sub { },
        'POST' => sub { 
            if ($code !~ m/20\d/) { die "Error, expected reponse code of 20? but got $code:$msg;" }
            if ($msg !~ m/Created|OK/) { die "Error, expected message of Created but got $msg"; }
            
        },
        'DELETE' => sub { },
    };
    $check_response->{$request_method}->();
}

sub _build_mappings {
    my ($self,) = @_;

    return {
        "git" => {
            "_source" => { "compress" => 1 },
            "numeric_detection" => 1,
            "dynamic" => "strict",
            "type" => "object",
            "properties" => {
                "commit_id" => { "type" => "string" },
                "content"   => {
                    "index" => "analyzed",
                    "store" => "yes",
                    "type" => "string",
                    "term_vector" => "with_positions_offsets",
                    "analyzer" => "edge_ngram_analyzer",
                },
                "mode" => { "type" => "string" },
                "name" => { "type" => "string" },
                "type" => { "type" => "string" }
            }
        }
    };
}

sub _build_settings {
    my ($self,) = @_;
    return {
        index => {
            number_of_shards => 2,
            number_of_replicas => 1,
            analysis => $self->analyzers,
        },
    };
}

sub _build_analyzers {
    my ($self,) = @_;
    return {
        analyzer => {
            verbatim => {
                type => 'custom',
                tokenizer => 'pattern_tokenizer',
#                filter => [''],
            },
            edge_ngram_analyzer => {
                type => 'custom',
                tokenizer => 'pattern_tokenizer',
#                filter => ['edge_ngram_filter'],
            },
        },
        tokenizer => {
            edge_ngram_tokenizer => {
                type => 'edge_ngram',
                min_gram => 1,
                max_gram => 24,
            }
        },
        tokenizer => {
            pattern_tokenizer => {
                type => 'pattern',
                pattern => '[^\w\.]+',
            }
        },
        filter => {
            edge_ngram_filter => {
                type => 'edge_ngram',
                min_gram => 1,
                max_gram => 24,
            }
        },
    };
}

1

__END__

=head1 NAME

Git::Search - search a git repo with elasticsearch

=head1 SYNOPSIS

    # Copy git-search.conf to git-search-local.conf and edit it to your needs
    perl -Ilib bin/insert_docs.pl  # create index
    plackup -Ilib web.psgi # start app
    # Do a search by requesting:  http://localhost:5000/search phrase
    
=cut
