use strict;
use warnings FATAL => 'all';
use Git::Search;
use Test::More;

my $gs = Git::Search->new;
my $doc = 'doc/install/02sandbox.txt';
my $response = $gs->update_doc($doc);
is($response->{code}, 200, 'Good response');

done_testing;