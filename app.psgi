#!/usr/bin/env perl
use 5.010;
 
package GitSearch;
use Web::Simple;
use Git::Search;
use DDP;

has gs => (
  is => 'lazy',
  builder => sub { Git::Search->new },
);
has file_root => (
  is => 'lazy',
  builder => sub { shift->gs->work_tree },
);
 
sub dispatch_request {
  sub (GET + /*) {
    my ($self, $query) = @_;

    my $root = $self->file_root;
    $self->gs->search_phrase($query);
    my $output;
    my $hits = $self->gs->hits;
    foreach my $hit (@{$hits}) {
      my $name = $hit->{_source}->{name};
      my $highlights = $hit->{highlight};
      my @content = @{$highlights->{content}};
      my $content = join '<br><hr><br>', @content;
      $output .= "<h2><a href='/${name}'>${name}</a></h2>\n";
      $output .= "<pre>${content}</pre>\n";
      #warn Dumper(@content);
    }
    my $page = $self->html_wrapper($output);
    [ 200, [ 'Content-type', 'text/html' ], [ $page ] ]
  },
  sub () {
    [ 405, [ 'Content-type', 'text/plain' ], [ 'Method not allowed' ] ]
  }
}

sub html_wrapper {
    my ($self, $content) = @_;

    $content //= 'No Hits';
 
    my $head =<<"EOH";
<html>
<head>
<style media="screen" type="text/css">
em.hlt1 { color: green; font-weight: bold; font-style: normal;}
</style>
</head>
EOH

    my $body =<<"EOB";
 <body>
${content}
</body>
</html>
EOB

    my $page = $head . $body;
    return $page;
}
 
GitSearch->run_if_script;
