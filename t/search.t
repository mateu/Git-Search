use JSON;
use HTTP::Request;
use LWP::UserAgent;
use Git::Search::Config;

use DDP;

my $config = Git::Search::Config->new->config;
my $search = {
    query => { match => {content => $ARGV[0]}},
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
p($output->{hits}->{hits}->[0]);

sub base_url { return $config->{base_url} }
