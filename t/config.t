use strictures 1;
use Git::Search::Config;
use Test::More;

my $config = Git::Search::Config->new->config;
ok(defined $config->{work_tree}, 'work tree defined');
ok(defined $config->{sub_dirs}, 'sub-directories defined');
ok(defined $config->{host}, 'host defined');
ok(defined $config->{port}, 'port defined');
ok(defined $config->{index}, 'index defined');
ok(defined $config->{type}, 'type defined');

done_testing();