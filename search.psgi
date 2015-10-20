#!/usr/bin/env perl
use 5.010;
 
package GitSearch;
use Web::Simple;
use Git::Search;

has gs => (
  is => 'lazy',
  builder => sub { Git::Search->new },
);
has file_root => (
  is => 'lazy',
  builder => sub { shift->gs->work_tree },
);
has git_branch => (
  is => 'lazy',
  builder => sub {
    my $self = shift;
    my $work_tree = $self->gs->work_tree;
    my $git_dir   = $work_tree . '.git';
    my $get_branch_command = "git --git-dir=${git_dir} --work-tree=${work_tree} rev-parse --abbrev-ref HEAD";
    my ($branch) = `$get_branch_command`;
    return $branch
  },
);
 
sub dispatch_request {
  sub (GET + /favicon.ico) {
    my ($self, ) = @_;
    [ 200, [ 'Content-type', 'text/plain' ], [ '' ] ]
  },
  sub (GET + /**.*) {
    my ($self, $query) = @_;

    my $root = $self->file_root;
    $self->gs->search_phrase($query);
    my $title = "<div style='font-size: 1.2em;'>Search phrase: <i>${query}</i> ";
    my $toc = "<div><ul>\n";
    my $body = '';
    my $hits = $self->gs->hits;
    if (not scalar @{$hits}) {
        $title .= "<strong>not found</strong></div>\n";
    }
    else {
        $title .= "found in:</div>\n";
    }
    foreach my $hit (@{$hits}) {
        my $name = $hit->{_source}->{name};
        $toc .= "<li><a href='#${name}'>${name}</a>\n";
        $body .= $self->add_hit_content($hit);
    }
    $toc .= "<\ul></div>\n";
    my $inner_page = $title . $toc . $body;
    my $page = $self->html_wrapper($inner_page);
    [ 200, [ 'Content-type', 'text/html' ], [ $page ] ]
  },
  sub () {
    [ 405, [ 'Content-type', 'text/plain' ], [ 'Method not allowed' ] ]
  }
}

sub add_hit_content {
    my ($self, $hit) = @_;

    my $git_branch = $self->git_branch;
    my $name = $hit->{_source}->{name};
    my $content = '';
    if (my $highlights = $hit->{highlight}) {
        my @content = @{$highlights->{content}};
        $content = join '<br><hr style="border-color: #fff; "><br>', @content;
    }
    my $output = "<div><a name='${name}'></a><span style='font-weight:bold; font-size: 1.08em;'>${name}</span><br><a href='${name}'>local</a>";
    if (my $remote_tree = $self->gs->remote_work_tree) {
        $output .= " or <a href='${remote_tree}${git_branch}/${name}'>remote</a>";
    }
    $output .= "</div>\n";
    $output .= "<pre>${content}</pre>\n";
    return $output;
}

sub html_wrapper {
    my ($self, $content) = @_;

    $content //= 'No Hits';
    my $highlight_css = $self->highlight_css;
 
    my $head =<<"EOH";
<html>
<head>
<style media="screen" type="text/css">
$highlight_css
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

sub highlight_css {
    my ($self, ) = @_;

    my @highlight_css;
    my @font = ('font-weight:bold', 'font-style:normal'); 
    my $highlight_colors = 'green,' x 3 . 'orange,' x 3 . 'purple,' x 3 . 'red';
    my @highlight_colors = split /,/, $highlight_colors;
    foreach my $n (1..10) {
        my $class = 'em.hlt' . $n;
        my $color = 'color:' . $highlight_colors[$n - 1];
        my $attributes = join '; ', $color, @font;
        my $css_line = $class . ' { ' . $attributes . '; }';
        push @highlight_css, $css_line;
    } 
    return join "\n", @highlight_css;
}
 
GitSearch->run_if_script;
