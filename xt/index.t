use strictures 1;
use Git::Search;
use Test::Simpler tests => 1;

use DDP;

my $gs = Git::Search->new;
ok($gs->insert_docs, "Inserted some docs");

