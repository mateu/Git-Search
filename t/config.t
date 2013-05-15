use strictures 1;
use Git::Search::Config;
use Test::More;

my $config = Git::Search::Config->new->config;
ok(defined $config->{work_tree}, 'work tree defined');
ok(defined $config->{sub_dirs}, 'sub-directories defined');
ok(defined $config->{base_url}, 'base URL defined');

done_testing();