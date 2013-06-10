use strict;
use warnings FATAL => 'all';
use Benchmark qw/cmpthese/;
use Git::Search;

# Compare indexing when we store _all and not
my $sub_dirs = ['doc/howto'];
my $gs_true  = Git::Search->new(
   _all_enabled => 'true', 
    sub_dirs => $sub_dirs,
   _source_enabled => 'true',
);
my $gs_false = Git::Search->new(
   _all_enabled => 'false', 
    sub_dirs => $sub_dirs,
   _source_enabled => 'false',
);

my $count = $ARGV[0] || 20;
cmpthese(
    $count,
    {
        '_all true'  => sub { $gs_true->insert_docs },
        '_all_false' => sub { $gs_false->insert_docs },
    }
);
