use strictures 1;
use Git::Search;
use Test::More;

my $gs = Git::Search->new(search_phrase => $ARGV[0]||'Moose Time');
my $hits = $gs->hits;
ok(scalar @{$hits}, "Got some hits");

done_testing();