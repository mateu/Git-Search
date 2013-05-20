use strict;
use warnings;
use Git::Search;
use Plack::Util;
use Plack::App::File;
use Plack::App::Cascade;
use Plack::Builder;

my $gs = Git::Search->new;
my $work_tree = $gs->work_tree;
my $search_psgi = 'app.psgi';
my $search_app = Plack::Util::load_psgi  $search_psgi;

my $static_app = Plack::App::File->new(root => $work_tree)->to_app;
my $cascaded_app = 
  Plack::App::Cascade->new(apps => [$static_app, $search_app ])->to_app;

builder {
    mount "/" => $cascaded_app;
};