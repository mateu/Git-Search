use strict;
use warnings;
use 5.010;

package Git::Search;
use Git::Search::Config;
use Moo;
use JSON;
use Furl;

our $VERSION = 0.01;

has debug => ( is => 'lazy', builder => sub { $ENV{GIT_SEARCH_DEBUG} }, );
has config => (
    is      => 'lazy',
    builder => sub { Git::Search::Config->new->config },
);
has work_tree => (
    is      => 'lazy',
    builder => sub { shift->config->{work_tree} },
);
has remote_work_tree => (
    is      => 'lazy',
    builder => sub { shift->config->{remote_work_tree} },
);
has sub_dirs => ( is => 'lazy', builder => sub { shift->config->{sub_dirs} }, );
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
has size          => (is => 'lazy', builder => sub { 10 },);
has fuzziness     => (is => 'lazy', builder => sub { shift->config->{fuzziness}//0.66 },);
has max_gram      => (is => 'lazy', builder => sub { shift->config->{max_gram}||15 },);
has operator      => (is => 'lazy', builder => sub { 'and' },);
has search_phrase => (is => 'rw',   builder => sub { $ARGV[0] }, );
has search_type   => (is => 'ro',   builder => sub { 'match_phrase_prefix_query' }, );
has _all_enabled  => (is => 'ro',   builder => sub { 'true' }, );
has _source_enabled => (is => 'ro',   builder => sub { 'true' }, );

after search_phrase => sub {
    my $self = shift;
    $self->clear_query;
    $self->clear_results;
    $self->clear_hits;
};
has mappings => (is => 'lazy');
has settings => (is => 'lazy');
has analyzers => (is => 'lazy');
# Cap file size to one megabyte by default
has max_file_size => (is => 'lazy', builder => sub { 1_048_576 });

sub _build_file_list {
    my ($self,) = @_;

    my $work_tree = $self->work_tree;
    my $git_dir   = $work_tree . '.git';
    my $command_line = "git --git-dir=${git_dir} --work-tree=${work_tree} ls-tree --full-tree -r HEAD";
    my @files = `$command_line`;

    @files = map { [ split /\s+/, $_ ] } @files;

    # Possibly use a set of sub-directories
    my $name     = 3;
    my @sub_dirs = @{ $self->sub_dirs };
    @sub_dirs = map { '^' . $_ } @sub_dirs;
    my $sub_dirs = join '|', @sub_dirs;
    @files = grep { $_->[$name] =~ m!($sub_dirs)! } @files;
    # Filter out non-text files
    my @text_files = grep {
        $self->is_text_file($self->work_tree . $_->[$name]) 
    } @files;
    # Weed out files considered too big
    @text_files = grep {
        $self->is_file_small_enough($self->work_tree . $_->[$name]) 
    } @text_files;


    return \@text_files;
}

sub is_text_file {
    my ($self, $file) = @_;
    -f $file && -T $file;
}

sub is_file_small_enough {
    my ($self, $file) = @_;
    my $size = -s $file;
    my $is_small_enough = ($size <= $self->max_file_size);
    if ($self->debug) {
        warn "file size too big: $size for $file\n" unless $is_small_enough
    }
    return $is_small_enough;
}

sub _build_docs {
    my ($self,) = @_;

    my @docs;
    my $mode = 0;
    my $type = 1;
    my $id   = 2;
    my $name = 3;
    foreach my $file (@{ $self->file_list }) {
        my $content = $self->get_content_for($file->[$name]);
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

sub get_content_for {
    my ($self, $name) = @_;

    my $filename = $self->work_tree . $name;
    open my $fh, '<', $filename or die "Can't open $filename Reason: $!";
    my $content = do { local $/; <$fh> };

    return $content;
}

sub insert_docs {
    my ($self,) = @_;

    my $docs_inserted_count = 0;
    $self->recreate_index;

    # Insert (and index) the docs
    foreach my $doc (@{ $self->docs }) {
        if ($self->debug) { warn "creating doc: ", $doc->{name}, "\n"; }
        if (my $success = $self->create_doc($doc)) {
            $docs_inserted_count++;
        }
    }

    return $docs_inserted_count;
}
sub query_doc {
    my ($self, $name) = @_;
    return { query => {term => {_id => $name} } };
}

sub get_doc {
    my ($self, $name) = @_;

    my $query_doc = $self->query_doc($name);
    my %args = (
        request_method => 'POST',
        content_type   => 'application/json',
        content        => encode_json($query_doc),
        path_query     => $self->path_query_base . '_search',
    );
    my $response = $self->crud(%args);

    return decode_json($response->{body});
}

sub update_doc {
    my ($self, $name) = @_;

    my $encoded_name = $name;
    # Enocde slash to keep ES happy with id
    $encoded_name =~ s|/|%2F|g;
    my $path_query = $self->path_query_base . $encoded_name . '/_update';
    # TODO: Update all document attributes including commit_id
    my $doc = { 
        doc => {
            content => $self->get_content_for($name),
        }
    };
    my %args = (
        request_method => 'POST',
        content_type   => 'application/json',
        content        => encode_json($doc),
        path_query     => $path_query,
    );

    return $self->crud(%args);
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
    warn "Getting $index_status_url\n" if $self->debug;
    my @status_response = $self->furl->get($index_status_url);

    # If we already have an index we'll need to delete it so we don't
    # have redundant records with this bulk load.
    # TODO: Use file name as unique id for the docs on insertion
    if ($status_response[2] eq 'OK') {
        warn "Have an index already, going to delete it\n" if $self->debug;
        my @delete_response = $self->furl->delete($self->index_url);

        # Remove existing data?
        if ($delete_response[2] ne 'OK') {
            warn "DELETE of ", $self->index_url,
              " failed with response status: ",
              $delete_response[1], ':', $delete_response[2];
            return;
        }
        else {
            warn "DELETE went $delete_response[2]\n" if $self->debug;
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
                operator       => $self->operator,
                fuzziness      => $self->fuzziness,
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
                operator       => $self->operator,
                fuzziness      => $self->fuzziness,
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
                operator       => $self->operator,
                fuzziness      => $self->fuzziness,
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

    my $search_type = $self->search_type;
    my $query = {
        query => $self->$search_type,
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

    my $config = $self->config;
    my $type = $config->{type};
    my $all_enabled = $self->_all_enabled;
    my $source_enabled = $self->_source_enabled;

    return {
        $type => {
            "_source" => {"enabled" => $source_enabled, "compress" => 1},
            "_all" => {"enabled" => $all_enabled},
            "numeric_detection" => 1,
            "dynamic" => "strict",
            "properties" => {
                "commit_id" => { "type" => "string" },
                "content"   => {
                    "index" => "analyzed",
                    "store" => "no",
                    "type" => "string",
                    "term_vector" => "with_positions_offsets",
                    "analyzer" => "edge_ngram_analyzer",
                },
                "mode" => { "type" => "string" },
                "name" => { "type" => "string", "analyzer" => "whitespace" },
                "type" => { "type" => "string" }
            },
            "_id" => { "path" => "name" },
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
                filter => ['lowercase'],
            },
            edge_ngram_analyzer => {
                type => 'custom',
                tokenizer => 'pattern_tokenizer',
                filter => ['edge_ngram_filter', 'lowercase'],
            },
        },
        tokenizer => {
            pattern_tokenizer => {
                type => 'pattern',
                pattern => '\s+',
            }
        },
        filter => {
            edge_ngram_filter => {
                type => 'edgeNGram',
                min_gram => 1,
                max_gram => $self->max_gram,
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
    # Create index (with debug on to see the files affected)
      GIT_SEARCH_DEBUG=1 perl -Ilib bin/insert_docs.pl  
    # Start app
      plackup -Ilib 
    # Do a search by requesting:  http://localhost:5000/search phrase
    
=cut
