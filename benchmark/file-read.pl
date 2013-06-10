use strict;
use warnings FATAL => 'all';
use Benchmark qw/cmpthese/;
use IO::All;

my @files = ('git-search.conf', 'lib/Git/Search.pm', );
my $file = $files[int(rand(2))];
my $count = $ARGV[0] || 20;

cmpthese(
    $count,
    {
        'IO::All' => sub {
            my $io = io $file;
            my $content = $io->slurp;    
        },
        'local slurp' => sub {
            open my $fh, '<', $file;
            my $content = do { local $/; <$fh> };
        },
    }
);

