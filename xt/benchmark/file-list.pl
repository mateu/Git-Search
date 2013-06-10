use strict;
use warnings FATAL => 'all';
use Benchmark qw/cmpthese/;
use Git::Search::Config;
use IPC::System::Simple qw/ capture /;

my $config = Git::Search::Config->new->config;
my $work_tree = $config->{work_tree};
my $git_dir = $work_tree . '.git';
my @files = ('git-search.conf', 'lib/Git/Search.pm', );
my $file = $files[int(rand(2))];
my $count = $ARGV[0] || 20;

cmpthese(
    $count,
    {
        'IPC' => sub {
             my @files =
               capture('git', "--git-dir=${git_dir}", "--work-tree=${work_tree}",
                 'ls-tree', '--full-tree', '-r', 'HEAD');
        },
        'backtick' => sub {
            my $command_line = "git --git-dir=${git_dir} --work-tree=${work_tree} ls-tree --full-tree -r HEAD";
            my @files = `$command_line`;
        },
    }
);

