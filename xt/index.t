use strictures 1;
use Git::Search;
use Test::More;

my $gs = Git::Search->new;
ok($gs->insert_docs, "Inserted some docs");

done_testing();

