use strict;
use warnings;

package Git::Search;
use Moo;
use IO::All;
use JSON;
use HTTP::Request;
use LWP::UserAgent;
use IPC::System::Simple qw/ capture /;
use Git::Search::Config;
use DDP;

our $VERSION = 1;

has config => (
    is      => 'lazy',
    builder => sub { Git::Search::Config->new->config },
);
has work_tree => (
    is      => 'lazy',
    builder => sub { shift->config->{work_tree} },
);
has base_url => (
    is      => 'lazy',
    builder => sub { shift->config->{base_url} },
);
has index_url => (
    is      => 'lazy',
    builder => sub { shift->config->{index_url} },
);
has ua => (is => 'lazy', builder => sub { LWP::UserAgent->new });
has file_list => (is => 'lazy',);
has docs      => (is => 'lazy',);
has query     => (is => 'lazy', clearer => 1);
has query_json     => (is => 'lazy', builder => sub { encode_json(shift->query) } );
has results   => (is => 'lazy', clearer => 1);
has hits => (
    is      => 'lazy',
    builder => sub { shift->results->{hits}->{hits} },
    clearer => 1,
);
has size          => (is => 'lazy', builder => sub { 100 },);
has search_phrase => (is => 'rw',   builder => sub { $ARGV[0] });
after search_phrase => sub {
    my $self = shift;
    $self->clear_query;
    $self->clear_results;
    $self->clear_hits;
};
has mapping => (is => 'lazy');
has mapping_json => (is => 'lazy', builder => sub { encode_json(shift->mapping) });

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

    return \@files;
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

    warn "insert docs...";
    my $docs_inserted_count = 0;
    $self->delete_index;
#    $self->set_mapping;

    # Insert (and index) the docs
    foreach my $doc (@{ $self->docs }) {
        warn "creating doc: ", $doc->{name}, "\n";
        if (my $success = $self->create_doc($doc)) {
            $docs_inserted_count++;
        }
    }

    return $docs_inserted_count;
}

sub delete_index {
    my ($self, ) = @_;

    # Check if index exists
    my $mapping_url = $self->base_url . '_mapping';
    my $get_request = HTTP::Request->new(GET => $mapping_url);
    warn "Getting $mapping_url";

    # If we already have an index we'll need to delete it so we don't
    # have redundant records with this bulk load.
    # TODO: Use file name is unique id for the docs on insertion
    my $get_response = $self->ua->request($get_request);
    if ($get_response->is_success) {
        warn "Have a index already, going to delete it";
        my $delete_request = HTTP::Request->new(DELETE => $self->base_url);
        my $delete_response = $self->ua->request($delete_request);

        # Remove existing data?
        if (not $delete_response->is_success) {
            warn "DELETE of ", $self->base_url,
              " failed with response status: ",
              $get_response->status_line;
            return;
        }
        else {
            return 1;
        }
    }

    return 1;
}

sub create_doc {
    my ($self, $doc) = @_;
    my $request = HTTP::Request->new(POST => $self->base_url);
    $request->content_type('application/json');
    my $json_doc = encode_json($doc);
    $request->content($json_doc);
    my $ua       = LWP::UserAgent->new;
    my $response = $ua->request($request);
    if (not $response->is_success) {
        warn "Request failed with response status: ", $response->status_line;
        p($response);
        return;
    }
    return 1;
}

sub _build_query {
    my ($self,) = @_;

    my $query = {
        query => {
            match => {
                content => {
                    query          => $self->search_phrase,
                    operator       => 'and',
                    max_expansions => 25,
                    fuzziness      => 0.75,
                    prefix_length  => 1,
#                    analyzer => 'verbatim',
                },
            }
        },
        highlight => {
            tags_schema => 'styled',
            order => 'score',
            fields      => {
                content => {
                    number_of_fragments => 12,
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

    my $request = HTTP::Request->new(POST => $self->base_url . '_search');
    $request->content_type('application/json');
    $request->content(encode_json($self->query));
    my $ua       = LWP::UserAgent->new;
    my $response = $ua->request($request);

    return decode_json($response->content);
}

sub crud {
    my ($self, %arg) = @_;

    my ($request_method, $url, $content_type, $content) =
      @arg{qw/request_method url content_type content/};

    my $request = HTTP::Request->new($request_method => $url);
    $request->content_type($content_type);
    $request->content($content);
    my $response = $self->ua->request($request);
    return $response;
}

sub set_mapping {
    my ($self,) = @_;

    my %args = (
        request_method => 'PUT',
        url            => $self->index_url,
        content_type   => 'application/json',
        content        => $self->mapping_json,
    );
    my $response = $self->crud(%args);
    return $response;
}

sub _build_mapping {
    my ($self,) = @_;

    my $map = {
        "mappings" => {
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
                         "analyzer" => "verbatim"
                    },
                    "mode" => { "type" => "string" },
                    "name" => { "type" => "string" },
                    "type" => { "type" => "string" }
                }
              }
        }
    };
}

1
