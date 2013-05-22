use strictures 1;
use Git::Search;
use Test::Simpler tests => 1;

my $gs = Git::Search->new(search_phrase => $ARGV[0]||'Moose Time');
my $hits = $gs->hits;
ok(scalar @{$hits}, "Got some hits");
