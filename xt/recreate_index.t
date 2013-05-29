use strictures 1;
use Git::Search;
use Test::More;

my $gs = Git::Search->new;
ok($gs->recreate_index, "Recreate index and mapping");

done_testing();