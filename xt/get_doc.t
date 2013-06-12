use strict;
use warnings FATAL => 'all';
use Git::Search;
use Test::More;

my $gs = Git::Search->new;
my $doc = 'doc/install/02sandbox.txt';
my $result = $gs->get_doc($doc);
is($result->{hits}->{total}, 1, 'Found one document');


done_testing();
