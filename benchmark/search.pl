use strictures 1;
use Benchmark qw/cmpthese/;
use Git::Search;
use ElasticSearch;

my $search_phrase = $ARGV[0] || 'Moose Time';
my $gs = Git::Search->new(search_phrase => $search_phrase);
my $es = ElasticSearch->new;

my $count = $ARGV[1] || 20;
cmpthese(
    $count,
    {
        'GS' => sub {
            $gs->search_phrase($search_phrase);
            $gs->hits;
        },
        'ES' => sub {
            $es->search(
                index => $gs->config->{index},
                type  => $gs->config->{type},
                query => $gs->query->{query},
                size  => $gs->size,
            );
        },
    }
);
