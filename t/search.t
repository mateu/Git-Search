use JSON;
use HTTP::Request;
use LWP::UserAgent;
use Git::Search::Config;

use DDP;

my $config = Git::Search::Config->new->config;
my $search = {
#    query => { match => {content => $ARGV[0]}},
    query => { 
        match_phrase => {
            content => {
                query => $ARGV[0],
                slop => 36,
#                max_expansions => 10,
                operator => 'and',
            },
        }
    },
    highlight => {
        fields => {
            content => {
#                pre_tags            => ['"'],
#                post_tags           => ['"'],
                number_of_fragments => 1,
                fragment_size       => 300,
            }
        },
    },
    #fields => ['content', 'name'],
};
my $search_json = encode_json($search);
my $base_url = base_url();
my $url = $base_url . '_search';
my $req = HTTP::Request->new(POST => $url);
$req->content_type('application/json');
$req->content($search_json);
my $ua = LWP::UserAgent->new;
my $res = $ua->request($req);
warn "RESPONSE: ";
my $output = decode_json($res->content);
p($output->{hits}->{hits}->[0]->{highlight});
p($output->{hits}->{hits}->[0]->{_source}->{name});

sub base_url { return $config->{base_url} }
