use strict;
use warnings;
use Git::Search;
use DDP;
use Data::Dumper::Concise;

my $gs = Git::Search->new;
my $hits = $gs->hits;
#p($hits);
foreach my $hit (@{$gs->hits}) {
    warn "name: ", $hit->{_source}->{name};
    my $highlights = $hit->{highlight};
    my @content = @{$highlights->{content}};
    warn Dumper(@content);
}